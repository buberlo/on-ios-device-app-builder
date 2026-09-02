import Foundation

enum HostCheckKind: String, CaseIterable, Codable, Sendable {
    case xcode
    case signing
    case tuist
    case codex
    case device

    var title: String {
        switch self {
        case .xcode: "Xcode"
        case .signing: "Development certificate"
        case .tuist: "Tuist"
        case .codex: "Codex CLI"
        case .device: "Deployment devices"
        }
    }
}

enum HostCheckStatus: String, Codable, Sendable {
    case ready
    case warning
    case unavailable
}

struct HostCheckResult: Identifiable, Codable, Equatable, Sendable {
    let kind: HostCheckKind
    let status: HostCheckStatus
    let detail: String

    var id: String { kind.rawValue }
}

enum HostProjectStatus: String, Codable, Sendable {
    case idle
    case planning
    case generating
    case building
    case installing
    case succeeded
    case failed
    case cancelled
}

struct HostProjectRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    let slug: String
    let bundleIdentifier: String
    var prompt: String
    let createdAt: Date
    var updatedAt: Date
    var status: HostProjectStatus
    var lastBuiltAppPath: String?
}

enum HostActivityKind: String, Codable, Sendable {
    case connection
    case request
    case plan
    case build
    case install
    case success
    case failure
}

struct HostActivity: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let kind: HostActivityKind
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: HostActivityKind,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.message = message
    }
}

struct PrototypeBuildProgress: Equatable, Sendable {
    enum Phase: String, Sendable {
        case preparing
        case generating
        case building
        case installing
        case launching
        case finished
    }

    let phase: Phase
    let message: String
    let fraction: Double?
}

struct PrototypeBuildResult: Equatable, Sendable {
    let appURL: URL
    let installedDeviceName: String?
}
