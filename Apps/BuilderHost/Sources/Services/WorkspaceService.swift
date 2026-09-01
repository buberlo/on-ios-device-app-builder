import Foundation

actor WorkspaceService {
    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootURL = applicationSupport
                .appending(path: "BuilderHost", directoryHint: .isDirectory)
                .appending(path: "Projects", directoryHint: .isDirectory)
        }
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }

    func createProject(name: String, bundleIdentifier: String, prompt: String) throws -> HostProjectRecord {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw WorkspaceError.invalidName }
        guard Self.isValidBundleIdentifier(bundleIdentifier) else { throw WorkspaceError.invalidBundleIdentifier }

        let slug = Self.slug(from: cleanName)
        let id = UUID()
        let now = Date()
        let record = HostProjectRecord(
            id: id,
            name: cleanName,
            slug: "\(slug)-\(id.uuidString.prefix(8).lowercased())",
            bundleIdentifier: bundleIdentifier,
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now,
            updatedAt: now,
            status: .idle,
            lastBuiltAppPath: nil
        )
        try persist(record)
        return record
    }

    func workspaceRootURL() -> URL {
        rootURL
    }

    func projects() throws -> [HostProjectRecord] {
        let contents = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents.compactMap { directory -> HostProjectRecord? in
            let metadata = directory.appending(path: "project.json")
            guard let data = try? Data(contentsOf: metadata) else { return nil }
            return try? decoder.decode(HostProjectRecord.self, from: data)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func project(id: UUID) throws -> HostProjectRecord {
        guard let record = try projects().first(where: { $0.id == id }) else {
            throw WorkspaceError.projectNotFound
        }
        return record
    }

    func update(_ record: HostProjectRecord) throws {
        guard try projects().contains(where: { $0.id == record.id }) else {
            throw WorkspaceError.projectNotFound
        }
        try persist(record)
    }

    func projectURL(for record: HostProjectRecord) throws -> URL {
        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let candidate = resolvedRoot
            .appending(path: record.slug, directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard candidate.path.hasPrefix(resolvedRoot.path + "/") else {
            throw WorkspaceError.pathEscapedWorkspace
        }
        return candidate
    }

    private func persist(_ record: HostProjectRecord) throws {
        let directory = try projectURL(for: record)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(record)
        try data.write(to: directory.appending(path: "project.json"), options: .atomic)
    }

    static func slug(from name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let segments = folded
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return String((segments.joined(separator: "-").isEmpty ? "prototype" : segments.joined(separator: "-")).prefix(40))
    }

    static func isValidBundleIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        return parts.allSatisfy { part in
            guard let first = part.unicodeScalars.first,
                  CharacterSet.letters.contains(first) else { return false }
            return part.unicodeScalars.allSatisfy(allowed.contains)
        }
    }
}

enum WorkspaceError: LocalizedError, Equatable {
    case invalidName
    case invalidBundleIdentifier
    case projectNotFound
    case pathEscapedWorkspace

    var errorDescription: String? {
        switch self {
        case .invalidName: "Project name cannot be empty."
        case .invalidBundleIdentifier: "Use a reverse-domain bundle identifier such as dev.example.app."
        case .projectNotFound: "The requested project does not exist on this Mac."
        case .pathEscapedWorkspace: "The project path is outside the controlled workspace."
        }
    }
}
