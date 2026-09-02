import Foundation
import XCTest
@testable import BuilderHost

final class DiagnosticsParserTests: XCTestCase {
    func testParsesIPhoneAndIPadWithXcodeCompatibility() throws {
        let data = Data(
            """
            {
              "result": {
                "devices": [
                  {
                    "identifier": "PHONE-ID",
                    "deviceProperties": {
                      "name": "Konrad's iPhone",
                      "osVersionNumber": "27.0",
                      "developerModeStatus": "enabled"
                    },
                    "connectionProperties": { "transportType": "localNetwork" },
                    "hardwareProperties": { "deviceType": "iPhone" }
                  },
                  {
                    "identifier": "PAD-ID",
                    "deviceProperties": {
                      "name": "iPad",
                      "osVersionNumber": "26.6",
                      "developerModeStatus": "enabled"
                    },
                    "connectionProperties": { "transportType": "localNetwork" },
                    "hardwareProperties": { "deviceType": "iPad" }
                  }
                ]
              }
            }
            """.utf8
        )

        let devices = try DeviceListParser.parse(data, xcodeMajorVersion: 26)

        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices.map(\.id), ["PHONE-ID", "PAD-ID"])
        XCTAssertEqual(devices[0].kind, .iPhone)
        XCTAssertFalse(devices[0].isSupportedByXcode)
        XCTAssertEqual(devices[1].kind, .iPad)
        XCTAssertTrue(devices[1].isReadyForInstallation)
    }
}
