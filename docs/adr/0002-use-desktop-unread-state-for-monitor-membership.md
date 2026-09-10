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


## Addendum, 2026-09-09: the set moved, and this decision no longer rests on a debounced projection

Codex Desktop `26.903.61454` — installed this morning, up from the `26.820.60940` the addendum above was measured on — moved the blue-dot set out of the renderer's persisted atom map and into a top-level `electron-thread-read-state-v1`, then **deleted** `electron-persisted-atom-state.unread-thread-ids-by-host-v1` as it went. The reader threw `incompatibleSchema` on every pass. Everything downstream then did precisely what it was built to do: an unreadable state is never authoritative, an unauthoritative reading may hide nothing, and so every Completed Codex row stayed on the notch however thoroughly its thread had been read. Reported by the user the same day.

The new shape adds an account identity above the host:

```
electron-thread-read-state-v1: {
  version: 1,
  unreadByIdentity: { <identityKey>: { <executionHostKey>: [threadId] } },
  legacyMigration?: { identityKey, unreadThreadIdsByHostId, adoptedHostIds, cleared? }
}
```

**Decision: read both shapes, take the new key when a file carries both, and merge every identity.**

- The `identityKey` is a SHA-256 over the signed-in account. This app could only reproduce it by reading Desktop's auth material, and will not — nor does it need to. A thread id belongs to exactly one identity, so a union adds nothing that is not this user's, and an identity left behind by an account switch can only *keep* a row listed. Logging out deletes that identity's entry outright, so nothing accumulates. The union is exactly the answer the old schema gave, which had no identity in it at all.
- `legacyMigration` is read for nothing. It holds the old set in the old shape and today matches the live one, which is what makes it dangerous: it records the adoption and is never revised, because the change path only ever rewrites `unreadByIdentity`. Reading it would freeze the answer at the instant the user upgraded — retiring every row read since, and never retiring the ones unread then.
- Host ids became execution host keys — `local` became `local:092af2cb…`, and Desktop's other by-host maps write `local:/Users/…/.codex` — so the "consume only the local host" rule is now a prefix match, with the bare form still legal because the pre-migration schema is still read.
- A `version` this app does not know rejects the file. That is the alarm for the next move: a schema break has to reach the user as a stale row and a diagnostic, never as an empty set that retires everything.

**The 2026-08-26 addendum's measurement no longer describes this set, and its decision stands anyway.** The 500 ms trailing debounce with no max-wait belongs to the key `electron-persisted-atom-state`, and to that key alone: Desktop's global-state store routes every other top-level key straight to a queued write, so the read state is now persisted on every change with nothing able to starve it. The composer draft can no longer hold a blue dot off disk for 45 seconds. `currentAsOf` is kept regardless — it costs one `stat` field already being read, and it is the only thing standing between this product and any future write delay, including one nobody has measured yet.

**Costs and boundaries.**

- A Codex that has never marked a thread unread writes neither key, and the reading is unavailable rather than empty. That fails closed, and it clears itself the first time a Turn completes into an unread thread — which is the first moment a row could need retiring.
- Nothing here changes what the membership gate does with a reading. This addendum is about getting one at all.
