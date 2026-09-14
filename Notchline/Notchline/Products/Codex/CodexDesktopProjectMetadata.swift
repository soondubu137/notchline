import Darwin
import Foundation

nonisolated protocol DesktopProjectMetadataProviding: Sendable {
    func snapshot() async -> DesktopProjectMetadataSnapshot
}

enum DesktopProjectResolution: Equatable, Sendable {
    case project(String)
    case chats
    case unavailable

    nonisolated var displayName: String {
        switch self {
        case let .project(name):
            name
        // Same words as other products' Project-less rows (``RowContentFallback``).
        case .chats:
            RowContentFallback.projectName
        case .unavailable:
            RowContentFallback.unavailableProjectName
        }
    }
}

struct DesktopProjectMetadataSnapshot: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case current
        case backup
        case lastKnownGood
        case unavailable

        nonisolated var isCurrent: Bool {
            if case .current = self {
                return true
            }
            return false
        }
    }

    let projectNamesByThreadID: [String: String]
    let projectlessThreadIDs: Set<String>
    let source: Source
    let diagnostic: String?

    nonisolated init(
        projectNamesByThreadID: [String: String],
        projectlessThreadIDs: Set<String>,
        source: Source,
        diagnostic: String? = nil
    ) {
        self.projectNamesByThreadID = projectNamesByThreadID
        self.projectlessThreadIDs = projectlessThreadIDs
        self.source = source
        self.diagnostic = diagnostic
    }

    nonisolated static func unavailable(_ diagnostic: String) -> Self {
        Self(
            projectNamesByThreadID: [:],
            projectlessThreadIDs: [],
            source: .unavailable,
            diagnostic: diagnostic
        )
    }

    nonisolated func resolution(for threadID: String) -> DesktopProjectResolution {
        if let projectName = projectNamesByThreadID[threadID] {
            return .project(projectName)
        }
        if projectlessThreadIDs.contains(threadID) {
            return .chats
        }
        return .unavailable
    }

    nonisolated func retainingData(
        source: Source,
        diagnostic: String
    ) -> Self {
        Self(
            projectNamesByThreadID: projectNamesByThreadID,
            projectlessThreadIDs: projectlessThreadIDs,
            source: source,
            diagnostic: diagnostic
        )
    }
}

actor CodexDesktopProjectMetadataRepository: DesktopProjectMetadataProviding {
    nonisolated private static let stateFileName = ".codex-global-state.json"
    nonisolated private static let maximumStateFileSize = 4 * 1_024 * 1_024

    private struct FileRevision: Equatable {
        let size: UInt64
        let modificationDate: Date?
        let fileNumber: UInt64?
    }

    private struct GlobalState: Decodable {
        let localProjects: [String: LocalProject]
        let remoteProjects: [RemoteProject]
        let assignments: [String: Assignment]
        let projectlessThreadIDs: [String]

        private enum CodingKeys: String, CodingKey {
            case localProjects = "local-projects"
            case remoteProjects = "remote-projects"
            case assignments = "thread-project-assignments"
            case projectlessThreadIDs = "projectless-thread-ids"
        }

        /// The minimum key set that counts as the current Desktop schema. `remote-projects` and
        /// `local-projects` can be absent from healthy files, so instead:
        /// 1. The mapping exists in at least one direction (assignments, projectless ids, or both).
        /// 2. Defined Projects come with an assignment key (else `thread-project-assignments` was
        ///    renamed).
        /// Renamed project keys surface in ``loadSnapshot(from:source:)`` as dangling assignments.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.assignments)
                    || container.contains(.projectlessThreadIDs) else {
                throw ProjectMetadataError.incompatibleSchema
            }

            localProjects = try container.decodeIfPresent(
                [String: LocalProject].self,
                forKey: .localProjects
            ) ?? [:]
            remoteProjects = try container.decodeIfPresent(
                [RemoteProject].self,
                forKey: .remoteProjects
            ) ?? []
            assignments = try container.decodeIfPresent(
                [String: Assignment].self,
                forKey: .assignments
            ) ?? [:]
            projectlessThreadIDs = try container.decodeIfPresent(
                [String].self,
                forKey: .projectlessThreadIDs
            ) ?? []

            guard container.contains(.assignments)
                    || (localProjects.isEmpty && remoteProjects.isEmpty) else {
                throw ProjectMetadataError.missingThreadAssignments
            }
        }
    }

    private struct LocalProject: Decodable {
        let name: String
    }

    private struct RemoteProject: Decodable {
        let id: String
        let label: String
    }

    private struct Assignment: Decodable {
        let projectKind: String
        let projectID: String

        private enum CodingKeys: String, CodingKey {
            case projectKind
            case projectID = "projectId"
        }
    }

    private enum ProjectMetadataError: LocalizedError {
        case incompatibleSchema
        case missingThreadAssignments
        case oversizedFile(Int)
        case unsafeFile
        case invalidProjectName
        case conflictingRemoteProjectID
        case conflictingThreadMembership
        case emptyThreadIdentifier
        case unsupportedProjectKind
        case danglingProjectReference

        var errorDescription: String? {
            switch self {
            case .incompatibleSchema:
                "The Desktop Project state schema is not compatible."
            case .missingThreadAssignments:
                "The Desktop Project state defines Projects but no thread assignments, so the schema is not compatible."
            case let .oversizedFile(size):
                "The Desktop Project state file is implausibly large (\(size) bytes)."
            case .unsafeFile:
                "The Desktop Project state file is not a regular file owned by the current user."
            case .invalidProjectName:
                "The Desktop Project state contains an empty name."
            case .conflictingRemoteProjectID:
                "The Desktop Project state contains a duplicate remote Project."
            case .conflictingThreadMembership:
                "The Desktop Project state marks a thread as belonging to both a Project and Chats."
            case .emptyThreadIdentifier:
                "The Desktop Project state contains an empty thread identifier."
            case .unsupportedProjectKind:
                "The Desktop Project state contains an assignment of an unsupported Project kind."
            case .danglingProjectReference:
                "The Desktop Project state assigns a thread to a Project it does not define."
            }
        }
    }

    private let stateFileURL: URL
    private let fileManager: FileManager
    private var lastKnownGood: DesktopProjectMetadataSnapshot?
    private var lastSuccessfulPrimaryRevision: FileRevision?

    nonisolated static func liveStateFileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        let configuredHome = environment["NOTCHLINE_CODEX_HOME"]
            ?? environment["CODEX_HOME"]
        let codexHome: URL
        if let configuredHome, !configuredHome.isEmpty {
            codexHome = URL(
                fileURLWithPath: (configuredHome as NSString).expandingTildeInPath,
                isDirectory: true
            )
        } else {
            codexHome = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }
        return codexHome.appendingPathComponent(Self.stateFileName)
    }

    init(
        stateFileURL: URL =
            CodexDesktopProjectMetadataRepository.liveStateFileURL(),
        fileManager: FileManager = .default
    ) {
        self.stateFileURL = stateFileURL
        self.fileManager = fileManager
    }

    func snapshot() async -> DesktopProjectMetadataSnapshot {
        let primaryRevision = try? revision(of: stateFileURL)
        if primaryRevision != nil,
           primaryRevision == lastSuccessfulPrimaryRevision,
           let lastKnownGood,
           lastKnownGood.source.isCurrent {
            return lastKnownGood
        }

        do {
            let snapshot = try loadSnapshot(from: stateFileURL, source: .current)
            lastKnownGood = snapshot
            lastSuccessfulPrimaryRevision = primaryRevision
            return snapshot
        } catch {
            let primaryError = error
            do {
                let backupURL = URL(fileURLWithPath: stateFileURL.path + ".bak")
                let backup = try loadSnapshot(from: backupURL, source: .backup)
                    .retainingData(
                        source: .backup,
                        diagnostic: "The primary Desktop Project state is unreadable; the backup was used: \(primaryError.localizedDescription)"
                    )
                lastKnownGood = backup
                lastSuccessfulPrimaryRevision = nil
                return backup
            } catch {
                let diagnostic = "Could not read the Codex Desktop Project mapping: \(primaryError.localizedDescription)"
                if let lastKnownGood {
                    return lastKnownGood.retainingData(
                        source: .lastKnownGood,
                        diagnostic: diagnostic + " The last valid mapping has been kept."
                    )
                }
                return .unavailable(diagnostic)
            }
        }
    }

    private func loadSnapshot(
        from url: URL,
        source: DesktopProjectMetadataSnapshot.Source
    ) throws -> DesktopProjectMetadataSnapshot {
        let data = try readValidatedData(from: url)
        let state = try JSONDecoder().decode(GlobalState.self, from: data)

        var localProjectNames: [String: String] = [:]
        for (projectID, project) in state.localProjects {
            let name = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !projectID.isEmpty, !name.isEmpty else {
                throw ProjectMetadataError.invalidProjectName
            }
            localProjectNames[projectID] = name
        }

        var remoteProjectNames: [String: String] = [:]
        for project in state.remoteProjects {
            let name = project.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !project.id.isEmpty, !name.isEmpty else {
                throw ProjectMetadataError.invalidProjectName
            }
            if remoteProjectNames.updateValue(name, forKey: project.id) != nil {
                throw ProjectMetadataError.conflictingRemoteProjectID
            }
        }

        // An unresolvable assignment is schema drift: reject the whole snapshot rather than publish a
        // short mapping as `.current`; the caller falls back to the backup or last-known-good.
        var namesByThreadID: [String: String] = [:]
        for (threadID, assignment) in state.assignments {
            guard !threadID.isEmpty else {
                throw ProjectMetadataError.emptyThreadIdentifier
            }
            let name: String?
            switch assignment.projectKind {
            case "local":
                name = localProjectNames[assignment.projectID]
            case "remote":
                name = remoteProjectNames[assignment.projectID]
            default:
                throw ProjectMetadataError.unsupportedProjectKind
            }
            guard let name else {
                throw ProjectMetadataError.danglingProjectReference
            }
            namesByThreadID[threadID] = name
        }

        guard !state.projectlessThreadIDs.contains(where: \.isEmpty) else {
            throw ProjectMetadataError.emptyThreadIdentifier
        }
        let projectlessThreadIDs = Set(state.projectlessThreadIDs)
        if !projectlessThreadIDs.isDisjoint(with: state.assignments.keys) {
            throw ProjectMetadataError.conflictingThreadMembership
        }

        return DesktopProjectMetadataSnapshot(
            projectNamesByThreadID: namesByThreadID,
            projectlessThreadIDs: projectlessThreadIDs,
            source: source
        )
    }

    private func readValidatedData(from url: URL) throws -> Data {
        let resourceValues = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ])
        guard resourceValues.isRegularFile == true,
              resourceValues.isSymbolicLink != true else {
            throw ProjectMetadataError.unsafeFile
        }
        let fileSize = resourceValues.fileSize ?? 0
        guard fileSize <= Self.maximumStateFileSize else {
            throw ProjectMetadataError.oversizedFile(fileSize)
        }

        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        if let owner = attributes[.ownerAccountID] as? NSNumber,
           owner.uint32Value != getuid() {
            throw ProjectMetadataError.unsafeFile
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maximumStateFileSize else {
            throw ProjectMetadataError.oversizedFile(data.count)
        }
        return data
    }

    private func revision(of url: URL) throws -> FileRevision {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return FileRevision(
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        )
    }
}
