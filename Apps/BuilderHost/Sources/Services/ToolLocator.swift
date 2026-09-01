import Foundation

final class SendableFileManager: @unchecked Sendable {
    let value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}

struct ToolLocator: Sendable {
    private let fileManager: SendableFileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = SendableFileManager(fileManager)
    }

    func tuistURL() -> URL? {
        firstExecutable(at: [
            "/opt/homebrew/bin/tuist",
            "/usr/local/bin/tuist",
        ])
    }

    func codexURL() -> URL? {
        let knownPaths = [
            FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
        ]
        let pathCandidates = ProcessInfo.processInfo.environment["PATH", default: ""]
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appending(path: "codex").path }
        return firstExecutable(at: knownPaths + pathCandidates)
    }

    private func firstExecutable(at paths: [String]) -> URL? {
        paths
            .map(URL.init(fileURLWithPath:))
            .first { fileManager.value.isExecutableFile(atPath: $0.path) }
    }
}
