import XCTest
@testable import BuilderCore

final class WireProtocolTests: XCTestCase {
    func testClientCommandRoundTrip() throws {
        let request = CreateProjectRequest(
            name: "Focus Timer",
            bundleIdentifier: "dev.buberlo.focus-timer",
            prompt: "Create a simple focus timer."
        )
        let command = ClientCommand.createProject(request)

        let data = try WireCodec.encode(command)
        let decoded = try WireCodec.decode(ClientCommand.self, from: data)

        XCTAssertEqual(decoded.version, BuilderWireProtocol.version)
        XCTAssertEqual(decoded.payload, command)
    }

    func testHostEventRoundTrip() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let project = ProjectSummary(
            id: UUID(uuidString: "E79209CA-AF4E-444E-93C1-CC3771507A58")!,
            name: "Focus Timer",
            bundleIdentifier: "dev.buberlo.focus-timer",
            createdAt: timestamp,
            updatedAt: timestamp,
            runState: .building
        )
        let snapshot = HostSnapshot(
            hostName: "Studio Mac",
            checkedAt: timestamp,
            checks: [
                SetupCheck(id: "xcode", title: "Xcode", detail: "26.0", status: .ready)
            ],
            connectedDeviceName: "iPhone",
            projects: [project]
        )
        let event = HostEvent.snapshot(snapshot)

        let data = try WireCodec.encode(event)
        let decoded = try WireCodec.decode(HostEvent.self, from: data)

        XCTAssertEqual(decoded.payload, event)
    }

    func testUnsupportedVersionIsRejected() throws {
        let envelope = WireEnvelope(
            version: BuilderWireProtocol.version + 1,
            payload: ClientCommand.requestSnapshot
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)

        XCTAssertThrowsError(try WireCodec.decode(ClientCommand.self, from: data)) { error in
            XCTAssertEqual(
                error as? WireProtocolError,
                .unsupportedVersion(
                    received: BuilderWireProtocol.version + 1,
                    supported: BuilderWireProtocol.version
                )
            )
        }
    }

    func testServiceTypeFitsBonjourLimit() {
        XCTAssertFalse(BuilderWireProtocol.serviceType.isEmpty)
        XCTAssertLessThanOrEqual(BuilderWireProtocol.serviceType.utf8.count, 15)
        XCTAssertTrue(
            BuilderWireProtocol.serviceType.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
            }
        )
    }
}
