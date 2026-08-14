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
        case .chats:
            "Chats"
        case .unavailable:
            DesktopProjectMetadataSnapshot.unavailableProjectName
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

    nonisolated static let unavailableProjectName = "Project unavailable"

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

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case localProjects = "local-projects"
            case remoteProjects = "remote-projects"
            case assignments = "thread-project-assignments"
            case projectlessThreadIDs = "projectless-thread-ids"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard CodingKeys.allCases.contains(where: container.contains) else {
                throw ProjectMetadataError.incompatibleSchema
            }

            localProjects = try container.contains(.localProjects)
                ? container.decode([String: LocalProject].self, forKey: .localProjects)
                : [:]
            remoteProjects = try container.contains(.remoteProjects)
                ? container.decode([RemoteProject].self, forKey: .remoteProjects)
                : []
            assignments = try container.contains(.assignments)
                ? container.decode([String: Assignment].self, forKey: .assignments)
                : [:]
            projectlessThreadIDs = try container.contains(.projectlessThreadIDs)
                ? container.decode([String].self, forKey: .projectlessThreadIDs)
                : []
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
        case oversizedFile(Int)
        case unsafeFile
        case invalidProjectName
        case conflictingRemoteProjectID
        case conflictingThreadMembership

        var errorDescription: String? {
            switch self {
            case .incompatibleSchema:
                "Desktop Project 状态 schema 不兼容。"
            case let .oversizedFile(size):
                "Desktop Project 状态文件异常过大（\(size) bytes）。"
            case .unsafeFile:
                "Desktop Project 状态文件不是当前用户拥有的普通文件。"
            case .invalidProjectName:
                "Desktop Project 状态包含空名称。"
            case .conflictingRemoteProjectID:
                "Desktop Project 状态包含重复远程 Project。"
            case .conflictingThreadMembership:
                "Desktop Project 状态同时把 thread 标记为 Project 与 Chats。"
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
        let configuredHome = environment["CODEX_IN_NOTCH_CODEX_HOME"]
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
                        diagnostic: "Desktop Project 主状态不可读，已使用备份：\(primaryError.localizedDescription)"
                    )
                lastKnownGood = backup
                lastSuccessfulPrimaryRevision = nil
                return backup
            } catch {
                let diagnostic = "无法读取 Codex Desktop Project 映射：\(primaryError.localizedDescription)"
                if let lastKnownGood {
                    return lastKnownGood.retainingData(
                        source: .lastKnownGood,
                        diagnostic: diagnostic + " 已保留最近一次有效映射。"
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

        var namesByThreadID: [String: String] = [:]
        for (threadID, assignment) in state.assignments where !threadID.isEmpty {
            let name: String?
            switch assignment.projectKind {
            case "local":
                name = localProjectNames[assignment.projectID]
            case "remote":
                name = remoteProjectNames[assignment.projectID]
            default:
                name = nil
            }
            if let name {
                namesByThreadID[threadID] = name
            }
        }

        let projectlessThreadIDs = Set(
            state.projectlessThreadIDs.filter { !$0.isEmpty }
        )
        let assignedThreadIDs = Set(
            state.assignments.keys.filter { !$0.isEmpty }
        )
        if !projectlessThreadIDs.isDisjoint(with: assignedThreadIDs) {
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
