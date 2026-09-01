import XCTest
@testable import BuilderCore

final class DomainModelsTests: XCTestCase {
    func testHostSnapshotReadinessUsesBlockingChecks() {
        let ready = SetupCheck(id: "xcode", title: "Xcode", detail: "26.0", status: .ready)
        let warning = SetupCheck(id: "codex", title: "Codex", detail: "Demo provider", status: .warning)
        let unavailable = SetupCheck(id: "signing", title: "Signing", detail: "Missing", status: .unavailable)

        XCTAssertTrue(HostSnapshot(hostName: "Mac", checks: [ready, warning]).isReady)

        let blocked = HostSnapshot(hostName: "Mac", checks: [ready, unavailable])
        XCTAssertFalse(blocked.isReady)
        XCTAssertEqual(blocked.blockingChecks, [unavailable])
    }

    func testEmptySetupIsNotReady() {
        XCTAssertFalse(HostSnapshot(hostName: "Mac", checks: []).isReady)
    }

    func testCreateProjectValidation() {
        XCTAssertTrue(
            CreateProjectRequest(
                name: "Mood Log",
                bundleIdentifier: "dev.buberlo.mood-log"
            ).isValid
        )
        XCTAssertFalse(CreateProjectRequest(name: " ", bundleIdentifier: "invalid").isValid)
        XCTAssertFalse(CreateProjectRequest(name: "Test", bundleIdentifier: "dev..test").isValid)
        XCTAssertFalse(CreateProjectRequest(name: "Test", bundleIdentifier: "1dev.test").isValid)
    }

    func testPromptRequiresVisibleText() {
        let projectID = UUID()
        XCTAssertFalse(PromptRequest(projectID: projectID, text: "\n  ").isValid)
        XCTAssertTrue(PromptRequest(projectID: projectID, text: "Add a timer").isValid)
    }

    func testRunStateHelpers() {
        XCTAssertTrue(RunState.building.isActive)
        XCTAssertFalse(RunState.building.isTerminal)
        XCTAssertTrue(RunState.succeeded.isTerminal)
        XCTAssertFalse(RunState.succeeded.isActive)
        XCTAssertEqual(RunState.installing.displayName, "Installing")
    }

    func testBuildProgressIsClamped() {
        let projectID = UUID()
        let over = BuildEvent(
            projectID: projectID,
            kind: .progress,
            phase: .building,
            message: "Compiling",
            progress: 1.4
        )
        let under = BuildEvent(
            projectID: projectID,
            kind: .progress,
            phase: .building,
            message: "Starting",
            progress: -0.2
        )

        XCTAssertEqual(over.progress, 1)
        XCTAssertEqual(under.progress, 0)
    }
}
