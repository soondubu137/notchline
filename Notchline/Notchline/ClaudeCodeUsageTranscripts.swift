import Foundation
import os

/// Reports what this app's quota readings have left on Claude Code's disk.
///
/// Every reading is a real Claude Code session, so every reading writes a
/// transcript — about 3.4 KB of it — into Claude Code's own project directory,
/// and nothing removes them. One file per reading, for the life of the machine.
///
/// **It reports; it never deletes.** An earlier version of this cleared the
/// folder at launch, and it did not survive being asked whether it was safe.
/// Claude Code files a session under a directory named after its working
/// directory, and that name flattens separators *and* spaces, so it is not
/// one-to-one: measured on 2.1.234, `…/a b` and `…/a-b` are filed in the *same*
/// directory. A folder holding this app's transcripts can therefore hold
/// somebody's real work as well, and while each file can be made to prove
/// whose it is, none of that is worth the residue of risk in deleting a user's
/// session history unasked. So the size goes in Settings with a button to the
/// folder, and the decision stays with the person whose files they are.
///
/// The folder is still found rather than derived, for the same reason it always
/// was: the naming rule is not published, and a wrong guess would point the
/// user at somebody else's transcripts.
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

    /// - Parameter freshness: How long a measurement stands. The folder grows
    ///   by a file every reading, so a figure taken at launch would be wrong by
    ///   the time anyone opened Settings on a machine left running.
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
    /// - Parameter sessionID: The session the reading reported. It is somebody
    ///   else's output about to become a path, so anything that is not plainly
    ///   a UUID is refused rather than resolved.
    func noteReading(_ sessionID: String) {
        guard directory == nil, UUID(uuidString: sessionID) != nil else { return }
        let transcript = "\(sessionID).jsonl"
        directory = contents(of: projectsDirectory).first {
            fileManager.fileExists(atPath: $0.appendingPathComponent(transcript).path)
        }
    }

    /// The transcripts and what they weigh, or nil until a reading has said
    /// where they go.
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
