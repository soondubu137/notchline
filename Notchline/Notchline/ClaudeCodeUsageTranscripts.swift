import Foundation
import os

/// Reports what this app's quota readings have left on Claude Code's disk: one ~3.4 KB
/// transcript per reading, never removed.
///
/// Reports, never deletes: project folder names flatten separators and spaces (`…/a b` and
/// `…/a-b` share one on 2.1.234), so a folder can hold the user's real work. Settings shows the
/// size with a button to the folder. The folder is found, not derived: the naming rule is
/// unpublished.
actor ClaudeCodeUsageTranscripts {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "ClaudeCodeUsageTranscripts"
    )

    private let projectsDirectory: URL
    private let fileManager: FileManager
    private let clock: any MonitorClock
    private let freshness: TimeInterval
    private var directory: URL?
    private var measured: AgentDiskFootprint?
    private var measuredAt: Date?

    /// - Parameter freshness: How long a measurement stands; the folder grows by a file per reading.
    init(
        projectsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        clock: any MonitorClock = SystemMonitorClock(),
        freshness: TimeInterval = 60
    ) {
        self.projectsDirectory = projectsDirectory
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)
        self.fileManager = fileManager
        self.clock = clock
        self.freshness = freshness
    }

    /// Learns which folder the readings go to, from one that just happened.
    ///
    /// - Parameter sessionID: The reported session; refused unless it is plainly a UUID, since it
    ///   becomes a path.
    func noteReading(_ sessionID: String) {
        guard directory == nil, UUID(uuidString: sessionID) != nil else { return }
        let transcript = "\(sessionID).jsonl"
        directory = contents(of: projectsDirectory).first {
            fileManager.fileExists(atPath: $0.appendingPathComponent(transcript).path)
        }
    }

    /// The transcripts and what they weigh, or nil until a reading has said where they go.
    func footprint() -> AgentDiskFootprint? {
        guard let directory else { return nil }
        if let measured, let measuredAt,
           clock.now().timeIntervalSince(measuredAt) < freshness {
            return measured
        }

        var bytes: Int64 = 0
        for url in contents(of: directory) where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ), values.isRegularFile == true else {
                continue
            }
            bytes += Int64(values.fileSize ?? 0)
        }

        let footprint = AgentDiskFootprint(directory: directory, byteCount: bytes)
        measured = footprint
        measuredAt = clock.now()
        return footprint
    }

    private func contents(of directory: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )) ?? []
    }
}
