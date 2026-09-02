import AppKit
import BuilderCore
import Foundation
import Observation

@MainActor
@Observable
final class HostStore {
    let nearbyHost: NearbyBuilderHost

    private(set) var checks: [HostCheckResult] = []
    private(set) var devices: [DeploymentDevice] = []
    private(set) var projects: [HostProjectRecord] = []
    private(set) var activities: [HostActivity] = []
    private(set) var isRefreshing = false
    private(set) var started = false

    @ObservationIgnored private let diagnostics: HostDiagnostics
    @ObservationIgnored private let workspace: WorkspaceService
    @ObservationIgnored private let generator: PrototypeGenerator
    @ObservationIgnored private let codex: CodexService
    @ObservationIgnored private let pipeline: PrototypeBuildPipeline
    @ObservationIgnored private var runTasks: [UUID: Task<Void, Never>] = [:]

    init(
        nearbyHost: NearbyBuilderHost,
        diagnostics: HostDiagnostics,
        workspace: WorkspaceService,
        generator: PrototypeGenerator,
        codex: CodexService,
        pipeline: PrototypeBuildPipeline
    ) {
        self.nearbyHost = nearbyHost
        self.diagnostics = diagnostics
        self.workspace = workspace
        self.generator = generator
        self.codex = codex
        self.pipeline = pipeline

        nearbyHost.onCommand = { [weak self] command, peer in
            self?.receive(command, from: peer)
        }
    }

    static func live() -> HostStore {
        let diagnosticsRunner = AllowlistedCommandRunner()
        let codexRunner = AllowlistedCommandRunner()
        let buildRunner = AllowlistedCommandRunner()
        let workspace: WorkspaceService
        do {
            workspace = try WorkspaceService()
        } catch {
            let fallback = FileManager.default.temporaryDirectory
                .appending(path: "BuilderHost-Projects", directoryHint: .isDirectory)
            workspace = try! WorkspaceService(rootURL: fallback)
        }
        return HostStore(
            nearbyHost: NearbyBuilderHost(displayName: Host.current().localizedName ?? "Builder Host"),
            diagnostics: HostDiagnostics(runner: diagnosticsRunner),
            workspace: workspace,
            generator: PrototypeGenerator(),
            codex: CodexService(runner: codexRunner),
            pipeline: PrototypeBuildPipeline(runner: buildRunner)
        )
    }

    var statusTitle: String {
        switch nearbyHost.connectionState {
        case .idle: "Stopped"
        case .advertising: "Ready for iPhone or iPad"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .failed: "Needs attention"
        case .browsing: "Searching"
        }
    }

    var menuBarSymbol: String {
        nearbyHost.connectedPeers.isEmpty ? "hammer" : "hammer.fill"
    }

    func start() async {
        guard !started else { return }
        started = true
        nearbyHost.start()
        addActivity(.connection, "Encrypted nearby host started")
        await refresh()
    }

    func stop() {
        runTasks.values.forEach { $0.cancel() }
        runTasks.removeAll()
        nearbyHost.stop()
        started = false
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let snapshot = diagnostics.inspect()
        async let storedProjects = loadProjects()
        let (diagnosticSnapshot, loadedProjects) = await (snapshot, storedProjects)
        checks = diagnosticSnapshot.checks
        devices = diagnosticSnapshot.devices
        projects = loadedProjects
    }

    func openProjectsFolder() {
        Task {
            let url = await workspace.workspaceRootURL()
            NSWorkspace.shared.open(url)
        }
    }

    func receive(_ command: ClientCommand, from peer: NearbyPeer) {
        addActivity(.request, "\(peer.displayName): \(command.activityName)")
        switch command {
        case .requestSnapshot:
            sendSnapshot(to: peer)
            Task {
                await refresh()
                sendSnapshot(to: peer)
            }
        case let .createProject(request):
            createProject(request, for: peer)
        case let .deleteProject(projectID):
            deleteProject(projectID, for: peer)
        case let .sendPrompt(request):
            planPrompt(request, for: peer)
        case let .buildProject(projectID):
            buildProject(projectID, installOn: nil, for: peer)
        case let .installProject(request):
            installProject(request, for: peer)
        case let .cancelRun(projectID):
            cancelRun(projectID, for: peer)
        }
    }

    private func createProject(_ request: CreateProjectRequest, for peer: NearbyPeer) {
        guard request.isValid else {
            sendError(
                code: "invalid_project",
                message: request.validationIssues.joined(separator: " "),
                projectID: nil,
                to: peer
            )
            return
        }

        Task {
            do {
                let record = try await workspace.createProject(
                    name: request.name,
                    bundleIdentifier: request.bundleIdentifier,
                    prompt: request.prompt
                )
                let url = try await workspace.projectURL(for: record)
                try generator.generate(record, at: url)
                projects.insert(record, at: 0)
                addActivity(.success, "Created \(record.name)")
                send(.projectCreated(record.summary), to: peer)
                sendSnapshot(to: peer)
                if !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    planPrompt(PromptRequest(projectID: record.id, text: request.prompt), for: peer)
                }
            } catch {
                sendError(code: "create_failed", message: error.localizedDescription, projectID: nil, to: peer)
            }
        }
    }

    private func deleteProject(_ projectID: UUID, for peer: NearbyPeer) {
        guard runTasks[projectID] == nil else {
            sendError(
                code: "run_active",
                message: "Cancel the active run before deleting this project.",
                projectID: projectID,
                to: peer
            )
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.runTasks[projectID] = nil }
            do {
                let projectName = projects.first(where: { $0.id == projectID })?.name ?? "Project"
                try await workspace.deleteProject(id: projectID)
                projects.removeAll { $0.id == projectID }
                addActivity(.success, "Deleted \(projectName)")
                send(.projectDeleted(projectID), to: peer)
                sendSnapshot(to: peer)
            } catch {
                sendError(code: "delete_failed", message: error.localizedDescription, projectID: projectID, to: peer)
            }
        }
        runTasks[projectID] = task
    }

    private func planPrompt(_ request: PromptRequest, for peer: NearbyPeer) {
        guard request.isValid else {
            sendError(code: "invalid_prompt", message: "Prompt cannot be empty.", projectID: request.projectID, to: peer)
            return
        }
        guard runTasks[request.projectID] == nil else {
            sendError(code: "run_active", message: "This project already has an active run.", projectID: request.projectID, to: peer)
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.runTasks[request.projectID] = nil }
            do {
                var record = try await workspace.project(id: request.projectID)
                let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
                record.prompt = trimmed
                record.updatedAt = Date()
                record.status = .planning
                try await workspace.update(record)
                replaceProject(record)

                send(.chatMessage(ChatMessage(projectID: record.id, role: .user, text: trimmed)), to: peer)
                sendRunState(projectID: record.id, state: .planning, message: "Codex is planning the change", to: peer)
                addActivity(.plan, "Planning \(record.name)")

                let url = try await workspace.projectURL(for: record)
                let assistantText: String
                do {
                    let result = try await codex.run(prompt: trimmed, in: url) { [weak self] event in
                        guard event.kind != .assistantMessage else { return }
                        await MainActor.run {
                            self?.publishLog(
                                event.message,
                                projectID: request.projectID,
                                phase: .planning,
                                peer: peer
                            )
                        }
                    }
                    assistantText = result.assistantText ?? "Codex updated the prototype source. It is ready to build."
                } catch {
                    try generator.generate(record, at: url)
                    assistantText = Self.demoPlan(for: trimmed, failure: error)
                }

                try Task.checkCancellation()
                record.status = .idle
                record.updatedAt = Date()
                try await workspace.update(record)
                replaceProject(record)
                send(.chatMessage(ChatMessage(projectID: record.id, role: .assistant, text: assistantText)), to: peer)
                sendRunState(projectID: record.id, state: .idle, message: "Plan ready", to: peer)
            } catch is CancellationError {
                markCancelled(request.projectID, peer: peer)
            } catch {
                markFailed(request.projectID, error: error, peer: peer)
            }
        }
        runTasks[request.projectID] = task
    }

    private func buildProject(_ projectID: UUID, installOn selectedDevice: DeploymentDevice?, for peer: NearbyPeer) {
        guard runTasks[projectID] == nil else {
            sendError(code: "run_active", message: "This project already has an active run.", projectID: projectID, to: peer)
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.runTasks[projectID] = nil }
            do {
                var record = try await workspace.project(id: projectID)
                let url = try await workspace.projectURL(for: record)
                record.status = .generating
                record.updatedAt = Date()
                try await workspace.update(record)
                replaceProject(record)
                sendRunState(projectID: projectID, state: .generating, message: "Preparing build", to: peer)

                let result = try await pipeline.build(
                    project: record,
                    at: url,
                    installOn: selectedDevice
                ) { [weak self] progress in
                    await MainActor.run {
                        self?.publish(progress, projectID: projectID, peer: peer)
                    }
                }
                try Task.checkCancellation()
                record.status = .succeeded
                record.lastBuiltAppPath = result.appURL.path
                record.updatedAt = Date()
                try await workspace.update(record)
                replaceProject(record)
                let finalMessage = result.installedDeviceName.map { "Installed and launched on \($0)" } ?? "Signed app built successfully"
                send(.buildEvent(BuildEvent(projectID: projectID, kind: .succeeded, phase: .succeeded, message: finalMessage, progress: 1)), to: peer)
                sendRunState(projectID: projectID, state: .succeeded, message: finalMessage, to: peer)
                addActivity(.success, finalMessage)
            } catch is CancellationError {
                markCancelled(projectID, peer: peer)
            } catch {
                markFailed(projectID, error: error, peer: peer)
            }
        }
        runTasks[projectID] = task
    }

    private func installProject(_ request: InstallProjectRequest, for peer: NearbyPeer) {
        guard let device = devices.first(where: { $0.id == request.deviceID }) else {
            sendError(
                code: "device_unavailable",
                message: "The selected device is unavailable. Refresh Setup and choose it again.",
                projectID: request.projectID,
                to: peer
            )
            return
        }
        guard device.developerModeEnabled else {
            sendError(
                code: "developer_mode_disabled",
                message: "Enable Developer Mode on \(device.name), then refresh Setup.",
                projectID: request.projectID,
                to: peer
            )
            return
        }
        guard device.isSupportedByXcode else {
            sendError(
                code: "xcode_device_mismatch",
                message: "\(device.name) runs iOS \(device.operatingSystem), which requires a matching newer Xcode version.",
                projectID: request.projectID,
                to: peer
            )
            return
        }
        guard let record = projects.first(where: { $0.id == request.projectID }) else {
            sendError(code: "project_unavailable", message: "The project is unavailable on this Mac.", projectID: request.projectID, to: peer)
            return
        }
        guard let path = record.lastBuiltAppPath, FileManager.default.fileExists(atPath: path) else {
            buildProject(request.projectID, installOn: device, for: peer)
            return
        }
        guard runTasks[request.projectID] == nil else {
            sendError(code: "run_active", message: "This project already has an active run.", projectID: request.projectID, to: peer)
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.runTasks[request.projectID] = nil }
            do {
                try await pipeline.install(
                    appURL: URL(fileURLWithPath: path),
                    bundleIdentifier: record.bundleIdentifier,
                    on: device
                ) { [weak self] progress in
                    await MainActor.run {
                        self?.publish(progress, projectID: request.projectID, peer: peer)
                    }
                }
                var updatedRecord = record
                updatedRecord.status = .succeeded
                updatedRecord.updatedAt = Date()
                try await workspace.update(updatedRecord)
                replaceProject(updatedRecord)
                sendRunState(projectID: request.projectID, state: .succeeded, message: "Installed on \(device.name)", to: peer)
                addActivity(.success, "Installed \(record.name) on \(device.name)")
            } catch is CancellationError {
                markCancelled(request.projectID, peer: peer)
            } catch {
                markFailed(request.projectID, error: error, peer: peer)
            }
        }
        runTasks[request.projectID] = task
    }

    private func cancelRun(_ projectID: UUID, for peer: NearbyPeer) {
        runTasks[projectID]?.cancel()
        runTasks[projectID] = nil
        Task { await pipeline.cancel() }
        markCancelled(projectID, peer: peer)
    }

    private func publish(_ progress: PrototypeBuildProgress, projectID: UUID, peer: NearbyPeer) {
        let state = progress.phase.runState
        let kind: BuildEvent.Kind = progress.phase == .finished ? .succeeded : .progress
        send(
            .buildEvent(
                BuildEvent(
                    projectID: projectID,
                    kind: kind,
                    phase: state,
                    message: progress.message,
                    progress: progress.fraction
                )
            ),
            to: peer
        )
        sendRunState(projectID: projectID, state: state, message: progress.message, to: peer)
        addActivity(progress.phase == .installing || progress.phase == .launching ? .install : .build, progress.message)
    }

    private func publishLog(_ message: String, projectID: UUID, phase: RunState, peer: NearbyPeer) {
        let safeMessage = String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        guard !safeMessage.isEmpty else { return }
        send(
            .buildEvent(
                BuildEvent(
                    projectID: projectID,
                    kind: .log,
                    phase: phase,
                    message: safeMessage
                )
            ),
            to: peer
        )
        addActivity(phase == .planning ? .plan : .build, safeMessage)
    }

    private func sendSnapshot(to peer: NearbyPeer) {
        let snapshot = HostSnapshot(
            hostName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            checks: checks.map(\.setupCheck),
            deploymentDevices: devices,
            projects: projects.map(\.summary)
        )
        send(.snapshot(snapshot), to: peer)
    }

    private func sendRunState(projectID: UUID, state: RunState, message: String?, to peer: NearbyPeer) {
        send(.runState(ProjectRunUpdate(projectID: projectID, state: state, message: message)), to: peer)
    }

    private func sendError(code: String, message: String, projectID: UUID?, to peer: NearbyPeer) {
        send(.error(BuilderErrorPayload(code: code, message: String(message.prefix(600)), projectID: projectID)), to: peer)
        addActivity(.failure, String(message.prefix(180)))
    }

    private func send(_ event: HostEvent, to peer: NearbyPeer) {
        do {
            try nearbyHost.send(event, to: peer)
        } catch {
            addActivity(.failure, "Unable to send event: \(error.localizedDescription)")
        }
    }

    private func markCancelled(_ projectID: UUID, peer: NearbyPeer) {
        updateProjectState(projectID, status: .cancelled)
        sendRunState(projectID: projectID, state: .cancelled, message: "Run cancelled", to: peer)
        addActivity(.failure, "Run cancelled")
    }

    private func markFailed(_ projectID: UUID, error: Error, peer: NearbyPeer) {
        updateProjectState(projectID, status: .failed)
        send(
            .buildEvent(BuildEvent(projectID: projectID, kind: .failed, phase: .failed, message: String(error.localizedDescription.prefix(600)))),
            to: peer
        )
        sendRunState(projectID: projectID, state: .failed, message: error.localizedDescription, to: peer)
        sendError(code: "run_failed", message: error.localizedDescription, projectID: projectID, to: peer)
    }

    private func updateProjectState(_ projectID: UUID, status: HostProjectStatus) {
        guard var record = projects.first(where: { $0.id == projectID }) else { return }
        record.status = status
        record.updatedAt = Date()
        replaceProject(record)
        Task { try? await workspace.update(record) }
    }

    private func replaceProject(_ record: HostProjectRecord) {
        projects.removeAll { $0.id == record.id }
        projects.insert(record, at: 0)
    }

    private func loadProjects() async -> [HostProjectRecord] {
        (try? await workspace.projects()) ?? []
    }

    private func addActivity(_ kind: HostActivityKind, _ message: String) {
        activities.insert(HostActivity(kind: kind, message: message), at: 0)
        if activities.count > 50 { activities.removeLast(activities.count - 50) }
    }

    private static func demoPlan(for prompt: String, failure: Error) -> String {
        """
        Demo plan ready:
        1. Keep the existing signed SwiftUI prototype structure.
        2. Use “\(String(prompt.prefix(180)))” as the prototype brief.
        3. Build it on this Mac and install it on the selected iPhone or iPad.

        Live Codex editing was unavailable for this run (\(String(failure.localizedDescription.prefix(160)))).
        """
    }
}

private extension ClientCommand {
    var activityName: String {
        switch self {
        case .requestSnapshot: "requested setup snapshot"
        case .createProject: "requested a new project"
        case .deleteProject: "requested project deletion"
        case .sendPrompt: "sent a prompt"
        case .buildProject: "requested a build"
        case .installProject: "requested installation"
        case .cancelRun: "cancelled a run"
        }
    }
}

private extension HostCheckResult {
    var setupCheck: SetupCheck {
        SetupCheck(id: id, title: kind.title, detail: detail, status: status.coreStatus)
    }
}

private extension HostCheckStatus {
    var coreStatus: SetupCheck.Status {
        switch self {
        case .ready: .ready
        case .warning: .warning
        case .unavailable: .unavailable
        }
    }
}

private extension HostProjectRecord {
    var summary: ProjectSummary {
        ProjectSummary(
            id: id,
            name: name,
            bundleIdentifier: bundleIdentifier,
            createdAt: createdAt,
            updatedAt: updatedAt,
            runState: status.runState
        )
    }
}

private extension HostProjectStatus {
    var runState: RunState { RunState(rawValue: rawValue) ?? .idle }
}

private extension PrototypeBuildProgress.Phase {
    var runState: RunState {
        switch self {
        case .preparing, .generating: .generating
        case .building: .building
        case .installing, .launching: .installing
        case .finished: .succeeded
        }
    }
}
