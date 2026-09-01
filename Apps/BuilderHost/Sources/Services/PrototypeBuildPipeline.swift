import Foundation

actor PrototypeBuildPipeline {
    private let runner: AllowlistedCommandRunner
    private let generator: PrototypeGenerator
    private let toolLocator: ToolLocator
    private let fileManager: FileManager
    private let developmentTeamID: String

    init(
        runner: AllowlistedCommandRunner,
        generator: PrototypeGenerator = PrototypeGenerator(),
        toolLocator: ToolLocator = ToolLocator(),
        fileManager: FileManager = .default,
        developmentTeamID: String = "K5TW9AU245"
    ) {
        self.runner = runner
        self.generator = generator
        self.toolLocator = toolLocator
        self.fileManager = fileManager
        self.developmentTeamID = developmentTeamID
    }

    func build(
        project: HostProjectRecord,
        at projectURL: URL,
        installOn device: ConnectedIPhone?,
        progress: @escaping @Sendable (PrototypeBuildProgress) async -> Void
    ) async throws -> PrototypeBuildResult {
        guard let tuistURL = toolLocator.tuistURL() else { throw BuildPipelineError.tuistUnavailable }

        await progress(.init(phase: .preparing, message: "Preparing controlled workspace", fraction: 0.05))
        try Task.checkCancellation()
        try prepareProjectIfNeeded(project, at: projectURL)

        await progress(.init(phase: .generating, message: "Generating Xcode workspace", fraction: 0.2))
        let generation = try await runner.run(.generateProject(executable: tuistURL, directory: projectURL))
        guard generation.succeeded else {
            throw BuildPipelineError.generationFailed(Self.safeSummary(generation.text))
        }

        await progress(.init(phase: .building, message: "Building and signing iOS app", fraction: 0.45))
        let build = try await runner.run(
            .buildProject(
                executable: tuistURL,
                directory: projectURL,
                scheme: PrototypeGenerator.schemeName,
                teamID: developmentTeamID
            )
        )
        guard build.succeeded else {
            throw BuildPipelineError.buildFailed(Self.safeSummary(build.text))
        }
        guard let appURL = findBuiltApp(in: projectURL) else {
            throw BuildPipelineError.appArtifactMissing
        }

        guard let device else {
            await progress(.init(phase: .finished, message: "Signed app is ready", fraction: 1))
            return PrototypeBuildResult(appURL: appURL, installedDeviceName: nil)
        }

        try await install(
            appURL: appURL,
            bundleIdentifier: project.bundleIdentifier,
            on: device,
            progress: progress
        )
        return PrototypeBuildResult(appURL: appURL, installedDeviceName: device.name)
    }

    func install(
        appURL: URL,
        bundleIdentifier: String,
        on device: ConnectedIPhone,
        progress: @escaping @Sendable (PrototypeBuildProgress) async -> Void
    ) async throws {
        guard fileManager.fileExists(atPath: appURL.path) else { throw BuildPipelineError.appArtifactMissing }
        let installJSON = temporaryJSONURL(prefix: "install")
        let launchJSON = temporaryJSONURL(prefix: "launch")
        defer {
            try? fileManager.removeItem(at: installJSON)
            try? fileManager.removeItem(at: launchJSON)
        }

        await progress(.init(phase: .installing, message: "Installing on \(device.name)", fraction: 0.78))
        let installation = try await runner.run(.installApp(deviceID: device.id, appURL: appURL, jsonURL: installJSON))
        guard installation.succeeded else {
            throw BuildPipelineError.installationFailed(Self.safeSummary(installation.text))
        }

        await progress(.init(phase: .launching, message: "Launching on \(device.name)", fraction: 0.94))
        let launch = try await runner.run(
            .launchApp(deviceID: device.id, bundleIdentifier: bundleIdentifier, jsonURL: launchJSON)
        )
        guard launch.succeeded else {
            throw BuildPipelineError.launchFailed(Self.safeSummary(launch.text))
        }
        await progress(.init(phase: .finished, message: "Installed and launched on \(device.name)", fraction: 1))
    }

    func cancel() async {
        await runner.cancel()
    }

    func prepareProjectIfNeeded(_ project: HostProjectRecord, at projectURL: URL) throws {
        if !fileManager.fileExists(atPath: projectURL.appending(path: "Project.swift").path) {
            try generator.generate(project, at: projectURL)
        }
    }

    private func findBuiltApp(in projectURL: URL) -> URL? {
        let preferred = projectURL
            .appending(path: ".derived/Build/Products/Debug-iphoneos/PrototypeApp.app", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: preferred.path) { return preferred }
        let products = projectURL.appending(path: ".derived/Build/Products", directoryHint: .isDirectory)
        guard let enumerator = fileManager.enumerator(
            at: products,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let candidate as URL in enumerator where candidate.pathExtension == "app" {
            return candidate
        }
        return nil
    }

    private func temporaryJSONURL(prefix: String) -> URL {
        fileManager.temporaryDirectory.appending(path: "builder-host-\(prefix)-\(UUID().uuidString).json")
    }

    private static func safeSummary(_ text: String) -> String {
        let lines = text
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return String((lines.suffix(6).joined(separator: "\n")).prefix(1_200))
    }
}

enum BuildPipelineError: LocalizedError, Equatable {
    case tuistUnavailable
    case generationFailed(String)
    case buildFailed(String)
    case appArtifactMissing
    case installationFailed(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .tuistUnavailable: "Tuist is not installed in an approved location."
        case let .generationFailed(message): "Project generation failed: \(message)"
        case let .buildFailed(message): "Build failed: \(message)"
        case .appArtifactMissing: "The build completed without producing an iOS app."
        case let .installationFailed(message): "Installation failed: \(message)"
        case let .launchFailed(message): "Launch failed: \(message)"
        }
    }
}
