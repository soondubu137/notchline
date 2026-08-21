import Foundation

/// Change signals for the session records of the turns still in flight.
///
/// **Why a file and not the directory it sits in.** Every other watcher in this
/// app points at a directory, because the state it wants is replaced atomically
/// and a descriptor on the old inode goes deaf. Claude Code's session records
/// are the opposite case: `~/.claude/sessions/<pid>.json` is rewritten **in
/// place**, and a directory vnode source does not fire for a write inside the
/// directory. Measured 2026-08-18 with the same event mask this app already
/// uses: an in-place rewrite produced no directory event at all, while a
/// create, a delete and an atomic replace produced one each.
///
/// That is why `~/.claude/sessions` reports sessions appearing and going away
/// and nothing else -- and a session that is interrupted neither appears nor
/// goes away, it only stops saying it is busy (CC-019). Without this, that
/// change waited for whatever refresh happened next, up to a whole heartbeat.
///
/// **Signal only, and deliberately.** Nothing here reads a byte of the file.
/// The edge invalidates the session list and wakes a refresh; the answer still
/// comes from `claude agents --json`, which is what keeps the private path a
/// hint rather than a schema this app depends on.
///
/// **Only the records worth watching.** ``watch(processIdentifiers:)`` is given
/// the sessions whose turn is still going -- usually none, sometimes one. A
/// session with no turn in flight needs no edge: the turn it starts next
/// announces itself with a hook.
///
/// The reconciling and the merging are ``PathSetChangeWatcher``'s, shared with
/// the watcher over Claude Desktop's account folders; what belongs here is
/// which paths to hand it.
final class ClaudeCodeSessionRecordWatcher: @unchecked Sendable {
    nonisolated private let directory: URL
    nonisolated private let watcher: PathSetChangeWatcher

    nonisolated init(directory: URL, debounceInterval: TimeInterval) {
        self.directory = directory
        self.watcher = PathSetChangeWatcher(debounceInterval: debounceInterval)
    }

    /// The path Claude Code writes a session's record to.
    ///
    /// The name is the session's pid, which the official command reports. This
    /// is the whole of the private knowledge here -- a location, not a schema.
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

    /// How many records are being watched. For tests and for a future
    /// diagnostic; nothing in the product branches on it.
    nonisolated var watchedCount: Int {
        watcher.watchedCount
    }
}
