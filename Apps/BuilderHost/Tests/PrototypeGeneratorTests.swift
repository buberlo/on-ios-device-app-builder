import Foundation
import XCTest
@testable import BuilderHost

final class PrototypeGeneratorTests: XCTestCase {
    func testGeneratesEscapedSwiftUIPrototype() throws {
        let root = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = fixture(prompt: "Show \"today\"\nwith focus")

        try PrototypeGenerator().generate(record, at: root)

        let source = try String(contentsOf: root.appending(path: "Sources/PrototypeApp.swift"), encoding: .utf8)
        let manifest = try String(contentsOf: root.appending(path: "Project.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("Show \\\"today\\\"\\nwith focus"))
        XCTAssertTrue(manifest.contains("dev.example.prototype"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "Tuist.swift").path))
    }

    func testBuildPreparationPreservesExistingCodexSource() async throws {
        let root = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = fixture(prompt: "Initial")
        let generator = PrototypeGenerator()
        try generator.generate(record, at: root)

        let sourceURL = root.appending(path: "Sources/PrototypeApp.swift")
        let codexSource = "// Codex-authored source\n"
        try Data(codexSource.utf8).write(to: sourceURL, options: .atomic)
        let pipeline = PrototypeBuildPipeline(runner: AllowlistedCommandRunner(), generator: generator)

        try await pipeline.prepareProjectIfNeeded(record, at: root)

        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), codexSource)
    }

    private func fixture(prompt: String) -> HostProjectRecord {
        HostProjectRecord(
            id: UUID(),
            name: "Prototype",
            slug: "prototype",
            bundleIdentifier: "dev.example.prototype",
            prompt: prompt,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            status: .idle,
            lastBuiltAppPath: nil
        )
    }

    private func uniqueTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "BuilderHostGeneratorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
