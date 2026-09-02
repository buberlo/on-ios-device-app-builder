import Foundation
import XCTest
@testable import BuilderHost

final class WorkspaceServiceTests: XCTestCase {
    func testCreatesAndReloadsProjectInsideControlledRoot() async throws {
        let root = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try WorkspaceService(rootURL: root)

        let project = try await service.createProject(
            name: "Focus Timer",
            bundleIdentifier: "dev.example.focus-timer",
            prompt: "A calm focus timer"
        )
        let projects = try await service.projects()
        let projectURL = try await service.projectURL(for: project)

        XCTAssertEqual(projects.map(\.id), [project.id])
        XCTAssertEqual(projects.first?.name, project.name)
        XCTAssertEqual(projects.first?.bundleIdentifier, project.bundleIdentifier)
        XCTAssertTrue(projectURL.path.hasPrefix(root.path + "/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.appending(path: "project.json").path))
    }

    func testRejectsInvalidBundleIdentifier() async throws {
        let root = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try WorkspaceService(rootURL: root)

        do {
            _ = try await service.createProject(name: "Bad", bundleIdentifier: "not valid", prompt: "")
            XCTFail("Expected invalid bundle identifier")
        } catch let error as WorkspaceError {
            XCTAssertEqual(error, .invalidBundleIdentifier)
        }
    }

    func testDeletesOnlyTheRequestedProjectDirectory() async throws {
        let root = uniqueTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try WorkspaceService(rootURL: root)
        let first = try await service.createProject(name: "First", bundleIdentifier: "dev.example.first", prompt: "")
        let second = try await service.createProject(name: "Second", bundleIdentifier: "dev.example.second", prompt: "")
        let firstURL = try await service.projectURL(for: first)
        let secondURL = try await service.projectURL(for: second)

        try await service.deleteProject(id: first.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        let remainingProjects = try await service.projects()
        XCTAssertEqual(remainingProjects.map(\.id), [second.id])
    }

    func testSlugRemovesPathCharacters() {
        XCTAssertEqual(WorkspaceService.slug(from: "../../Über Cool App"), "uber-cool-app")
    }

    private func uniqueTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "BuilderHostTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
