import Foundation
import XCTest
@testable import BuilderHost

final class BuildPipelineIntegrationTests: XCTestCase {
    func testGeneratedPrototypeBuildsForGenericIOSDevice() async throws {
        #if !BUILDER_INTEGRATION_TESTS
        throw XCTSkip("Build with BUILDER_INTEGRATION_TESTS to run the signed Tuist/Xcode integration build.")
        #endif

        let root = FileManager.default.temporaryDirectory
            .appending(path: "BuilderHostBuildTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let record = HostProjectRecord(
            id: UUID(),
            name: "Pipeline Probe",
            slug: "pipeline-probe",
            bundleIdentifier: "dev.buberlo.builderhost.pipeline-probe",
            prompt: "Show a signed build readiness screen.",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            status: .idle,
            lastBuiltAppPath: nil
        )
        let pipeline = PrototypeBuildPipeline(runner: AllowlistedCommandRunner())

        let result = try await pipeline.build(
            project: record,
            at: root,
            installOn: nil,
            progress: { _ in }
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.appURL.path))
        XCTAssertNil(result.installedDeviceName)
    }
}
