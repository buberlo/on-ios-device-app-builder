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
        connect(store)

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

    @Test("Creating while disconnected returns a visible error and changes nothing")
    func createProjectRequiresMacConnection() throws {
        let store = PhoneBuilderStore(configuration: .uiTesting)

        let result = store.createProject(
            name: "Offline App",
            bundleIdentifier: "dev.example.offline-app",
            prompt: "Keep this draft"
        )

        guard case let .failure(error) = result else {
            Issue.record("Expected project creation to fail while disconnected")
            return
        }
        #expect(error.title == "Connect your Mac first")
        #expect(store.projects.isEmpty)
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
        #expect(store.setup.deploymentDevices.count == 2)
        #expect(store.setup.selectedDeploymentDevice?.kind == .iPad)
        #expect(store.setup.isReadyToBuild)
    }

    @Test("Install uses the explicitly selected ready device")
    func installTargetSelection() async throws {
        let store = makeProjectStore()
        let mac = try #require(store.setup.discoveredMacs.first)
        store.connect(to: mac)
        let projectID = try #require(store.projects.first?.id)
        let iPad = try #require(store.setup.deploymentDevices.first(where: { $0.kind == .iPad }))

        await store.install(projectID: projectID, deviceID: iPad.id)

        #expect(store.setup.selectedDeploymentDeviceID == iPad.id)
        #expect(store.events(for: projectID).last?.detail.contains(iPad.name) == true)
        #expect(store.project(id: projectID)?.runState == .succeeded)
    }

    @Test("Install rejects a device that needs newer Xcode")
    func rejectsUnsupportedDevice() async throws {
        let store = makeProjectStore()
        let mac = try #require(store.setup.discoveredMacs.first)
        store.connect(to: mac)
        let projectID = try #require(store.projects.first?.id)
        let iPhone = try #require(store.setup.deploymentDevices.first(where: { $0.kind == .iPhone }))

        await store.install(projectID: projectID, deviceID: iPhone.id)

        #expect(store.alert?.title == "Device not ready")
        #expect(store.alert?.message.contains("newer Xcode") == true)
        #expect(store.project(id: projectID)?.runState == .idle)
    }

    @Test("Deleting a project clears its presentation data")
    func deleteProject() throws {
        let store = makeProjectStore()
        let projectID = try #require(store.projects.first?.id)

        store.deleteProject(projectID)

        #expect(store.project(id: projectID) == nil)
        #expect(store.messages(for: projectID).isEmpty)
        #expect(store.events(for: projectID).isEmpty)
    }

    @Test("Deleting while disconnected preserves the project and shows an error")
    func deleteProjectRequiresMacConnection() throws {
        let store = makeProjectStore()
        let projectID = try #require(store.projects.first?.id)
        store.disconnect()

        store.deleteProject(projectID)

        #expect(store.project(id: projectID) != nil)
        #expect(store.alert?.title == "Connect your Mac first")
    }

    private func makeProjectStore() -> PhoneBuilderStore {
        let store = PhoneBuilderStore(configuration: .uiTesting)
        connect(store)
        store.createProject(
            name: "Focus Timer",
            bundleIdentifier: "dev.example.focus-timer",
            prompt: ""
        )
        return store
    }

    private func connect(_ store: PhoneBuilderStore) {
        guard let mac = store.setup.discoveredMacs.first else { return }
        store.connect(to: mac)
    }
}
