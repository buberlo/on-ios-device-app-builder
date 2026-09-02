import BuilderCore
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class PhoneBuilderStore {
    enum Configuration: Equatable, Sendable {
        case live
        case demo
        case uiTesting
        case preview
    }

    var selectedTab: BuilderAppTab = .projects
    var presentedSheet: BuilderSheet?
    var alert: AppAlert?
    var projects: [AppProject] = []
    var messagesByProject: [UUID: [AppChatMessage]] = [:]
    var activity: [AppBuildEvent] = []
    var setup = AppSetupState(
        connectionState: .discovering,
        discoveredMacs: [],
        connectedMac: nil,
        checks: [],
        deploymentDevices: [],
        selectedDeploymentDeviceID: nil
    )

    @ObservationIgnored private let configuration: Configuration
    @ObservationIgnored private let client: NearbyBuilderClient
    @ObservationIgnored private var transportMirrorTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var snapshotRequestedForHostID: String?

    init(
        configuration: Configuration,
        client: NearbyBuilderClient? = nil
    ) {
        self.configuration = configuration
        self.client = client ?? NearbyBuilderClient(displayName: UIDevice.current.name)

        switch configuration {
        case .live:
            break
        case .uiTesting:
            bootstrapUITesting()
        case .demo, .preview:
            bootstrapDemo()
        }
    }

    static func makeForCurrentProcess() -> PhoneBuilderStore {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing") {
            return PhoneBuilderStore(configuration: .uiTesting)
        }
        if arguments.contains("-demo-mode") {
            return PhoneBuilderStore(configuration: .demo)
        }
        return PhoneBuilderStore(configuration: .live)
    }

    static func preview() -> PhoneBuilderStore {
        PhoneBuilderStore(configuration: .preview)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        guard configuration == .live else { return }

        client.onEvent = { [weak self] event in
            self?.receive(event)
        }
        client.start()
        syncTransportState()

        transportMirrorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.syncTransportState()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func project(id: UUID) -> AppProject? {
        projects.first(where: { $0.id == id })
    }

    func messages(for projectID: UUID) -> [AppChatMessage] {
        messagesByProject[projectID, default: []]
    }

    func events(for projectID: UUID) -> [AppBuildEvent] {
        activity.filter { $0.projectID == projectID }
    }

    func connect(to mac: AppMac) {
        if configuration != .live {
            setup.connectionState = .connecting
            setup.connectedMac = mac
            completeDemoConnection(to: mac)
            return
        }

        guard let peer = client.discoveredHosts.first(where: { $0.id == mac.id }) else {
            alert = AppAlert(title: "Mac unavailable", message: "Refresh Setup and choose the Mac again.")
            return
        }
        client.connect(to: peer)
        syncTransportState()
    }

    func disconnect() {
        if configuration == .live {
            client.disconnect()
        }
        snapshotRequestedForHostID = nil
        setup.connectionState = .disconnected
        setup.connectedMac = nil
        setup.checks = []
        setup.deploymentDevices = []
        setup.selectedDeploymentDeviceID = nil
        appendEvent(
            kind: .connection,
            title: "Mac disconnected",
            detail: "Build requests are paused until you reconnect."
        )
    }

    func refreshSetup() {
        if configuration == .live {
            syncTransportState()
            requestSnapshot()
        } else if let mac = setup.connectedMac {
            completeDemoConnection(to: mac)
        }
    }

    func requestSnapshot() {
        guard configuration == .live else { return }
        send(.requestSnapshot, errorTitle: "Could not refresh")
    }

    func createProject(name: String, bundleIdentifier: String, prompt: String) {
        let request = CreateProjectRequest(
            name: name,
            bundleIdentifier: bundleIdentifier,
            prompt: prompt
        )
        guard request.isValid else {
            alert = AppAlert(
                title: "Check the project details",
                message: request.validationIssues.joined(separator: "\n")
            )
            return
        }

        if configuration == .live {
            send(.createProject(request), errorTitle: "Could not create project")
            return
        }

        let project = AppProject(
            id: UUID(),
            name: request.name,
            bundleIdentifier: request.bundleIdentifier,
            updatedAt: Date(),
            runState: .idle
        )
        projects.insert(project, at: 0)
        appendEvent(
            projectID: project.id,
            kind: .project,
            title: "Project created",
            detail: "\(project.name) is ready for its first change."
        )

        messagesByProject[project.id] = [
            AppChatMessage(
                id: UUID(),
                projectID: project.id,
                role: .assistant,
                text: "Project ready. Describe a change, then tap Build when it looks right.",
                createdAt: Date()
            ),
        ]

        if !request.prompt.isEmpty {
            Task { await sendPrompt(request.prompt, projectID: project.id) }
        }
    }

    func sendPrompt(_ text: String, projectID: UUID) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if configuration == .live {
            send(
                .sendPrompt(PromptRequest(projectID: projectID, text: trimmed)),
                errorTitle: "Could not send prompt"
            )
            return
        }

        appendMessage(
            AppChatMessage(
                id: UUID(),
                projectID: projectID,
                role: .user,
                text: trimmed,
                createdAt: Date()
            )
        )
        setRunState(.planning, projectID: projectID)
        appendEvent(
            projectID: projectID,
            kind: .planning,
            title: "Change planned",
            detail: "Builder converted your prompt into an implementation plan.",
            progress: 0.15
        )

        if configuration == .demo {
            try? await Task.sleep(for: .milliseconds(180))
        } else {
            await Task.yield()
        }

        appendMessage(
            AppChatMessage(
                id: UUID(),
                projectID: projectID,
                role: .assistant,
                text: "I’ve prepared the SwiftUI change and kept it inside the project’s allowed workspace. Tap Build to compile it on your Mac.",
                createdAt: Date()
            )
        )
        setRunState(.idle, projectID: projectID)
    }

    func build(projectID: UUID) async {
        if configuration == .live {
            send(.buildProject(projectID), errorTitle: "Could not start build")
            return
        }

        await runDemoPhases(
            projectID: projectID,
            phases: [
                (.planning, .planning, "Planning", "Checking the requested change", 0.12),
                (.generating, .code, "Generating", "Writing compile-safe SwiftUI files", 0.38),
                (.building, .build, "Building", "Xcode is compiling and signing the app", 0.76),
                (.succeeded, .success, "Build succeeded", "The signed app is ready to install", 1.0),
            ]
        )
    }

    func selectDeploymentDevice(_ deviceID: String) {
        guard setup.deploymentDevices.contains(where: { $0.id == deviceID }) else { return }
        setup.selectedDeploymentDeviceID = deviceID
    }

    func install(projectID: UUID, deviceID: String? = nil) async {
        let targetID = deviceID ?? setup.selectedDeploymentDeviceID
        guard let targetID,
              let device = setup.deploymentDevices.first(where: { $0.id == targetID }) else {
            alert = AppAlert(title: "Choose an install target", message: "Open Setup and select an available iPhone or iPad.")
            return
        }
        guard device.isReadyForInstallation else {
            alert = AppAlert(title: "Device not ready", message: device.statusDetail)
            return
        }
        setup.selectedDeploymentDeviceID = targetID

        if configuration == .live {
            send(
                .installProject(InstallProjectRequest(projectID: projectID, deviceID: targetID)),
                errorTitle: "Could not start installation"
            )
            return
        }

        await runDemoPhases(
            projectID: projectID,
            phases: [
                (.installing, .install, "Installing", "Sending the signed app to \(device.name)", 0.8),
                (.succeeded, .success, "App installed", "The latest build is now on \(device.name)", 1.0),
            ]
        )
    }

    func cancelActiveRun() {
        for project in projects where project.runState.isRunning {
            if configuration == .live {
                send(.cancelRun(project.id), errorTitle: "Could not cancel run")
            } else {
                setRunState(.cancelled, projectID: project.id)
                appendEvent(
                    projectID: project.id,
                    kind: .error,
                    title: "Run cancelled",
                    detail: "No build or installation is still running."
                )
            }
        }
    }

    static func bundleComponent(from name: String) -> String {
        let mapped = name.lowercased().map { character -> Character in
            if character.isASCII, character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        var value = String(mapped)
        while value.contains("--") {
            value = value.replacingOccurrences(of: "--", with: "-")
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if value.first?.isLetter != true {
            value = "app-\(value)"
        }
        return String((value.isEmpty ? "app" : value).prefix(40))
    }

    private func runDemoPhases(
        projectID: UUID,
        phases: [(AppRunState, AppEventKind, String, String, Double)]
    ) async {
        for (state, kind, title, detail, progress) in phases {
            guard !Task.isCancelled else { return }
            setRunState(state, projectID: projectID)
            appendEvent(
                projectID: projectID,
                kind: kind,
                title: title,
                detail: detail,
                progress: progress
            )
            if configuration == .demo {
                try? await Task.sleep(for: .milliseconds(140))
            } else {
                await Task.yield()
            }
        }
    }

    private func receive(_ event: HostEvent) {
        switch event {
        case let .snapshot(snapshot):
            apply(snapshot)
        case let .projectCreated(project):
            upsert(project: AppProject(project))
            appendEvent(
                projectID: project.id,
                kind: .project,
                title: "Project created",
                detail: "\(project.name) was created on the Mac."
            )
        case let .chatMessage(message):
            appendMessage(AppChatMessage(message), deduplicateEcho: true)
        case let .runState(update):
            setRunState(AppRunState(update.state), projectID: update.projectID)
            if let message = update.message {
                appendEvent(
                    projectID: update.projectID,
                    kind: AppEventKind(update.state),
                    title: AppRunState(update.state).title,
                    detail: message
                )
            }
        case let .buildEvent(event):
            appendEvent(AppBuildEvent(event))
        case let .error(error):
            alert = AppAlert(title: "Builder Host", message: error.message)
            appendEvent(
                projectID: error.projectID,
                kind: .error,
                title: "Host error",
                detail: error.message
            )
        }
    }

    private func apply(_ snapshot: HostSnapshot) {
        setup.connectedMac = AppMac(
            id: client.connectedHost?.id ?? snapshot.hostName,
            name: snapshot.hostName,
            detail: "Builder Host"
        )
        setup.connectionState = .connected
        setup.checks = snapshot.checks.map(AppSetupCheck.init)
        let previousSelection = setup.selectedDeploymentDeviceID
        setup.deploymentDevices = snapshot.deploymentDevices.map(AppDeploymentDevice.init)
        if let previousSelection,
           setup.deploymentDevices.contains(where: { $0.id == previousSelection }) {
            setup.selectedDeploymentDeviceID = previousSelection
        } else {
            setup.selectedDeploymentDeviceID = setup.deploymentDevices.first(where: \.isReadyForInstallation)?.id
                ?? setup.deploymentDevices.first?.id
        }
        projects = snapshot.projects.map(AppProject.init).sorted { $0.updatedAt > $1.updatedAt }
    }

    private func syncTransportState() {
        let previousState = setup.connectionState
        setup.connectionState = AppConnectionState(client.connectionState)
        setup.discoveredMacs = client.discoveredHosts.map {
            AppMac(id: $0.id, name: $0.displayName, detail: "Nearby Builder Host")
        }
        setup.connectedMac = client.connectedHost.map {
            AppMac(id: $0.id, name: $0.displayName, detail: "Encrypted local connection")
        }

        if let error = client.lastError, !error.isEmpty {
            alert = AppAlert(title: "Connection failed", message: error)
        }

        guard client.connectionState == .connected, let host = client.connectedHost else {
            if previousState == .connected {
                snapshotRequestedForHostID = nil
            }
            return
        }

        guard snapshotRequestedForHostID != host.id else { return }
        snapshotRequestedForHostID = host.id
        appendEvent(
            kind: .connection,
            title: "Mac connected",
            detail: "Encrypted session with \(host.displayName) is active."
        )
        requestSnapshot()
    }

    private func send(_ command: ClientCommand, errorTitle: String) {
        do {
            try client.send(command)
        } catch {
            alert = AppAlert(title: errorTitle, message: error.localizedDescription)
        }
    }

    private func upsert(project: AppProject) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.insert(project, at: 0)
        }
    }

    private func setRunState(_ state: AppRunState, projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].runState = state
        projects[index].updatedAt = Date()
    }

    private func appendMessage(_ message: AppChatMessage, deduplicateEcho: Bool = false) {
        if deduplicateEcho,
           let last = messagesByProject[message.projectID]?.last,
           last.role == message.role,
           last.text == message.text
        {
            return
        }
        messagesByProject[message.projectID, default: []].append(message)
    }

    private func appendEvent(
        projectID: UUID? = nil,
        kind: AppEventKind,
        title: String,
        detail: String,
        progress: Double? = nil
    ) {
        appendEvent(
            AppBuildEvent(
                id: UUID(),
                projectID: projectID,
                timestamp: Date(),
                kind: kind,
                title: title,
                detail: detail,
                progress: progress
            )
        )
    }

    private func appendEvent(_ event: AppBuildEvent) {
        guard !activity.contains(where: { $0.id == event.id }) else { return }
        activity.append(event)
    }

    private func bootstrapUITesting() {
        setup = AppSetupState(
            connectionState: .disconnected,
            discoveredMacs: [AppMac(id: "ui-test-mac", name: "Test Mac", detail: "Nearby Builder Host")],
            connectedMac: nil,
            checks: [],
            deploymentDevices: [],
            selectedDeploymentDeviceID: nil
        )
    }

    private func bootstrapDemo() {
        let projectID = UUID(uuidString: "F3ACDE2A-44AB-47C1-8C5F-6774043F05A2")!
        let mac = AppMac(id: "demo-mac", name: "Konrad’s MacBook", detail: "Nearby Builder Host")
        let demoDevices = Self.demoDevices
        setup = AppSetupState(
            connectionState: .connected,
            discoveredMacs: [mac],
            connectedMac: mac,
            checks: Self.readyChecks,
            deploymentDevices: demoDevices,
            selectedDeploymentDeviceID: demoDevices.first?.id
        )
        projects = [
            AppProject(
                id: projectID,
                name: "Pocket Tasks",
                bundleIdentifier: "dev.example.pocket-tasks",
                updatedAt: Date(),
                runState: .idle
            ),
        ]
        messagesByProject[projectID] = [
            AppChatMessage(
                id: UUID(),
                projectID: projectID,
                role: .user,
                text: "Build a focused daily task list.",
                createdAt: Date().addingTimeInterval(-120)
            ),
            AppChatMessage(
                id: UUID(),
                projectID: projectID,
                role: .assistant,
                text: "The first SwiftUI screen is ready. Build it when you want to test it on-device.",
                createdAt: Date().addingTimeInterval(-90)
            ),
        ]
        appendEvent(
            projectID: projectID,
            kind: .project,
            title: "Project ready",
            detail: "Pocket Tasks is ready to build."
        )
    }

    private func completeDemoConnection(to mac: AppMac) {
        setup.connectionState = .connected
        setup.connectedMac = mac
        setup.checks = Self.readyChecks
        setup.deploymentDevices = Self.demoDevices
        setup.selectedDeploymentDeviceID = Self.demoDevices.first?.id
        appendEvent(
            kind: .connection,
            title: "Mac connected",
            detail: "Encrypted demo session with \(mac.name) is active."
        )
    }

    private static let readyChecks = [
        AppSetupCheck(id: "xcode", title: "Xcode 26", detail: "Installed and selected", state: .ready),
        AppSetupCheck(id: "signing", title: "Apple signing", detail: "Development certificate available", state: .ready),
        AppSetupCheck(id: "codex", title: "Codex CLI", detail: "Demo provider ready", state: .warning),
        AppSetupCheck(id: "device", title: "Deployment devices", detail: "iPad and iPhone paired over Wi-Fi", state: .ready),
    ]

    private static let demoDevices = [
        AppDeploymentDevice(
            id: "demo-ipad",
            name: "Konrad’s iPad",
            kind: .iPad,
            operatingSystem: "26.6",
            connection: "Wi-Fi",
            developerModeEnabled: true,
            isSupportedByXcode: true
        ),
        AppDeploymentDevice(
            id: "demo-iphone",
            name: "Konrad’s iPhone",
            kind: .iPhone,
            operatingSystem: "27.0",
            connection: "Wi-Fi",
            developerModeEnabled: true,
            isSupportedByXcode: false
        ),
    ]
}

private extension AppProject {
    init(_ project: ProjectSummary) {
        self.init(
            id: project.id,
            name: project.name,
            bundleIdentifier: project.bundleIdentifier,
            updatedAt: project.updatedAt,
            runState: AppRunState(project.runState)
        )
    }
}

private extension AppRunState {
    init(_ state: RunState) {
        switch state {
        case .idle: self = .idle
        case .planning: self = .planning
        case .generating: self = .generating
        case .building: self = .building
        case .installing: self = .installing
        case .succeeded: self = .succeeded
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        }
    }
}

private extension AppChatMessage {
    init(_ message: ChatMessage) {
        let role: AppChatRole = switch message.role {
        case .user: .user
        case .assistant: .assistant
        case .system: .system
        }
        self.init(
            id: message.id,
            projectID: message.projectID,
            role: role,
            text: message.text,
            createdAt: message.createdAt
        )
    }
}

private extension AppBuildEvent {
    init(_ event: BuildEvent) {
        let kind: AppEventKind
        switch event.kind {
        case .succeeded: kind = .success
        case .failed: kind = .error
        case .started, .progress, .log: kind = AppEventKind(event.phase)
        }
        self.init(
            id: event.id,
            projectID: event.projectID,
            timestamp: event.timestamp,
            kind: kind,
            title: AppRunState(event.phase).title,
            detail: event.message,
            progress: event.progress
        )
    }
}

private extension AppSetupCheck {
    init(_ check: SetupCheck) {
        let state: AppCheckState = switch check.status {
        case .ready: .ready
        case .warning: .warning
        case .unavailable: .unavailable
        }
        self.init(id: check.id, title: check.title, detail: check.detail, state: state)
    }
}

private extension AppDeploymentDevice {
    init(_ device: DeploymentDevice) {
        self.init(
            id: device.id,
            name: device.name,
            kind: device.kind == .iPad ? .iPad : .iPhone,
            operatingSystem: device.operatingSystem,
            connection: device.connection,
            developerModeEnabled: device.developerModeEnabled,
            isSupportedByXcode: device.isSupportedByXcode
        )
    }
}

private extension AppConnectionState {
    init(_ state: NearbyConnectionState) {
        switch state {
        case .browsing, .advertising: self = .discovering
        case .idle, .disconnected, .failed: self = .disconnected
        case .connecting: self = .connecting
        case .connected: self = .connected
        }
    }
}

private extension AppEventKind {
    init(_ state: RunState) {
        switch state {
        case .idle: self = .project
        case .planning: self = .planning
        case .generating: self = .code
        case .building: self = .build
        case .installing: self = .install
        case .succeeded: self = .success
        case .failed, .cancelled: self = .error
        }
    }
}
