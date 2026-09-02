import Foundation

struct CommandOutput: Equatable, Sendable {
    let status: Int32
    let text: String

    var succeeded: Bool { status == 0 }
}

enum AllowedCommand: Sendable {
    case xcodeVersion
    case signingIdentities
    case tuistVersion(executable: URL)
    case codexVersion(executable: URL)
    case codexLoginStatus(executable: URL)
    case codexExec(executable: URL, directory: URL, prompt: String)
    case listDevices(jsonURL: URL)
    case generateProject(executable: URL, directory: URL)
    case buildProject(executable: URL, directory: URL, scheme: String, teamID: String)
    case installApp(deviceID: String, appURL: URL, jsonURL: URL)
    case launchApp(deviceID: String, bundleIdentifier: String, jsonURL: URL)

    var invocation: CommandInvocation {
        switch self {
        case .xcodeVersion:
            CommandInvocation(executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["xcodebuild", "-version"])
        case .signingIdentities:
            CommandInvocation(executable: URL(fileURLWithPath: "/usr/bin/security"), arguments: ["find-identity", "-v", "-p", "codesigning"])
        case let .tuistVersion(executable):
            CommandInvocation(executable: executable, arguments: ["version"])
        case let .codexVersion(executable):
            CommandInvocation(executable: executable, arguments: ["--version"])
        case let .codexLoginStatus(executable):
            CommandInvocation(executable: executable, arguments: ["login", "status"])
        case let .codexExec(executable, directory, prompt):
            CommandInvocation(
                executable: executable,
                arguments: [
                    "exec",
                    "--ignore-user-config",
                    "--skip-git-repo-check",
                    "--ephemeral",
                    "--json",
                    "--sandbox", "workspace-write",
                    "-C", directory.path,
                    prompt,
                ],
                currentDirectory: directory
            )
        case let .listDevices(jsonURL):
            CommandInvocation(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["devicectl", "list", "devices", "--json-output", jsonURL.path]
            )
        case let .generateProject(executable, directory):
            CommandInvocation(
                executable: executable,
                arguments: ["generate", "--no-open"],
                currentDirectory: directory,
                environment: ["TUIST_SKIP_UPDATE_CHECK": "1"]
            )
        case let .buildProject(executable, directory, scheme, teamID):
            CommandInvocation(
                executable: executable,
                arguments: [
                    "xcodebuild", "build",
                    "-scheme", scheme,
                    "-configuration", "Debug",
                    "-destination", "generic/platform=iOS",
                    "-derivedDataPath", directory.appending(path: ".derived").path,
                    "DEVELOPMENT_TEAM=\(teamID)",
                    "CODE_SIGN_STYLE=Automatic",
                ],
                currentDirectory: directory,
                environment: ["TUIST_SKIP_UPDATE_CHECK": "1"]
            )
        case let .installApp(deviceID, appURL, jsonURL):
            CommandInvocation(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: [
                    "devicectl", "device", "install", "app",
                    "--device", deviceID,
                    appURL.path,
                    "--json-output", jsonURL.path,
                ]
            )
        case let .launchApp(deviceID, bundleIdentifier, jsonURL):
            CommandInvocation(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: [
                    "devicectl", "device", "process", "launch",
                    "--device", deviceID,
                    bundleIdentifier,
                    "--json-output", jsonURL.path,
                ]
            )
        }
    }
}

struct CommandInvocation: Sendable {
    let executable: URL
    let arguments: [String]
    let currentDirectory: URL?
    let environment: [String: String]

    init(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String] = [:]
    ) {
        self.executable = executable
        self.arguments = arguments
        self.currentDirectory = currentDirectory
        self.environment = environment
    }
}

actor AllowlistedCommandRunner {
    private var activeProcess: Process?

    func run(
        _ command: AllowedCommand,
        onLine: (@Sendable (String) async -> Void)? = nil
    ) async throws -> CommandOutput {
        let invocation = command.invocation
        guard FileManager.default.isExecutableFile(atPath: invocation.executable.path) else {
            throw CommandRunnerError.executableUnavailable(invocation.executable.path)
        }
        guard activeProcess == nil else { throw CommandRunnerError.runnerBusy }

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.currentDirectory
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let inherited = ProcessInfo.processInfo.environment
        let safeEnvironmentKeys = ["HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG", "LC_ALL", "DEVELOPER_DIR"]
        var environment = Dictionary(
            uniqueKeysWithValues: safeEnvironmentKeys.compactMap { key in
                inherited[key].map { (key, $0) }
            }
        )
        invocation.environment.forEach { environment[$0.key] = $0.value }
        process.environment = environment
        activeProcess = process
        defer {
            if activeProcess === process { activeProcess = nil }
        }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let readTask = Task.detached(priority: .utility) {
                let handle = outputPipe.fileHandleForReading
                var collected = Data()
                var pending = Data()

                while let chunk = try? handle.read(upToCount: 4_096), !chunk.isEmpty {
                    collected.append(chunk)
                    pending.append(chunk)

                    while let newline = pending.firstIndex(of: 0x0A) {
                        let lineData = Data(pending[..<newline])
                        pending.removeSubrange(pending.startIndex...newline)
                        let line = String(decoding: lineData, as: UTF8.self)
                            .trimmingCharacters(in: .newlines)
                        if !line.isEmpty, let onLine {
                            await onLine(line)
                        }
                    }
                }

                if !pending.isEmpty, let onLine {
                    let line = String(decoding: pending, as: UTF8.self)
                    if !line.isEmpty { await onLine(line) }
                }
                return collected
            }
            let status: Int32 = try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { terminatedProcess in
                    try? outputPipe.fileHandleForWriting.close()
                    continuation.resume(returning: terminatedProcess.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    try? outputPipe.fileHandleForWriting.close()
                    continuation.resume(throwing: error)
                }
            }
            let data = await readTask.value
            try Task.checkCancellation()
            return CommandOutput(
                status: status,
                text: String(decoding: data, as: UTF8.self)
            )
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func cancel() {
        guard let activeProcess else { return }
        if activeProcess.isRunning {
            activeProcess.terminate()
        }
        self.activeProcess = nil
    }
}

enum CommandRunnerError: LocalizedError, Equatable {
    case executableUnavailable(String)
    case runnerBusy

    var errorDescription: String? {
        switch self {
        case let .executableUnavailable(path):
            "Required executable is unavailable: \(path)"
        case .runnerBusy:
            "Another approved command is already running."
        }
    }
}
