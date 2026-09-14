import Foundation

/// Change signals for the session records of the Turns still in flight (CC-019).
///
/// - Watches files, not the directory: `~/.claude/sessions/<pid>.json` is rewritten in place,
///   which fires no directory event (measured 2026-08-18), and an interrupt only changes it.
/// - Signal only: nothing is read; the answer still comes from `claude agents --json`.
/// - Only sessions whose Turn is still going are watched; a new Turn arrives by hook.
final class ClaudeCodeSessionRecordWatcher: @unchecked Sendable {
    nonisolated private let directory: URL
    nonisolated private let watcher: PathSetChangeWatcher

    nonisolated init(directory: URL, debounceInterval: TimeInterval) {
        self.directory = directory
        self.watcher = PathSetChangeWatcher(debounceInterval: debounceInterval)
    }

    /// A session's record path, named by its pid: a location, not a schema.
    nonisolated func recordURL(forProcessIdentifier pid: Int32) -> URL {
        directory.appendingPathComponent("\(pid).json")
    }

    nonisolated func events() -> AsyncStream<Void> {
        watcher.events()
    }

    /// Watches exactly these sessions' records, and no others.
    nonisolated func watch(processIdentifiers: Set<Int32>) {
        watcher.watch(
            paths: Set(processIdentifiers.map(recordURL(forProcessIdentifier:)))
        )
    }

    /// For tests; nothing in the product branches on it.
    nonisolated var watchedCount: Int {
        watcher.watchedCount
    }
}
