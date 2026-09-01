import Foundation
import Testing
@testable import PhoneBuilder

@MainActor
@Suite("Phone Builder store")
struct PhoneBuilderStoreTests {
    @Test("Bundle names become valid deterministic components")
    func bundleComponent() {
        #expect(PhoneBuilderStore.bundleComponent(from: "Focus Timer") == "focus-timer")
        #expect(PhoneBuilderStore.bundleComponent(from: " 123 ") == "app-123")
        #expect(PhoneBuilderStore.bundleComponent(from: "Über App") == "ber-app")
    }

    @Test("Creating a project updates projects and activity")
    func createProject() {
        let store = PhoneBuilderStore(configuration: .uiTesting)

        store.createProject(
            name: "Focus Timer",
            bundleIdentifier: "dev.example.focus-timer",
            prompt: ""
        )

        #expect(store.projects.count == 1)
        #expect(store.projects[0].name == "Focus Timer")
        #expect(store.messages(for: store.projects[0].id).count == 1)
        #expect(store.activity.last?.kind == .project)
    }

    @Test("A prompt adds both sides of the conversation")
    func promptFlow() async throws {
        let store = makeProjectStore()
        let projectID = try #require(store.projects.first?.id)

        await store.sendPrompt("Add a countdown ring", projectID: projectID)

        let messages = store.messages(for: projectID)
        #expect(messages.count == 3)
        #expect(messages.suffix(2).map(\.role) == [.user, .assistant])
        #expect(store.project(id: projectID)?.runState == .idle)
    }

    @Test("Build flow reaches a successful terminal state")
    func buildFlow() async throws {
        let store = makeProjectStore()
        let projectID = try #require(store.projects.first?.id)

        await store.build(projectID: projectID)

        #expect(store.project(id: projectID)?.runState == .succeeded)
        #expect(store.events(for: projectID).contains(where: { $0.kind == .build }))
        #expect(store.events(for: projectID).last?.kind == .success)
    }

    @Test("Connecting the demo Mac exposes readiness checks")
    func connectionFlow() throws {
        let store = PhoneBuilderStore(configuration: .uiTesting)
        let mac = try #require(store.setup.discoveredMacs.first)

        store.connect(to: mac)

        #expect(store.setup.connectionState == .connected)
        #expect(store.setup.connectedMac?.name == "Test Mac")
        #expect(store.setup.checks.count == 4)
        #expect(store.setup.isReadyToBuild)
    }

    private func makeProjectStore() -> PhoneBuilderStore {
        let store = PhoneBuilderStore(configuration: .uiTesting)
        store.createProject(
            name: "Focus Timer",
            bundleIdentifier: "dev.example.focus-timer",
            prompt: ""
        )
        return store
    }
}
