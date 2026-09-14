# Extending support to Claude Code (Desktop + CLI) — technical exploration

| Field | Value |
| --- | --- |
| Status | Feasibility study, now largely superseded by what shipped. It records **why** each decision was made; the contracts live in `PRD.md`, `tech-design.md`, `figma-design.md` and [`docs/adr`](../../adr/) |
| First recorded | 2026-08-15 |
| Question | Can the notch monitor, which serves Codex Desktop today, also summarise Claude Code sessions? |
| Verification baseline | Claude Desktop `1.30096.5` (bundle `com.anthropic.claudefordesktop`), built-in Claude Code CLI `2.1.229`, macOS `Darwin 25.5.0`, verified `2026-08-15` |
| Conclusion | **Feasible, and Phase 0's make-or-break question is closed.** User-level hooks do fire in Desktop-hosted sessions (measured 2026-08-16, §9). Navigation is degraded by product decision |

> Directory convention follows [`shared-app-server/README.md`](../shared-app-server/README.md): one second-level directory per question, with later experiments appended to §9 rather than overwriting earlier evidence.

## 1. Purpose

This answers one question: is extending Notchline into a multi-agent centre that also monitors Claude Code (Desktop and CLI) technically sound, where are the costs, and which capabilities do not exist yet. It records the integration capabilities verified on this machine and whether each is officially public or a private observation; a point-by-point comparison with the current Codex path; the abstraction changes the architecture needs; the staged verification plan and NO-GO conditions; and the decisions the product must make.

Apart from read-only inspection and one deep-link probe, the original study modified no configuration, code or user state.

## 2. Summary of conclusions

| Dimension | Verdict | Evidence |
| --- | --- | --- |
| Session discovery | **Better than Codex.** An official public command enumerates active sessions directly | `claude agents --json` returns `pid / cwd / kind / startedAt / sessionId / name` |
| Cold-start sync | **Better than Codex** — the "no cold-start sync" limit does not exist here | As above; which sessions are running is knowable at launch. **Later overturned in practice, §5.3** |
| Lifecycle status | **Better than Codex.** A finer event set with fuller identity fields | Official hooks give paired `PermissionRequest` / `PermissionDenied` / `Notification(permission_prompt)` / `Elicitation` |
| Subagent filtering | **Better than Codex.** Exact rather than inferred | Hook payloads carry `agent_id` / `agent_type` |
| Desktop + CLI unified | **Holds.** One integration covers both | Desktop starts the same CLI binary, with `--setting-sources=user,project,local` |
| Titles and metadata | **Holds.** Paths come from the official hook payload | `transcript_path`, `cwd`; titles need JSONL parsing (an undocumented format) |
| **Exact navigation** | **Not possible; degradation decided.** No supported interface focuses an existing session | The official deep link can only create; `claude://code/sessions/local_…` is measurably rejected |
| A native live status source | **Does not exist.** Hooks are the only supported push channel | All five candidates describe identity or something that already happened, §4.7 |
| Implementation cleanliness | **Can be better than the Codex side.** No polling, no files in steady state | Push hooks into an in-app listener plus event-driven discovery, §5 |
| Automatic removal once read | Private read-only, at the same risk level as the Codex unread adapter. **Implemented 2026-08-19 (CC-013)** with a different test from this row's guess, and a second revision the same day covered terminal sessions with neither Desktop nor a private schema: controlling-terminal access time | Desktop's `lastFocusedAt`; the terminal's `st_atime` |
| Quota ring | Feasible for Desktop users; no equivalent for pure CLI users | `plan-usage-history.json` is Claude Desktop private state. **Superseded by [ADR 0007](../../adr/0007-read-claude-code-quota-from-the-cli.md)**: reading the CLI works for every user |

**Overall:** apart from navigation, Claude Code's integration surface is broader, more public and easier to get right than Codex's. The half of the value proposition that is "jump straight back to the session" has nowhere to land, and that — not engineering difficulty — is what decides whether to do this.

## 3. Compared with the current Codex path

Three of the most expensive designs in the current architecture become simpler here:

1. **The standalone App Server subprocess** (all 860 lines of `CodexAppServerClient.swift`, NDJSON framing, timeout probing, transport rebuild) has no counterpart. The session set comes from one official command that returns in 0.2 s, and titles and metadata from the `transcript_path` a hook hands over.
2. **The launch-cutoff capability boundary** does not apply, because a supported "which sessions exist right now" query exists.
3. ~~**`PermissionRequest` proves the pipeline ran without expressing a continuing wait** has a direct solution here.~~ **This was wrong** (measured 2026-08-16, §9): `PermissionRequest` carries no `tool_use_id`, so the Codex model of borrowing a still-open call id survives intact and that problem does not disappear. What does disappear is the other half — `PermissionDenied` **does** carry `tool_use_id`, so a refusal can be closed precisely rather than hanging for Codex's measured 67 seconds. **Later overturned again** (§9, 2026-08-23): that event reports the automatic-mode classifier refusing, not a person, so the inference is needed on both products after all.

## 4. Verified facts

Each was measured on this machine, and must be re-verified after a version change.

### 4.1 Session discovery (officially public)

`claude agents --json` is documented, and measured output is:

```json
[
  {
    "pid": 91157,
    "cwd": "/Users/yinfenglu/Projects/codex-in-notch",
    "kind": "interactive",
    "startedAt": 1786832578142,
    "sessionId": "45510eae-d774-464e-bff9-972b2c28bae5",
    "name": "codex-in-notch-f6"
  }
]
```

- `claude agents --help` states that `--json` will "Print active sessions (interactive and background) as a JSON array and exit (for scripting; does not require a TTY)". **Interactive sessions being visible is a documented promise rather than an observed coincidence**, Desktop-hosted ones included. This is the single most important finding of the study.
- **It returns no status field at all.** Run while this session was mid-Turn, the output was identical to when it was idle. It is the authority on identity and not on status (§4.7).
- It supports `--all` (including finished background sessions) and `--cwd <path>`.
- Three timings: 0.19–0.26 s. Too heavy for a one-second poll; fine at launch or after an event.
- The same information is in `~/.claude/sessions/<pid>.json` (additionally `entrypoint`, `kind`, `version`, `messagingSocketPath`), held by the `claude` process itself (`lsof` confirms pid 91157 holds `/tmp/cc-socks/91157.sock`) — **so terminal-started and Desktop-hosted sessions use one registration mechanism**. That file's format is undocumented and should be a watcher input meaning "time to re-query the official command", never a data source.

### 4.2 Lifecycle events (officially public)

The official hooks documentation publishes 30 events, the configuration location and the payload fields. The mapping that matters:

| Product status | Claude Code evidence | Closed by |
| --- | --- | --- |
| Running | `UserPromptSubmit` (measured field `prompt`; `source` optional and absent under `-p`) | A later status event |
| Approval needed | `PermissionRequest` (**measurably without `tool_use_id`**, §9 2026-08-16) | Borrowing a still-open call id, closed by the `PostToolUse` with that `tool_use_id` |
| Input needed | `Notification(notification_type: idle_prompt / agent_needs_input)`, `Elicitation` | `ElicitationResult`, `Notification(elicitation_complete)` |
| Completed | `Stop` (with `last_assistant_message`, `background_tasks`), `StopFailure` (the field is `error`, not `error_type`) | Terminal stickiness |
| Session gone | `SessionEnd` (the field is `reason`) | — |
| Row content preview | **`MessageDisplay`** ("While assistant message text is displayed"; public payload `turn_id, message_id, index, final, delta`) | A new `message_id` replaces the old text |

> **Correction (2026-08-18).** The `MessageDisplay` row was added later. "The official documentation publishes 30 events" was mapped event by event during the study and **missed exactly this one**, so `ClaudeCodeHookVocabulary.managedDefinitions` missed it too, and [#34 / CC-015](https://github.com/soondubu137/notchline/issues/34) concluded that Claude Code text was unobtainable without building a second channel equivalent to `HookPreviewChannel`. Both halves were wrong: the text is obtainable, and no new channel is needed — the payload already arrives in this process, so the text is in memory when it lands.
>
> Measured (CLI 2.1.234, registered to a separate listener in a temporary `--settings` file, **leaving `~/.claude/settings.json` untouched**): `-p` delivers once with `index: 0`, `final: true`, a multi-line message arriving whole with its newlines; an interactive session delivers incrementally, measured about every 0.3 s. It is also the only event carrying both `prompt_id` and `turn_id` (with different values); the reducer's identity is still `prompt_id`.

Key structural advantages:

- **`prompt_id` (v2.1.196+) is the direct counterpart of `turn_id`**, so `HookTurnState`'s exact `threadID + turnID` identity and unrevivable retired ids carry over unchanged.
- **`agent_id` / `agent_type` exist in a subagent context**, so "subagents are never their own row" is exact filtering rather than inference.
- **Hook configuration is hot-loaded**: the documentation states that direct edits to hooks in a settings file usually take effect through a file watcher, with no session restart.
- **An `http` hook type exists**, so Claude Code could POST straight to an in-app loopback listener with no Python helper writing 0600 event files. **Overturned by [ADR 0013](../../adr/0013-claude-code-hooks-run-a-helper-not-a-port.md)**, see §5.1.

### 4.3 Session identity and metadata

- Every hook payload carries `session_id`, `transcript_path`, `cwd` and `permission_mode` — **paths come from an official interface**, never guessed.
- The transcript JSONL holds `custom-title`, `ai-title` and `last-prompt` records, plus `cwd`, `gitBranch`, `version` and `isSidechain` on each record. Titles, Project attribution and previews can all come from there.
- **But the JSONL record structure is not a public contract.** Parsing it is a private dependency, must be registered per [`AGENTS.md`](../../../AGENTS.md), and must fail closed on missing or corrupt data.
- Claude Code has no user-created Project entity like Codex's. The equivalents are `cwd` + `gitBranch`, or the derived `name` from `claude agents --json` (`nameSource: derived`). This conflicts directly with the PRD's ban on deriving a Project from cwd, the Git root or the last path component, and needed a product decision — **settled by [ADR 0009](../../adr/0009-resolve-project-per-product.md)**: `cwd` *is* this product's grouping unit, so the ban binds only Codex.

### 4.4 Navigation (degradation decided)

**No supported way exists to focus an already-existing Claude Code session.**

- The [deep links documentation](https://code.claude.com/docs/en/deep-links) defines only `claude-cli://open` with `q`, `cwd` and `repo`, which **always opens a new terminal window and a new session** and accepts no session ID.
- Desktop publishes `claude://code/new` (optionally `?q=`, `?folder=`, `?file=`), which likewise only creates.

Measured:

```text
open "claude://code/sessions/local_5ddb387b-66f4-4356-80f0-713248074c23"
→ main.log: [warn] claudeURLHandler: unrecognized code path { pathname: '/sessions/local_...' }
```

A read-only inspection shows the `/code/sessions/…` route does exist in the implementation, but it is behind a feature gate and its ID validation is `/^(cse|session)_/` — aimed at cloud/remote session IDs, which a local session's `local_` prefix does not match. A probe with a `cse_` prefix was also rejected, implying stricter shape validation still. **This is a package implementation detail rather than a product contract and must not be built on.** Its only value is the hint that a local-session deep link may appear later, worth re-checking after every Desktop update.

The viable alternatives, all with costs: activating Claude.app only (Desktop sessions; the user still has to find the session in the sidebar); pid → tty → Apple Events to focus a terminal tab (CLI sessions; needs Automation authorisation and per-terminal support); Accessibility clicking Desktop's sidebar (**conflicts directly with the PRD's ban and is not recommended**); or waiting for an official local-session deep link (unbounded).

The process ancestor chain distinguishes the two hosts publicly, measured:

```text
91157 (claude) → 91156 (Claude.app/Contents/Helpers/disclaimer) → 39127 (Claude.app)
```

so walking up with `ps -o ppid=` decides "Desktop-hosted" versus "a CLI in some terminal" without reading a private file.

### 4.5 Read state and automatic removal

Claude Desktop stores per session, in `~/Library/Application Support/Claude/claude-code-sessions/<org>/<account>/local_<uuid>.json`: `sessionId / cliSessionId / cwd / title / titleSource / createdAt / lastFocusedAt / lastActivityAt / isArchived / completedTurns / model / permissionMode`.

`lastActivityAt > lastFocusedAt` looks like a natural unread equivalent, and `isArchived` maps to archived directly. `cliSessionId` provides the hook `session_id` ↔ Desktop session ID mapping.

> **Correction, 2026-08-19: the implementation did not adopt that equivalent.** `lastFocusedAt`'s real meaning measured as "the moment the session was displayed on screen", and this app already knows when a Turn ended, so the test is `lastFocusedAt` later than **that Turn's end**, with the right-hand side no longer taken from the same file. Reasoning and costs in §9 and [ADR 0012](../../adr/0012-read-state-is-answered-per-product-or-not-at-all.md).

The risk level is identical to the existing Codex unread adapter: a private read-only schema, high version risk, fail closed. A pure CLI session has no concept of read at all — **superseded by the second revision of 2026-08-19**, which asks the terminal instead.

### 4.6 Quota

`~/Library/Application Support/Claude/plan-usage-history.json` looks like `{"version": 2, "samples": [{"t": …, "org": "…", "u": {"fh": 3, "sd": 0}}]}`, where `fh` / `sd` correspond to the rolling windows `/usage` shows (presumed 5-hour / 7-day percentages, **unverified**). It is Claude Desktop private state and a pure CLI user has no such file. **Superseded by [ADR 0007](../../adr/0007-read-claude-code-quota-from-the-cli.md)**: reading `claude -p "/usage"` works for every Claude Code user and removes the Desktop dependency entirely.

### 4.7 Why there is no native live status source

Whether all sessions' live status could be had by watching one native source of truth, with no hooks and no polling. The answer is **no**:

| Candidate | What it is | Why it is not enough |
| --- | --- | --- |
| `claude agents --json` | The official command returning active sessions | **Identity only, no status.** Its fields are fixed at `pid / cwd / kind / startedAt / sessionId / name`, and running it mid-Turn is byte-identical to running it idle |
| The session message bus `/tmp/cc-socks/<pid>.sock` | `[uds-messaging]`: NDJSON over a Unix domain socket, 1 MiB per line, with an auth frame | **Private, authenticated, and equally status-free.** The token is in `~/.claude/sessions/<pid>.<sha256>.key` (0600) and the server validates peer pid against token; the CLI's own peer list shows only name / kind / started. Connecting to it is a §8 NO-GO |
| The transcript JSONL | The path comes from the official hook payload and it is appended live | **It records what happened, not what is being waited on.** A 3.3 MB real transcript's record types are only `assistant / user / system / attachment / custom-title / ai-title / last-prompt / queue-operation`: **no Turn-end record and no pending-approval record.** Waiting on approval and waiting on input write nothing until they are resolved — and those are the reason this product exists |
| Desktop `local_*.json` | Claude Desktop's private session state | `lastActivityAt` updates live, but `isRunning` exists only in Desktop's in-memory model and is never persisted; and a pure CLI session has no such file |
| `--output-format stream-json` | The session's real full event stream, and what Desktop consumes | Only the session process's **parent** can read that pipe; an external app cannot attach |

**Hooks are the only officially supported channel that can express what is being waited on right now.** That is a capability boundary of the same kind as the Codex-side conclusion in [`shared-app-server`](../shared-app-server/README.md), except that Claude Code's hook set is fine-grained enough to need no second evidence source.

But "must use hooks" does not mean "must look like the Codex side": hooks are push, so the whole chain can be a passive listener with no polling and nothing written to disk.

## 5. Recommended implementation, and what actually shipped

The Codex shape is a product of constrained capabilities: a one-second poll, a Python helper writing 0600 event files, the app consuming them, a standalone App Server subprocess, and 30/60-second refresh tiers. **None of those four is needed here.** In steady state there are no timers: status changes are pushed by hooks, and sessions appearing and disappearing are file events; `claude agents --json` runs at launch and on a directory change.

### 5.1 Transport: `http` hooks — proposed, then overturned

The proposal was an `http` hook posting to a loopback listener, needing no helper script (so no script upgrade, permission or hash checks) and producing no event files (so no atomic 0600 writes, cutoff classification, delete-after-consume or quarantine directory), with the session not blocked because the listener answers `200` immediately.

**This was overturned by [ADR 0013](../../adr/0013-claude-code-hooks-run-a-helper-not-a-port.md)**, on two grounds neither of which registration can fix:

1. While the app is not running the port belongs to nobody, so the CLI prints a `hook error` line per event into the user's session — measured, 9 lines for one prompt and two tool calls — and **no setting or environment variable turns it off**.
2. An unoccupied port can be taken. `51741` sits in the macOS ephemeral range, and a 40-line impersonating listener received the full `prompt`, `cwd`, `transcript_path`, `session_id` and bearer token, then steered the next session by returning `additionalContext`. **The bearer token authenticates the CLI, not the listener.**

The shipped transport is a `type: "command"` handler running a four-line helper that writes to a 0600 Unix domain socket in this app's own support directory.

### 5.2 Event count

The proposal was 4 registrations, possibly 3, with one `Notification` registration covering every notification type by `notification_type`. What shipped is different and larger, for reasons measured later (CC-011 withdrew `Notification` once its types were measured, and subagent boundaries were added). **Count `managedDefinitions` in `ClaudeCodeHookVocabulary.swift` rather than trusting a number in prose.**

### 5.3 Session discovery: event-driven, not polled

- Run `claude agents --json` once at launch to establish the existing session set. ~~**This solves the Codex cold-start boundary directly**, with no need to wait for the next lifecycle event.~~ **Overturned in implementation (2026-08-19).** The session list answers only which sessions exist, and Turn status has to come from the transcript — which writes nothing while waiting on a user, so a rebuilt Turn could only ever be *Running*, and a session parked on a permission request at launch was drawn as working. "Show nothing from before launch" is now one rule for both products, `PRD.md` §3.
- Watch `~/.claude/sessions/` with a `DispatchSourceFileSystemObject` and re-run the official command on a change.
- **Never parse the directory's contents** — treat it purely as "time to re-check". The authority is always the official command, so a changed private schema at worst makes re-checks sluggish rather than producing wrong state.

~~Sessions whose status is unknown at launch can be published as Unknown until the first hook converges them.~~ **Also rejected (2026-08-19)**: a row of unknown status cannot answer "who is waiting for me", which is the reason this product exists.

### 5.4 Rejected routes

Pure transcript watching with no hooks (§4.7: waits are invisible); connecting to the session message bus (reading a private token file and reversing an undocumented frame format, a §8 NO-GO); and reusing the Codex on-disk helper pipeline (workable and structurally identical to existing code, but pure extra complexity where a push channel exists — kept only as a fallback, and in fact what shipped after ADR 0013, for reasons unrelated to disk).

## 6. Architectural impact

The domain layer barely moves. `MonitorDomain.swift`'s four statuses, `MonitorAvailability`, `MonitoredSession` and `MonitorAggregation` carry no Codex semantics, and `HookEventRepository`'s event schema corresponds almost field for field:

| Existing `HookEvent` field | Claude Code |
| --- | --- |
| `session_id` | `session_id` |
| `turn_id` | `prompt_id` |
| `hook_event_name` | `hook_event_name` |
| `tool_use_id` | `tool_use_id` |
| `prompt` | `user_message` |
| `last_assistant_message` | `last_assistant_message` |

The boundaries that need changing: `CodexMonitoring` becomes a multi-provider protocol (its eight methods are already a generic shape; what is needed is several instances coexisting and their snapshots merging); `MonitoredSession` gains a source identifier for the in-row marker, aggregation and navigation dispatch (its `id` is `threadID:turnID`, so a prefix is needed to avoid collisions across sources); `CodexNavigating` splits into per-source navigators and must allow "navigation unavailable", a state Codex never had; `MonitorStatus`'s display strings stop naming Codex; `CodexAppServerClient` stays Codex-only and never enters the shared layer; and the product name needs a decision.

## 7. Staged verification

**Phase 0 (must come first): confirm hooks fire in both hosts.** Prove that user-level hooks in `~/.claude/settings.json` take effect for Desktop-hosted and terminal CLI sessions alike. It requires explicit user authorisation, because it modifies the user's Claude Code configuration: back up the existing file (which did not exist on this machine, so first-creation and later-merge differ); install the registrations; start a Turn in Claude Desktop and confirm events arrive; repeat in a terminal `claude`; verify `Notification`'s type coverage (whether `permission_prompt` fires in an ordinary interactive session and **whether anything closes it after approval or refusal**; whether `agent_completed` fires in an ordinary session; and `idle_prompt`'s real trigger conditions); verify the transport's reliability when the app is not listening; confirm hot-loading; confirm the real effect of workspace trust; and remove the hooks completely, confirming the configuration is restored.

**Stop if** Desktop sessions receive no hook; if installing hooks makes the user re-run workspace trust in every project; or if the transport has any visible effect on a user's session while the app is not running.

**Phase 1: the session set and identity** — completeness of `claude agents --json` under concurrency (two Desktop, one terminal, one background agent); `sessionId` matching the hook's `session_id`; `prompt_id` genuinely changing across consecutive Turns and never being reused; subagent events carrying `agent_id` / `agent_type` and filtering correctly; and when a finished session leaves the listing.

**Phase 2: the four-status matrix** — replay real event sequences against the existing reducer rules, covering normal completion, permission approval (opened by `PermissionRequest`, closed by the same `tool_use_id`), a refused approval, needed input (`Elicitation → ElicitationResult` paired), a failed request (`StopFailure` straight to Completed), the next Turn on one session (a new `prompt_id` replacing atomically, with the old unrevivable), compaction (`PreCompact` / `PostCompact` changing no status) and session end. Minimum repetitions as in the `shared-app-server` exploration: 30 completions, 30 approvals, 20 inputs, and at least 10 each of failure and concurrency.

**Phase 3: degraded navigation** — implemented and merged 2026-08-19 ([#31](https://github.com/soondubu137/notchline/issues/31)); see [`tech-design.md`](../../tech-design.md) §14.2. Two things differ from the plan: the ancestor chain uses `sysctl(KERN_PROC_PID)` and `proc_pidpath` rather than a `ps` subprocess; and Ghostty has a full scripting dictionary with no tty anywhere in it, so it falls into "activate the application only" rather than needing per-terminal support.

> **A trap hit while verifying this, left for whoever is next.** TCC's notion of client identity depends on **how the app was launched**. Authorisation granted after directly exec'ing `…/DerivedData/…/Notchline.app/Contents/MacOS/Notchline` is **not the same record** as one granted after launching the same bundle through Launch Services (`open -n -a`): with the former authorised, the latter still reports `undecided`. That also explains two other observations — that authorisation does not appear in System Settings › Privacy & Security › Automation at all, and `tccutil reset AppleEvents com.yinfenglu.Notchline` cannot match it. **Only the Launch Services path is the real post-release identity**, so verification must go through `open -n -a … --env … --stderr …`, and conclusions from running the binary directly do not count.

**Phase 4: read state, quota and degradation** — the update timing and throttling of `lastFocusedAt` / `lastActivityAt`; whether `plan-usage-history.json`'s `fh` / `sd` match `/usage`; and degradation when Claude Code is absent, too old, or its hooks untrusted.

## 8. Product decisions and NO-GO conditions

**Decided 2026-08-15:** navigation degradation is acceptable and applies **only** to Claude Code — a Desktop session activates Claude Desktop and a CLI session focuses its terminal tab, with neither required to locate the specific session, while **Codex keeps its exact-navigation requirement** and ADR 0004's release gate continues to bind it. Requesting Automation (Apple Events) authorisation for focusing a terminal tab is acceptable; Accessibility and Screen Recording remain excluded.

**Since resolved:** Project semantics by [ADR 0009](../../adr/0009-resolve-project-per-product.md); quota by [ADR 0007](../../adr/0007-read-claude-code-quota-from-the-cli.md) (available to every user, not only Desktop); the product name in #36; and whether to align both sides' status semantics — **decided to keep four**, because a status only Claude Code can observe would make the shared vocabulary lie on Codex.

**NO-GO conditions**, any one of which stops productising this:

- ~~Phase 0 proves user-level hooks do not work for Desktop-hosted sessions~~ — **ruled out 2026-08-16, §9**.
- Installing hooks makes the user re-run workspace trust in every project, an unacceptable installation friction.
- The hook transport has a visible effect on the user's session while the app is not running or has crashed (blocking, errors, a stuck approval). **This was hit — see §9's 2026-08-18 entry and ADR 0013 — and answered by changing the transport rather than abandoning the integration.**
- Degraded navigation cannot even activate the right application or terminal, or can only be done through Accessibility and GUI automation.
- It requires modifying `Claude.app` or `app.asar`, injecting Electron IPC, or connecting to `/tmp/cc-socks/*.sock`.
- Official builds remove `claude agents --json`'s visibility of interactive sessions, regressing to Codex's "cannot query the current state".

## 9. Exploration log

Appended, never overwritten. Entries whose reasoning has moved into an ADR are summarised here with a pointer.

### 2026-08-15 — initial feasibility study (read-only)

Read-only inspection plus one `claude://` deep-link probe and two `claude agents --json` runs, against Claude Desktop `1.30096.5`, CLI `2.1.229`, macOS `Darwin 25.5.0`. Nothing modified. **Result: status summarisation PASS (§4.1–4.3); exact navigation FAIL (§4.4).** Unverified: whether hooks fire in Desktop-hosted sessions; `fh` / `sd`'s exact window semantics; `lastFocusedAt`'s update timing.

### 2026-08-15 — native truth-source investigation (read-only)

Prompted by "could this work with no hooks and no polling". **Answer: no** — all five candidates describe identity or something already past (§4.7). Three incidental findings: `claude agents --help` documents `--json` as printing active sessions including interactive ones, making that a promise rather than a coincidence; one `Notification` registration can cover approval and input waits by `notification_type`; and the session message bus is token-authenticated NDJSON over UDS with the token in `~/.claude/sessions/<pid>.<sha256>.key`, listed as a NO-GO.

### 2026-08-16 — Phase 0 in part: `http` hooks measured (CLI only)

**`~/.claude/settings.json` was not modified**; everything went through `claude -p --settings <temp file>` injecting 15 `type: "http"` registrations pointed at a temporary listener bound to `127.0.0.1` requiring a bearer token, recording only field names and safe scalars. Five `-p` runs on `claude-haiku-4-5`, CLI `2.1.233`.

**Conclusion: the channel works, and a NO-GO was one step from being triggered.**

| # | Result | Consequence |
| --- | --- | --- |
| 1 | All 15 registrations delivered | The channel is usable |
| 2 | With the listener closed, hooks failed **completely silently** and the session finished normally (`is_error: false`) | ⚠️ **Partly corrected 2026-08-18: the silence holds only under `-p`; an interactive session prints a `hook error` line per event** |
| 3 | **`SessionEnd` is the exception**: one `connect ECONNREFUSED` line to stderr per session | ⚠️ Corrected 2026-08-18: interactive sessions print a line for every other event too, so "visible impact reduced to zero" held only for `-p` and scripts |
| 4 | **`PermissionRequest` carries no `tool_use_id`** (measured fields: `agent_id, agent_type, cwd, hook_event_name, permission_mode, permission_suggestions, prompt_id, session_id, tool_input, tool_name, transcript_path`) | §4.2 and §3 were wrong: the Codex "borrow a still-open call id" model is **still required** here |
| 5 | `PermissionRequest` fires in a non-interactive run with nobody asked | The same lesson as Codex: a lone `PermissionRequest` is not evidence anyone is waiting |
| 6 | `prompt_id` appears on **every** event, `SessionEnd` included | It is the `turn_id`, and the identity rules carry over |
| 7 | **Subagent events carry the parent's `session_id` and `prompt_id`** plus `agent_id` / `agent_type` | Subagent activity folds into the parent Turn naturally, with no extra identity work and no separate row |
| 8 | **`UserPromptSubmit` has no `source` field under `-p`** | Self-noise filtering **cannot** rely on `source == "user"`; pinning the quota read to a dedicated working directory and filtering by `cwd` is the primary defence |
| 9 | **No timestamp anywhere in the payload** | Codex's helper writes its own `received_at`; a listener must stamp arrival itself |
| 10 | **Delivery is unordered.** Under one `prompt_id`, the parent `Stop` arrived before a subagent's `PermissionRequest` and `SubagentStop` | The reducer's `lastEventAt` monotonicity can only come from the listener's arrival stamp; and "activity on another `tool_use_id` closes a borrowed approval" needed separate handling. **Later re-read (subagent-row-consistency §6.1): that is not disorder but the shape of an asynchronous subagent, and per-agent slots dissolve it** |
| 11 | `Stop` additionally carries `session_crons`; `background_tasks` was empty here | — |
| 12 | `PostToolUseFailure` fires on an ordinary tool error with `error` / `is_interrupt` / `duration_ms` | Interrupts and errors are distinguishable |

**Left unanswered, and answerable only with a real `~/.claude/settings.json`: do hooks fire in Claude Desktop-hosted sessions.** That is the make-or-break question, and `--settings` affects only the CLI process it starts.

### 2026-08-16 — Phase 0 closed: Desktop-hosted sessions do fire hooks

The user wrote seven `type: "http"` registrations into their real `~/.claude/settings.json` (this agent was stopped by the permission classifier and did not write it) and restored from backup immediately afterwards. `SessionEnd` was deliberately excluded.

**Conclusion: the first NO-GO does not hold. User-level hooks fire normally in Desktop-hosted sessions, and the whole approach stands.** The evidence was that conversation itself — `~/.claude/sessions/45912.json` recorded `"entrypoint":"claude-desktop"` while every event the listener received carried the same `session_id`, with `UserPromptSubmit` (`permission_mode: auto`), `PreToolUse` (`tool_name: Bash`, `tool_use_id: toolu_01Qq4o…`) and `PostToolUse` (the same `tool_use_id`, `duration_ms: 3049`) — so the paired open/close model is structurally identical in both hosts.

Two supplementary observations: `permission_mode` produced `auto`, previously unseen under `-p`, so the status mapping must not assume that field's value set; and `UserPromptSubmit` has no `source` field on a real human submission either, making it **universally absent** rather than `-p`-specific.

### 2026-08-18 — correction: `async` is not a configuration key, and the silence holds only under `-p`

CLI `2.1.235` (schema also checked on `2.1.233`), prompted by a user reporting hundreds of `connect ECONNREFUSED 127.0.0.1:51741` lines in a CLI session.

| # | Result | Consequence |
| --- | --- | --- |
| 1 | **The `http` hook schema has no `async`.** The accepted keys are `type` / `url` / `if` / `timeout` / `headers` / `allowedEnvVars` / `statusMessage` / `once` | Every earlier "`async` guarantees it does not block" claim is void. `async` is a **response** field: a hook returning `{"async": true, "asyncTimeout": n}` says it will continue in the background |
| 2 | **A written `async` is silently deleted.** Hooks are parsed by zod (unknown keys dropped without warning), and any settings write (`/effort`, `/theme`, `/config`, permissions, plugin install) rewrites `~/.claude/settings.json` wholesale from the parsed model | This is why the user's edits "kept disappearing", and it is worse for this app: `isCurrentManagedHandler` compares the whole handler, so a dropped key means `repairRequired`, a re-paste, and the next write dropping it again |
| 3 | Registrations with and without `async` behave **identically** | Corroborates #1; removing it loses nothing |
| 4 | **An interactive session prints a `<hookName> hook error` line per failed event.** The renderer returns `null` only for `Stop` / `SubagentStop` and prints everything else, and **no setting or environment variable turns it off** (`suppressHook` / `hideHook` / `HOOK_SILENT` / `DISABLE_HOOK` all absent) | 2026-08-16's "completely silent" holds only under `-p`. The NO-GO about visible impact while the app is not running therefore holds **for every event**, not only `SessionEnd`. See CC-021 and [ADR 0013](../../adr/0013-claude-code-hooks-run-a-helper-not-a-port.md) |
| 5 | The failure **does not enter the model's context and costs no tokens**: it is recorded as a `{"type":"hook_non_blocking_error","exitCode":0}` attachment | The noise is a UI matter and does not affect session quality, duration or cost |
| 6 | A refused connection on loopback returns immediately, so `timeout: 5` is never waited out | Only an unreachable (rather than refused) address, behind a filtering firewall say, would genuinely hang |
| 7 | **An unoccupied port can be taken.** `51741` is inside the macOS ephemeral range | A 40-line impersonating listener received the full `prompt`, `cwd`, `transcript_path`, `session_id` and bearer token, and steered the next session by returning `additionalContext`. The bearer token proves the CLI's identity, not the listener's — the real risk surface of this channel, CC-021 |

### 2026-08-19 — automatic removal once read: `lastFocusedAt`'s meaning confirmed and implemented (CC-013)

Claude Desktop `1.32885.1`, built-in CLI `2.1.234`, local CLI `2.1.235`. Read-only throughout.

§2's "unread: `lastActivityAt` vs `lastFocusedAt`" was a **guess**; this measured it and **changed the test**:

| # | Result |
| --- | --- |
| 1 | `lastFocusedAt` means **"the session was displayed on screen"**, not "last active": `setSessionVisibility(id, isVisible, reason)` sets `lastFocusedAt = Date.now()` when `isVisible` and calls `saveSession` immediately. That is exactly "the user read it", more direct than the `lastActivityAt` guess |
| 2 | **The test became `lastFocusedAt` later than that Turn's own end**, no longer compared against the same file's `lastActivityAt` — so a desktop's bookkeeping delay, throttling or write stall cannot make a Turn read, and a stale snapshot can only keep a row longer |
| 3 | Records are written by **`rename` from a temporary file in the same directory** (measured inode change `63502564 → 63503966`), so a directory-level watcher works — the opposite of `~/.claude/sessions/<pid>.json`'s in-place rewrite |
| 4 | 31 records, about 2 MB: **5 ms** to parse all, **1 ms** re-read once cached on `(size, mtime, inode)` — affordable every refresh, needing no separate throttle |
| 5 | In real data, 17 of 20 records have `lastFocusedAt > lastActivityAt`, so users really do stamp again after reading |
| 6 | **A pure terminal session has no file in this tree**, and Claude Code persists no focus/read/seen field (`2.1.235` string search; `isFocused` hits are all Ink component props). Read state can cover only the Desktop half — a capability boundary rather than an implementation gap ([ADR 0012](../../adr/0012-read-state-is-answered-per-product-or-not-at-all.md)) |
| 7 | Two Desktop-hosted sessions joined by `cliSessionId` and yielded focus moments; the terminal session this document was written in reported `unknown`. Identity needs no inference |

**A live observation the same evening (250 ms sampler, 30 minutes):** opening a session in Claude Desktop produced exactly **one** write — `lastFocusedAt` from `1787114114311` to `1787126484364`, by a new inode. The one surprise: that stamp landed **1.249 seconds before** the CLI process resuming that session had its `startedAt`, so "the user opened a session" is visible to this app before that session's process exists. The same shape held in another record the previous day (focus about 1.1 s before `startedAt`).

**A second real-machine run the same day answered a question in the negative, more thoroughly than expected.** The user ran a full flow: open a session in Desktop → submit → switch to another window → the Turn finishes (Completed appears on the notch) → switch back to Claude Desktop and read it. The sampler recorded `lastFocusedAt` at 01:06:33.307 (selecting the session), `lastActivityAt` at 01:06:43.458 (submitting), `lastActivityAt` and `completedTurns` 1→2 at 01:07:37.826 (**the Turn ending**), and **nothing afterwards**. A scan of the whole `~/Library/Application Support/Claude` tree for files modified in the last 6 minutes found **0**. So it is not merely that `lastFocusedAt` is not stamped — **that reading leaves no trace on disk at all**. The existence of a `reason === 'blur'` branch had suggested gaining focus would also send `true`; measurement disproved it, because the renderer sends document-visibility transitions and another app taking focus on macOS does not change `document.hidden`.

**Conclusion: a read-only file adapter cannot cover the most common usage — staying on one session, switching away and back.** Hence the second test (the app returning to the foreground, with Desktop's records showing that session as the last displayed), which overturns two rules written only for Codex; reasoning and costs in [ADR 0012](../../adr/0012-read-state-is-answered-per-product-or-not-at-all.md).

### 2026-08-19 (review) — the file side ends here; the remaining two must come from a person's action

Read-only: `app.asar` and `~/Library/Logs/Claude/main.log` string searches, a full field dump of `local_*.json`, and one `claude agents --json`.

| # | Result |
| --- | --- |
| 1 | **Claude Desktop has no read field for Claude Code sessions.** `lastReadAt` / `hasUnread` / `seenAt` / `viewedAt` are zero hits, and every `markAsRead`(8) and `isRead`(89) hit belongs to the Outlook MCP connector's mail rules. There is no set to use as a blue dot |
| 2 | **`main.log` says no more than the files.** `[CCD] LocalSessions.setFocusedSession: sessionId=…` is written at `[info]` (531 lines over 4 days here) but appears only on session switches, a subset of the stamps. **Overturned that evening — see below: in the decisive direction it is a superset, because it also writes `sessionId=null`** |
| 3 | **Regaining window focus really does write nothing.** Of 46 `[SkillsPlugin] Window focused` lines, two (23:11:42, 00:17:05) had no visibility write in the following 60 lines, while every other was immediately followed by the user's own session switch — independently confirming the previous entry's "0 files changed" |
| 4 | **`lastFocusedAt` gets stamped with nobody present.** At 09:29:00 `system woke — reconnecting` and `main process blocked for 603508ms [likely sleep: power_event]`, at 09:29:06 `[WarmLifecycle] Warming up session local_e7cca89e…`, and `lastFocusedAt` landed at 09:29:09 with no `setFocusedSession` anywhere (that session's previous one was 8 hours earlier). So test 1 has a direction that retires early — limited, since the answer is on screen at wake, but it is the only existing rule that can hold with nobody present |
| 5 | **Desktop-hosted rows are not "kept forever".** A local session hidden for 900 seconds is torn down by `teardownSession` (`idle_timeout` with `shouldKillOnIdlePause()` true), the process goes, the session leaves the listing, and the row follows (22:04:26 `Starting idle timeout … 900s` → 22:19:27 `Pausing session … (idle_timeout)`). **This corrects #32's premise**: a Desktop session switched away from disappears within 15 minutes, and CC-013 is about "waiting up to another fifteen minutes after reading", with only "parking on that session" genuinely indefinite |
| 6 | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType:)` gives per-event-type values, public, no entitlement, no authorisation prompt (measured `keyDown 82.9s` / `scrollWheel 574.1s` / `leftMouseDown 294.6s` / `mouseMoved 293.4s`). This supported the first version of test 3 (`c1052bb`), later replaced by a state test |
| 7 | `com.apple.loginwindow`'s `activationPolicy` is `.accessory`(1) rather than `.regular`(0) — recorded because it conversely supports **rejecting** "another regular app taking the foreground from Desktop means read": that route would filter the lock screen by this policy, and it cannot filter a regular app stealing focus |
| 8 | "Might anyone be looking at the screen" has three public, entitlement-free, prompt-free readings: `CGDisplayIsAsleep`; `CGSessionCopyCurrentDictionary`'s `CGSSessionScreenIsLocked` (**the key is absent when unlocked**, not `false`) and `kCGSSessionOnConsoleKey`; and the screen saver's `com.apple.screensaver.didstart` / `didstop`. The first two are **readable states** and the saver is a **notification that may be missed**, so it is a supplement rather than a dependency |

**Conclusion: at the moment a Turn ends the two kinds of user are identical, and that is not a missing API.** The person watching it finish and the person who submitted and walked away both last did the same thing — submit — and waiting grows no difference. The first shipped version (`c1052bb`) took "the first thing the reader does next", typing or scrolling into Desktop; safe, but unable to answer "sat, read, did nothing", which is what was asked. **The product then replaced it**: stop telling the two apart and ask instead whether that answer is on a screen someone might be looking at, accepting that whoever leaves the window in front and walks away loses a notification. Rules, guards, per-scenario behaviour and costs in [ADR 0012](../../adr/0012-read-state-is-answered-per-product-or-not-at-all.md).

### 2026-08-19 (second revision) — terminal sessions have an exit too: ask the terminal, not Claude Code

The previous entry concluded there was no truth source for the terminal half. **That conclusion was wrong about who to ask, not about the evidence.** Claude Code still has no concept of read (re-checked on 2.1.236: `lastFocusedAt` / `hasUnread` / `seenAt` / `viewedAt` all zero hits; the in-process `userPresence` holds `lastInteractionTime()` and `terminalFocus()` but lives only in memory). What can speak is **that session's controlling terminal**.

Measured (Ghostty, CLI `2.1.236`):

| Action | `/dev/ttys001` access time | `/dev/ttys004` (another, hidden window) |
| --- | --- | --- |
| Start | `…652.114` | `…705.770` |
| Ghostty already frontmost, activate it again | unchanged | unchanged |
| Ghostty → Chrome | **advances** (`…683.874`) | unchanged |
| Chrome → Ghostty | **advances** (`…685.954`) | unchanged |
| Ghostty → Chrome | **advances** (`…688.028`) | unchanged |
| Another full foreground round trip | **advances twice** | **0 changes** |

Throughout, `claude` was rendering and the **modify** time moved every 0.5 s while access time did not — so access time is the usable one, and modify time would count every frame as a user.

**Whether a Turn ending itself produces input** was verified separately, because if it did, a row would retire with nobody having read it. A purpose-built pty with `claude` attached, fed one prompt from the master and then merely watched:

```
slave=/dev/ttys004
…770.728  atime=…770.000  <-- MOVED   the startup terminal capability query's reply
…778.509  WROTE prompt
…778.509  atime=…778.509  <-- MOVED   the prompt I typed
(0 changes for the next 67 seconds, while the screen showed Contemplating → OK → Ran 1 stop hook → Cooked for 2s)
```

The rule, its later correction for all-motion mouse reporting (2026-08-20), and every degradation direction are in [ADR 0012](../../adr/0012-read-state-is-answered-per-product-or-not-at-all.md) and `tech-design.md` §1.5.1.

### 2026-08-20 — the hook transport moved from a port to a helper

`command` has `async` and `http` does not; a port belongs to nobody while the app is closed, and an unoccupied one can be taken. Measurements, the rejected launchd socket-activation alternative, the per-event cost table and the consequences are in [ADR 0013](../../adr/0013-claude-code-hooks-run-a-helper-not-a-port.md) (CC-021).

### 2026-08-20 (same day) — `SessionEnd` reconsidered and still not registered: it is later than the watcher

Its original exclusion was that it is the one event whose failure writes to the CLI's own stderr; the helper cannot fail that way, so that reason lapsed. Re-examined on its own merits it earns nothing: sampling `~/.claude/sessions/<pid>.json` every 20 ms on 2.1.237 in a pty session, the file was deleted at **+15.09 s / +15.08 s** across two runs while `SessionEnd` arrived at **+15.41 s** both times — **the watcher's signal is about 330 ms earlier**. `/clear` looks like an exception (the process lives, no file changes) but swaps the session id under the same pid, so the old id leaves the listing at once and the row disappears as usual. Full reasoning in ADR 0013.

## 10. References

- Official Claude Code Hooks: <https://code.claude.com/docs/en/hooks>
- Official CLI reference (including `claude agents --json`): <https://code.claude.com/docs/en/cli-reference>
- Official deep links: <https://code.claude.com/docs/en/deep-links>
- Official Desktop app: <https://code.claude.com/docs/en/desktop>
- Current domain state, hook reducer and orchestrator: [`MonitorDomain.swift`](../../../Notchline/Notchline/MonitorDomain.swift), [`HookIntegration.swift`](../../../Notchline/Notchline/HookIntegration.swift), [`LiveCodexMonitorService.swift`](../../../Notchline/Notchline/Products/Codex/LiveCodexMonitorService.swift)
- Current architecture: [`system-architecture.md`](../../system-architecture.md)
- Non-public dependency registration rules: [`AGENTS.md`](../../../AGENTS.md)
