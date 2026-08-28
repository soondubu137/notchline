# Hook events never touch disk: one socket straight into the reducer

Both products' hook payloads are now delivered by `hook.sh` (`sh` + `nc -U`) down a 0600 Unix domain socket, and `AgentHookListener` hands them to `HookEventRepository` in arrival order. **There is no file in between.**

## Why

The event queue existed for exactly one reason: the first Codex-side helper was a shell script with no way to talk to a running process. With a socket, all of this loses its reason to exist:

- atomic temp-and-rename writes, `0600` on every event file, ordering by a `time_ns` filename;
- quarantining corrupt files to `.invalid`, deleting after consumption, rolling back reducer state when a marker fails to persist;
- the `DirectoryChangeWatcher` on the queue directory and the `attachIfNeeded` it retried on every refresh;
- `hookEventDebounceInterval` — **100 ms added to every hook-driven redraw**, on precisely the path where a user is watching one row for a change.

The second socket goes too. `HookPreviewChannel`, `event_id` splicing, `claimPreview` and the retention cap on unclaimed previews all existed only because message text was not allowed into an event file. One socket carrying the whole payload has no such split.

**Deleting the queue also removed a cross-product detour.** `AgentHookListener` received Claude Code's payload from a socket and then wrote it out as an event file, purely so `HookEventRepository` — a directory reader, because of Codex — could read it back. This change deleted that reader's last client. Both products are now one store, one reducer, one transport each. It is the largest simplification here, and a by-product of getting the Codex path right.

`.invalid`'s real consequence is worth recording: this machine had accumulated **155** quarantined files under `agents/claudeCode/events/`, which nothing would ever read and nothing would ever clean. An unparseable payload is now "report a diagnostic and drop it", with nowhere for anything to be left behind. **That sentence was false for half a year**: 6aeb6b9 deleted the queue era's `Ignored a corrupted hook event file.` without giving it a successor, leaving only the dropping (CR-029). Every unreadable payload — including a connection that delivered no bytes at all — is now counted under `deliver`, accumulated for the run, and shown on that product's row in Settings.

## Three rules become architectural properties

- **No launch cutoff.** An arriving event is current by construction: it came down a socket into this process, from a helper that ran moments ago. `AGENTS.md` §6.2's "historical events carry no business semantics" is no longer a check on `received_at` but a property — **there is no backlog, because nothing is written down**. `liveEventCutoff` and backlog classification disappear with it.
- **Message text needs no promise.** It stays in memory because it has nowhere else to go, not because a rule forbids the alternative (PRD §7 deleted that promise).
- **`retiredTurnIDs` stays.** The proposal deleted it along with the cutoff, reasoning that arrival stamps taken on a serial read queue are monotonic, so a late event for a retired Turn cannot exist. That holds for the transport, not the executor: ADR 0013 records Claude Code delivering `Stop` ahead of its own subagent's `PermissionRequest` under one `prompt_id`, and the reducer is shared by both products. The Codex half is unmeasured. So it stays, at the cost of one `Set` per tracked thread.

## Signal only when what is drawn has changed

The store now emits one change signal **only when the rendered projection changes** — status, Turn identity, or the line of text on the row — rather than one per event. A 17-event Turn is one wake-up, not seventeen. This satisfies `AGENTS.md` §7 at the source: redraw count follows what is drawn, not what changed.

Streaming deltas are not in that projection, and that is not an oversight: putting them in means redrawing a sentence the user is reading 3.4 times a second (measured in `system-architecture.md` §6).

**But it needs an edge of its own, and that edge was first drawn too narrow.** This document originally said a row's text was updated incidentally by refreshes from the Turn's own lifecycle events, with only "the row has nothing on it" needing an edge. The first half is false: an ordinary tool call opening and closing changes no field in the projection, so no refresh happens at all between two status changes and the row sits on whatever message it showed at the last one. The edge is now "**the line of text the row will draw has changed**" — still not one per delta, because once the 240-character head is full the rest of a message's deltas return before being stored anywhere (measured on CLI 2.1.234: a 1561-character message woke it twice and then went quiet). It is still reported only for sessions listed at the previous refresh. See `tech-design.md` §11.

## Ordering: one GCD queue handing to one actor

The listener's serial read queue guarantees `deliver` is called in the order payloads landed. It cannot `await` into an actor here — two `Task`s spawned in order are not two `Task`s that run in order. So payloads go in order into a lock-protected inbox and one drain takes the whole array: whichever drain runs first sees a prefix, every payload is reduced exactly once, and the order is arrival order (`AGENTS.md` §6.3).

The same reasoning keeps `MessageDisplay` folding on the read queue, backed by a lock-protected preview store, rather than in the actor's mailbox: that path runs 3.4 times a second, and an actor hop would put it on the product's critical path in exchange for nothing.

## Costs

- **No crash buffer.** The queue was the only place that survived a crash between an event arriving and being reduced. That window is worthless: in-memory Turn state dies in the same crash, and this design already discards everything written before launch.
- ~~**A payload over 1 MB is dropped rather than truncated.**~~ **That judgement was wrong and was changed by CR-030.** Its reasoning — "half a payload decodes to nothing useful" — holds only for decoding the **whole** payload, which is exactly what this path should not do. The fields the reducer reads total a few hundred bytes; everything that grows is what it does not read: `PostToolUse` carries `tool_response` (a large file `Read`, a long stdout, a wide `Grep`), `UserPromptSubmit` carries `prompt` (whatever the user pasted). Using whole-payload size to decide whether a lifecycle event is heard treats a tool result's size as evidence about the Turn. The worst loss was `PostToolUse`: it does not close the wait on its own `tool_use_id`, and the Claude Code side deliberately removes borrowed inference (`reportsApprovalDenials = true`), so the row sat at *Approval needed* until that Turn's `Stop`.

  Field selection now happens **before** decoding: `HookPayloadDistiller` walks the bytes once, keeping only the keys `HookPayload.CodingKeys` knows and skipping every other value — not copying, decoding or measuring it — so `JSONDecoder` receives a few-hundred-byte object. `HookPayload` is still the sole authority on what a field means; this pass only decides which bytes it can see. The transport's ceiling therefore bounds **read-queue time** and no longer bounds what the reducer can be told.

  The cost changed shape rather than disappearing:
  - **Text truncates at 16 KiB; identity does not.** A row draws 240 characters, so shorter text is the same answer; half a `session_id` is a different session, so an over-long identity means dropping the field entirely and the payload with it — the fail-closed side (`AGENTS.md` §6.2).
  - **A connection past 16 MiB is cut, and fields that arrived whole before the cut still count.** Which field it cuts after is decided by the payload's own field order, which nobody guarantees; the same clause also covers the half payload from a client that connects and then stops writing.
  - **Small payloads cost 3 µs more per event.** Measured in Release: a 1.4 KB `PostToolUse` decodes whole in 5.0 µs and select-then-decode in 8.0–9.7 µs, against this path's own 2.06 ms/event. **Around 1 MB it is 4.7× faster** (976 KB: 416 µs → 89 µs) because `JSONDecoder` never looks at the tool result; at 8.8 MB selection is 1.4× slower (3.6 ms → 5.2 ms), a byte-scan becoming memory-bandwidth bound past L2 — and that size previously produced a whole dropped payload, so there is no regression there, only work that did not exist before.
- **The connection closes after handover.** Closing microseconds earlier removes this path's only backpressure: two payloads from one session would be in flight at once, and the ordering the read queue exists for would be decided by the scheduler instead.

## Status

Implemented. `AgentHookListener` is transport only (bind, accept, read one payload, hand it over); `HookEventRepository` holds the reducer, the text and the delivery evidence. `HookPreviewChannel.swift` is deleted. Tests: `aPayloadTheStoreCannotReadIsReportedRatherThanDroppedInSilence`, `theReportOfADroppedPayloadStandsForTheRun`, `whatAProductReportedReachesTheCardThatReportsIt`, `anOversizedToolResultStillClosesTheWaitItBelongsTo`, `aPromptTooBigToForwardStillOpensItsTurnAndStillReadsAsItself`, `aConnectionPastTheCeilingIsCutAndKeepsWhatArrivedWhole`, `selectingFieldsReadsTheSameAsDecodingTheWholePayload`, `anIdentityTooLongToBeOneIsLeftOutRatherThanCutShort`, `aTextFieldIsCutOnlyWhereAJSONStringCanBeCut`, `aPayloadThatStopsPartWayThroughKeepsTheFieldsThatArrivedWhole`, `payloadsAreReducedInTheOrderTheyLanded`, `theStoreSignalsWhatIsDrawnAndNothingElse`, `nothingAThirdPartyCouldReplayIsEverWrittenDown`, `theListenerHandsOverOnePayloadPerConnection`, `aPayloadWrittenAfterTheConnectionIsAcceptedStillArrives`, `messageDisplayTextIsHeldInMemoryAndReducesNothing`, `aPreviewArrivingWhereThereWasNoneAsksToBeDrawn`.
