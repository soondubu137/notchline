# Saying one thing across the whole interface while a subagent runs

| Field | Value |
| --- | --- |
| Status | **Adopted and implemented in full (2026-08-23).** §4, §5 and §8.1 landed first; §6 (subagent approvals) landed the same day once both products had been measured. The resulting contracts live in `PRD.md` §6.2/§8.2/§9.3, `CONTEXT.md`'s "derived status", `tech-design.md` §9.2 and `figma-design.md` §4.6. **From here this file is a record of *why*, not a contract** — implementation plans, impact tables and acceptance lists that landed have been removed, and what remains is the measurement and the reasoning |
| First recorded | 2026-08-23 |
| Question | When a Codex Thread's own Turn ends while subagents it spawned keep running, how do the collapsed state, sorting, membership and the row itself say one thing? |
| Scope | Phase one was Codex only; the Claude Code side (§8) was measured and landed the same day |

> The directory convention follows [`shared-app-server/README.md`](../shared-app-server/README.md): one second-level directory per question, with later evidence appended rather than overwriting what is there.

## 1. Correcting a description first

The behaviour after `65e63ab` is **not** "stay Running and write the count where the timer was". The main agent's `Stop` lands as usual, the Turn goes `Completed`, the preview becomes the final answer, the timer stops, and **the count is written in the space the timer vacated** — `runningSubagentSummary` is explicitly conditioned on `!status.keepsTiming`.

The distinction matters: genuinely pinning the row to `Running` puts back the defect `65e63ab` fixed (§7).

## 2. The problem: four rules used status as a proxy for "is this thread still working"

The row itself is right. The problem is **elsewhere**: four rules read `SessionStatus` and assume `.completed` means nothing is happening here. For this kind of row that assumption is false.

| # | Rule | What happened |
| --- | --- | --- |
| 1 | The top summary and product marker | The row contributed only `.completed`. As the last row it made the collapsed state say `Completed`, the matrix draw its finished pattern and the timer disappear (`longestRunningSessionStart` filters on `keepsTiming`) — while the expanded row read `2 subagents`. **The surface the user is actually looking at said the opposite of the truth.** |
| 2 | The unread membership gate | A terminal row is hidden once Desktop reports it read, with the boundary taken from `state.lastEventAt` — and a subagent boundary deliberately does **not** advance `lastEventAt`. So that sentence could be erased one settling interval after the main `Stop` — and the person staring at that thread in Desktop is exactly the one most likely to have just spawned a subagent. |
| 3 | Sorting and the three-row viewport | `.completed` sorts last, so with three other active Turns **the only row carrying evidence that work is still in flight is the first pushed out of the viewport**. |
| 4 | Manual removal | A row actively reporting "work is still in flight" could be dismissed by secondary click and remembered by Turn id, never returning. |

Two more inconsistencies that are not "status used as a proxy":

- **A subagent's approval was invisible.** Events carrying `agent_id` were discarded in pairs, so a subagent's own `PermissionRequest` never reached the row. The row read `1 subagent` steadily while Codex was in fact stopped at a dialogue — **and reporting exactly that state is why this product exists**. A lost `SubagentStop` has the same shape: the count does not move and nothing on the row separates stuck from busy.
- **The future of that trailing text slot.** `CONTEXT.md`'s terminal reason reserves the same position for failure text. Once that exists, "one marker per row and it is the timer" cannot arbitrate between two runs of text. Separately, at the moment the timer stops the trailing element goes from a short timer to a longer run of text (`.fixedSize()` with the panel fixed at `expandedBaselineWidth = 520`), so the title and preview re-truncate at completion — a look-and-feel matter rather than a correctness one.

## 3. The design principle

**The status the row draws does not change; what changes is the question everyone else asks.**

The Turn genuinely ended: the preview genuinely is the final answer, the timer genuinely should stop, and `Completed` genuinely is terminal — `CONTEXT.md`'s thread status is about **the current Turn**, and a subagent is the thread's work rather than that Turn's. So no fifth status, and no change to this row's status.

What needed fixing is that those four rules were really asking "is this thread still working" while using `SessionStatus` as the answer. Give them a real answer.

## 4. The solution

### 4.1 One derived test

```swift
// MonitorAggregation
/// "Is this thread still working" — a different question from what the row draws.
/// The two diverge only when `.completed` still has subagents running.
nonisolated static func effectiveStatus(of session: MonitoredSession) -> SessionStatus {
    session.status == .completed && session.hasRunningSubagent ? .running : session.status
}
```

> This section originally added "so it is the identity transform for Claude Code", and **that stopped being true the day it was written**. Claude Code's count was zero because the two subagent boundaries were not registered there yet, not because it has no subagents (§8.1). The test needs no change — it reads the count rather than the product — but "identity for Claude Code" holds only for **rows with no subagent running**, on any product.

### 4.2 Summary and sorting: one change, because the PRD already says they are one rule

`PRD.md` §6.2 says "the list sorts by the same priority", so both `MonitorAggregation.status` and `rowOrder` read `effectiveStatus`, and §2's rules 1 and 3 are solved together rather than with two separate justifications.

The collapsed state then says `Running` with the Codex mark animating Running's pattern, **and with no timer reading** — `longestRunningSessionStart` filters on `keepsTiming` and finds nothing, which is right: the collapsed state times Turns, and no Turn is timing. (§5's decision later half-rewrote this: the trailing wing no longer disappears with the timer, because the count was promoted into exactly that cell.)

`marks(agents:sessions:)` calls through to `status(agents:sessions:)`, so product marks follow automatically.

### 4.3 The unread gate: it must not delete the only evidence

Two halves, both required:

1. **The gate reads the derived test.** `shouldDisplay` receives `effectiveStatus`'s answer, so this row takes the non-terminal path: not hidden, its entry dropped, no per-second re-check — exactly like a Running row.
2. **The moment the count clears needs its own boundary.** With only the first half, the entry at the last `SubagentStop` still uses a long-past `lastEventAt` whose settling has expired, and the row vanishes **immediately**. So `HookTurnState` gained `lastSubagentBoundaryAt`, stamped in `reduceSubagentBoundary`, **read only by this gate**, with `terminalBoundaryAt` taking `max(lastEventAt, lastSubagentBoundaryAt)`.

`lastEventAt` itself is untouched to the byte, and `65e63ab`'s reasoning for it (not letting subagent activity fend off membership reconciliation, the reducer's only bound) stands unchanged.

### 4.4 Manual removal: unchanged

`isDismissable == (status == .completed)` looks like the most glaring of §2's four, and it should not move: removal means "I have seen this row", the user's judgement outranks everything this app knows, and when a count sticks it is the only human exit. That is documented rather than quietly kept.

### 4.5 The row itself: not one word

`SessionStatusControl` still decides between drawing the timer and the count from `session.status`, the preview is still the final answer, and the accessibility label still reads `N subagents still running`. `effectiveStatus` **must not** enter the row's rendering path — the moment it does, the row starts timing again, which is the rejected approach (§7).

## 5. The one judgement call: promoting the count to the collapsed state

Wiring it into the summary raises the cost of a known failure mode: with `SubagentStart` arriving and `SubagentStop` never doing so, what used to be one stalled line of text becomes **the whole collapsed state sitting at `Running` with the matrix animating** until that thread leaves the list.

No safe fallback exists, and both were checked: timer inference is banned by `AGENTS.md` §6.2, and the App Server cannot answer — subagent threads carry `parentThreadId`/`agentRole` and never become rows, while "how many subagents are running" is in no Thread payload, so `thread/list` cannot self-heal either.

**Still recommended.** The collapsed state saying `Completed` while work continues is wrong every single time; a stuck count is occasional and already has a human exit (§4.4).

### 5.1 Decision (2026-08-23): adopt, and draw the count itself

Adopted, and one step beyond the recommendation — the collapsed state does not merely draw **as** Running, it says **how many**. The trailing cell is shared by the timer and the count:

| List state | Trailing wing |
| --- | --- |
| No subagents, a Turn timing | `1:23` |
| Subagents, a Turn timing | `2 │ 1:23` |
| Subagents, every Turn finished | `2` |
| No subagents, every Turn finished | the whole wing disappears (as before) |

The reasoning: the count is the only thing in this form that explains where `Running` came from. Drawing Running without the number makes the collapsed state a status word with no reading, whose only check is expanding the panel — and the panel was always right; what this change buys is being right without expanding. The row-end rule ("one marker, the two never coexist") does not apply here: a row-end cell belongs to one row while the collapsed cell belongs to the whole list, so the timer describes the longest Turn and the count describes how many subagents remain — not one sentence said twice.

The separator is `U+2502` (BOX DRAWINGS LIGHT VERTICAL) with one ordinary space each side: in SF Pro it is the same width and nearly the same shape as an ASCII bar, and it is taken because it is a dividing rule rather than a character. The whole string is drawn on one raster (`ElapsedReadout`'s `prefix`), because only its timer half changes every second while panel width must come from **one** measurement.

The cost stands as §5 records it, is written into `PRD.md` §6.2 and the non-public registry, and is tracked separately in [#102](https://github.com/soondubu137/notchline/issues/102) (CR-033): a permanently lost `SubagentStop` leaves the collapsed state at `Running` showing a number that never reaches zero, until that Thread leaves the list or the user right-clicks the row away.

## 6. Subagent approvals

All the parts were already there: a subagent's `PermissionRequest` does reach the parent thread's hooks — the original takeover defect was caused by exactly those events — and it was being discarded in pairs.

The proposal was to **consume it into a thread-level flag** `subagentsAwaitingApproval` rather than dropping it (pairs still drop in pairs, so the lost-trust probe is unaffected), with the same trailing position drawn in the **bright** treatment while the flag is set. Still one position and one run of text, and brightness is already this app's attention channel.

**The prerequisite measurement** (originally not done, and taken 2026-08-23) was whether that approval's closing event carries the same `tool_use_id` and its own `agent_id`, or the flag can never clear and degrades into a permanently lit row. **The answer is half and half**: approval carries both, while a human refusal **emits nothing at all** — so the flag cannot be cleared by pairing alone, and §6.2's closing rules became three plus a cap rather than the proposal's one.

### 6.1 Claude Code measurement (2026-08-23, CLI `2.1.241`)

The probe uses the throwaway `--settings` plus `--setting-sources project` method, but here it must be a pty interactive session: under `-p` the tool simply runs and no `PermissionRequest` is ever produced. The same prompt ("use `Agent` to start a general-purpose subagent to run `sw_vers -productVersion`, and do not wait for it") ran four times, differing only in what was done once the dialogue appeared — approve, `Esc` to refuse, leave it — plus one main-thread refusal as a control.

The approval run's arrival order:

```text
+ 0.00  UserPromptSubmit   prompt=808f…
+ 2.78  PreToolUse         prompt=808f…                  tool=Agent  tool_use_id=toolu_0182…
+ 2.80  SubagentStart      prompt=808f…  agent_id=a28a…  agent_type=general-purpose
+ 4.21  Stop               prompt=808f…  background_tasks=[{id: a28a…, type: subagent, status: running}]
+ 4.73  PreToolUse         prompt=808f…  agent_id=a28a…  tool=Bash   tool_use_id=toolu_015Z…
+ 4.75  PermissionRequest  prompt=808f…  agent_id=a28a…  tool=Bash   (no tool_use_id)
+11.72  PostToolUse        prompt=808f…  agent_id=a28a…  tool=Bash   tool_use_id=toolu_015Z…
+14.97  SubagentStop       prompt=808f…  agent_id=a28a…
```

Six conclusions, the first four deciding the design:

1. **A subagent's approval has the main thread's shape.** `PreToolUse` carries a `tool_use_id`, and 20–30 ms later `PermissionRequest` carries `tool_name` and **not** a `tool_use_id` — which is what the official schema says too (`PermissionRequest`'s own fields are `tool_name`/`tool_input`/`permission_suggestions?`; Codex's `permission-request.command.input` likewise has no `tool_use_id` but does have an optional `agent_id`). So that wait can only borrow an already-open call, and it must be one **this subagent itself** has open. What §8.2 inferred — that the Turn needs per-agent slots — became a requirement rather than an option.
2. **The dialogue does not necessarily open after the Turn ends.** In the approval run `Stop` was at `+4.21` and the dialogue at `+4.73`; another run reversed them, with the dialogue at `+4.02` and `Stop` at `+4.17`. Both were measured, so this is not specific to terminal rows: a row that is still Running can equally have a subagent stuck at a dialogue — and such a row draws no count at all today (`runningSubagentSummary` is conditioned on `!status.keepsTiming`).
3. **Approval closes precisely, refusal emits nothing.** The approval run's `PostToolUse` arrived with the same `agent_id` and the same `tool_use_id`. The `Esc` refusal (the TUI afterwards wrote "It was denied permission to run the Bash command") produced **no `PermissionDenied` and no `PostToolUse`**; the only event afterwards was that subagent's own `SubagentStop`, 6.9 s later.
4. **`PermissionDenied` does not mean "a person refused".** The binary has one production site for it, whose only call site is gated on `decisionReason?.type === "classifier" && decisionReason.classifier === "auto-mode"` — it reports **the automatic-mode classifier** refusing, and pressing `No` does not produce it. Tested separately on the main thread (arrowing to `No`, with `❯No` visible in the TUI): no `PermissionDenied`, no `PostToolUse` and not even a `Stop` in the following 90 seconds — a human refusal **interrupts** that Turn, and the official hooks have no interrupt event.
5. **The TUI's own internal agents also carry `agent_id`.** Across four runs there were three `SubagentStop`s with no paired `SubagentStart` (`agent_type` an empty string) and one `PreToolUse` with `agent_type` absent (`agent_id=a1ba…`, tool=Bash). So **no slot opened by `agent_id` may itself be evidence that this thread has a subagent running** — only `runningSubagentIDs` can give that, and only the two boundary events add to it.
6. **There is one absolute reading, and only Claude Code has it.** While the subagent's dialogue is open and the parent Turn has already `Stop`ped, `claude agents --json` reports that session as `status: "waiting"`, `waitingFor: "permission prompt"`. This app already reads that field ([ADR 0011](../../adr/0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md)). It cannot be the primary source — no Turn identity, no agent identity, one reading per cadence, and desktop-hosted sessions never have it — but it is an absolute reading, and the "measured but not adopted" note below returns to it.

### 6.2 The design (implemented): per-agent slots rather than a gate

**The gate became a diversion.** The `if stableIdentifier(event.agentID) != nil { return true }` no longer means "consume in pairs" but hands off to `reduceSubagentToolEvent`, under the same discipline as `reduceSubagentBoundary`: it does not enter `mutateExactTurn`, does not read or write `turn_id`, and does not advance `lastEventAt`. A `turnStarted`/`turnEnded` carrying `agent_id` is still dropped — Codex's `stop.command.input` has no `agent_id` at all, so that is purely defensive.

**The Turn gains a table indexed by agent.**

```swift
/// What one agent has open. The main agent uses the Turn's original three slots,
/// and each subagent has its own, indexed by `agent_id`.
nonisolated struct AgentWaitSlots: Sendable {
    var pendingInputToolUseID: String?
    var pendingApproval: PendingApproval?
    var openToolUse: OpenToolUse?
}

var subagentSlots: [String: AgentWaitSlots] = [:]
```

A thread-level fact at the same level as `runningSubagentIDs`, copied across Turn boundaries (measurement 2: a dialogue may open after `Stop`, so that slot must outlive the Turn). The main agent's three slots are untouched, so every existing main-thread behaviour — borrowed ids, `request_permissions`, `Elicitation`, terminal clearing — is unaffected.

**Three closing rules plus a cap**, in the order of the outcomes they cover:

1. **Any closing event on the same `(agent_id, tool_use_id)`** — `PostToolUse`/`PostToolUseFailure`/`PermissionDenied`/`ElicitationResult` — clears that slot's wait. This is the **approval** path, and also Claude Code's automatic-mode classifier refusing (conclusion 4).
2. **Activity on another call by the same agent** clears the borrowed wait — `resolveInferredApproval` moved across with its scope narrowed from the whole Turn to one slot. This is the **human refusal** path: measurably neither product emits anything (Codex's 67 seconds of silence on 2026-08-15, and Claude Code's conclusions 3 and 4). So "does this product report refusals" is **"no" on both** for a subagent slot, and `reportsApprovalDenials` takes no part in it.
   > Claude Code originally had this inference off because "`Stop` was measured arriving before its own subagent's `PermissionRequest`". Conclusion 2 shows that is not out-of-order delivery but the shape of an asynchronous subagent — the `Agent` call returns immediately, the Turn ends first, and the subagent asks later. **Per-agent slots dissolve that reason**: that `Stop` and that `PermissionRequest` land in two slots, and one stream's activity can no longer reach the other's wait.
3. **That agent's `SubagentStop` deletes the slot outright.** In the measurement it is the only event after a human refusal, so this is a backstop rather than a supplement.
4. **The cap: the drawn flag recognises only agents in `runningSubagentIDs`.**

```swift
/// Is one of this thread's subagents stuck at a dialogue.
nonisolated var subagentsAwaitingApproval: Bool {
    subagentSlots.contains {
        runningSubagentIDs.contains($0.key) && $0.value.pendingApproval != nil
    }
}
```

That keeps conclusion 5 (internal agents also carry `agent_id`) out, and guarantees **the flag can never outlive the count**: however the count clears — `SubagentStop`, right-click removal, the row leaving the list — the flag goes with it. So §5.1's already-accepted cost ([#102](https://github.com/soondubu137/notchline/issues/102)) remains the only place anything can stick, and this adds no second one.

**The derived status gains a clause.** `effectiveStatus` now reads two facts:

```swift
// Someone is being asked, which beats "still working": a thread can be both.
if session.subagentsAwaitingApproval, session.status != .inputNeeded {
    return .approvalNeeded
}
return session.status == .completed && session.hasRunningSubagent
    ? .running
    : session.status
```

`inputNeeded` still beats approval (`PRD.md` §6.2's priority, and the state machine's "approval yields to input"). Note this clause **also diverges for Running rows** — measurement 2 says that genuinely happens — while §3's principle is unchanged: a row draws its own Turn, and the derived status answers whether this thread needs a person.

**The row gains one brightness and changes nothing it draws.** What §4.5 forbids is letting the derived status decide what the row **draws** — that would restart the timer and stop the preview ever reaching the final answer. It does not forbid deciding how **bright** it is. So `SessionStatusControl.wantsAttention` became either-of-two, and that trailing cell draws in the bright Medium treatment. The accessibility copy has to say it in words (`1 subagent still running, waiting for approval`) — brightness cannot be read aloud.

**Codex's `auto_review` subtraction: do it.** This originally read "do not, deliberately", because the registry recorded that `heartbeat-thread-permissions-by-id` has **no entries for subagent threads**, so nothing could answer whether a subagent's approval also goes to the automatic reviewer; and the two directions were asymmetric, since getting it wrong **hides a real dialogue**. **§6.3's second measurement settled it: 72/72 inherit the parent thread's `approvals_reviewer`, with no exceptions.** So `approvalsReachTheUser(threadID)` is asked with the row's own (the parent thread's) threadID and its answer holds for the subagents it spawned.

**Failure directions**

| Direction | Consequence | Exit |
| --- | --- | --- |
| `SubagentStop` lost permanently with that slot still waiting | The collapsed state sits at `Approval needed`, lit — louder than #102's "stuck at Running" | Yes, and the same one: right-click the row away. The flag is capped inside the count, so both go together |
| The permission pipeline ran but nobody was asked (Codex `auto_review`, Claude Code automatic mode) | About 2.5 seconds of false brightness | Self-healing — a classifier's decision brings a closing event (rule 1) |
| `agent_id` renamed or removed | Those events fall into no slot again, reverting to the old behaviour: the row reads `N subagents` and approvals are invisible | No exit needed; this is the safe direction |
| A subagent's `PreToolUse` counted into the lost-trust probe | `observedPreToolUseCount` is read only when `== 0`, so over-counting cannot misfire; **counting only closes and not opens would** — so both are counted or neither, never one half | — |

#### Landing record (2026-08-23)

Implemented as above, with four differences from what was written, recorded here rather than quietly changed:

1. **The `auto_review` passage inverted entirely**, because §6.3 measured the inheritance. It said "no subtraction" and the implementation subtracts.
2. **`ClaudeCodeHookVocabulary.reportsApprovalDenials` changed from `true` to `false`**, fixing the pre-existing defect noted below in the same change. It is not a bonus: a subagent's slot must infer regardless, and letting the same reducer go on pretending this product reports refusals on the main thread would leave two contradictory rules side by side. The existing `aProductThatReportsRefusalsDoesNotInferThemFromUnrelatedActivity` pinned the old behaviour and was rewritten as `neitherProductReportsAHumanRefusalSoBothInferIt`, where only the Claude Code assertion of three flipped.
3. **`pendingInputToolUseID` is also per-agent, but not drawn.** Separating it keeps pairing correct (one slot's `AskUserQuestion` must not be closed by another's `PostToolUse`); not drawing it is because "would a subagent's question actually reach a person" is unmeasured, and a prompt this app cannot vouch for is worse than none.
4. **`renderedProjection` carries one more field.** That is the projection the reducer uses to decide whether to wake the panel; without the flag in it, the collapsed state would wait for some other event to catch up.

**Measured but not adopted: `claude agents --json`'s `waiting` reading.** It can do two things this design cannot — confirm (the dialogue really is open) and **clear** (no `waiting` means nobody is being asked, an absolute reading that therefore cannot stick). Not adopted here for three reasons: one reading per cadence is too slow for the state this product reports; desktop-hosted sessions never have it ([#41](https://github.com/soondubu137/notchline/issues/41)); and it belongs to Claude Code alone with no Codex equivalent, so adopting it means one thing drawn two ways. If #102 ever gives Claude Code a self-heal, this and the `background_tasks` route should be considered together — both are absolute readings and both should only ever subtract.

**A pre-existing defect found in passing, recorded rather than hidden.** `reportsApprovalDenials = true` holds only for the **classifier's** refusal (conclusion 4). When a person presses `No`, Claude Code emits nothing while `infersDenials` is off because of that `true`, so a main-thread row reads `Approval needed` until `claude agents --json` reports `idle` and takes that Turn to Completed (ADR 0011), or, for a desktop-hosted session, until the transcript's interrupt record. This is the same rule from the other side: **refusal is silent on both products**, so the "activity on another call means a person answered" inference is needed on both.

#### Follow-up (2026-08-23): half of "measured but not adopted" was overturned

The day this landed, the user hit the hole it did not cover: *"a subagent raises an approval, the row goes Approval needed, and **after approving it does not go away** — it stays until the ten-second sleep finishes."*

Not an implementation gap but a missing exit in §6.2's model. **Claude Code emits no hook when a person presses approve.** That slot's wait can therefore only await that call's own `PostToolUse` — which lands when **the tool finishes** rather than when the dialogue closes. At 200 ms the two are indistinguishable; at ten-plus seconds the row spends the whole execution asking the user to answer a question they already answered. The landing record's "refusal is silent on both products" was about **refusal**; this is **approval**, equally silent, only with a late closing event behind it that made it look covered.

Measured (2026-08-23, CLI `2.1.241`, parent `Stop` at +4.90 s, the subagent asked to sleep 12 seconds):

```text
+6.18  PreToolUse         agent_id=a1f0…  tool=Bash  tool_use_id=toolu_01UX…
+6.22  PermissionRequest  agent_id=a1f0…  tool=Bash  (no tool_use_id)
       claude agents --json: status=waiting, waitingFor="permission prompt"   [+6.37 … +8.37]
+9.35  person approves
       claude agents --json: status=busy                                      [from +9.07, throughout]
+22.72 PostToolUse        agent_id=a1f0…  tool=Bash  tool_use_id=toolu_01UX…
```

**13.4 seconds of misreport after the approval, while the session itself says `busy` throughout.** So the three reasons for rejecting that reading were re-examined:

1. "One reading per cadence is too slow" — **does not hold.** That is the figure with no edge. `waiting → busy` rewrites `~/.claude/sessions/<pid>.json`, and `ClaudeCodeSessionRecordWatcher` already watches **every listed session** rather than only those with a Turn running, with the registry's `edgeFloor` compressing a burst of flips to one read every two seconds. The wait therefore closes within one debounce plus one `claude agents --json`.
2. "Desktop-hosted sessions never have it" — **holds, but this is a deliberate partial fix**, the same shape ADR 0011 itself originally had. Those sessions keep today's behaviour.
3. "It belongs to Claude Code alone" — **does not apply.** This rule draws nothing new; it only **closes** a wait. The Codex side is unchanged and both products still draw the same thing.

What is adopted is the smallest of its three abilities: not confirming (only `PermissionRequest` says a dialogue is open), not self-healing, only answering "a person has already answered". And **only `busy` counts, never "not `waiting`"** — `idle` does not prove the dialogue is gone (CC-019: pressing `Esc` with it still open reaches `idle` within 160 ms), and reading the end of a wait out of an absence closes the one the user is looking at.

#### Correction (2026-08-23, same day): that section fixed only terminal sessions

After writing the above the user reproduced it and **the problem was unchanged**: still at *Approval needed* after approving, until a 20-second `sleep` finished. The direction was right and the coverage was wrong — that whole section was measured only on a pty TUI, while the user was testing a **Claude Code desktop-hosted session**, which never reports `status` at all (measured: its `~/.claude/sessions/<pid>.json` carries `entrypoint: "claude-desktop"` with no `status`/`updatedAt`/`statusUpdatedAt`, and is never rewritten after the session starts). So the `busy` rule does not apply to it at all. **The lesson, recorded here: the host is a real dividing line in this product, and any non-event evidence must be measured once per host — measuring one is measuring neither.**

A more basic thing was measured in passing, since the whole design rests on it: **is there any hook for an approval.** Registering **all 31** events dug out of the binary with `strings -a` and running a subagent asked to sleep 25 seconds gave 26 seconds between the approval (+9.96 s) and `PostToolUse` (+36.23 s), with the only arrival being an unrelated agent's `SubagentStop`. **No event was missed from the registration; there are simply no events on this path.**

The desktop writes the evidence into its own log (`~/Library/Logs/Claude/main.log`, verbatim from the user's reproduction):

```text
18:10:40 Emitted tool permission request c930390d-… for Bash in session local_6c63f909-…
18:10:45 LocalSessions.respondToToolPermission: requestId=c930390d-…, decision=once, …
18:10:45 Received permission response for c930390d-…: once (tool: Bash)
```

Only the first line names a session and only the third proves a person answered, with the request id pairing them — the same shape as §6.2 having `PermissionRequest` borrow an open call's id. Landed as `ClaudeDesktopPermissionLogReader`, joined back to a thread through Desktop's records (`sessionId ↔ cliSessionId`), with the answer going to **the same entry point as the terminal path**, `HookEventRepository.endAnsweredApprovalWaits(_:)`. **The decision itself is not read**, which also fixes desktop **refusals** — that half previously had to await `SubagentStop`. The log and Desktop's record tree are read, and the edge built, only while an approval is genuinely open. See ADR 0011's two 2026-08-23 addenda.

### 6.3 Codex measurement (2026-08-23, Codex CLI `0.149.0-alpha.4.1`)

Two things: one run, and one read out of existing rollouts. The user's `~/.codex` was read-only throughout — `hooks.json` was not touched.

**One: a subagent's approval really does land on the parent thread's hooks, matching Claude Code point for point.** With an isolated `CODEX_HOME` (a symlinked `auth.json`, its own `config.toml` and `hooks.json`, and the definitions trusted by taking `currentHash` from `codex app-server`'s `hooks/list` and writing it into `[hooks.state."<key>"]`), `codex exec --approve-for-me`, and a prompt telling the main agent to `spawn_agent` a subagent to run a network command the sandbox blocks:

```text
+ 3.50  PreToolUse         tool=collaboration…spawn_agent  tool_use_id=call_sx15…  turn_id=01a03064…(parent)
+ 4.59  SubagentStart      agent_id=01a03065-0ff5…  agent_type=default
+ 8.15  PreToolUse         agent_id=01a03065-0ff5…  tool=Bash  tool_use_id=exec-b66c8f31…   ← the sandboxed attempt
+ 8.34  PostToolUse        agent_id=01a03065-0ff5…  tool=Bash  tool_use_id=exec-b66c8f31…
+12.78  PreToolUse         agent_id=01a03065-0ff5…  tool=Bash  tool_use_id=exec-5aaefacb…
+12.81  PermissionRequest  agent_id=01a03065-0ff5…  tool=Bash  (no tool_use_id)
+18.51  PostToolUse        agent_id=01a03065-0ff5…  tool=Bash  tool_use_id=exec-5aaefacb…   ← the reviewer answered
+20.79  SubagentStop       agent_id=01a03065-0ff5…
```

Four conclusions:

- `PermissionRequest` **does arrive**, with `agent_id` and without `tool_use_id` — word for word §6.1's conclusion 1. The borrowing rule is one rule for both products.
- **Three identities, each its own**: `session_id` is the **parent thread** (`01a03064-fd1b…`), `agent_id` is the **subagent's own thread id** (`01a03065-0ff5…`, equal to the `id` of its own rollout), and `turn_id` is the **subagent's own Turn** (`01a03065-100a…`, not the parent's). That is exactly why these events must never enter `mutateExactTurn`, and the cause of the original takeover defect. Claude Code stamps the parent Turn's `prompt_id` instead — **the one place the two products differ** — and per-agent slots hold for both stampings, because a slot never asks for a `turn_id`.
- `PostToolUse` **closes precisely** on the same `(agent_id, tool_use_id)` (5.7 s here, the reviewer's decision time).
- The same subagent opened **two** calls in one slot in sequence (`exec-b66c8f31` and `exec-5aaefacb`), so §6.2's rule 2 ("activity on **another** call by the same agent") genuinely occurs in a real event stream rather than only on paper.

One negative observation supports `PRD.md` §14.2's "a lone `PermissionRequest` does not misreport": running the same prompt non-interactively with `approval_policy="on-request"` (nobody present to ask, so it resolves to `never`), `PermissionRequest` **does not fire at all** and the subagent runs both its commands.

**Two: a subagent inherits the parent thread's approval routing, 72/72.** This was the one place §6.2 chose conservatively for lack of measurement, and the answer makes conservatism unnecessary. The method reads 119 rollouts under `~/.codex/sessions` read-only: 77 carry `parent_thread_id` (subagents), and 72 have their parent's rollout on disk too. Comparing each subagent rollout's first `turn_context.approvals_reviewer` against the parent rollout's most recent `turn_context` value **at the moment it was spawned**:

| Result | Count |
| --- | --- |
| Same as the parent thread's `approvals_reviewer` then | **72** |
| Different | **0** |
| Parent rollout not on disk, not comparable | 5 |

Both values occur (1996 `auto_review` and 21 `user` across subagent `turn_context`s), so this is not a false agreement from only one value existing on disk. The probe's own two rollouts have the same shape: the `--approve-for-me` parent and the subagent it spawned both say `auto_review`.

**So §6.2's "do not subtract" is void and becomes "subtract"**: `approvalsReachTheUser(threadID)` is asked with the row's own (the parent thread's) threadID, and the answer holds for its subagents. The original worry — subtracting wrongly hides a real dialogue — does not arise: on a thread proven `auto_review`, the subagents it spawns are in the same reviewer's hands, and that `PermissionRequest` was never going to reach a person.

**Three: something seen in passing that supports §6.2's cap.** The `--approve-for-me` reviewer **is itself a nested agent**: the probe directory held a third rollout whose `parent_thread_id` is that subagent and whose `session_id` is still the root session, and it has **no** `SubagentStart`. So agents that "carry `agent_id` while never having announced themselves" exist on both products (Claude Code's TUI internal agents, §6.1 conclusion 5; Codex's reviewer), making §6.2's cap a shape both sides need rather than a patch for one product.

**Four: one thing not measured, which changes no design.** What Codex emits when a person **refuses** a subagent's approval in an interactive TUI was not measured separately. The reasoning: the main-thread path was measured on 2026-08-15 (67 seconds of silence, nothing emitted), Codex's `infersDenials` is already on, §6.2's rule 2 merely narrows its scope from the Turn to one slot on this product, and the backstop rule 3 (`SubagentStop`) does not depend on it. Measuring it could only add a closing point and could overturn no rule.

## 7. Explicitly rejected: pinning the row to Running

- It upgrades a lost `SubagentStop` from "one stalled line of text" to "a row stuck at Running with **nothing able to end it**" — the old defect argued through point by point in `65e63ab`'s commit message;
- the preview can never reach the final answer (`assistantPreview` is taken only when `status == .completed`);
- the row stops being removable (§4.4's only human exit goes with it);
- the unread gate never evaluates it, so it stays listed whether or not Desktop read it.

## 8. The relationship to Claude Code

Phase one wrote this section as "not this time, just registered", resting on two assumptions never measured. **Both were wrong**, per §8.1.

- ~~The Claude Code side never sets `runningSubagentCount`, and its `managedDefinitions` has no subagent boundaries. **The same thing is drawn differently on the two products**, a known and currently accepted difference.~~ That difference was not "drawn differently" but not drawn at all — and it needed drawing.
- Codex's **takeover** defect genuinely does not reproduce on Claude Code: Turn identity there is `prompt_id`, and subagent events measurably land on the **parent Turn's same** `prompt_id` (2026-08-16), never looking like a new Turn. **But that only refutes the takeover, not "a subagent outlives its Turn"** — phase one treated the two as one thing, and that is this section's biggest error.
- Phase one also wrote "besides, `claude agents --json`'s activity reading and the transcript interrupt record are two backstops". Those end **Turns**, not subagents: the Turn ended normally and they have nothing to say.

### 8.1 Measurement (2026-08-23, CLI `2.1.241`) and landing

The probe uses the existing throwaway `--settings` plus `--setting-sources project` (`-p` suffices, since the point is not approvals), with a prompt explicitly saying not to await the `Agent` call. Arrival order:

```text
UserPromptSubmit  prompt_id=5fd7…
PreToolUse        prompt_id=5fd7…  tool=Agent   tool_use_id=toolu_01Un…
PostToolUse       prompt_id=5fd7…  tool=Agent   tool_use_id=toolu_01Un…
SubagentStart     prompt_id=5fd7…  agent_id=ae14…  agent_type=general-purpose
Stop              prompt_id=5fd7…  background_tasks=[{id: ae14…, type: subagent, status: running}]
PreToolUse        prompt_id=5fd7…  agent_id=ae14…  tool=Bash
PostToolUse       prompt_id=5fd7…  agent_id=ae14…  tool=Bash
SubagentStop      prompt_id=5fd7…  agent_id=ae14…
```

Three conclusions:

1. **The `Agent` call returns the instant the subagent starts**, so a Turn can reach `Stop` carrying work it spawned — Codex's shape with a different cause (there the subagent is asynchronous by nature; here the tool call itself does not wait). The main agent's `Stop` carries `background_tasks` naming that subagent as still running.
2. **`agent_id` genuinely exists**, and on the base schema every hook input inherits rather than as an optional field on four inputs; the official description is "present only when the hook fires from inside a subagent… use this rather than `agent_type` to distinguish subagent calls from main-thread calls".
3. **Subagent events are stamped with the parent session's `session_id` and the parent Turn's `prompt_id`**, both the parent's. That is why they land on the right row, and why the takeover defect does not arise here.

What landed is §4 and §5's design carried across unchanged: registering `SubagentStart`/`SubagentStop`, passing `turn.runningSubagentIDs.count` when building a row, and having `ClaudeCodeMonitorService`'s read gate take `effectiveStatus` and `terminalBoundaryAt`. One extra small thing: `MessageDisplay` folding diverts inside `deliver` and thereby bypasses the reducer's `agent_id` gate, while what it writes is text the user sees, so the same test was added there (from the schema; `-p` cannot observe it, since `-p` does not display subagent text anyway).

### 8.2 The one thing not done, and its shape now

That `agent_id` discard gate is in the **shared** reducer, so Claude Code's subagent `PermissionRequest` was swallowed too. The third worry — the row sits at Running and never reports Approval needed — holds, with one more reading now: the row may read `1 subagent` while Claude Code is stopped at a dialogue.

It was not fixed here because it is not a matter of one gate: `HookTurnState` has one `openToolUse` and one `pendingApproval`, and admitting subagent events means a second stream through the same two slots. Fixing it means per-agent slots on the Turn, which is its own change and the same thing as §6 in this product's version.

**One possible exit not thought of then and measured now, belonging to Claude Code alone**: both its `Stop` and `SubagentStop` carry `background_tasks` whose `subagent`-typed entries have an `id` equal to `agent_id`. That is an **absolute** reading rather than a running total, arriving on `Stop` — the moment the count starts being drawn — so it cannot stick the way §5.1's cost does, and it is a ready-made answer to [#102](https://github.com/soondubu137/notchline/issues/102) on this product. It was not adopted because it needs measurements of its own: `SubagentStop`'s own copy **still lists the subagent that is stopping** (visible in the measurement above), and whether a cancelled `pending` subagent gets a `SubagentStop` is entirely unmeasured.

## 9. Open items

- ~~§5's trade-off needs a decision~~ — decided and implemented, §5.1; the trade-off itself is written into `PRD.md` §6.2 and the non-public registry rather than living only here.
- ~~§8's last item (whether Claude Code also stamps `agent_id`) is unmeasured~~ — measured, §8.1: it does, on the base schema. The same measurement also overturned this section's own premise, so §4 and §5 were carried across whole.
- ~~§6's prerequisite measurement is still not done~~ — the Claude Code half is measured (§6.1), the design is §6.2, and both landed. Of the remaining three: the Codex side ~~has never run a real subagent approval~~ is measured (§6.3 one); ~~who a subagent's approval goes to on an auto-reviewed thread~~ is measured (§6.3 two), so §6.2 now subtracts; and the only thing still unmeasured is **what Codex emits when a person refuses a subagent's approval in an interactive TUI**, with §6.3 four explaining why that changes no design.
- ~~"Measured but not adopted: `claude agents --json`'s `waiting`"~~ — half overturned, per the follow-up above: **approval is as silent as refusal**, and that session reading is the only evidence that says a person has answered; of the three reasons for rejecting it, only "desktop-hosted sessions do not have it" survives.
- §8.2's `background_tasks` route **as a count** is still unmeasured (whether a cancelled `pending` gets a `SubagentStop`), tracked in #102. **The half of it that is a status is adopted and landed**, §10: it asks only whether that one `Stop`'s own list is empty, never who is in it, so it depends on neither unmeasured fact.

## 10. The instant between a subagent wrapping up and the parent Turn waking (2026-08-23, CLI `2.1.241`)

### 10.1 The report

> Running the prompt "start a subagent and then finish immediately", the row reads: Running → Approval needed (the subagent wants permission to `sleep`) → Running (the subagent sleeping) → **Completed (the subagent woke)** → Running (the main agent summarising) → Completed. Can that middle Completed go? Too many state changes, and it is distracting.

### 10.2 Measurement

The same probe (throwaway `--settings` plus `--setting-sources project`, all 16 events registered to a helper that only writes a timestamp and the payload), run twice: once `-p` and once in a pty. Both had exactly the same shape, differing only in the interval.

The pty run (times from `SessionStart`):

```text
+26.25  UserPromptSubmit   prompt=1b21…
+29.21  PreToolUse         prompt=1b21…  tool=Agent
+29.25  SubagentStart      prompt=1b21…  agent=a489…
+29.25  PostToolUse        prompt=1b21…  tool=Agent
+31.18  Stop               prompt=1b21…  background_tasks=[{id: a489…, type: subagent, status: running}]
+31.61  PreToolUse         prompt=1b21…  agent=a489…  tool=Bash
+42.85  PostToolUse        prompt=1b21…  agent=a489…  tool=Bash
+44.30  SubagentStop       prompt=1b21…  agent=a489…  background_tasks=[{id: a489…, …, status: running}]
+44.35  UserPromptSubmit   prompt=0f4a…                ← a new Turn, 50 ms later
+47.47  Stop               prompt=0f4a…  background_tasks=[]
```

Four conclusions:

1. **That Completed lasts only 50 ms** (130 ms under `-p`), being the gap between `SubagentStop` emptying `runningSubagentIDs` and Claude Code waking the parent Turn under a **new `prompt_id`**. The row reads the count, and at that moment the count really is zero — so the row is not lying, it is answering a question nobody asked.
2. **The parent Turn is woken by a `UserPromptSubmit` with a new `prompt_id`**, not a continuation of the original. So what follows that instant is an entirely new Turn rather than the old one revived.
3. **`Stop` had already said which kind of terminal it was.** `background_tasks` is on the official schema for both `Stop` and `SubagentStop`, and the description says exactly this: "In-flight background work (running/pending + backgrounded) registered in this session. Lets hooks distinguish 'session is done' from 'session is paused waiting for background work to wake it'. Empty array when nothing is in flight." That last `Stop` carried `[]`.
4. **`SubagentStop`'s copy cannot be used**: it still lists the subagent that is stopping (both runs), so it is not an absolute reading of what remains. The same runs also showed two `SubagentStop`s with no paired `SubagentStart` (the TUI's own internal agents, §6.1 conclusion 5) — unrelated here, but another reminder that something opened by `agent_id` cannot vouch for itself as a subagent.

### 10.3 Adopted: record "paused" as a fact of the Turn itself

`HookTurnState.pausedForBackgroundWork`, written on `turnEnded` when `background_tasks` is non-empty, carried to the row as `MonitoredSession.isPausedForBackgroundWork`, and read by `MonitorAggregation.effectiveStatus` **beside** the count:

```swift
return session.status == .completed
    && (session.hasRunningSubagent || session.isPausedForBackgroundWork)
    ? .running
    : session.status
```

Three decisions, each independently justified:

- **Turn-level rather than Thread-level.** The opposite of `runningSubagentIDs` and `subagentSlots`, which are inherited across Turn boundaries because subagents outlive Turns; this one is written by that Turn's own terminal state and so must not outlive it. The next Turn's terminal state answers for itself, and that one carried an empty list. It is an assignment rather than an or, so a Turn pausing twice takes the last.
- **Read only on `Stop`** (conclusion 4).
- **No timer.** `AGENTS.md` §6.2 forbids inferring Running from a timer, and there is none here: one event writes it and another clears it. The real alternative — "a two-second grace after the last `SubagentStop`" — is exactly what that ban describes, and exactly why it was not chosen.

**The row itself still changes nothing** (§3, §4.5). In those 50 ms the row end draws nothing: its own Turn genuinely ended and there is genuinely no subagent to name. The collapsed state and the expanded panel disagreeing for that instant is written design rather than an oversight.

### 10.4 The cost, and why it is lighter than the flash it replaces

One new failure direction: if the parent Turn is never woken after `SubagentStop` (the user quits inside those 50 ms, or an update stops waking it), that row sits at `Running` instead of reaching `Completed`. It shares a direction and an exit (right-click the row away) with §5.1's already-accepted cost (#102) rather than being a second source of sticking: both require the same thing, that the Thread never produces another terminal state. In the other direction, the field disappearing or being renamed is safe: `pausedForBackgroundWork` is permanently false, the row reverts to today's behaviour, flashes once, and fabricates nothing.

**The registry (`AGENTS.md` §8) gains no row**: `background_tasks` is on the official hook input schema shipped with the CLI and carries an official description, the same nature as `agent_id` — that half is public. Nothing undocumented is depended on here: the entries' `id`, `type` and `status` are never read, only whether the list is empty. The existing "the row says so while a subagent is still running" row records the new display consequence.

### 10.5 Verification

Three unit tests: `aTurnPausedForItsSubagentDoesNotSayFinishedBetweenTheTwo` (replaying §10.2's event sequence and pinning, frame by frame, that the derived status stays Running through those 50 ms, that the count really is zero, that the new Turn does not inherit the flag, and that the final empty list takes the row to Completed); `aTerminalThatNamesNoBackgroundWorkIsTheThreadFinishing` (an empty list and an absent field, once per product); and `aListTooLongToCarryIsLeftOutRatherThanCutShort` (`HookPayloadDistiller`'s third carried kind: kept whole or not at all, with the event itself still landing past the ceiling). The first was reverse-verified: reverting `effectiveStatus` to reading the count alone makes it fail.
