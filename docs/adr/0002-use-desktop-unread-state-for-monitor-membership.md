# Desktop unread state decides whether a terminal Thread stays monitored

The expanded list is a live summary of current Turns, not an entry point into Codex history. A Turn enters the monitoring lifecycle when the user submits input; while unfinished it always shows, and once terminal it stays only while Codex Desktop still marks the Thread unread with its blue dot and the Thread is neither archived nor deleted. A read, archive or delete event removes it immediately. The scope covers every Project and Chats under the current Desktop account and does not follow the sidebar selection.

Fixed time windows and "the last N" were both rejected. If the supported integration interfaces cannot reliably observe activity, unread state and membership changes, V1 must not guess from local timers, window focus or a failed click — and must not ship this live summary at all.

## Addendum, 2026-08-26: the blue-dot set is a projection, so read its timestamp with it

The rule above says "stays while Codex Desktop still marks it unread". The implementation read that as "the thread id is still in `unread-thread-ids-by-host-v1.local`". Those are not the same thing: that set is the on-disk **projection** of the blue dots in Desktop's memory, and a projection may lag arbitrarily.

Desktop's main process persists the **entire** `electron-persisted-atom-state` through a single 500 ms trailing debounce with no max-wait, and every persisted atom shares that one debounce. The composer draft `composer-prompt-drafts-v2` is one of them, written by the editor's `dispatchTransaction` on every keystroke. Measured (Desktop `26.820.60940`, 2026-08-26): typing 165 characters continuously into the composer produced exactly one write to that file in a 45.4-second window, about half a second after the typing stopped, and none during it.

So a Turn finishing in a **different** thread gets its blue dot in the sidebar within milliseconds while its id stays out of the file for that whole stretch. The file parses cleanly, so it counts as an authoritative snapshot; it does not mention the Thread, so the settling window retires the row; and hiding is final, so the id landing on disk seconds later cannot bring it back. The user watches a Completed row they never read leave the notch with its blue dot still lit — which is how this was reported, and why this addendum exists.

**Decision: an unread reading may only speak for Turns that ended before it was written.** Every snapshot carries the moment it is complete as of (`DesktopUnreadStateSnapshot.currentAsOf`, taken from the main file's `modificationDate` on the Codex side). Where that is earlier than the Turn's end, the membership gate refuses to make any hiding decision, the row stays, and it waits for the next write on the 1-second re-check. It is waiting on a file rather than on the user, so it keeps waiting through a locked screen.

This is not a new principle but the Codex-side completion of the first clause of [ADR 0012](0012-read-state-is-answered-per-product-or-not-at-all.md), which already held that a desktop app's bookkeeping delay, throttling, or total silence cannot make a Turn read — **only evidence that genuinely happened after it ended can**. That rule had landed only on Claude Desktop's focus timestamps; the Codex side was reading "absent from the set" and had never asked how fresh the reading itself was.

**Costs and boundaries.**

- The rejected alternative was widening the settling window. The delay has no upper bound, and any window wide enough to cover a burst of typing keeps **read** rows on the notch just as long — trading the product's most common path for its rarest.
- Desktop never writes a blue dot for a thread run from the CLI, so those rows now leave only at Desktop's next write to that file (usually within minutes while Desktop is open), where they previously left 2 seconds after terminating. They cannot become undismissable: a Codex row already requires Desktop to be running (with no PID the live branch is never entered and no row is drawn), so they disappear with the branch when Desktop quits, and right-click removal still works.
- The case where the user **reads the Turn during the typing window** still converges: the id never reached disk, it is still absent when the file is finally written, and that write is now later than the Turn, so the row hides. This is also why the rule was not made "hiding requires having first observed the unread state" — that would strand such rows on the notch forever.
