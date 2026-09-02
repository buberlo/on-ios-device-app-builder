import Foundation

enum BuilderAppTab: String, CaseIterable, Identifiable, Sendable {
    case projects
    case activity
    case setup

    var id: Self { self }

    var title: String {
        switch self {
        case .projects: "Projects"
        case .activity: "Activity"
        case .setup: "Setup"
        }
    }

    var systemImage: String {
        switch self {
        case .projects: "square.stack.3d.up.fill"
        case .activity: "waveform.path.ecg"
        case .setup: "macbook.and.iphone"
        }
    }
}

enum BuilderSheet: Identifiable, Sendable {
    case createProject

    var id: String { "create-project" }
}

struct AppProject: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var bundleIdentifier: String
    var updatedAt: Date
    var runState: AppRunState
}

enum AppRunState: String, Hashable, Sendable {
    case idle
    case planning
    case generating
    case building
    case installing
    case succeeded
    case failed
    case cancelled

    var title: String {
        switch self {
        case .idle: "Ready"
        case .planning: "Planning"
        case .generating: "Writing code"
        case .building: "Building"
        case .installing: "Installing"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    var isRunning: Bool {
        switch self {
        case .planning, .generating, .building, .installing: true
        default: false
        }
    }
}

enum AppChatRole: String, Hashable, Sendable {
    case user
    case assistant
    case system
}

struct AppChatMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let projectID: UUID
    let role: AppChatRole
    let text: String
    let createdAt: Date
}

enum AppEventKind: String, Hashable, Sendable {
    case connection
    case project
    case planning
    case code
    case build
    case install
    case success
    case error
}

struct AppBuildEvent: Identifiable, Hashable, Sendable {
    let id: UUID
    let projectID: UUID?
    let timestamp: Date
    let kind: AppEventKind
    let title: String
    let detail: String
    let progress: Double?
}

enum AppConnectionState: String, Hashable, Sendable {
    case discovering
    case disconnected
    case connecting
    case connected

    var title: String {
        switch self {
        case .discovering: "Looking for your Mac"
        case .disconnected: "Mac not connected"
        case .connecting: "Connecting"
        case .connected: "Mac connected"
        }
    }
}

struct AppMac: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String
}

enum AppCheckState: Hashable, Sendable {
    case ready
    case warning
    case unavailable
    case checking
}

struct AppSetupCheck: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let state: AppCheckState
}

struct AppDeploymentDevice: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case iPhone
        case iPad
    }

    let id: String
    let name: String
    let kind: Kind
    let operatingSystem: String
    let connection: String
    let developerModeEnabled: Bool
    let isSupportedByXcode: Bool

    var isReadyForInstallation: Bool {
        developerModeEnabled && isSupportedByXcode
    }

    var systemImage: String {
        kind == .iPad ? "ipad" : "iphone"
    }

    var statusDetail: String {
        if !developerModeEnabled { return "Developer Mode is disabled" }
        if !isSupportedByXcode { return "Requires a matching newer Xcode" }
        return "iOS \(operatingSystem) · \(connection)"
    }
}

struct AppSetupState: Hashable, Sendable {
    var connectionState: AppConnectionState
    var discoveredMacs: [AppMac]
    var connectedMac: AppMac?
    var checks: [AppSetupCheck]
    var deploymentDevices: [AppDeploymentDevice]
    var selectedDeploymentDeviceID: String?

    var selectedDeploymentDevice: AppDeploymentDevice? {
        deploymentDevices.first { $0.id == selectedDeploymentDeviceID }
    }

    var readyCount: Int {
        checks.count(where: { $0.state == .ready })
    }

    var isReadyToBuild: Bool {
        connectionState == .connected
            && !checks.isEmpty
            && checks.allSatisfy { $0.state != .unavailable }
    }
}

struct AppAlert: Error, Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}
