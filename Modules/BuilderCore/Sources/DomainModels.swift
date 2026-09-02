import Foundation

public struct SetupCheck: Codable, Hashable, Identifiable, Sendable {
    public enum Status: String, Codable, CaseIterable, Sendable {
        case ready
        case warning
        case unavailable
    }

    public let id: String
    public let title: String
    public let detail: String
    public let status: Status

    public init(id: String, title: String, detail: String, status: Status) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
    }

    public var isBlocking: Bool {
        status == .unavailable
    }
}

public enum RunState: String, Codable, CaseIterable, Sendable {
    case idle
    case planning
    case generating
    case building
    case installing
    case succeeded
    case failed
    case cancelled

    public var isActive: Bool {
        switch self {
        case .planning, .generating, .building, .installing:
            true
        case .idle, .succeeded, .failed, .cancelled:
            false
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled:
            true
        case .idle, .planning, .generating, .building, .installing:
            false
        }
    }

    public var displayName: String {
        switch self {
        case .idle: "Ready"
        case .planning: "Planning"
        case .generating: "Generating"
        case .building: "Building"
        case .installing: "Installing"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

public struct ProjectSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var bundleIdentifier: String
    public let createdAt: Date
    public var updatedAt: Date
    public var runState: RunState

    public init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        runState: RunState = .idle
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.runState = runState
    }
}

public enum ChatRole: String, Codable, CaseIterable, Sendable {
    case user
    case assistant
    case system
}

public struct ChatMessage: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let role: ChatRole
    public let text: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        role: ChatRole,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public struct BuildEvent: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case started
        case progress
        case log
        case succeeded
        case failed
    }

    public let id: UUID
    public let projectID: UUID
    public let timestamp: Date
    public let kind: Kind
    public let phase: RunState
    public let message: String
    public let progress: Double?

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        timestamp: Date = Date(),
        kind: Kind,
        phase: RunState,
        message: String,
        progress: Double? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.timestamp = timestamp
        self.kind = kind
        self.phase = phase
        self.message = message
        self.progress = progress.map { min(max($0, 0), 1) }
    }
}

public enum DeploymentDeviceKind: String, Codable, Hashable, Sendable {
    case iPhone
    case iPad

    public var displayName: String { rawValue }
}

public struct DeploymentDevice: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: DeploymentDeviceKind
    public let operatingSystem: String
    public let connection: String
    public let developerModeEnabled: Bool
    public let isSupportedByXcode: Bool

    public init(
        id: String,
        name: String,
        kind: DeploymentDeviceKind,
        operatingSystem: String,
        connection: String,
        developerModeEnabled: Bool,
        isSupportedByXcode: Bool
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.operatingSystem = operatingSystem
        self.connection = connection
        self.developerModeEnabled = developerModeEnabled
        self.isSupportedByXcode = isSupportedByXcode
    }

    public var isReadyForInstallation: Bool {
        developerModeEnabled && isSupportedByXcode
    }
}

public struct HostSnapshot: Codable, Hashable, Sendable {
    public let hostName: String
    public let checkedAt: Date
    public let checks: [SetupCheck]
    public let deploymentDevices: [DeploymentDevice]
    public let projects: [ProjectSummary]

    public init(
        hostName: String,
        checkedAt: Date = Date(),
        checks: [SetupCheck],
        deploymentDevices: [DeploymentDevice] = [],
        projects: [ProjectSummary] = []
    ) {
        self.hostName = hostName
        self.checkedAt = checkedAt
        self.checks = checks
        self.deploymentDevices = deploymentDevices
        self.projects = projects
    }

    public var isReady: Bool {
        !checks.isEmpty && !checks.contains(where: \.isBlocking)
    }

    public var blockingChecks: [SetupCheck] {
        checks.filter(\.isBlocking)
    }
}

public struct InstallProjectRequest: Codable, Hashable, Sendable {
    public let projectID: UUID
    public let deviceID: String

    public init(projectID: UUID, deviceID: String) {
        self.projectID = projectID
        self.deviceID = deviceID
    }
}

public struct CreateProjectRequest: Codable, Hashable, Sendable {
    public let name: String
    public let bundleIdentifier: String
    public let prompt: String

    public init(name: String, bundleIdentifier: String, prompt: String = "") {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.prompt = prompt
    }

    public var validationIssues: [String] {
        var issues: [String] = []

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Project name is required.")
        }

        if !Self.isValidBundleIdentifier(bundleIdentifier) {
            issues.append("Bundle identifier must contain at least two dot-separated identifiers.")
        }

        return issues
    }

    public var isValid: Bool {
        validationIssues.isEmpty
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2 else { return false }

        return components.allSatisfy { component in
            guard let first = component.first, first.isASCII, first.isLetter else { return false }
            return component.allSatisfy { character in
                character.isASCII && (character.isLetter || character.isNumber || character == "-")
            }
        }
    }
}

public struct PromptRequest: Codable, Hashable, Sendable {
    public let projectID: UUID
    public let text: String

    public init(projectID: UUID, text: String) {
        self.projectID = projectID
        self.text = text
    }

    public var isValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct ProjectRunUpdate: Codable, Hashable, Sendable {
    public let projectID: UUID
    public let state: RunState
    public let message: String?

    public init(projectID: UUID, state: RunState, message: String? = nil) {
        self.projectID = projectID
        self.state = state
        self.message = message
    }
}

public struct BuilderErrorPayload: Codable, Error, Hashable, Sendable {
    public let code: String
    public let message: String
    public let projectID: UUID?
    public let isRecoverable: Bool

    public init(
        code: String,
        message: String,
        projectID: UUID? = nil,
        isRecoverable: Bool = true
    ) {
        self.code = code
        self.message = message
        self.projectID = projectID
        self.isRecoverable = isRecoverable
    }
}
