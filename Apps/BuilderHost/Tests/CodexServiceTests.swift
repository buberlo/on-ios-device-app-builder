import Foundation
import XCTest
@testable import BuilderHost

final class CodexServiceTests: XCTestCase {
    func testCodexInvocationUsesEphemeralWorkspaceSandbox() {
        let command = AllowedCommand.codexExec(
            executable: URL(fileURLWithPath: "/approved/codex"),
            directory: URL(fileURLWithPath: "/controlled/project"),
            prompt: "Build a timer"
        ).invocation

        XCTAssertEqual(command.executable.path, "/approved/codex")
        XCTAssertEqual(
            command.arguments,
            [
                "exec",
                "--ignore-user-config",
                "--skip-git-repo-check",
                "--ephemeral",
                "--json",
                "--sandbox", "workspace-write",
                "-C", "/controlled/project",
                "Build a timer",
            ]
        )
    }

    func testParsesAssistantMessageAndErrorFromJSONL() {
        let text = """
        {"type":"thread.started","thread_id":"abc"}
        {"type":"item.completed","item":{"type":"agent_message","text":"Implemented the timer."}}
        {"type":"error","message":"Authentication required"}
        """

        let events = CodexJSONLParser.parse(text)

        XCTAssertEqual(events.map(\.kind), [.status, .assistantMessage, .error])
        XCTAssertEqual(events[1].message, "Implemented the timer.")
        XCTAssertEqual(events[2].message, "Authentication required")
    }

    func testParsesSingleStreamingStatusLine() {
        let event = CodexJSONLParser.parseLine(#"{"type":"turn.started","message":"Inspecting project"}"#)

        XCTAssertEqual(event, CodexRunEvent(kind: .status, message: "Inspecting project"))
    }

    func testBuildProgressKeepsUsefulLinesAndDropsNoise() {
        XCTAssertEqual(
            PrototypeBuildPipeline.progressMessage(from: "SwiftCompile normal arm64 View.swift", phase: .building),
            "SwiftCompile normal arm64 View.swift"
        )
        XCTAssertNil(PrototypeBuildPipeline.progressMessage(from: "cd /private/project", phase: .building))
        XCTAssertEqual(
            PrototypeBuildPipeline.progressMessage(from: "Generating project", phase: .generating),
            "Generating project"
        )
    }
}
