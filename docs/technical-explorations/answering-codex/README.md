# Answering a Codex request in the notch

| Field | Content |
| --- | --- |
| Document status | Open research, not a decision. Nothing here is implemented or approved, **except §3.6**, whose defect was measured and fixed on 2026-09-07 |
| First recorded | 2026-09-07 |
| Question | Can Notchline answer a Codex permission request directly, instead of only offering `Answer in Codex` |
| Audience | Whoever decides whether to close the remaining Codex gaps, and whoever implements it |
| Basis | Read-only inspection of the Codex CLI bundled in `ChatGPT.app` (`codex-cli 0.153.4`), the hook JSON schemas embedded in that binary, the App Server protocol schema it generates, this machine's 185 local rollouts and `~/.codex/logs_2.sqlite`, plus `HookIntegration.swift`, `RequestAnswering.swift`, `answer-in-notch.md` §14/§16 and `system-architecture.md` §3, at commit `20ff4f1` |
| Measurements | §3 is measured on this machine on 2026-09-07 and says how. §4 is carried from existing documents and is attributed at the point of use. Everything except §3.6 is read-only; **§3.6 drove a real `codex app-server`** against an isolated `CODEX_HOME` in a scratch working directory, never `~/.codex/hooks.json` and never Codex Desktop |

> Directory convention follows [`shared-app-server/README.md`](../shared-app-server/README.md): one second-level directory per exploration, later evidence appended rather than overwriting earlier evidence.

## 1. The short answer

**A Codex permission request is already answered directly, and has been since 2026-09-05.** `CodexRequestAnswering` writes `hookSpecificOutput.decision` on the connection the `PermissionRequest` helper is holding open, and [`answer-in-notch.md`](../../answer-in-notch.md) §16 records it working end to end against this same CLI version on 2026-09-06 — the command ran, the row went back to `80`, and the App Server's own client was never asked for an approval at all.

So the premise this exploration started from — *Notchline can only lead the user back to Codex* — is true of some Codex requests and not of others, and it is worth being exact about which:

| Shape | How it arrives | Today |
| --- | --- | --- |
| An ordinary tool approval (a command) | `PreToolUse(<tool>)`, then `PermissionRequest` ~30 ms later borrowing that call's id | **Answered here.** `Approve` / `Deny`, with a message on the refusal |
| An escalation — network, filesystem, a skill | On this build, the same `PermissionRequest` path (§3.4) | **Answered here** |
| The same escalation with `request_permissions_tool` on | `PreToolUse(request_permissions)` alone, **no `PermissionRequest`** | `Answer in Codex` |
| A question — `request_user_input` | `PreToolUse(request_user_input)` alone; Codex has no hook for a user-input request at all | `Answer in Codex` |
| A question — `request_user_input_async` | `PreToolUse(request_user_input_async)`; the *Turn* does not stop, but ~~nobody is waiting~~ **a person is** (§3.6.1, re-measured 2026-09-08) | An ordinary tool call, and the row says `Working…` throughout. **A hole, not a reading** — the open edge is on the wire, the closing edge is the unsolved half |
| `Always` / `for this session` / a policy amendment | Reserved on the hook's decision, which fails closed if the field is present | Not offered, and `answer-in-notch.md` §6.5 declines to offer it anyway |

The rest of this document is about the three rows that are not answered, why the hook channel cannot carry them, and what could.

## 2. Why this is worth writing down now

The answering half is new and unreleased, and the Codex side of it rests on a fact that is **not a contract**: that an escalation currently goes through the core approval pipeline rather than through the dedicated `request_permissions` tool. That is a feature flag, and it is one OpenAI can flip without telling anybody (§3.4). The day it flips, an approval a person could answer here becomes one they cannot, and the only visible sign is the row quietly saying `Answer in Codex`.

So the question is not only "can the gap be closed" but "what happens when the ground moves".

## 3. What was measured, on this machine, on 2026-09-07

All of it read-only. Nothing was started, no daemon was created, no Turn was driven, `~/.codex/hooks.json` was not touched, and Codex Desktop was not interacted with.

### 3.1 Versions

`/Applications/ChatGPT.app/Contents/Resources/codex --version` → `codex-cli 0.153.4`. This is the binary Desktop launches, and the same version `answer-in-notch.md` §16's Codex measurement was taken against.

### 3.2 Codex declares twelve hook events, and none of them is a question

The binary embeds its own hook JSON schemas. Extracting every `"title": "<name>.command.<input|output>"` gives:

```text
session-start   session-end     user-prompt-submit
pre-tool-use    post-tool-use   permission-request
pre-compact     post-compact
subagent-start  subagent-stop
stop            interrupt
```

**There is no user-input event.** A Codex question is only ever visible as a `PreToolUse` naming the tool that asks it, which is exactly how `CodexHookVocabulary` reads it — and it means a question can never carry a held connection *of its own* on this product. That is a stronger statement than `answer-in-notch.md` §11 rule 06 makes: the rule says Codex will not accept a question's answer, and the schema list says Codex never even offers the question a channel.

### 3.3 The two output schemas, verbatim

`permission-request.command.output` — `hookSpecificOutput.decision`:

| Field | Status |
| --- | --- |
| `behavior` | `allow` \| `deny`, required |
| `message` | free text |
| `interrupt` | *"Reserved for future short-circuiting semantics. PermissionRequest hooks currently fail closed if this field is `true`."* |
| `updatedInput` | *"Reserved for a future input-rewrite capability. PermissionRequest hooks currently fail closed if this field is present."* |
| `updatedPermissions` | *"Reserved for a future permission-rewrite capability."* Fails closed the same way |

`CodexRequestAnswering` is exactly this and nothing more, and its refusal to send `updatedInput` is the schema's own instruction rather than caution.

`pre-tool-use.command.output` — `hookSpecificOutput`:

| Field | Status |
| --- | --- |
| `permissionDecision` | `allow` \| `deny` \| `ask` |
| `permissionDecisionReason` | free text |
| `additionalContext` | free text |
| `updatedInput` | **present, and not marked reserved** |

**This corrects [`answer-in-notch.md`](../../answer-in-notch.md) §14.2's table**, which lists Codex's `pre-tool-use.command.output` as `permissionDecision` and `permissionDecisionReason` alone. It has a fourth field, and unlike its `PermissionRequest` sibling nothing in the schema says it fails closed.

It buys nothing here, and §5.1 says why: rewriting a tool's *input* only delivers an answer when the tool's input has somewhere to put one, and `request_user_input`'s does not.

### 3.4 The dedicated approval tool is behind a flag, and the flag is off

`codex features list` on this machine:

```text
request_permissions_tool                 under development  false
exec_permission_approvals                under development  false
guardian_approval                        stable             true
tool_call_mcp_elicitation                stable             true
code_mode_host                           stable             true
```

Two independent observations agree with `request_permissions_tool` being off:

- Across all **185** rollouts under `~/.codex/sessions` and `~/.codex/archived_sessions` there is **not one** `request_permissions` tool call. The name appears 491 times as text, and every occurrence is this repository's own source quoted back inside a tool result.
- `answer-in-notch.md` §16's Codex measurement, taken 2026-09-06 on `0.153.4`, describes *"an escalation request under a read-only sandbox"* whose decision was taken by the `permission-request` hook, running for `28,285 ms`. An escalation went down the `PermissionRequest` path.

That is the opposite of what [`system-architecture.md`](../../system-architecture.md) §3 records for 2026-08-15, where a network-access approval arrived as `PreToolUse(request_permissions)` and sent **no** `PermissionRequest`. Both measurements are believable; what changed between them is a flag, not this app.

**So the read-only escalation shape is a state Codex can return to, not a state it is in.** The code is right to keep handling it; the row is right to say `Answer in Codex` when it appears; and nobody should conclude from a working escalation today that the shape is gone.

### 3.5 What the user's own threads actually ask

Every `turn_context` in the last week of rollouts, by `(approval_policy, approvals_reviewer)`:

| Combination | Turns |
| --- | --- |
| `never` / `auto_review` | 142 |
| `on-request` / `auto_review` | 41 |
| `on-request` / `user` | 5 |

183 of 188 Turns hand their approvals to Codex's own reviewer, which is exactly the case `TurnApprovalRoutingPin` exists to keep off the notch. Against that, one `request_user_input_async` call on 2026-09-06 — a real question, put to a person, on a thread whose approvals never reach one.

**On this machine, the shape a person is actually asked is the question, not the approval.** That does not decide anything on its own — the sample is one user over one week, and it says nothing about what a different user's threads do — but it is worth knowing which of §1's unanswered rows is the one being met.

### 3.6 A defect found on the way — measured, and half of it was a different defect

This section previously read "a probable defect", predicted that the async question would leave the row saying `Working...` "for the whole time a person is being asked", and asked for a payload capture. The capture was taken on 2026-09-07 against CLI `0.153.4`: an isolated `CODEX_HOME` with `auth.json` symlinked, all twelve events registered to a handler that `cat`s stdin to a log, each entry's `currentHash` written back as `trusted_hash`, and turns driven through `codex app-server` in a scratch cwd. It found the naming defect real and the consequence wrong, and it found a second, worse defect underneath.

**Which tool a Turn gets is chosen by the model, not by a setting.** Four runs, same prompt:

| Model | Mode | Tool registered |
| --- | --- | --- |
| `gpt-5.6-sol` | Default | none — `request_user_input is unavailable in Default mode` |
| `gpt-5.6-sol` | Default, `features.default_mode_request_user_input` | `request_user_input` |
| `gpt-6-astra` | Default, feature on **and** off | `request_user_input_async` |
| `gpt-6-astra` | Plan | `request_user_input` |

`gpt-6-astra` is this machine's default model, so both shapes reach the same user on the same day by route rather than by configuration — and the feature flag, which looked like the gate, is not one.

**Both carry a `tool_use_id`, and both are `call_…`.** The async `PreToolUse` is:

```json
{ "hook_event_name": "PreToolUse", "tool_name": "request_user_input_async",
  "tool_use_id": "call_UxE0jhpkEpFVXJBvZNEWHCcU",
  "tool_input": { "questions": [ { "title": "Which function should I rename, …" } ] } }
```

**But the prediction above was wrong about what happens next.** The async tool does not hold anything open. Its `PostToolUse` arrived **51 ms** later carrying `tool_response: "{\"accepted\":true}"`, the Turn ran another tool 3 seconds after that and reached its own `Stop`, and Codex emitted the question as an `AgentMessage` with `delivery: "async"`. So the row does not say `Working...` "while a person is being asked" — the Turn genuinely *is* working, and the question is not a wait at all. Any answer arrives later as a new user message, which is a new Turn.

That inverts the fix. `.inputWaitOpened` would announce `Input needed` for 51 ms and withdraw it; the catch-all's `.toolCallOpened` was right, by accident. The repair is to say so explicitly — so that the next reader does not "fix" it — and to note that the catch-all fails in the safe direction, since it can under-report a wait but never invent one. There is also nothing lost: the Turn's `Stop` carries the question in `last_assistant_message`, which the Completed row already draws.

**The second defect is the one that mattered.** The blocking `request_user_input` sends

```json
{"questions":[{"header":"Function rename","id":"function_rename",
  "question":"Which function do you want to rename, and what exact new name should it have?",
  "options":[{"label":"Provide both names","description":"…"}]}]}
```

— field for field the shape `AgentRequestReading.questions(in:)` already reads for Claude Code's `AskUserQuestion`. `CodexHookVocabulary.request(forEvent:…)` looked for a **top-level** `question` or `prompt`, which this has not got, so it fell through to the arguments and every real Codex question reached the row as a **command on the recessed ground reserved for machine text**. A test with the captured payload fails on the old code with `drawn as command, not a question set`.

So §1's row for `request_user_input` was also wrong in a way this document inherited from `answer-in-notch.md` §2: Codex's question **does** carry options with labels and descriptions. Both were corrected on 2026-09-07.

Fixed in `CodexHookVocabulary`, with the measurements recorded in [`system-architecture.md`](../../system-architecture.md) §3 and [`tech-design.md`](../../tech-design.md) §7.1/§9.2. This was independent of everything else here.

#### 3.6.1 Re-measured 2026-09-08 — the 51 ms was the *model's* wait, not the person's

A user of a second machine sent a screenshot: a Codex Desktop Turn on `gpt-6-astra`, still running, with an answerable question card in the composer — the question, two numbered options, a free-text field, `Skip` and `Send` — and Notchline's row beside it showing the Turn's *next* sentence and no `Input needed` anywhere. §3.6's reading predicts exactly that row, so the reading is what was examined.

**It is `request_user_input_async`.** Identified from the screenshot itself rather than assumed: the model is `gpt-6-astra`, which registers only the async tool outside Plan mode (§3.6's table); the transcript continues *past* the question with another assistant message; and the composer still shows a running Turn. The blocking tool would have stopped there.

Three things §3.6 asserted, checked against the shipped binaries:

| §3.6 said | 2026-09-08 |
| --- | --- |
| `{"questions":[{"title": …}]}`, no options | **Wrong.** The async tool's schema in CLI `0.153.4` documents `options` — *"Suggested answers, in display order… Omit options for a free-text-only question"* — and the system prompt tells the model to **prefer** multiple choice. The `title`-only capture was a free-text question |
| The `Stop` carries the question in `last_assistant_message` | **Only when the model stops on it.** The same prompt tells it to "continue useful work that does not depend on the answer while waiting", which is what the screenshot shows it doing. The Completed row then draws the later sentence |
| Nobody is waiting | **Codex disagrees.** Desktop derives thread status `waiting` from an outstanding `item/tool/requestUserInput`, blocking or not |

**And the wait has a clock.** Read out of `app.asar` (Desktop `26.901.51231`), both question tools reach the client as the same server request, `item/tool/requestUserInput`, carrying `isBlocking`. Desktop hands the non-blocking one to `requestUserInputAutoResolution`, which answers **`{answers:{}}` for the person**: 60 s of foreground inactivity then a 90 s countdown while that conversation is focused, or the 90 s countdown **immediately** when it is not; snooze cancels it. So a person who is not looking at that thread has about ninety seconds — which is the notch's entire case, and also the constraint on any row that claims the state.

The card is gated on remote feature id `580984490` (`requestUserInputAsyncUiEnabled`) and built from `item/started` where `item.delivery === "async"`. **It therefore arrives by rollout**, and a machine without the gate cannot reproduce the screenshot however current its build is.

**What this changes, and what it does not.** `.toolCallOpened` is still what ships, but the justification has moved from "there is nothing to draw" to "there is nothing to draw it *off* with":

- **Open edge — already paid for.** `PreToolUse(request_user_input_async)` carries the whole question set; the catch-all `PreToolUse` is registered; `carriesRequest` is one line of the same table.
- **Closing edge — unsolved, and the whole problem.** `PostToolUse` closes the tool, not the question. An answer is only the next `UserPromptSubmit`. Skip, snooze and the auto-resolution are silent. `AGENTS.md` §6's *state is never guessed* rules out a bare timer standing in for evidence, and this app's existing displayed-thread and focus evidence is the nearest thing to the input Desktop's own timer uses — which makes "mirror the product's clock" a candidate to be measured rather than a design to be adopted.

**One more shape, unmeasured.** `item/tool/requestOptionPicker` sits beside `requestUserInput` in the same bundle, answered `{action, selectedOptions, freeformAnswer}`. Nothing is known about its tool name, its payload or whether it reaches a hook at all. It is recorded here so the next survey looks for it, and deliberately kept out of `answer-in-notch.md` §2's table until a real payload is caught.

**Open questions this leaves.** (1) Does the gated card's `Send` route back as a response to the server request or as a new user message — the two differ in whether a Turn is created. (2) Does the auto-resolution clock actually run on the gated card; the numbers above are read from code, not watched. (3) How long do these questions stay open in practice: one sample on this machine is not a distribution.

### 3.7 The App Server can answer everything the hook cannot

Generated from `codex app-server generate-json-schema --experimental`. The server-to-client requests are:

```text
item/commandExecution/requestApproval    item/permissions/requestApproval
item/fileChange/requestApproval          item/tool/requestUserInput
item/tool/call                           mcpServer/elicitation/request
applyPatchApproval                       execCommandApproval          (legacy)
```

and their response shapes are far richer than `allow` / `deny`:

- `CommandExecutionRequestApprovalResponse` — `accept`, `acceptForSession`, `acceptWithExecpolicyAmendment { execpolicy_amendment }`, `applyNetworkPolicyAmendment { network_policy_amendment }`, and the refusals.
- `PermissionsRequestApprovalResponse` — grants filesystem entries and network access directly.
- `ToolRequestUserInputResponse` — `{ answers: { <questionId>: { answers: [String] } } }`, keyed by the question ids that arrive in `ToolRequestUserInputParams`, which also carry `header`, `question`, `options[{label, description}]`, `isOther`, `isSecret` and `isBlocking`.

**That last one is the whole gap in one object.** It is the same shape `answer-in-notch.md` §5 already draws and the same shape Claude Code's `updatedInput` delivers; Codex has it, and it is on a channel this app is not on.

Two more protocol facts point the same way:

- `serverRequest/resolved` is a **notification**, carrying `requestId` and `threadId` — the protocol expects somebody watching who is not the one answering.
- `thread/unsubscribe` is scoped to the current connection and the protocol has last-subscriber semantics, so several connections per Thread are a designed-for case rather than an accident.

### 3.8 But there is no second connection to be had today

Re-confirming [`shared-app-server/README.md`](../shared-app-server/README.md) §3.2 against the running system:

- Desktop launches `codex … app-server --analytics-default-enabled` with no `--listen`, so the transport is `stdio://` between Desktop and its own child.
- `lsof` on that PID (75367) shows only anonymous Unix sockets and the stdio pair — no path listener, no TCP listener.
- `$CODEX_HOME/app-server-control/app-server-control.sock` **does not exist**; no daemon is running.
- `~/.codex/ipc/ipc.sock` exists but belongs to the ChatGPT process itself, not to the App Server, and is out of bounds under `shared-app-server` §5.3.

So §3.7's vocabulary is real and currently unreachable.

## 4. What the hook channel can and cannot be made to do

### 4.1 Holding `PreToolUse` does not answer anything

The obvious move is to register `PreToolUse` with `AgentHookHelper.answeringArgument` and let the reducer hold only the two tools that ask a person. The transport already supports it — `deliver` returns `.close` or `.held` per event, so the app decides per payload rather than per definition, and every other tool call would be released within microseconds.

It still does not work, for a reason that is about meaning rather than mechanism:

- `permissionDecision: "allow"` on `PreToolUse(request_permissions)` says *let this tool run*. The tool's job is to ask the human. Allowing it produces the dialogue, which is the thing being avoided.
- `permissionDecision: "deny"` blocks the **tool call**. The model is told its escalation tool was blocked, which is not the same sentence as *the person declined this escalation*, and this app would be saying it in its own voice. `answer-in-notch.md` §14.2 already refused to paraphrase an answer into a refusal on the other product; the same objection applies with more force here, because a blocked tool is not even a refusal of the thing being asked.
- `updatedInput` (§3.3) rewrites the tool's arguments. `request_user_input`'s arguments are `{questions: [...]}` — measured from the one real call in this machine's history — with no field an answer could go in. The answers travel on `ToolRequestUserInputResponse`, which is a *client response*, not tool input. This is precisely the asymmetry `answer-in-notch.md` §14.2 identified on Claude Code, read from the other side: `AskUserQuestion` works because its own input schema carries `answers`; `request_user_input` has no such field to write into.

And it costs something real. `PreToolUse` fires on every tool call, so this app moves into the path of every tool call on every Codex thread. A wedged or crashed Notchline that stops draining its socket would leave each of them waiting on the definition's timeout. The current design pays that cost on 0.18% of events by construction; this would pay it on all of them, to gain a refusal nobody asked for.

**Verdict: no.** Not a deferral — the channel cannot express the answer.

### 4.2 Asking OpenAI is a one-field change

The Codex schema does not say *never*; it says **reserved**, three times, on the three fields that would close every gap in §1 at once. `updatedInput` on `permission-request.command.output` un-reserved would make a question answerable on the hook exactly as it is on Claude Code. That is worth recording as the cheapest possible outcome and worth an upstream issue, and it is not something this repository can schedule.

## 5. What could actually close the gap

### 5.1 The shared App Server, with Notchline answering

[`shared-app-server/README.md`](../shared-app-server/README.md) already designed the transport half — daemon, `codex app-server proxy`, envelope classification, an ordered event stream — for a *read-only observer*. Its §11 says, flatly: **"Never make Notchline an approval client."**

This exploration is the case for revisiting that sentence, and it should be revisited honestly rather than quietly. The sentence was written to protect a status feature from side effects. Answering is not a side effect of a status feature; it is `answer-in-notch.md`'s whole subject, and the panel already answers on the other product. What the rule should become is narrower and harder: *Notchline answers only the request a row is already showing, only on a person's click, and never automatically* — which is `PRD.md` §3's amendment as `answer-in-notch.md` §14.4 already made it.

That said, three things stand between here and there, and two of them are outside this repository.

**The routing question is unproven and decides everything.** `shared-app-server` §Phase 2 names it: is a server request delivered to the connection that owns the Turn, broadcast to every subscribed connection, or routed by some host-client rule? If it is owner-only, this whole route is dead for answering and remains alive only for observing. If it is broadcast, then answering is possible **and** two clients can now race for one decision, which needs its own rule. Nothing in the generated schema settles it; only an experiment does.

**Desktop has to be on the daemon.** That is `CODEX_APP_SERVER_USE_LOCAL_DAEMON=1`, a package implementation detail found by reading `app.asar`, plus a full Desktop restart. A product that only answers when the user has restarted Desktop under a private environment variable is not a product feature; it is a preference for people who read the source. `shared-app-server` §9 already lists "Desktop updates frequently change the hidden environment variable" as a NO-GO, and that judgement stands.

**The socket is a bigger door than it looks.** `thread/shellCommand`'s own schema says it *"runs unsandboxed with full access rather than inheriting the thread sandbox policy"*. Any local process that can reach the daemon's control socket can run arbitrary commands as the user, with no approval anywhere. That is not an argument against Codex's design — the socket is `0700` in the user's own home — but it is an argument against this app encouraging a daemon to exist, and it belongs beside `shared-app-server` §11's socket-permission rule rather than buried in it.

**Verdict: the only route that reaches the answer, and it is not ready.** It is worth the Phase 1 spike — daemon plus proxy plus two connections, read-only methods only — because that spike is cheap, reversible, and settles the routing question that everything else waits on. It is not worth building against until that question has an answer.

### 5.2 Driving Codex Desktop's own controls

Find the approval in Desktop's accessibility tree and press its button. It would work, and this app already drives other applications' accessibility trees for navigation.

It is still the wrong thing. It is `Answer in Codex` performed by a robot: the panel would be claiming to have answered while the answer is really a synthetic press on a window whose layout nobody promised, on a thread the app had to navigate to first. Every failure mode is silent and every one of them is a wrong decision on a real permission. `answer-in-notch.md` §11 rule 03 — do not offer an affirmative the app cannot deliver — rules this out on its own, because "can deliver" would mean "found a button that looked right".

**Verdict: no.**

### 5.3 Remote control

`codex remote-control` pairs a daemon to an OpenAI relay over a WebSocket, with pairing codes and enrolment, and it is the shipped mechanism for answering Codex from another device. It requires ChatGPT authentication, network egress and an OpenAI-side enrolment.

`PRD.md` §7 is that this product has no network egress. Routing a local notch's approval through a cloud relay to reach an application running six inches away is also, on its own terms, absurd.

**Verdict: no.**

## 6. Recommendation

1. **Correct the record first, because two documents are now wrong.** `answer-in-notch.md` §14.2's Codex `pre-tool-use` row omits `updatedInput` (§3.3), and `system-architecture.md` §3's "a dedicated approval tool sends no `PermissionRequest`" is true of a shape that a feature flag has since taken out of the build (§3.4). Neither should be overwritten — both are correct measurements of their own date — but both need what follows them.
2. ~~**Confirm §3.6 and fix it.** … it is one payload probe away from certain.~~ **Confirmed twice, in opposite directions, and now open again (§3.6.1, 2026-09-08).** The hole is real: an async question never says `Input needed`, and the question is usually gone from the Completed row too. What it is not is one probe away — the open edge is free and the *closing* edge has no hook event at all, so the next step is to establish how the wait ends (an answer, a Skip, a snooze, or Desktop's own ~90 s auto-resolution) before any signal is re-mapped.
3. **Do not build §4.1.** It cannot express an answer, and it puts this app in the path of every tool call to fail at it.
4. **Run `shared-app-server` Phase 1, and add one question to it.** The existing plan already starts a daemon and opens two proxy connections with read-only methods. The addition is the server-request routing question in §5.1, which needs a Turn that actually raises an approval and a second connection watching whether it sees it. That single fact decides whether §5.1 is a route or a dead end, and everything downstream is unplanned until it is known. It needs the user's explicit authorisation, because it starts a daemon.
5. **Keep `Answer in Codex` as the honest fallback, whatever happens.** It is not a placeholder for a feature that is late. It is the true statement for a request this app is holding no connection for, and §3.4 says Codex can put requests back in that state without warning.

## 7. Exploration record

### 2026-09-08 — re-measurement of the async question (§3.6.1)

- Executor: Claude Opus 5, at the user's request, from a screenshot supplied by a user of another machine
- Desktop bundle: `/Applications/ChatGPT.app` `26.901.51231`; bundled `codex-cli 0.153.4`
- Scope of user authorisation: investigate, no code changes; documentation updated in a second, separate instruction
- Read-only throughout: `strings`/byte-scan of the CLI binary and of `app.asar`, and reads of `~/.codex/sessions`, `~/.codex/.codex-global-state.json`, `~/.codex/state_5.sqlite`, `~/.codex/thread_history_1.sqlite` and `~/.codex/logs_2.sqlite` (opened `mode=ro`)
- Result: PASS for the re-measurement; §3.6's timing confirmed, two of its conclusions overturned; **BLOCKED** on the three questions at the end of §3.6.1, all of which need a live gated card rather than a file
- Side effects observed: none. No Turn driven, no daemon started, no Desktop interaction; nothing written outside this repository but the executor's own memory notes, and the byte-scan dumps were deleted afterwards
- Recommended next step: §6.2 as rewritten — establish the closing edge before re-mapping the signal

### 2026-09-07 — protocol and schema survey

- Executor: Claude Opus 5, at the user's request
- Desktop bundle: `/Applications/ChatGPT.app`, `Codex Framework 152.0.7977.83`
- Bundled Codex CLI: `codex-cli 0.153.4`
- Branch and commit: `master`, `20ff4f1`
- Scope of user authorisation: investigate feasibility. Read-only was chosen for everything below without needing it
- Commands run: `codex --version`, `codex features list`, `codex app-server generate-json-schema [--experimental]`, `strings`/byte-scan of the CLI binary for embedded hook schemas, `ps`, `lsof`, and read-only reads of `~/.codex/sessions`, `~/.codex/archived_sessions`, `~/.codex/hooks.json`, `~/.codex/queue_1.sqlite`, `~/.codex/thread_history_1.sqlite` and `~/.codex/logs_2.sqlite` (each copied before opening)
- Result: PASS for the survey; **BLOCKED** on the one question that matters, which is server-request routing under several clients (§5.1)
- Side effects observed: none. No daemon started, no Turn driven, no Desktop interaction, no file written outside this repository
- Stop conditions triggered: none
- Environment variable set: none
- Final daemon state: none was running before or after
- Recommended next step: §6.2, then §6.4
