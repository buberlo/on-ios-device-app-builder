import Foundation

public enum ClientCommand: Codable, Hashable, Sendable {
    case requestSnapshot
    case createProject(CreateProjectRequest)
    case sendPrompt(PromptRequest)
    case buildProject(UUID)
    case installProject(InstallProjectRequest)
    case cancelRun(UUID)
}

public enum HostEvent: Codable, Hashable, Sendable {
    case snapshot(HostSnapshot)
    case projectCreated(ProjectSummary)
    case chatMessage(ChatMessage)
    case runState(ProjectRunUpdate)
    case buildEvent(BuildEvent)
    case error(BuilderErrorPayload)
}

public enum BuilderWireProtocol {
    public static let version = 2
    public static let serviceType = "phonebuilder"
}

public struct WireEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let version: Int
    public let messageID: UUID
    public let sentAt: Date
    public let payload: Payload

    public init(
        version: Int = BuilderWireProtocol.version,
        messageID: UUID = UUID(),
        sentAt: Date = Date(),
        payload: Payload
    ) {
        self.version = version
        self.messageID = messageID
        self.sentAt = sentAt
        self.payload = payload
    }
}

public enum WireProtocolError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedVersion(received: Int, supported: Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(received, supported):
            "Unsupported protocol version \(received). This app supports version \(supported)."
        }
    }
}

public enum WireCodec {
    public static func encode<Payload: Codable & Sendable>(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(WireEnvelope(payload: payload))
    }

    public static func decode<Payload: Codable & Sendable>(
        _ payloadType: Payload.Type,
        from data: Data
    ) throws -> WireEnvelope<Payload> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(WireEnvelope<Payload>.self, from: data)

        guard envelope.version == BuilderWireProtocol.version else {
            throw WireProtocolError.unsupportedVersion(
                received: envelope.version,
                supported: BuilderWireProtocol.version
            )
        }

        return envelope
    }
}
