# Codex CLI support — implementation plan and isolated evidence

> Implementation update, 2026-09-15: the current contract is in [product support](../../product-support.md#51-local-codex-cli). Native timing showed that `/new` delays SessionStart until the next submission; the proposed current-view/TTY-navigation inference below was rejected, and the implementation uses host return only. §5's rule that read evidence needs the *displayed* root was rejected with it, on 2026-09-15 pty readings: a Codex TUI's device is moved by a keystroke, a paste or a focus report and by nothing the TUI itself does, so a gesture there is the same evidence every other terminal row is retired on, and read removal is enabled without a display binding. Home identity uses an open `state_5.sqlite` descriptor because this macOS does not return process environment through KERN_PROCARGS2. The remainder is the historical preflight record.


| Field | Value |
| --- | --- |
| Status | Historical proposal; implementation and corrected boundaries are linked above |
| Verified | 2026-09-14, macOS 26.6.2, standalone `codex-cli 0.154.0` |
| Baseline | `af903a2`, branch `feature/codex_cli_integration` |
| Objective | Support ordinary local Codex CLI alongside Desktop, reusing Codex protocol handling and the shared monitoring model |
| Recommended first route | Live Hooks plus an independent App Server for metadata and persisted content; terminal evidence for the local CLI |

This records the preflight proposal, not the current [support contract](../../product-support.md). At preflight, that contract excluded standalone Codex CLI. The [glossary](../../../CONTEXT.md) owns terminology. Proposed changes to its Desktop-only Codex rules are identified below and must land with the implementation.

## 1. Proposed scope

One Codex product, one Provider and one Turn reducer. Desktop and CLI are execution surfaces of that product, not separate products with duplicate quota and Hook installations. Keep the Desktop path working independently of CLI discovery and failures.

| Mode | First-release proposal | Admission and limits |
| --- | --- | --- |
| Ordinary local interactive `codex` | Include | Verified local TUI process, controlling terminal, live Hook evidence and an eligible root Thread returned by the matching home’s App Server |
| Several local CLI terminals, including identical working directories | Include | Attribute by native process identity and TTY; never by directory, title or most recently active app |
| `/new` and local resume | Include after native acceptance | Track process ownership separately from the Thread currently displayed; `/new` observed, resume still an acceptance gate |
| CLI and Desktop open together | Include after native acceptance | One row per Thread/Turn; each owner has its own lifetime; Desktop quitting cannot retire CLI-owned Turns |
| Custom `CODEX_HOME`, multiple accounts | Defer | First release targets the normal shared home. Positively establish the home; never query the default home for a custom-home event |
| `--remote`, shared daemon, `codex agents` | Defer | Hook ancestry identifies the executor, not the TUI. A separate client-to-Thread association source is needed |
| `codex exec`, piped output, SDK-created work | Exclude initially | CLI installation and `source: cli` are not sufficient to establish an interactive, returnable surface |
| SSH, tmux, screen and detached processes | Exclude initially | No verified mapping to a local visible terminal surface |
| IDE extensions, cloud work, ephemeral side chats | Exclude | Preserve root eligibility and explicit mode boundaries |

The target is cumulative **L6 for ordinary command approvals**, with synchronous question reading and waiting at L4/L5, conditional on all lower-level gates passing. This is a target, not earned coverage. Additional request forms need their own samples. No question-answering control is promised over Hooks.

## 2. What was verified

### Method and limits

The installed CLI was run in allocated pseudo-terminals with an isolated `CODEX_HOME` and working directory. A loopback HTTP service supplied deterministic Responses-format messages and harmless tool calls. No remote model, user credentials, user conversations or user Hook configuration were used. The probe’s known Hook definitions ran under the documented one-invocation trust bypass; this did **not** test the normal trust UI or authorise bypassing it in production.

The CLI, its TUI, Hook execution, approval engine, persistence and App Server were real. The model output was synthetic. The custom probe model used fallback metadata, so these results do not establish which forms a production model chooses. No native terminal application was opened or focused: terminal emulation bytes and kernel access times were tested, not end-to-end application navigation or human read removal.

### Observations

| Probe | Result | Architectural consequence |
| --- | --- | --- |
| Ordinary TUI launch and submission | No shared control socket and no child App Server process observed; the TUI process executed its Hooks | Do not require a daemon for the ordinary local mode |
| Successful Turn | `SessionStart`, `UserPromptSubmit`, `Stop`; submission/end share the exact Turn ID; `Stop.last_assistant_message` contains the supplied final text | Reuse the Codex Hook vocabulary and final-answer path |
| Esc during a held model response | `Interrupt` with the exact active `turn_id`; no `Stop` for that interrupted Turn in the sample | Add the public interruption event; do not require a private rollout read for this CLI path |
| Command approval allowed by Hook | `PreToolUse(Bash)` → `PermissionRequest` → `PostToolUse` → `Stop`; the harmless `printf` executed | Existing decision encoding and request-bound answer channel are viable |
| Command approval denied by Hook | `PreToolUse` → `PermissionRequest` → `Stop`; no `PostToolUse`; CLI displayed the denial | Preserve current refusal-settlement rules; denial does not invent a missing native event |
| Shared-file parser compatibility | Desktop's bundled `0.154.0-alpha.6.2` App Server accepted the isolated ten-event file; `hooks/list` returned all ten events with no errors | The current two installed parsers accept the proposed additions; normal trust activation and future version compatibility still need checks |
| Plan-mode synchronous question | `PreToolUse(request_user_input)` contained question IDs/options; TUI displayed the question; answering in TUI produced matching `PostToolUse` and then `Stop` | Existing question reading and call-ID settlement are viable; Hook question answering remains unavailable |
| Current shell/`nc` helper shape | `LOCAL_PEERPID` on the accepted Unix connection identified `nc`, then `/bin/sh`, then the live TUI with its TTY | Source provenance can be added at the listener boundary without rewriting the trusted command or changing native payload JSON |
| Two TUIs in the same directory | Different TUI PIDs and TTYs were correctly recovered from their separate Hook connections | Directory-based attribution is unnecessary and incorrect |
| `/new` in one TUI | New Thread emitted `SessionStart` on the same TUI PID/TTY; the old Thread’s `SessionEnd` arrived only when the process exited | Separate ownership from currently displayed Thread; late end events must not erase a newer binding |
| Terminal focus protocol | TUI emitted `ESC[?1004h`; sending a focus-in sequence advanced the controlling TTY’s access time | Terminal read evidence is technically viable; actual host focus/unlock/tab behaviour remains unverified |
| Independent App Server during a CLI Turn | `thread/read(includeTurns:false)` returned the correct ID, `source: cli`, `originator: codex-tui`, `threadSource: user`, `ephemeral:false`, and **`status:notLoaded`**; `thread/loaded/list` was empty | Persisted metadata is useful, but this server does not know the other runtime’s active state |
| Persisted content | After completion, `thread/items/list` scoped to the exact Turn returned its user and agent messages | Reuse the existing bounded content reader; this sample does not measure in-flight text freshness |
| Project metadata | Sample CLI Thread had `projectId:null`; `project/list` returned a valid empty set in the isolated home | A CLI without a Project is real; no proof that Desktop’s current private Project adapter can be removed |
| Proxy to a test Unix listener | `initialize` did not answer within five seconds; proxy remained alive until the probe stopped it | Do not base first-release support on proxy availability; one timeout is not a claim that every proxy topology is broken |
| Direct Unix WebSocket and remote TUI | Direct initialisation succeeded; `codex --remote unix://…` completed a Turn. Its Hook parent was the server process with no TTY, not the TUI | Remote execution needs a different ownership source even when both processes are local |

These tests establish feasibility and several failure boundaries. They do not establish Notchline support: the production listener, Provider and panel were not connected to these probes.

## 3. Architecture and reuse

### 3.1 Keep one Codex orchestration centre

Retain the Codex Provider because it owns the App Server connection as well as Hooks. Do not copy `LiveCodexMonitorService` into a second Provider or force its connection management into the Hook-only runtime. Extract surface-specific dependencies while preserving the shared reducer, ordered delivery, request occurrence identity, metadata batching and membership rules.

Proposed flow:

```text
Desktop Hooks ─┐
              ├─ listener + kernel sender evidence ─ Hook boundary ─ MonitoringRepository
CLI Hooks ────┘                                      │
                                                    └─ Codex owner/display bindings

Independent App Server ─ root eligibility, title, persisted content, account/quota
Desktop sources ──────── Desktop presence, Project, unread state, deep-link destination
CLI sources ──────────── TUI presence/lifetime, current TTY, terminal gestures, host destination
                                  │
                            one Codex Provider
                                  │
                         AgentSnapshot → MonitorSnapshot
```

Source adapters return evidence. Only the Provider decides how sources combine; only `MonitoringRepository` changes Turn state. UI layers consume the existing snapshot contract.

### 3.2 Reuse map

| Existing code | Proposed treatment |
| --- | --- |
| [MonitoringRepository](../../../Notchline/Notchline/MonitoringRepository.swift), [MonitoringEvidence](../../../Notchline/Notchline/MonitoringEvidence.swift) | Preserve the sole reducer and its identity/order/retirement guards |
| [CodexHookVocabulary](../../../Notchline/Notchline/Products/Codex/CodexHookVocabulary.swift) | Reuse payload/request interpretation and answer encoding; add public `Interrupt`; route session metadata outside Turn-start semantics |
| [AgentHookListener](../../../Notchline/Notchline/AgentHookListener.swift), [HookEvidenceBoundary](../../../Notchline/Notchline/HookEvidenceBoundary.swift) | Capture sender provenance while the peer is alive; pass a typed boundary context alongside native JSON |
| [CodexHookRegistrar](../../../Notchline/Notchline/Products/Codex/CodexHookRegistrar.swift), [CodexHookActivation](../../../Notchline/Notchline/Products/Codex/CodexHookActivation.swift) | One managed installation per home; preserve existing definition bytes/indices and trust; check activation in the relevant configuration context |
| [CodexAppServerClient](../../../Notchline/Notchline/Products/Codex/CodexAppServerClient.swift) | Reuse JSONL framing, request correlation, timeouts and compatibility fallback; retain independent read-only mode in the first release |
| [LiveCodexMonitorService](../../../Notchline/Notchline/Products/Codex/LiveCodexMonitorService.swift) | Extract owner lifetime, context, read and navigation selection; reuse metadata/content scheduling and root admission |
| [CodexUsageReader](../../../Notchline/Notchline/Products/Codex/CodexUsageReader.swift) | One account reading for the shared home; preserve unavailable/signed-out/provider distinctions |
| [TerminalReadEvidence](../../../Notchline/Notchline/TerminalReadEvidence.swift), [ProcessHostNavigator](../../../Notchline/Notchline/ProcessHostNavigator.swift), [TerminalHostRegistry](../../../Notchline/Notchline/TerminalHostRegistry.swift) | Reuse kernel gesture and host selection mechanisms through a Codex `SessionProcessLocating` adapter, with an additional current-Thread check |
| [CodexDesktopNavigator](../../../Notchline/Notchline/Products/Codex/CodexDesktopNavigator.swift), Desktop unread/Project sources | Retain for Desktop-owned evidence; do not apply them indiscriminately to CLI Threads |
| [CodexRolloutTurnEvidence](../../../Notchline/Notchline/Products/Codex/CodexRolloutTurnEvidence.swift) | Preserve Desktop and held-start compatibility paths; public CLI interruption can replace only the cancellation part verified for that mode/version |

The shared UI, requests, answers, aggregation and quota presentation should require little change. The principal work is correct ownership and surface lifetimes, not a new status implementation. No line-count reuse percentage is claimed.

## 4. Ownership is the first implementation package

### 4.1 Facts to retain

Keep two distinct concepts in a proposed `CodexSurfaceEvidence` adapter:

- **Execution owner:** a validated process identity (PID plus creation identity), execution mode, home identity and observation epoch; a Thread may remain owned after another Thread appears in that TUI.
- **Displayed binding:** which root Thread is currently displayed by that TUI/TTY, and the evidence generation that established it.

Use kernel peer identity and a bounded process ancestry walk while the Hook helper waits for acknowledgement. Validate executable identity, process role and controlling terminal. A process called `codex` is not sufficient: `app-server`, `exec`, a proxy, a TUI and a daemon must not be conflated. Reject changed/reused PIDs and unverifiable provenance. Keep process queries out of SwiftUI; avoid spawning `ps` in production.

`source` and `originator` provide creation metadata, not current ownership. A distant Desktop ancestor is not proof of Desktop ownership: a genuine local CLI can be run from an integrated terminal. Home discovery must be an allowlisted boundary operation, not a dump of process environment variables. If a home or mode cannot be established, do not query another home or guess a destination.

The native Hook payload does not gain synthetic Codex fields. Extend Notchline’s listener delivery context; keep filesystem/process details outside the Turn reducer. Capturing peer context must preserve the queue’s existing acknowledgement ordering and answer descriptor ownership.

### 4.2 Binding transitions

1. Root `SessionStart` establishes a current display binding, **not** a Running Turn. A subagent event never selects the root displayed by the TUI.
2. `UserPromptSubmit` supplies the live Turn boundary, updates validated ownership and confirms current root display. Root eligibility still comes from matching-home `thread/read`.
3. A new root `SessionStart` on the same TUI replaces only the displayed binding. Do not end an older active Turn or let its later background activity select it again.
4. `SessionEnd` invalidates only its matching Thread/owner binding. It carries no Turn ID and must not manufacture completion or erase a newer displayed Thread.
5. Owner process exit ends that owner’s observation lifetime and retires its rows according to the product lifetime contract. It does not claim the work completed. Other CLI processes and Desktop remain unaffected.
6. A binding without fresh validation can support neither read removal nor exact navigation. Preserve a usable host-return outcome only when that host itself is still verified.
7. If the same Thread is observed on two surfaces, keep one Turn row and separate owner/display evidence. A surface ending cannot invalidate another live owner. Conflicting simultaneous executors for the same native Turn require a fail-closed reconciliation rule and a dedicated acceptance case.

`SessionStart`, `SessionEnd` and `Interrupt` would extend the current seven managed definitions to ten. Append only the missing definitions; do not rewrite the seven existing ones. New definitions require the normal `/hooks` review. Recheck after trust changes, and keep monitoring intent separate from activation evidence.

The shared file also reaches Desktop's bundled CLI, which may be a different version. Before installing the added events, test that both readers accept the complete file; a standalone version check alone is insufficient. If a reader rejects an event, retain a compatible configuration and its existing fallback rather than breaking the other surface. Do not change indices or hashes merely to negotiate versions.

Keep invalidation scoped to its owner. A CLI process exit or a failed CLI adapter must not advance the entire repository epoch and discard Desktop callbacks. Retain a product-wide epoch for disabling/restarting observation and an owner generation for events/bindings inside that lifetime.

## 5. Behaviour by capability

### Lifecycle, content and requests

- Open Turns only from live submissions and keep current duplicate, held-start, late-event and subagent guards. Historical records never create rows after launch.
- Feed public `Interrupt` through typed interruption evidence with the exact Thread/Turn identity. It is not a `Stop` alias; test pending request settlement and child work explicitly.
- Use `thread/read` for root eligibility and title, and the existing Turn-scoped `thread/items/list` for persisted progress. Never use the independent server’s `notLoaded` or empty loaded list to end a live CLI Turn.
- Ordinary `PermissionRequest` uses the existing grant/refuse channel. `PermissionRequest` lacks `tool_use_id` in the sample, so retain association with the preceding call and the existing refusal rules. A sent answer does not change lifecycle state until native evidence arrives.
- Synchronous `request_user_input` is waiting and reading-only. Asynchronous questions must retain their separate preview semantics; test them before declaring CLI coverage. Unknown tools/forms remain reading-only or return to the product.
- No first-release recovery of pre-launch active or unread Turns. Reconnect may correct Turns already observed in the current lifetime, with epoch guards; it may not replay history as new activity.

### Context

Propose a mode-specific glossary amendment: Desktop keeps product-owned Project semantics; ordinary CLI uses its native working directory as its declared grouping, with the shared missing-name fallback. Call this a CLI grouping, never an inferred Desktop Project. Use the native Thread title where available and the established permitted fallback where absent; a folder name is not a title.

This deliberately changes the present blanket rule that all Codex Projects are Desktop Projects. The reason is that a standalone CLI can have no Project object (`projectId:null` in the probe). If later admitting a CLI Thread with a real product-owned Project assignment, define precedence explicitly and validate it; do not silently override it with a folder. Migration of Desktop’s private Project reader to public `project/list` is a separate task.

### Read removal and navigation

- Terminal gestures count only for an ended Turn whose root is positively bound to the displayed TUI/TTY. A gesture in another tab, another Thread in the same TUI, or an editor’s different terminal is not read evidence.
- Combine attributable Desktop read evidence and terminal read evidence as peers when both surfaces genuinely display that Thread. Absence from Desktop’s unread set alone cannot retire a CLI row.
- Verify foreground application, screen availability, process identity and binding again at use time. The pseudo-terminal focus probe does not substitute for this native acceptance.
- CLI navigation first attempts the registry’s exact TTY selection where supported. Otherwise report the truthful host-return outcome. Do not claim an exact Thread was opened when only a host was raised; do not automatically start a second CLI or run `codex resume` on the user’s behalf.
- Retain Desktop deep links for Desktop destinations. Change the current exact-navigation requirement for all Codex rows to a per-surface contract, alongside the implementation and tests.

### Presence, setup and quota

Presence is the union of verified Desktop presence and eligible local TUI presence. Observation health remains per surface, so one failing executable or metadata connection cannot erase the other surface’s verified work. Discover the standalone executable explicitly, including the normal `~/.local/bin/codex` installation; a GUI-launched process cannot rely on a login shell’s `PATH`.

Use one Codex settings entry and monitoring intent. Wording must say that the supported Desktop and local CLI modes share the Hook setup. Default-home shared account quota is read once. Do not add Desktop and CLI usage together, or treat an API-key/custom-provider session as proof of a ChatGPT quota window. Native authenticated quota behaviour is not covered by these credential-free probes.

## 6. Implementation sequence and release gates

| Package | Work and relevant files | Gate before proceeding |
| --- | --- | --- |
| 1. Boundary provenance | Listener delivery context; bounded peer/process evidence; current display versus ownership; default-home validation | Existing helper works unchanged; two same-directory TUIs remain distinct; `/new`, resume, late end, PID reuse, unknown mode and custom home fail safely |
| 2. Codex Provider composition | Extract Desktop lifetime/context/read selection; add CLI ownership/presence adapter; preserve one reducer and one metadata connection per admitted home | CLI works without Desktop; Desktop works without CLI; closing/restarting either preserves the other’s rows; same Thread is not duplicated |
| 3. Public CLI lifecycle and requests | Append session/interruption definitions; trust/activation checks; typed interruptions; reuse request and answer adapters | Submit, normal end, interrupt, exit, allow, deny, unanswered request expiry, synchronous question and unknown form; request occurrence/channel races remain covered |
| 4. Context, read and return | CLI grouping policy, conditional TTY read evidence, navigator dispatch and truthful host outcomes | Native Terminal/iTerm2/Ghostty samples; same-host wrong tab; same-TUI Thread switch; lock/unlock; stale process; no row disappears from Desktop unread absence |
| 5. Productisation | Settings/discovery, shared quota, documentation, compatibility and Release measurements | Full unit suite, complete native matrix, no added continuous overlay animation, clean diff and registry consistency |

Mandatory tests should exercise externally meaningful invariants rather than file layout: sequence preservation with provenance capture; sender exit during capture; session metadata never opening Turns; late `SessionEnd` not clearing a replacement binding; no `notLoaded`-driven completion; no wrong-surface retirement; unchanged old Hook trust; one-time answer delivery; a close on one owner not closing another; and no read/navigation based on reused PIDs or creation-only `source` values.

Native gates still outstanding after this planning round:

- Actual Terminal.app, iTerm2, Ghostty and an IDE terminal: focus in/out, switching tabs, keyboard input, window occlusion and screen lock/unlock. Declare exact navigation versus host-only navigation individually.
- Default-home ordinary CLI with normal Hook trust, Desktop absent and present. The isolated tests did not quit or reconfigure the user’s Desktop.
- `/resume`, restored terminals, a Thread moving between CLI and Desktop, CLI process failure, Notchline restart mid-Turn, and reconnect while a request is open.
- In-flight progress freshness, subagents continuing after the parent end, subagent waits, automatic approval review, async questions, permission-form variants and authenticated quota.
- Release cost: measure idle/steady state and Hook bursts separately. Compare against the baseline on the same machine; use cumulative CPU time for bursts. Avoid whole-process-table polling on each refresh, avoid a second identical quota reader, and keep terminal sampling limited to eligible ended rows.

Do not widen the scope or claim cumulative L6 until the corresponding samples pass. A failure in remote-mode attribution does not block shipping the verified ordinary local mode; it keeps remote mode excluded.

## 7. Public interfaces, private dependencies and documents

Public Hooks, CLI help/schema, independent App Server reads and BSD socket/process APIs are the preferred interfaces. **Observed Codex process topology, mode discrimination and TUI focus-reporting behaviour are compatibility dependencies**, even when read using public OS APIs. Register them if production support relies on them, with version drift signals, corruption/absence tests and conservative degradation. Do not conceal them under a claim that the kernel API is public.

This planning change adds no production dependency and does not change the current non-public integration registry. Implementation must update, together:

- `CONTEXT.md`: Codex surfaces, presence, CLI grouping, per-surface navigation and read evidence.
- `docs/product-support.md` and `docs/product-support-zh.md`: modes, cumulative level, request forms and independent capabilities.
- `docs/PRD.md`, `docs/tech-design.md`, `docs/system-architecture.md`: ownership, source authority, lifetime, recovery and performance boundaries.
- `docs/product-connections.md`, `docs/integration-settings-behaviour.md`, `docs/artifacts.md`: discovery, shared installation, three added definitions, trust and any new local artifacts.
- `docs/answer-in-notch.md` and `docs/dual-agent-design.md`: declared request coverage and shared product/account attribution where affected.
- `docs/non-public-codex-integration-features.md`: precise process/focus dependencies and any migration of private cancellation evidence; do not remove Desktop fallback from a CLI-only result.

Rejected first-release alternatives: clone the entire Desktop Provider; identify current mode from `source` alone; treat any Codex process as an interactive client; infer a Turn from persisted history or server `notLoaded`; apply Desktop unread absence to CLI; require users to relaunch under a daemon; use `thread/resume` as an unverified passive subscription; or open another CLI to simulate returning to the current terminal.

## 8. References and verification record

- [Official Hooks](https://learn.chatgpt.com/docs/hooks): event semantics, normal trust review, interruption and decision-output limits.
- [Official App Server](https://learn.chatgpt.com/docs/app-server): version-specific schemas, read-only summary reads, persisted items and transports.
- [Official advanced configuration](https://learn.chatgpt.com/docs/config-file/config-advanced): custom provider configuration used only by the isolated mock service.
- [Earlier shared App Server exploration](../shared-app-server/README.md): the 2026-09-09 record has different versions and scope; current probe results above take precedence for this CLI.
- [Generalisation plan](../../product-generalisation-plan.md): shared evidence, request identity, source ownership and answer outcomes.

The complete `xcodebuild test -only-testing:NotchlineTests` run passed on this unchanged application baseline, using a separate DerivedData directory: **1,003 tests, zero failures and zero skips** (1,006 device executions including parameterised cases). This checks the existing baseline, not the proposed CLI implementation. All 19 local document links resolve, fenced blocks are balanced and `git diff --check` passes.

No application code or user configuration was changed for this plan. Probe processes, synthetic conversations, generated schemas and test scratch output were removed before delivery. Production implementation and native application acceptance remain future work.
