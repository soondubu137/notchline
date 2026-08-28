# A Turn may end on evidence that is not a Hook event

When a user presses `Esc` to interrupt a Turn in Claude Code, **no hook arrives at all**. Measured on 2.1.235 (2026-08-18): the CLI's hook event table has 31 events and none of them means cancelled or interrupted, and every interrupt path in the query loop returns before the `Stop` hook runs (a subagent's `SubagentStop` does run — the log line in the code reads `SubagentStop on interrupted query failed` — with no main-agent counterpart). The next event after an interrupt is `SessionEnd` when the session exits.

So the row freezes in whatever state the interrupt caught it: *Running* with its timer still counting, or — if `Esc` landed on an approval dialogue — permanently at **Approval needed**, a state that explicitly asks the user to act while nobody is waiting.

## Decision

**Allow one non-event piece of evidence to end an already-open Turn, and only to end it.** That evidence is the working status a Claude Code session reports about itself: besides identity, `claude agents --json` gives `status` (`busy` / `waiting` / `idle` / `shell`) and `waitingFor`. When a session reports `idle` or `shell` while the reducer still holds an open Turn for it, that Turn goes to Completed.

Four boundaries, all required:

1. **It may not open, name or describe any Turn.** This reading contains no Turn identity whatsoever. It can only tell the reducer, about a Turn it already holds, that nobody is working on it any more. Running / Input needed / Approval needed remain Hook-decided.
2. **It takes effect inside the reducer**: `HookEventRepository.endTurnsForStoppedSessions(_:)`. "One Turn reducer" therefore still holds literally — the service layer hands over a fact about a **session**, not an amended Turn. The Codex side's `removeThreads(notIn:snapshotStartedAt:)` has long had the same shape: a second source retiring something inside the same actor, behind an ordering guard.
3. **Ordering guard: the reading must be entirely later than the Turn's last event**, comparing against the moment the command **started** running, not when it answered. The list is cached for up to 30 seconds and the answer in hand is often older than events that arrive afterwards; comparing at answer time would let a read spanning a submission report a Turn it never saw as idle.
4. **Only a positive stop counts.** `busy` and `waiting` mean the session is working — under `waiting` the Turn is alive and merely parked in front of the user, which is the reducer's own state and not this reading's to overwrite. **The field being absent entirely** likewise does nothing: a desktop-hosted session never has it (see #41 — it runs the CLI as `stream-json` with no terminal interface, and this field is written by the terminal interface), and neither do older CLI versions. Silence is not another way of saying idle.

## This does not violate "state is never guessed"

`AGENTS.md` §6.2 forbids **inferring business state from a timer**. There is no timer here: a Turn that has been quiet for a long time is still not a Turn that ended, which is why this repository has never added a timeout for interrupts. What changed is that observable evidence appeared — the session no longer says it is working — not that a new way of guessing did.

For the same reason this decision does **not** take the other route: matching the fixed string `[Request interrupted by user]` in the transcript. That would either make the product read message bodies (conflicting with a promise already written down) or rest on a structural rule for telling an interrupt record from a slash-command record. Session status is nearer, faster and cheaper, and it is already in the output of a command this app treats as authoritative.

## Costs

- **Desktop-hosted sessions are not fixed** (#41). They do not report `status`, so by boundary 4 nothing happens and those rows still freeze. A deliberately partial fix. **Filled in 2026-08-19, below.**
- **One more non-public dependency**: the command is public and so is `--json`, but these fields' vocabulary and semantics are not. It is registered in `non-public-codex-integration-features.md`, and any value outside the vocabulary is treated as "did not report" rather than guessed into working or idle — the wrong guess retires a live Turn out from in front of the user.
- **It needs an edge of its own.** That record is rewritten in place and a directory-level watcher does not fire for it (measured: an in-place rewrite produces 0 events), so this reading would otherwise wait for the next refresh — at worst one heartbeat (60 seconds). `ClaudeCodeSessionRecordWatcher`, added afterwards, watches the record files of sessions whose Turns are still running (still only as a signal, never parsing contents), compressing that to one debounce. This decision does not depend on it: without the edge the conclusion is the same, only slower.

## Addendum, 2026-08-19: a second piece of evidence, and it names the Turn

The first cost above no longer holds. Desktop-hosted sessions still never report `status` — that is written by the terminal interface and they have none, and this decision's judgement on that is unchanged — but they do not leave nothing behind: when Claude Code aborts a Turn it writes a `user` record into its own transcript, and that record carries the aborted Turn's `promptId`. **So a second non-event evidence may end an already-open Turn, again only end it**: `HookEventRepository.endInterruptedTurns(_:)`.

**This overturns the rejection above, and the reason must be stated.** The original text rejected the transcript route as "either the product reads message bodies, or it rests on a structural rule for telling an interrupt record from a slash-command record". The first half is still true and still not done; the second half was wrong — the rule exists, it just has to ask one more question than was assumed. The rule is: a `user` record whose `message.content` is **exactly one `text` block**, with no `promptSource` and no `isMeta`. Measured 2026-08-19 across every transcript on this machine (205 files, 7,438 `user` records): it matched 15 of 15 interrupt records and nothing else. The version without the `content` shape check also matched 202 slash-command and `<local-command-stdout>` records, 23 of which had the model continuing to work on the same `promptId` afterwards — so that is not an imprecise rule but a rule that retires running Turns, and that sentence has to come from measurement rather than reasoning.

Boundary 1 therefore needs rewriting rather than restating. It said "it may not open, name or describe any Turn", where "name" described the shape of the evidence itself: the session-status reading holds no Turn identity. This one does — `promptId` is the hook's `prompt_id` (measured on 2.1.237: `UserPromptSubmit` and the interrupt record carry the same id). **Evidence that carries identity is pinned tighter, not looser**: it can end only the Turn it names, and does nothing when it names a Turn the reducer does not hold, whereas the identity-free reading can only speak about "whichever one is open now". So the boundary is properly written as a constraint on **capability**, not on shape: both pieces of evidence may only **end** an already-open Turn and may never open or describe one, and the one that can name a Turn must also name the right one.

The other three boundaries hold unchanged. The ordering guard is sharper here — it compares against the moment the record was **written**, not the moment this app read it. So is "only a positive stop counts": no record, nothing happens; a record with an unreadable timestamp or a structure that does not match, likewise nothing.

Cost: **one more use of a non-public dependency.** The transcript is already a registered private read-only schema (titles and today's usage read it); what this adds is a new question — "was this Turn interrupted?" — and a new structural rule, both registered in `non-public-codex-integration-features.md`. Plus an edge of its own: an interrupt does not rewrite `~/.claude/sessions/<pid>.json`, so `ClaudeCodeSessionRecordWatcher` cannot see it and `transcriptWatcher` watches those sessions' transcripts by file. It does not mark the session list stale, because the answer is not in that command.

## Addendum, 2026-08-23: the same reading can also end a **wait**

Boundary 4 says "`busy` and `waiting` mean the session is working", and then waves both through. **Waving `busy` through is right; what was missed is that while it cannot end a Turn, it answers a different question: is the dialogue still there?**

The cost of missing it is a definite misreport. **Claude Code emits no hook when a person approves an approval.** `PermissionRequest` opens the wait, and the next event to arrive is that call's own `PostToolUse` — which lands when **the tool finishes**, not when the dialogue closes. At 200 ms the two are indistinguishable; at ten-plus seconds the row reads *Approval needed* for the whole execution, asking the user to answer a question they just answered. Subagents are where it shows (an unawaited `Agent` call plus a long command, the parent Turn long since `Stop`ped), but the shape has nothing to do with subagents: approving a slow command on the main thread is the same thing.

Measured 2026-08-23 on CLI 2.1.241, a subagent asked to sleep 12 seconds, parent Turn `Stop` at +4.90 s:

```text
+6.18  PreToolUse         agent_id=a1f0…  tool=Bash  tool_use_id=toolu_01UX…
+6.22  PermissionRequest  agent_id=a1f0…  tool=Bash  (no tool_use_id)
       claude agents --json: status=waiting, waitingFor="permission prompt"   [+6.37 … +8.37]
+9.35  person approves
       claude agents --json: status=busy                                      [from +9.07, throughout]
+22.72 PostToolUse        agent_id=a1f0…  tool=Bash  tool_use_id=toolu_01UX…
```

**13.4 seconds** of *Approval needed* after the approval. Throughout, the session itself is saying `busy`.

**So this reading is allowed one more job: ending an already-open approval wait.** The service layer still hands over a fact about a **session** and the reducer changes its own state.

Aligned against the four boundaries:

1. **The capability is still only "end".** This reading has no Turn identity and no `agent_id`, so it can open no wait and can only speak to the waits this thread holds right now — the Turn's own, and one in each subagent slot. In a session with no dialogue, none of those waits is in front of the user.
2. **Only positive evidence counts: `busy` only, never "not `waiting`".** `idle` does not prove the dialogue is gone — measured in CC-019, pressing `Esc` while the dialogue is still open reaches `idle` within 160 ms. Reading the end of a wait out of an *absence* closes the one the user is looking at. A session that reports no status (desktop-hosted) again does nothing here.
3. **The ordering guard is pinned to each wait's own opening**, not to the Turn's `lastEventAt`: a read that **started** before a wait opened cannot have seen that dialogue and may not close it. `PendingApproval` records when it opened for this. The cost is at most one refresh, and that refresh is already on its way — `waiting → busy` rewrites the session record, and `ClaudeCodeSessionRecordWatcher` is watching every listed session.
4. **It does not move `lastEventAt`.** This is not the Turn doing anything, and `lastEventAt` is the reducer's only constraint when reconciling membership. (`endOpenTurn` moves it because it *ends* the Turn and must fend off a late event reopening it; nothing here needs fending off — a later `PermissionRequest` is a new dialogue and should reopen the wait.)

Two alternatives rejected. `Notification(permission_prompt)` was already measured in CC-011: it fires on a 6-second keyboard-idle timer and **no notification type means "resolved"**, so it opens later than `PermissionRequest` and cannot close anything. "Wait for `PostToolUse`" is today's behaviour, which treats the approval interval and the execution interval as one span when they are not.

Cost: **one more use of that non-public dependency.** `status`'s vocabulary previously answered only "is this session still working" and now also answers "is there a dialogue in front of the user". Not a new field, but a stronger claim, registered in `non-public-codex-integration-features.md` all the same; everything but `busy` — including new words outside the vocabulary — is still treated as "did not report".

## Further addendum, 2026-08-23 (same day): the sessions the last one only half fixed

The day that section was written, the user reproduced the same misreport in their own environment — the row stayed at *Approval needed* after approval until a 20-second `sleep` finished. The cause is not the implementation but the **evidence's range of applicability**: that whole section was measured on terminal sessions, and the user was testing a **Claude Code desktop-hosted session**, which never reports `status` at all. This is exactly the hole recorded in this ADR's first cost and fixed for **interrupts** in the 2026-08-19 addendum — nobody had connected it to **approvals**.

First a more basic thing had to be measured, since the whole section rests on it: **is there any hook for an approval at all?** On 2026-08-23, CLI 2.1.241, registering **all 31** hook events dug out of the binary with `strings -a` (`ConfigChange`…`WorktreeRemove`) into a throwaway settings file, running a subagent asked to sleep 25 seconds:

```text
+6.69  PreToolUse         agent_id=a0de…  tool=Bash  tool_use_id=toolu_012V…
+6.72  PermissionRequest  agent_id=a0de…  tool=Bash
+9.96  person approves
+10.96 SubagentStop       agent_id=aeed…   ← an unrelated agent, the TUI's own
+36.23 PostToolUse        agent_id=a0de…  tool=Bash  tool_use_id=toolu_012V…
```

**26 seconds between the approval and `PostToolUse`, with not one relevant event.** So this is not a missing registration; there are no events on this path at all. The end of an approval can only be answered by non-event evidence, and the two hosts keep that evidence in different places.

Desktop writes it into its own log, both ends, joined by a request id (`~/Library/Logs/Claude/main.log`, verbatim from the user's reproduction):

```text
18:10:40 Emitted tool permission request c930390d-… for Bash in session local_6c63f909-…
18:10:45 LocalSessions.respondToToolPermission: requestId=c930390d-…, decision=once, …
18:10:45 Received permission response for c930390d-…: once (tool: Bash)
```

**So a third non-event evidence may end an already-open wait**: `ClaudeDesktopPermissionLogReader` reads both line shapes and `ClaudeCodeMonitorService` joins it back to a thread through the `sessionId ↔ cliSessionId` pairing in Desktop's records. The answer goes to **the same entry point as the terminal one**, `HookEventRepository.endAnsweredApprovalWaits(_:)` — deliberately, because both pieces of evidence say one sentence, "this thread has no dialogue in front of the user right now", and differ only in how they prove it.

The four boundaries again, in order:

1. **End only, never open.** The log lines carry neither Turn identity nor `agent_id`. **Only the opening line names a session and only the response line proves a person answered**, so a response that cannot be matched to an opening line is attributed to no session — failing towards leaving the wait in place, which is the permitted direction.
2. **Only positive evidence counts.** No response line, nothing happens. **The decision itself is not read**: `once`, always-allow and deny all equally mean a person answered, and this app has no reason to care which they chose — which incidentally also fixes Desktop **denials**, whose only previous exit was the subagent's own `SubagentStop`.
3. **The ordering guard** is pinned to each wait's own opening. The log's timestamps are local-zone and second-precision, truncating in the safe direction: they can only make a response look older and be rejected, never newer.
4. **It does not move `lastEventAt`**, for the reason above.

Two new costs, stated plainly:

- **Another use of a non-public dependency, and this time it reads log bodies.** That log is already a registered private read-only source (the focus reading uses it), but that one matches a single line shape and extracts a single id; this extracts a session, a request id and a timestamp. Line shapes are a Claude Desktop implementation detail with higher version risk than a CLI field, so the degradation is hard-wired: match nothing and fall back to today's behaviour. **The two questions hold separate cursors** — sharing one offset would let whichever asks first swallow the other's line.
- **An edge of its own, and a conditional one.** The focus reading explicitly refused to watch this file, on the grounds that "an oauth query or a git timing would wake it too". That reason holds only while **nothing is waiting on it**: when a desktop session is parked on a dialogue, the response line is exactly what is waited on, and without an edge it costs a whole heartbeat (60 seconds). So `permissionLogWatcher` points at the file only while "the reducer holds an approval wait whose session reports no status", and at an empty set otherwise — the same "watch only what is worth watching" rule as `recordWatcher` and `transcriptWatcher`. Likewise the log and Desktop's record tree are read only while an approval is open, so CR-Fable-003's "only terminal rows pay" property is not diluted by this change.
