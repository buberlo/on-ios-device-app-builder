import Foundation
import XCTest
@testable import BuilderHost

final class DiagnosticsParserTests: XCTestCase {
    func testParsesOnlyIPhonesFromDeviceCtlDocument() throws {
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

        let devices = try DeviceListParser.parse(data)

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.id, "PHONE-ID")
        XCTAssertEqual(devices.first?.connection, "localNetwork")
        XCTAssertEqual(devices.first?.developerModeEnabled, true)
    }
}
