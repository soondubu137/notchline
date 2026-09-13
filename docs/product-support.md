# Product support

[简体中文](product-support-zh.md)

This is the support contract, adopted on 2026-09-12. It replaces the former three-tier definition in the [provider architecture exploration](technical-explorations/multi-product-provider-architecture/tiered-support.md). The glossary owns the terms; this document owns level requirements, request coverage and the current product matrix.

## 1. How levels are assigned

Support has six cumulative levels, L1–L6. A product earns the highest level whose requirements it meets in its **declared execution modes and request forms**. A feature above that level is still listed individually. The level is derived from coverage; it is not a product rank, a runtime status or a promise of every feature Notchline offers.

The earlier definition bundled metadata and navigation into its first tier, then combined wait detection and request reading in its second. That concealed the difference between a row with only a clock and one with useful progress, and between observing a request and being able to read it. The six levels separate those obligations. Read removal, navigation and usage remain independent because none requires an answer channel, and an answer channel supplies none of them.

Every admitted product still needs trustworthy Thread identity and eligibility, a declared presence and observation-health source, a way to inspect/configure the integration (or nothing to configure), and at least a usable host return route. These are admission requirements, not additional support levels. Navigation quality is declared separately. A process starting or exiting is not itself a Turn boundary.

Coverage uses four descriptions: **supported**, **conditional** (name the mode, host, version or gesture), **unsupported**, and **unverified**. Use **not applicable** only when the product has no corresponding concept. Keep runtime failures separate: signed out, an unavailable reading and a disconnected integration do not mean unsupported, and an unsupported quota is never zero.

## 2. The six levels

Each row adds to every preceding row. “Not required” is not a claim that the product lacks those features: independent capabilities and extra request coverage must still be listed.

| Level | Required support | Not required by this level | Additional integration work |
| --- | --- | --- | --- |
| **L1 — Lifecycle monitoring** | Correlated Thread and Turn identities; observed Turn start and end in the declared modes; elapsed time from a known start; concurrent Threads kept separate; duplicate, stale and old-epoch events handled; manual row dismissal | Useful Project names or titles, progress, waits, request reading or answering; any independent capability | Establish positive boundaries and identity across retries, overlap and late events. Silence cannot end a Turn |
| **L2 — Context identification** | L1 plus Project names and Thread titles, their sources and missing-data rules; metadata attached to the right Thread even when it arrives late | Progress, waits, request reading or answering; exact agreement with product-managed names | Resolve metadata and updates without substituting a path for a product-owned Project or another Turn's prompt for a title |
| **L3 — Progress monitoring** | L2 plus updates during a Turn using text the product has already displayed; current-Turn attribution; declared update mechanism and timing | Token-by-token streaming, final answer text, waits, request reading or answering | Obtain and correlate content; handle incremental or event-triggered reads and delayed publication |
| **L4 — Wait detection** | L3 plus opening and resolving each declared approval/input wait; request identity; cancellation, in-product answers and invalidation clear the matching wait | The command, question, options or document being requested; answering | Pair positive wait and resolution evidence. A tool call alone is not evidence that a person is being asked |
| **L5 — Request reading** | L4 plus faithful reading-only presentation of each declared command, question, option set or document; unsupported forms direct the user back to the product | Submitting approval, refusal, choices or free text | Project request schemas once at the boundary; handle multiple questions, concurrent requests and replacement |
| **L6 — Request answering** | L5 plus the explicitly listed answer operations through a live request-bound handle; stale and duplicate answers cannot reach another request; delivery outcome is reported; native evidence alone changes lifecycle state | Every request form, persistent permission rules, starting a Turn, or any independent capability | Own a valid write channel, correlate its lifetime, serialise answers and handle uncertain delivery without blind retries |

The work column describes the usual dependency order, not an estimate of time or difficulty for every product. Public events, cross-source correlation, private formats and write-channel availability determine the actual cost. A product with request answering but no progress remains below L3 and lists that answering as extra coverage; nothing should be implemented solely to inflate a level.

An L1–L3 product cannot report whether an unfinished Turn is waiting. The existing surface continues to use the Running state (`Working...` in user-readable copy); Settings declares that approvals and questions are not detected. This preserves the current presentation, not evidence that the Turn is doing work continuously. Missing wait support must never clear a wait already known from trustworthy evidence.

## 3. Request coverage is mandatory at L4–L6

Approval and input coverage are separate. For each native form, state whether Notchline **detects**, **reads** and **answers** it, and name the available answer operations. A product that has approval requests but no question concept may declare questions not applicable. A product that has questions which Notchline cannot observe must declare them unsupported.

L6 is scoped to the supported forms; it does not mean every request in the product is answerable. Even a supported form is answerable only while its individual connection remains valid. An expired request becomes reading-only. Unknown forms must not acquire an answer button by resemblance to a known form.

| Product and native form | Detection and reading | Answers from the notch |
| --- | --- | --- |
| Codex: ordinary `PermissionRequest` | Approval wait and supplied request fields | Grant or refuse, with optional refusal text, while its hook connection is held |
| Codex: `request_permissions` | Approval wait and supplied request fields | Unsupported: its `PreToolUse` observation holds no answer connection |
| Codex: synchronous `request_user_input` | Input wait; question sets with optional choices | Unsupported: the hook encoding accepts no question answers; answer in Codex |
| Codex: `request_user_input_async` | Question text retained as a preview; **no blocking input wait** is asserted | Unsupported: the Desktop card outlives the hook call and this app has no answer connection to it |
| Claude Code: `PermissionRequest` | Approval wait; supplied tool arguments | Grant or refuse, with optional refusal text |
| Claude Code: `ExitPlanMode` | Plan approval and document | Accept or send back, with text where accepted |
| Claude Code: `AskUserQuestion` | Input wait; question sets and labelled options | Single or multiple selections as requested, free text and supported per-question notes |
| Antigravity (Desktop and CLI): approvals and questions | Unsupported: neither a wait nor its request content is observed. Desktop's own records of a waiting step were not measured | Unsupported |

Persistent permission rules are not offered by Notchline. For request shapes, encoding limits and delivery semantics, [answer-in-notch.md](answer-in-notch.md) remains authoritative. An L6 classification does not widen those operations.

## 4. Independent capabilities

These are separate axes, not L7 and beyond. Record each supported measure or behaviour and its conditions; do not replace this table with a single “full support” label.

| Capability | Coverage to declare | Required boundary |
| --- | --- | --- |
| Read removal | No read evidence; specified terminal gestures; product Thread read records; combinations of those sources | Only retire an ended Turn using evidence attributable to its Thread. Returning to an application is not universally a read. Removing a monitoring row never archives the Thread |
| Navigation | Unavailable; raise host; select the matching terminal window/tab/pane; open the exact Thread | Report the actual outcome. Identity, not a title or window position, determines a specific destination |
| Quota and usage | Remaining quota; window duration; reset time; multiple windows; today's token usage, each separately | Token consumption is not remaining quota. Missing windows, signed-out accounts and failed reads are distinct |
| Final answer | Unavailable; final-answer preview; fuller answer reading | Progress support does not imply final-answer support |
| Subagents | Counts; running activity; waits; effect on parent Thread aggregation, each separately | A count alone does not establish whether work continues after the parent Turn ends |
| Recovery | New live events only; recovery of current active Turns; recovery of unread terminal Turns | A historical event is not a current snapshot. Transport reconnection alone does not recover state |
| Terminal reason | End observed; normal completion, failure and cancellation distinguished where supported | Completed is not a guarantee that the cause is known |

Metadata and progress also retain their detailed declarations even though they contribute to L2/L3: product-owned Project versus working directory; product title versus prompt-derived title; and pushed, polled or event-triggered progress with its refresh limits.

## 5. Current product coverage

This matrix describes the current implementation, not every installed product version. Existing measurements and limits remain in the linked implementation documents. A new version or mode is unverified until its evidence has been checked. In particular, Codex question answers are rejected by the current [answer encoding](../Notchline/Notchline/RequestAnswering.swift); detecting or rendering a question does not establish a write path.

| Feature | Codex Desktop | Claude Code (Desktop and CLI) | Antigravity (Desktop and CLI) |
| --- | --- | --- | --- |
| **Level** | **L6** for ordinary `PermissionRequest`; L4/L5 coverage for synchronous questions and `request_permissions` | **L6**, for the request forms in §3 | **L3**, for observed Turns on both surfaces; mode limits below |
| Turn lifecycle and elapsed time | Supported | Supported | Supported from the first model invocation to `Stop`. Desktop's **Stop execution** emits no `Stop` (measured), so that Turn keeps `Working...` until the conversation's next Turn, Desktop quitting or dismissal; CLI interruption without `Stop` is not independently observed |
| Project name | Desktop's Project assignment, or `Chats`; never inferred from cwd | Working directory name | Desktop: its Project assignment, `Standalone` for none, `Project unavailable` when unreadable; never the folder. CLI: TUI workspace path; current `-p` payloads have no path and display `Untitled folder` |
| Thread title | Desktop name → Thread preview → current prompt → `Untitled` | Transcript title records; `Untitled` when unavailable | User request read from the transcript on both surfaces; prompt-derived, not synchronised with Desktop's generated title |
| Live progress | Pulled content; per-Thread degradation when unavailable | Pushed `MessageDisplay` updates | Transcript read at the next model invocation and at `Stop`; a long tool call can delay the update |
| Approval and input waits | Supported for ordinary approvals, `request_permissions` and synchronous questions; automatic review is filtered | Supported for §3's forms | Neither supported |
| Request reading and answering | Ordinary approvals answerable; `request_permissions` and synchronous questions reading-only; asynchronous questions preview-only | Scoped by §3 | Neither supported |
| Manual row dismissal | Supported, in any Turn state | Supported, in any Turn state | Supported, in any Turn state |
| Read removal | Desktop's per-Thread unread state | Desktop records and qualified foreground evidence; direct-terminal gestures | Desktop: its per-conversation view record, conditional — written when the user leaves the conversation, returns focus to Desktop's window on it, or starts another; a Turn watched to its end records nothing until then. CLI: conditional — type or paste after the Turn ends, with its terminal application in front; merely returning to the tab or moving the pointer does not clear the row |
| Navigation | Exact Thread deep link after target validation | Raise Desktop or terminal host; select a terminal tab/pane where the host supports identity matching | Desktop: raise the application only; its one deep link opens no conversation. CLI: raise the process's host; select a matching terminal tab/pane where supported |
| Remaining quota, window duration and reset time | Supported for the reported primary window | Supported for the reported windows; up to three | All unsupported |
| Multiple quota windows | One reported window in the current presentation | Up to three | Unsupported |
| Today's token usage | Supported | Supported, independently of successful quota reads | Unsupported |
| Final-answer preview | Supported | Not provided, by design | Supported; falls back to the last model text when appropriate |
| Subagents | Counts, activity and approval evidence contribute to parent aggregation | Counts, activity, approval evidence and background-work pause evidence contribute to parent aggregation | Unsupported |
| Cold-start state recovery | Unsupported | Unsupported | Unsupported |
| Terminal reason | No failure reason from hooks; interruption evidence is read separately | Failure reason and interruption evidence where provided | End observed; reliable failure/cancellation classification is unverified, and a Desktop cancellation is not observed at all |

Terminal read removal does not cover the current unsupported `tmux`, `screen`, `ssh` or pipe cases. With no usable read evidence, an ended row stays until the next submission, the Thread going away or manual dismissal. Navigation also depends on host reachability and Automation consent; selecting a supported terminal tab is conditional, not a guarantee for every host. See [tech-design.md](tech-design.md) §§1.5, 14.2 and [ADR 0012](adr/0012-read-state-is-answered-per-product-or-not-at-all.md).

Antigravity's two surfaces are one engine reading one `~/.gemini/config/hooks.json`, so a single registration observes both and Settings has one switch for them. Its live progress is event-updated, not token streaming. The CLI's interruption experiment did not establish whether `Ctrl-C` always emits `Stop`; Desktop's **Stop execution** was measured emitting none, and a missing end is never synthesised from silence, even though Desktop's own summaries record the conversation going idle. The [CLI measurement](technical-explorations/multi-product-provider-architecture/antigravity-cli.md) and the [Desktop measurement](technical-explorations/multi-product-provider-architecture/antigravity-desktop.md) record the modes, delays and conservative exits. These limits are part of its L3 declaration.

## 6. Implementation and verification

The shared entry is now typed `MonitoringEvidence` into `MonitoringRepository`; `HookEvidenceBoundary` interprets native Hooks before submission. `ProductMonitoringRuntime` accepts any `MonitoringLifecycleSource`, with `HookProductProvider` supplying the Hooks composition. [MonitoringEvidenceConformanceTests](../Notchline/NotchlineTests/MonitoringEvidenceConformanceTests.swift) verify lifecycle, progress, wait projection/resolution, subagent isolation and observation-epoch rejection through a source with no Hooks, JSON or socket. This changes no product coverage: concurrent request collections, structured answers, transport-neutral answer handles/results remain separate packages in [the implementation plan](product-generalisation-plan.md).


The levels classify existing capabilities; they do not select reducer behaviour. `AgentMonitoring` supplies observation, `RowContentSource` supplies row content, `AgentHookVocabulary` supplies supported events and request projection, and `AnswerDelivering` supplies an answer path. Read evidence, navigation and usage retain their own contracts. No level field or runtime capability matrix is implemented merely to repeat this document.

The implementation and tests must establish each promised behaviour, not just a level number:

| Coverage | Evidence to keep |
| --- | --- |
| L1 | Start/end correlation, overlapping Threads, duplicate/old events, no historical admission, dismissal and absent timestamps |
| L2 | Native and fallback metadata, absence, delayed arrival, identity and updates |
| L3 | Current-Turn progress, update triggers, no previous-Turn leakage and unavailable content |
| L4 | Each declared wait opening, resolution, cancellation and supersession; no false waits from ordinary tool calls |
| L5 | Native request fields and shape-specific presentation, including multi-question sets and unsupported forms |
| L6 | Native answer encoding, stale/consumed handles, concurrent requests, lost connections and no optimistic lifecycle transition |
| Independent capabilities | Each stated source, mode and negative boundary, including unsupported versus failed quota reads and terminal gesture limits |

The generic [hook conformance fixtures](../Notchline/NotchlineTests/HookProductConformanceTests.swift) exercise lifecycle/context and independent wait/request-reading capabilities. Their synthetic reading-only product has no live progress, so it is not proof of cumulative L5. [AntigravityConformanceTests](../Notchline/NotchlineTests/AntigravityConformanceTests.swift) cover that product's L1–L3 behaviour on both surfaces, its terminal and Desktop read conditions and its surface routing, and [AntigravityDesktopRecordsTests](../Notchline/NotchlineTests/AntigravityDesktopRecordsTests.swift) the Desktop Project and view-record readers; request and answer tests remain in [NotchlineTests.swift](../Notchline/NotchlineTests/NotchlineTests.swift). Runtime measurements are separate evidence, not implied by a unit-test pass.

When coverage changes, update this matrix, the glossary if its definitions change, README, relevant contracts and Settings boundary copy in the same change. Record supported request forms and execution modes explicitly. Check the [non-public integration registry](non-public-codex-integration-features.md) when a source or write path changes. This reclassification adds, modifies, migrates and removes no production non-public integration.


Generalisation package 5 adds explicit no-setup configuration, optional source ownership and deadline composition, and restricted phased supplementary evidence. These are shared implementation capabilities, not a higher native support level. Packages 2–4 (request collections, structured answers and answer channels) remain planned.
