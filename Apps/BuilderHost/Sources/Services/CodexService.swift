import Foundation

struct CodexRunEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case status
        case assistantMessage
        case error
    }

    let kind: Kind
    let message: String
}

struct CodexRunResult: Equatable, Sendable {
    let events: [CodexRunEvent]

    var assistantText: String? {
        events.last(where: { $0.kind == .assistantMessage })?.message
    }
}

struct CodexService: Sendable {
    private let runner: AllowlistedCommandRunner
    private let toolLocator: ToolLocator

    init(runner: AllowlistedCommandRunner, toolLocator: ToolLocator = ToolLocator()) {
        self.runner = runner
        self.toolLocator = toolLocator
    }

    func run(
        prompt: String,
        in projectURL: URL,
        onEvent: (@Sendable (CodexRunEvent) async -> Void)? = nil
    ) async throws -> CodexRunResult {
        guard let executable = toolLocator.codexURL() else {
            throw CodexServiceError.unavailable
        }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CodexServiceError.emptyPrompt }
        guard projectURL.isFileURL else { throw CodexServiceError.invalidWorkspace }

        let commandPrompt = """
        Work only inside the supplied project directory. Update the generated SwiftUI iOS prototype to satisfy this request. Do not read secrets, credentials, or files outside the project. Keep the app buildable with the existing Tuist manifest.

        User request:
        \(trimmed)
        """
        let output = try await runner.run(
            .codexExec(executable: executable, directory: projectURL.standardizedFileURL, prompt: commandPrompt)
        ) { line in
            guard let event = CodexJSONLParser.parseLine(line) else { return }
            await onEvent?(event)
        }
        let events = CodexJSONLParser.parse(output.text)
        guard output.succeeded else {
            let reason = events.last(where: { $0.kind == .error })?.message
                ?? Self.lastMeaningfulLine(in: output.text)
                ?? "Codex exited with status \(output.status)."
            throw CodexServiceError.executionFailed(reason)
        }
        return CodexRunResult(events: events)
    }

    private static func lastMeaningfulLine(in text: String) -> String? {
        text
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .last { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { String($0.prefix(400)) }
    }
}

enum CodexJSONLParser {
    static func parse(_ text: String) -> [CodexRunEvent] {
        text.split(whereSeparator: \Character.isNewline).compactMap { parseLine(String($0)) }
    }

    static func parseLine(_ line: String) -> CodexRunEvent? {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let type = object["type"] as? String ?? ""
        if type.localizedCaseInsensitiveContains("error") {
            return CodexRunEvent(kind: .error, message: extractMessage(from: object) ?? "Codex reported an error.")
        }
        if let item = object["item"] as? [String: Any],
           let itemType = item["type"] as? String,
           itemType == "agent_message",
           let text = item["text"] as? String,
           !text.isEmpty {
            return CodexRunEvent(kind: .assistantMessage, message: String(text.prefix(2_000)))
        }
        if let message = extractMessage(from: object), !message.isEmpty {
            return CodexRunEvent(kind: .status, message: String(message.prefix(500)))
        }
        if !type.isEmpty {
            return CodexRunEvent(kind: .status, message: type.replacingOccurrences(of: ".", with: " ").capitalized)
        }
        return nil
    }

    private static func extractMessage(from object: [String: Any]) -> String? {
        if let message = object["message"] as? String { return message }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let item = object["item"] as? [String: Any], let text = item["text"] as? String { return text }
        return nil
    }
}

enum CodexServiceError: LocalizedError, Equatable {
    case unavailable
    case emptyPrompt
    case invalidWorkspace
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Codex CLI is unavailable; the deterministic demo planner will be used."
        case .emptyPrompt: "The prompt cannot be empty."
        case .invalidWorkspace: "Codex requires a validated local project workspace."
        case let .executionFailed(message): String(message.prefix(400))
        }
    }
}
