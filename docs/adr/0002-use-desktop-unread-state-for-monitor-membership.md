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

## Addendum, 2026-08-29: the timestamp answers two questions, and one instant cannot serve both

The addendum above is right and was applied to one instant too many — and the same mistake had already been made on the other product, so this corrects both.

`HookTurnState.terminalBoundaryAt` is not the Turn's end. It is the later of the Turn's own terminal and the last boundary of a subagent that Turn spawned, and it exists for one job: the settling window, so a row is not snatched off the notch in the instant its subagent badge clears. A subagent's `SubagentStop` was measured **91 seconds** past its parent's `Stop` (2026-08-22), and `dff7d66` introduced that stamp for exactly this reason.

From `dff7d66` (2026-08-23) both products also used it as the instant *read evidence* had to be later than. That is a different question, and it has a different answer. Reading is something a person does to a Turn's **answer**, and the answer landed when the Turn ended. So:

- **Codex** demanded an unread file written after the subagent's stop — an instant Codex Desktop has no reason to write after, since the dot for that Turn was set or withheld a minute and a half earlier. The write that recorded the user opening the thread happened *while the subagent was still working*, because that is exactly when the row is on the notch, and it fell short of the bar.
- **Claude Code** demanded the same of `lastFocusedAt`, of Claude Desktop returning to the foreground, and of the controlling terminal's access time. `ClaudeCodeDesktopReadStateRepository`'s own documentation said the left half is "the instant the Turn actually ended, from the event that ended it"; only the call site disagreed.

Either way the user read the answer, the subagent finished afterwards, and the row came back reported unread — staying until that product happened to put the session on screen a second time. Reported on both products on 2026-08-29.

**Decision: read evidence is dated against `HookTurnState.turnEndedAt`, the Turn's own terminal. `terminalBoundaryAt` keeps the settling window and nothing else.** Two questions, two stamps. `TerminalUnreadMembershipGate`'s `endedAgain` asks the Turn's terminal too, so a late `SubagentStop` no longer un-hides a row already retired.

**Costs and boundaries.**

- The case `dff7d66` was fixing does not come back: the window still starts when the thread stopped working, so a row is not erased in the instant its badge clears.
- A row whose Turn was read *before* it finished is unaffected — a focus earlier than the `Stop` never showed anybody this answer, and still reads as unread.
- The narrower consequence is deliberate: once the thread stops working, a Turn already read stays read. A user who read the answer and then wanted to be told about the subagent's own outcome is not served by this row, and never was — the row reports its Turn.

