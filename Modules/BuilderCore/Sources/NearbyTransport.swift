@preconcurrency import MultipeerConnectivity
import Foundation
import Observation

public struct NearbyPeer: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public enum NearbyConnectionState: String, Codable, CaseIterable, Sendable {
    case idle
    case browsing
    case advertising
    case connecting
    case connected
    case disconnected
    case failed

    public var isConnected: Bool {
        self == .connected
    }
}

public enum NearbyTransportError: Error, Equatable, LocalizedError, Sendable {
    case notConnected
    case peerUnavailable(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            "No trusted Mac is connected."
        case let .peerUnavailable(name):
            "The peer \(name) is no longer available."
        case let .transport(message):
            message
        }
    }
}

private struct PeerIDBox: @unchecked Sendable {
    let value: MCPeerID
}

private final class SessionBox: @unchecked Sendable {
    let value: MCSession

    init(_ value: MCSession) {
        self.value = value
    }
}

private struct InvitationHandlerBox: @unchecked Sendable {
    let value: (Bool, MCSession?) -> Void
}

@MainActor
@Observable
public final class NearbyBuilderClient: NSObject {
    public private(set) var discoveredHosts: [NearbyPeer] = []
    public private(set) var connectionState: NearbyConnectionState = .idle
    public private(set) var connectedHost: NearbyPeer?
    public private(set) var lastError: String?

    @ObservationIgnored public var onEvent: (@MainActor (HostEvent) -> Void)?

    @ObservationIgnored private let localPeerID: MCPeerID
    @ObservationIgnored private let sessionBox: SessionBox
    @ObservationIgnored private let browser: MCNearbyServiceBrowser
    @ObservationIgnored private var peerIDs: [String: MCPeerID] = [:]
    @ObservationIgnored private var isBrowsing = false

    public init(displayName: String = ProcessInfo.processInfo.hostName) {
        let localPeerID = MCPeerID(displayName: Self.validPeerName(displayName))
        let session = MCSession(
            peer: localPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )

        self.localPeerID = localPeerID
        self.sessionBox = SessionBox(session)
        self.browser = MCNearbyServiceBrowser(
            peer: localPeerID,
            serviceType: BuilderWireProtocol.serviceType
        )

        super.init()
        session.delegate = self
        browser.delegate = self
    }

    public func start() {
        guard !isBrowsing else { return }
        lastError = nil
        isBrowsing = true
        connectionState = .browsing
        browser.startBrowsingForPeers()
    }

    public func stop() {
        if isBrowsing {
            browser.stopBrowsingForPeers()
        }
        isBrowsing = false
        sessionBox.value.disconnect()
        peerIDs.removeAll()
        discoveredHosts.removeAll()
        connectedHost = nil
        connectionState = .idle
    }

    public func connect(to peer: NearbyPeer) {
        guard let peerID = peerIDs[peer.id] else {
            setError(NearbyTransportError.peerUnavailable(peer.displayName))
            return
        }

        lastError = nil
        connectedHost = peer
        connectionState = .connecting
        browser.invitePeer(peerID, to: sessionBox.value, withContext: nil, timeout: 30)
    }

    public func disconnect() {
        sessionBox.value.disconnect()
        connectedHost = nil
        connectionState = isBrowsing ? .browsing : .disconnected
    }

    public func send(_ command: ClientCommand) throws {
        let peers = sessionBox.value.connectedPeers
        guard !peers.isEmpty else {
            throw NearbyTransportError.notConnected
        }

        do {
            let data = try WireCodec.encode(command)
            try sessionBox.value.send(data, toPeers: peers, with: .reliable)
        } catch let error as NearbyTransportError {
            throw error
        } catch {
            throw NearbyTransportError.transport(error.localizedDescription)
        }
    }

    private func found(_ peerID: MCPeerID) {
        let peer = Self.peer(from: peerID)
        peerIDs[peer.id] = peerID

        if !discoveredHosts.contains(where: { $0.id == peer.id }) {
            discoveredHosts.append(peer)
            discoveredHosts.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
    }

    private func lost(_ peerID: MCPeerID) {
        let peer = Self.peer(from: peerID)
        peerIDs[peer.id] = nil
        discoveredHosts.removeAll { $0.id == peer.id }
    }

    private func didChangeState(for peerID: MCPeerID, state: MCSessionState) {
        let peer = Self.peer(from: peerID)

        switch state {
        case .notConnected:
            if connectedHost?.id == peer.id {
                connectedHost = nil
            }
            connectionState = isBrowsing ? .browsing : .disconnected
        case .connecting:
            connectedHost = peer
            connectionState = .connecting
        case .connected:
            connectedHost = peer
            connectionState = .connected
            lastError = nil
        @unknown default:
            connectionState = .failed
            lastError = "The peer reported an unknown connection state."
        }
    }

    private func receive(_ event: HostEvent) {
        onEvent?(event)
    }

    private func setError(_ error: Error) {
        connectionState = .failed
        lastError = error.localizedDescription
    }

    nonisolated private static func peer(from peerID: MCPeerID) -> NearbyPeer {
        NearbyPeer(id: peerID.displayName, displayName: peerID.displayName)
    }

    nonisolated private static func validPeerName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Phone Builder" : trimmed
        return String(fallback.prefix(60))
    }
}

extension NearbyBuilderClient: MCNearbyServiceBrowserDelegate {
    nonisolated public func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: any Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.setError(NearbyTransportError.transport(message))
        }
    }

    nonisolated public func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        let peerBox = PeerIDBox(value: peerID)
        Task { @MainActor [weak self] in
            self?.found(peerBox.value)
        }
    }

    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peerBox = PeerIDBox(value: peerID)
        Task { @MainActor [weak self] in
            self?.lost(peerBox.value)
        }
    }
}

extension NearbyBuilderClient: MCSessionDelegate {
    nonisolated public func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        let peerBox = PeerIDBox(value: peerID)
        Task { @MainActor [weak self] in
            self?.didChangeState(for: peerBox.value, state: state)
        }
    }

    nonisolated public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let event = try WireCodec.decode(HostEvent.self, from: data).payload
            Task { @MainActor [weak self] in
                self?.receive(event)
            }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor [weak self] in
                self?.setError(NearbyTransportError.transport(message))
            }
        }
    }

    nonisolated public func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated public func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated public func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: (any Error)?
    ) {}
}

@MainActor
@Observable
public final class NearbyBuilderHost: NSObject {
    public private(set) var connectionState: NearbyConnectionState = .idle
    public private(set) var connectedPeers: [NearbyPeer] = []
    public private(set) var lastError: String?

    @ObservationIgnored public var onCommand: (@MainActor (ClientCommand, NearbyPeer) -> Void)?

    @ObservationIgnored private let localPeerID: MCPeerID
    @ObservationIgnored private let sessionBox: SessionBox
    @ObservationIgnored private let advertiser: MCNearbyServiceAdvertiser
    @ObservationIgnored private var isAdvertising = false

    public init(displayName: String = ProcessInfo.processInfo.hostName) {
        let localPeerID = MCPeerID(displayName: Self.validPeerName(displayName))
        let session = MCSession(
            peer: localPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )

        self.localPeerID = localPeerID
        self.sessionBox = SessionBox(session)
        self.advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: ["protocol": String(BuilderWireProtocol.version)],
            serviceType: BuilderWireProtocol.serviceType
        )

        super.init()
        session.delegate = self
        advertiser.delegate = self
    }

    public func start() {
        guard !isAdvertising else { return }
        lastError = nil
        isAdvertising = true
        connectionState = .advertising
        advertiser.startAdvertisingPeer()
    }

    public func stop() {
        if isAdvertising {
            advertiser.stopAdvertisingPeer()
        }
        isAdvertising = false
        sessionBox.value.disconnect()
        connectedPeers.removeAll()
        connectionState = .idle
    }

    public func send(_ event: HostEvent, to peer: NearbyPeer? = nil) throws {
        let targets: [MCPeerID]

        if let peer {
            guard let target = sessionBox.value.connectedPeers.first(where: { $0.displayName == peer.id }) else {
                throw NearbyTransportError.peerUnavailable(peer.displayName)
            }
            targets = [target]
        } else {
            targets = sessionBox.value.connectedPeers
        }

        guard !targets.isEmpty else {
            throw NearbyTransportError.notConnected
        }

        do {
            let data = try WireCodec.encode(event)
            try sessionBox.value.send(data, toPeers: targets, with: .reliable)
        } catch let error as NearbyTransportError {
            throw error
        } catch {
            throw NearbyTransportError.transport(error.localizedDescription)
        }
    }

    private func didReceiveInvitation(
        from peerID: MCPeerID,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        connectionState = .connecting
        let handlerBox = InvitationHandlerBox(value: invitationHandler)
        handlerBox.value(true, sessionBox.value)
    }

    private func didChangeState(for peerID: MCPeerID, state: MCSessionState) {
        let peer = Self.peer(from: peerID)

        switch state {
        case .notConnected:
            connectedPeers.removeAll { $0.id == peer.id }
            connectionState = isAdvertising ? .advertising : .disconnected
        case .connecting:
            connectionState = .connecting
        case .connected:
            if !connectedPeers.contains(where: { $0.id == peer.id }) {
                connectedPeers.append(peer)
                connectedPeers.sort {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            }
            connectionState = .connected
            lastError = nil
        @unknown default:
            connectionState = .failed
            lastError = "The peer reported an unknown connection state."
        }
    }

    private func receive(_ command: ClientCommand, from peer: NearbyPeer) {
        onCommand?(command, peer)
    }

    private func setError(_ error: Error) {
        connectionState = .failed
        lastError = error.localizedDescription
    }

    nonisolated private static func peer(from peerID: MCPeerID) -> NearbyPeer {
        NearbyPeer(id: peerID.displayName, displayName: peerID.displayName)
    }

    nonisolated private static func validPeerName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Builder Host" : trimmed
        return String(fallback.prefix(60))
    }
}

extension NearbyBuilderHost: MCNearbyServiceAdvertiserDelegate {
    nonisolated public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: any Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.setError(NearbyTransportError.transport(message))
        }
    }

    nonisolated public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let peerBox = PeerIDBox(value: peerID)
        let handlerBox = InvitationHandlerBox(value: invitationHandler)
        Task { @MainActor [weak self] in
            self?.didReceiveInvitation(from: peerBox.value, invitationHandler: handlerBox.value)
        }
    }
}

extension NearbyBuilderHost: MCSessionDelegate {
    nonisolated public func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        let peerBox = PeerIDBox(value: peerID)
        Task { @MainActor [weak self] in
            self?.didChangeState(for: peerBox.value, state: state)
        }
    }

    nonisolated public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let command = try WireCodec.decode(ClientCommand.self, from: data).payload
            let peer = Self.peer(from: peerID)
            Task { @MainActor [weak self] in
                self?.receive(command, from: peer)
            }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor [weak self] in
                self?.setError(NearbyTransportError.transport(message))
            }
        }
    }

    nonisolated public func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated public func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated public func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: (any Error)?
    ) {}
}
