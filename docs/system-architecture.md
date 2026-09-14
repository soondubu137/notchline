# Notchline — current system architecture

| Field | Value |
| --- | --- |
| Nature | The architecture as implemented, not a future plan |
| Baseline | 2026-08-28 |
| Purpose | Summarise, in one macOS top-of-screen surface, the active or unread-terminal Turns of the monitored products' root threads |
| Entry point | `MonitorStore.shared` → one Provider per product from `ProductRegistry.builtIn`: `LiveCodexMonitorService` for Codex, `HookProductProvider` composed for Claude Code and Antigravity (Desktop and CLI, `AntigravitySurfaces.swift`), and `TraeProvider` composing `TraeSource` for Trae local IDE |

This document follows the current Swift implementation, from a product's boundary signals entering the app through row-level status convergence, set filtering, top-level summary and exact navigation. The main chain stays:

```text
boundary signals → one reducer / orchestrator → MonitorSnapshot → MonitorStore → AppKit / SwiftUI
```

"Private read-only" in the diagrams means only that a dependency is on an undocumented Desktop schema; those are confined to boundary adapters, never enter the domain model, and are never written back. Risks are registered in [`non-public-codex-integration-features.md`](non-public-codex-integration-features.md).

## Source composition and setup (2026-09-12)

[Generalisation package 5](product-generalisation-plan.md#8-work-package-5--configuration-and-source-lifecycle-composition) is implemented by `MonitoringSourceComposition.swift` and `SupplementaryMonitoringEvidence.swift`. A product declares `ProductSetup.none`, a managed Hooks description, or Trae’s companion extension setup. No-setup snapshots report `.notRequired`, and Settings offers no configuration action or file link for them.

The runtime discovers optional source ownership and scheduling capabilities from the sources it already composes. An owned instance starts once, contributes its change streams, and stops once per shutdown in reverse order. Scheduled reads run initially, on their own edges or deadlines, with one in flight, 5–60 second failure backoff and no expired deadline loop. Their cached values are consumed by the usual evidence/content contracts. Usage and terminal read-removal deadlines remain part of the same minimum; all deadlines park while observation is stopped. Source edges are counted before notification and buffered so a reading cannot consume a later change silently.

Supplementary sources now return restricted evidence batches instead of receiving the mutable repository. Phases preserve Codex's identity-before-abort order and Claude Code's lifecycle-before-Desktop-answer order. Only the repository applies them, behind its existing exact identity/time guards and an observation-epoch check. Row content receives a read-only `TurnMessageReading` value.

Disconnect and configuration removal cancel source reads, stop owned file watchers, clear the explicit observation epoch and its previews, and park deadlines. A suspended refresh checks its revision before publishing or continuing to another source. Native list/quota readers additionally reject late completions by generation. A transient closed channel gate preserves last-trustworthy Turn state; lack of registration clears it. Passive OS notification subscriptions and buffered forwarders remain for the lifetime of the product object and do no polling while stopped. The detailed ownership and cancellation obligations are in the package 5 handover.

## Structured answers and permitted operations (2026-09-12)

[Generalisation package 3](product-generalisation-plan.md#6-work-package-3--structured-answers-and-permitted-operations) is implemented in `RequestAnswering.swift`, `AgentRequest.swift` and the Hooks boundary. A request carries `AnswerOperations` — what the connection held for it was declared to accept — set by the vocabulary when the connection is taken (`answerOperations(forEvent:toolName:)`), carried on the evidence, filed on the request by the reducer and kept on the ticket in `HookReplyRegistry`. `AgentRequest.canBeAnswered` requires the handle and a form those operations answer; the row draws only the permitted answers; `MonitorStore.send` and `MonitoringRepository.answer(_:on:)` both refuse an answer the connection was not declared for, the latter before composing bytes and without releasing the connection. A question carries `acceptsFreeText`, `acceptsNote` and the product's own `nativeID` beside its options. `AgentQuestionAnswer` is typed — the question as asked, the chosen positions, or the words — and each product's `RequestAnswering` performs the final spelling; the `", "` join is Claude Code's and lives in its encoder. `AnswerProgress` keys drafts by the request stripped of its connection.

One transport defect was found and fixed by the package's tests: a connection held on the listener's queue could be closed by the reconciliation of a drain kicked by the previous event, in the gap before its own evidence was appended. The registry now reconciles only connections whose evidence a drain has applied (`markReduced`), and an observation reset releases the connections of the evidence it drops. No native schema, registration bytes, write contract or product coverage changed.

## Request collections and selection (2026-09-12)

[Generalisation package 2](product-generalisation-plan.md#5-work-package-2--requests-identified-independently-of-slots) replaces the one-slot-per-kind waits with `ProducerWaits` on the Turn's own agent and on each subagent: announced calls, questions and approvals in arrival order, each keyed by the request's identity (`MonitoringEvidence.requestID`, or the call's id). A replacement takes its entry's place; `toolCallClosed` ends the waits about a call; the new `requestResolved` signal ends one request by identity; resolving one never clears another; `MonitoredTurnState.deriveStatus` derives the status from what is left instead of stepping it per event. `requestsAwaitingAnAnswer` orders every live request (own questions, own approvals, running subagents' approvals; answerable first; arrival order; identity) and reaches the UI as `MonitoredSession.requests`, the first being `request`; the projection carries every live request's identity so a second arrival wakes the panel. `MonitorStore.openRequest` pins the request being read while it is still live, `closeARowWhoseRequestHasGone` moves on only when it is gone, and an answer that arrived opens the next answerable request on the same row. An id-less approval pairs with exactly one open call of its tool, or the one with no approval yet, and otherwise with none. The §9 synthetic product fixture (`SyntheticProductConformanceTests`) runs the whole path — typed identities, two simultaneous requests, identical labels, a choices-only question, an asynchronous uncertain channel, deadline-driven progress, no quota, navigation dispatch — through the shared runtime and store with nothing built for it.

## Answer channels and delivery outcomes (2026-09-12)

[Generalisation package 4](product-generalisation-plan.md#7-work-package-4--answer-channels-and-delivery-outcomes) keeps `AnswerDelivering` as the one channel contract and changes what it returns: `AnswerOutcome` — `accepted`, `sent`, `expired(peerGone | timedOut | notHeld)`, `rejected(reason)`, `unsupportedOperation`, `uncertain` — each claiming only what the channel proved. The Hooks channel reports `sent` for a complete write, `expired(.peerGone)` for a write that took nothing because the peer had gone, `uncertain` for one that took part, and `expired(.notHeld)` for a handle it does not hold. `AnswerHandle` carries the minting registry's `issuer` beside its ticket, so a handle from another channel or an earlier one addresses nothing. Each held connection records the product's own answer window; `MonitoringRepository.drainDeliveredEvents` withdraws expired handles on every refresh and `nextAnswerExpiry()` joins both products' refresh deadlines, so the request stays readable and says `Read` at the moment the product moved on. `MonitorStore` spends each handle once, says the outcome's own sentence on the preview line, and ignores a result for a request the row no longer holds. No outcome moves a status and none retries. No native schema, registration bytes, write contract or product coverage changed.

## Standardised evidence boundary (2026-09-12)

Work package 1 of [the generalisation plan](product-generalisation-plan.md) separates observation from Hooks. `MonitoringRepository` is the same single state machine, now taking `MonitoringEvidence` through `submit(_:in:)`. `MonitoringProgress` uses its bounded, non-actor preview path. `MonitoringReductionPolicy` preserves the measured parent/subagent refusal and held-Turn policies without depending on a hook vocabulary. `MonitoredTurnState` and `MonitoringStateSnapshot` are shared domain values; the old `Hook…` names are compatibility aliases, not parallel implementations.

`HookEvidenceBoundary` owns native payload distillation, request projection, installation/trust bookkeeping and `HookReplyRegistry`. Its `MonitoringRepository` extension is the compatibility facade for raw hook callers. The shared repository has no hook paths, decoder, vocabulary or descriptor writes. Boundary observation callbacks cannot mutate Turn state. The request-bound handle still wraps a hook ticket and delivery still returns a boolean: those are explicitly package 4, not a completed transport-neutral answer system.

`ProductMonitoringRuntime` owns the common refresh previously inside `HookProductProvider`. Its `MonitoringLifecycleSource` supplies a repository, channel readiness and disconnect. `HookLifecycleSource` implements it; `HookProductProvider` now composes it and adds Hooks setup/answer methods. A source requiring no setup returns `.open(nil)` and uses the same runtime directly. Package 5 replaces the legacy absent-setup `.active` mapping with `.notRequired` and gives Settings an explicit no-setup case. Codex keeps its App Server orchestrator and uses this same repository through the compatibility facade.

A source captures `observationEpoch` when subscribing and submits both lifecycle and progress with that token. Reset rotates it and atomically clears pending evidence and previews; late callbacks retaining the old token are rejected. This is subscription invalidation, not new upstream producer detection: Codex's PID guard and each product's native identity qualification remain necessary. Append order remains synchronous on the source's serial queue; actor tasks only kick drains. No historical replay or cold-start recovery was added.

[MonitoringEvidenceConformanceTests](../Notchline/NotchlineTests/MonitoringEvidenceConformanceTests.swift) exercise the complete shared runtime without JSON, hook configuration or sockets, including epoch rejection and the existing wait/subagent/held-start rules. Existing Hooks and product suites continue to exercise native translation and write paths. No product level, registration bytes or private native schema changed.

Release measurement (`ENABLE_TESTABILITY=YES`, macOS 26.6.2, arm64): cumulative process CPU from `getrusage`, differenced around submission and drain of 2,000 lifecycle events (1,000 sequential Turns on one Thread), three fresh repositories per path. Typed evidence used **7.48–8.71 ms**; the current Hooks boundary plus the same reducer used **28.35–29.79 ms**, with native fixture JSON encoded before timing. Both reached the final Turn in Completed. This is a burst ingestion measurement of the two new entry paths, **not** a before/after comparison, socket/helper latency, request-body benchmark, UI measurement or steady-state CPU claim. The temporary measurement fixture was removed; the ordered-batch conformance test remains.

## Support classification

[Product support](product-support.md) defines six cumulative levels and independent capabilities. This is a coverage contract, not another state machine: the shared reducer still accepts only actual evidence, the Provider composes supported sources, and a request's live handle decides answerability. No level number drives runtime behaviour or replaces `MonitorSnapshot`. Code, fixtures and documentation name lifecycle, context, progress, wait detection, request reading and request answering separately.

## 1. The implementation at a glance

```mermaid
flowchart LR
    subgraph codexSources ["Codex Desktop and local data sources"]
        desktopHooks["Codex Desktop official Hooks lifecycle"]
        desktopState[(".codex-global-state.json private read-only")]
        codexBinary["codex executable and private Desktop bundle discovery paths"]
        appServerProcess["standalone codex app-server subprocess"]
        desktopProcess["Codex Desktop private bundle ID and current PID"]
        desktopDeepLink["Codex Desktop deep link target"]
    end

    subgraph hookBoundary ["Hook boundary"]
        hookRegistrar["CodexHookRegistrar actor, seven frozen definitions"]
        hooksConfig[("~/.codex/hooks.json")]
        hookHelper["hook.sh: sh plus nc -U, always exit 0"]
        hookSocket(["hook.sock 0600, one payload per connection"])
        hookListener["AgentHookListener serial read queue, stamps arrival"]
        installState[("install.json: only installedAt and lastEventAt")]
        hookRepository["MonitoringRepository actor: typed evidence and Turn reduction"]
        hookEvidenceAdapter["HookEvidenceBoundary: decode, requests, trust and replies"]
    end

    subgraph appServerBoundary ["Public App Server read-only boundary"]
        executableLocator["CodexExecutableLocator"]
        appServerClient["CodexAppServerClient actor"]
        streamPump["AppServerStreamPump: NDJSON framing on a serial queue"]
        streamConsumer["single consumer task, decoding off the actor"]
        requestGuard["pendingRequests timeout and one liveness probe"]
    end

    subgraph desktopAdapters ["Desktop private read-only adapters"]
        projectRepository["CodexDesktopProjectMetadataRepository actor"]
        unreadRepository["CodexDesktopUnreadStateRepository actor"]
        approvalRoutingRepository["CodexDesktopApprovalRoutingRepository actor"]
        directoryWatcher["directory watcher, 50 ms debounce, re-attachable"]
        desktopPidGate["NSRunningApplication PID observation gate"]
    end

    subgraph applicationCore ["Application core"]
        liveService["LiveCodexMonitorService actor: Codex's orchestrator"]
        snapshotParser["CodexSnapshotParser: pure parsing and sorting"]
        unreadGate["TerminalUnreadMembershipGate"]
        serviceState[("in-memory caches and background refresh tasks")]
        monitorSnapshot["MonitorSnapshot: availability, sessions, quota, diagnostic"]
    end

    subgraph presentationState ["Main-thread presentation state"]
        stabilityGate["ConnectionStabilityGate, 3 s disconnect grace"]
        aggregation["MonitorAggregation: top-level status"]
        monitorStore["MonitorStore @MainActor, the only UI state source"]
    end

    subgraph macUi ["macOS presentation and control"]
        panelController["OverlayPanelController: NSPanel geometry and animation"]
        notchView["NotchOverlayView: collapsed and expanded session list"]
        productRoot["ProductRootView: first run"]
        settingsView["AppSettingsView: three-pane settings window"]
        navigator["CodexDesktopNavigator"]
        claudeNavigator["ProcessHostNavigator: raises the host up the process chain"]
    end

    desktopHooks -->|"runs the trusted handler"| hookHelper
    hookHelper -->|"the whole payload, unfiltered"| hookSocket
    hookSocket --> hookListener
    hookListener -->|"bytes in arrival order"| hookEvidenceAdapter
    hookEvidenceAdapter -->|"typed live evidence"| hookRepository
    hookRepository -->|"MonitoringStateSnapshot"| liveService
    hookEvidenceAdapter -->|"persists hook-configuration trust only"| installState

    hookRegistrar -->|"appends seven definitions at the tail, never rewritten"| hooksConfig
    hooksConfig -.->|"official Hooks configuration"| desktopHooks
    hooksConfig -.->|"FSEvents change, recompute registration completeness"| hookRegistrar
    hookRegistrar -->|"overwrites only when bytes differ"| hookHelper

    executableLocator -->|"locates the executable URL"| codexBinary
    executableLocator -->|"injects executableURL"| appServerClient
    codexBinary -->|"executed by Process"| appServerProcess
    appServerClient -->|"launches and manages the subprocess"| appServerProcess
    appServerProcess -->|"stdout byte stream"| streamPump
    streamPump -->|"ordered complete frames, AsyncStream"| streamConsumer
    streamConsumer -->|"decoded envelope"| appServerClient
    appServerClient -->|"stdin JSON-RPC request"| appServerProcess
    requestGuard -->|"guards the request lifecycle"| appServerClient
    appServerClient <-->|"seven read-only methods and their results"| liveService

    desktopState -.->|"Project assignments"| projectRepository
    desktopState -.->|"local unread thread IDs"| unreadRepository
    desktopState -.->|"per-thread approvalsReviewer"| approvalRoutingRepository
    desktopState -.->|"directory atomic-replace events"| directoryWatcher
    directoryWatcher -->|"debounced change signal"| unreadRepository
    projectRepository -->|"Project, Chats or unavailable"| liveService
    unreadRepository -->|"unread set tagged with its authority"| liveService
    approvalRoutingRepository -->|"threads proven to be auto-reviewed"| liveService
    desktopProcess -->|"current PID"| desktopPidGate
    desktopPidGate -->|"binds hook trust to the current process"| liveService
    hookRegistrar <-->|"registration, install, remove"| liveService

    liveService -->|"constructs row state"| snapshotParser
    liveService <-->|"30 s list and 60 s usage refresh while Turns exist (the Claude Code list and quota carry liveness and screen gates too, §2)"| serviceState
    snapshotParser -->|"MonitoredSession candidates"| unreadGate
    unreadGate -->|"active or unread-terminal members"| monitorSnapshot
    liveService -->|"availability, quota, diagnostic"| monitorSnapshot

    monitorSnapshot -->|"candidate publish"| stabilityGate
    monitorSnapshot -->|"aggregates sessions when ready"| aggregation
    stabilityGate -->|"publish or hold for retry"| monitorStore
    aggregation -->|"top-level MonitorStatus"| monitorStore
    hookRepository -.->|"changeEvents: rendered projection changed, row text changed, Codex PreToolUse"| monitorStore
    unreadRepository -.->|"changeEvents"| monitorStore

    monitorStore -->|"Published state"| panelController
    monitorStore -->|"Published state and user intent"| notchView
    monitorStore -->|"onboarding state"| productRoot
    settingsView -->|"install, remove, display"| monitorStore
    monitorStore -->|"click a Codex row"| navigator
    monitorStore -->|"click a Claude Code row"| claudeNavigator
    navigator -->|"pre-flight thread/read"| liveService
    navigator -->|"codex://threads/{threadId}"| desktopDeepLink
    desktopDeepLink -.->|"Launch Services targeted open"| desktopProcess
```

Boundary classification:

| Kind | Capability | Constraint |
| --- | --- | --- |
| Officially public | Hooks lifecycle; the App Server protocol and its **six** public read-only methods (`account/read`, `account/rateLimits/read`, `account/usage/read`, `thread/list`, `thread/loaded/list`, `thread/read` — the last always with `includeTurns: false`); `codex://threads/{threadId}` | Used as the primary integration contract |
| Registered experimental App Server method | `thread/items/list` (scoped to this Turn, descending, `limit: 6`, taking only the newest `agentMessage.text`) — the seventh method the client speaks | Only for the current progress on a Running row; absent from the schema without `--experimental`, so registered as a non-public dependency. `-32601` (method absent, or that thread's `historyMode` is `legacy`) is **recorded per thread**, that row falls back to the prompt preview, and other rows are unaffected |
| Registered non-public dependencies | Desktop Project/unread schema, the executable path inside the Desktop bundle, the Desktop bundle identifier | Read-only or discovery-only; fail closed on failure; keep the non-public feature registry in sync |
| Internal to the app | The hook helper, socket, `install.json`, reducer, caches, snapshot and UI store | `install.json`'s `lastEventAt` answers only "has a hook ever executed successfully" and never proves anything about the current runtime, and its `eventsAwaitingTrust` answers only "which definitions did this app rewrite and not see fire since"; Turn state, thread identity, previews and caches exist **only** in memory — there is no event queue, so there are no events awaiting consumption ([ADR 0015](adr/0015-hook-events-go-straight-into-the-reducer.md)) |

## 2. The core refresh sequence

This sequence is why the main chain needs no UI patch per anomaly: `MonitorStore` accepts only a complete `MonitorSnapshot`, and low-latency events, low-frequency correction, private metadata and recovery policy all converge inside `LiveCodexMonitorService`.

```mermaid
sequenceDiagram
    participant store as MonitorStore
    participant service as LiveCodexMonitorService
    participant hooks as MonitoringRepository
    participant registrar as CodexHookRegistrar
    participant appServer as CodexAppServerClient
    participant project as Project metadata repository
    participant unread as Unread state repository
    participant reducer as Parser and membership gates

    loop Triggered by a watcher edge, a due deadline or the 60 s heartbeat
        store->>service: fetchSnapshot
        service->>hooks: drainDeliveredEvents
        hooks-->>service: post-launch exact Turn evidence
        service->>registrar: registration
        registrar-->>service: configuration trust cached until hooks.json changes
        service->>service: retire held Turns unless the current Desktop PID produced them
        service->>appServer: connect and initialize if needed
        service->>project: snapshot
        project-->>service: exact Project mapping or conservative fallback

        alt Post-launch hook observation exists under the current Desktop PID
            service->>unread: snapshot
            unread-->>service: unread IDs with source authority
            opt reducer thread metadata stale beyond 10 s, or older than the Turn
                service->>appServer: schedule background thread/read includeTurns false
                appServer-->>service: per-thread metadata record
            end
            opt a hook names an unlisted, unrefused thread, or 30 s membership is due
                service->>appServer: schedule background paginated thread/list
                appServer-->>service: membership replacement on full success
            end
            note over service: a Turn with no Thread record draws no row; a remote error records "no such thread"
            service->>reducer: merge hook evidence, fresh App Server data and metadata
            service->>hooks: reconcile exact four-state session status
            reducer-->>service: sorted active or unread-terminal sessions
        else no post-launch hook observation
            service->>appServer: thread/list limit 1
            appServer-->>service: one page, discarded unread
            service->>service: Ready with an empty session set
        end

        service->>service: schedule quota and daily usage refresh after the core snapshot
        service-->>store: MonitorSnapshot
        store->>store: apply disconnect grace, the dismissed-row filter and aggregation
        store-->>store: publish only changed UI fields
    end
```

Both directory watchers can re-attach: a missing or replaced directory is not terminal, `rename`/`delete` triggers a reopen, and the refresh path retries in passing. They have no retry timer of their own, so the cost of "cannot attach" is one failed `open` per refresh rather than a new wake-up source.

Refresh no longer samples on a fixed cadence. Four sources drive it, merged into one `changeEvents` stream or a sleep duration: the store's signal when the rendered projection changes; the directory watchers on `hooks.json` and the Desktop state file, and the file watcher on the rollouts of Codex Turns still going (§9.5 of the technical design — the abort record is the only report a stopped Codex Turn makes, and an append inside a directory fires no directory-level event); **the invalidation signal the service emits when a background read lands**; the next due moment the service reports through `nextRefreshDeadline()` (terminal settling, metadata/membership/quota cache expiry); and a 60-second heartbeat.

The first source has three supplements outside the rendered projection, all existing solely for the row's "current progress" line, whose source is not in the projection:

- **Claude Code**: when a `MessageDisplay` delta folds into the preview store, signal once if the line the row will draw genuinely changed — a Turn change counts, because before this Turn speaks the row draws the prompt. The frequency is capped not by a rule but by the 240-character head: once full, later deltas of the same message return before being stored anywhere. Measured (CLI 2.1.234, 1561 characters / 11 deltas), a long message wakes it twice and a short one once.
- **Antigravity (Desktop and CLI)**: the same fold, fed a whole message per model response rather than deltas. The translator reads the transcript at a later `PreInvocation` and hands over only a step it has not handed over before, so the wake-up frequency is one per model call that said something new.
- **Codex**: `PreToolUse` signals once (`PostToolUse` does not). It changes no field in the projection, but Codex prints commentary before calling a tool, so this is when that sentence changes and when that `thread/items/list` read should be scheduled.

Neither generalises to "redraw when content changes": `MonitorStore.apply` still publishes only when `sessions` genuinely differ, so a wake-up with no change costs one refresh run rather than the 20 ms whole-surface re-evaluation (`AGENTS.md` §7).

The third source is necessary rather than an optimisation: quota, membership and thread metadata are all read in the background, and by the time a result lands the snapshot that started it has long been published. Before polling was removed these results were carried out by the next poll cycle (within a second); afterwards, if they do not signal for themselves, they wait for some unrelated deadline — measured as a blank quota ring for about 10 seconds after launch. So **every background read must end in an invalidation signal**. `isRefreshInFlight` merges them into one refresh rather than creating a second state pipeline.

**`nextRefreshDeadline()` may report only a deadline this refresh can genuinely clear.** The store wakes at that moment and refreshes; if it is still in the past afterwards, the same wake-up fires again immediately — the failure is not "a late wake-up" but a busy loop. So every deadline must mirror its own scheduler's condition: metadata expiry is computed only over **the threads that will actually be re-read** (those the hooks track) rather than the whole `threadRecords` cache — the rest are refreshed by the membership read on 30 seconds, and measuring them with a 10-second metadata window yields a deadline 20 seconds early that no work will ever clear; and a backoff marker is a floor on "no earlier than the next attempt", not an independent reason to wake. Both were once true here.

Terminal rows are the one deliberate exception. Read evidence does not arrive with time but with a file change on a watcher, and by its own documentation a watcher is "a low-latency hint, never a source of truth". Reporting **no deadline at all** looked like the natural conclusion of the same rule, and measured out as betting the product's core interaction on one edge: in a real trace, a terminal row went **a full eight seconds with zero refreshes** between being listed and being read. So such rows report a re-check **measured forward from now** (`terminalUnreadRecheckInterval`, 1 second). Since ADR 0012's rule 3 that second is **also** a genuine sample: it needs the foreground, the display and the lock state to hold simultaneously, and can only be read at the re-check. The terminal half lands on the same second for a harder reason — a controlling terminal's access time is advanced by the kernel and produces no observable event, so there is no edge to wait for at all; it too reads three states together (access time, whether the host application holds the foreground, whether the screen is available) and can only do so at the re-check. It does not turn the re-check into a busy loop: with no row waiting it is never asked, and an answer either removes that row or books the next one. The distinction is not "report or not" but "is what is reported stale" — `terminalObservedAt + settlingInterval` is permanently in the past for an unread row, clamped by the store to a 1-second floor with no refresh able to move it, and *that* is a busy loop wearing a deadline's clothes; a re-check measured forward from `now` is clearable by construction, because the refresh at that moment either hides the row or books the next. Normally the watcher arrives first and this floor never comes due.

**"Can clear it" has to be read together with the branch, not just the row.** The previous paragraph argues that a re-check measured from `now` is clearable by construction — which holds only while **this refresh will actually evaluate this row**, and that failed in five places with identical symptoms: a 1 Hz that is permanently in the future and therefore invisible even to the store's `stuckDeadlines` suppression (which only suppresses *the same expired moment reported repeatedly*, while this one advances on every call).

1. **The gate is pruned only on the live-hook branch** (CR-Fable-001). `shouldDisplay` and `retain` live inside `sessions(from:)`, reached only by the Codex live-hook branch; the no-hook, awaiting-install and every error branch return before it, so entries froze in place, were never hidden, and the re-check was re-reported second after second. To the user: a Turn finishes unread, Codex Desktop quits — nothing on the notch, and the app wakes once a second all day. The fix is not a `reset()` before each `return` but a `defer` plus a "did this refresh evaluate rows" flag: the problem was never those particular branches but the next one nobody remembers to teach.
2. **A re-check samples nothing while there is no screen** (CR-Fable-018). The defence of 1-second sampling above holds, but it was made about "a screen someone might be looking at". Every path that can retire such a row requires the display awake, the session unlocked and on console — Claude Code's `isInFrontOfThem` and the terminal gesture path both rest directly on `systemScreenIsAvailable()`, and the Codex side needs the user to open that thread in Desktop. With all three false the answer is known before any work starts and the sample gathers nothing. So that reading was promoted from "read inside the test" to **read once before booking the deadline**: rows waiting on a *user* stop booking, and hang on `ScreenAvailabilityWatcher`'s edges instead (display wake, unlock, screen saver end, session returning to console, system wake). A locked night goes from one wake-up per second to none, with no change in latency when the user returns — those notifications all arrive before the user can do anything. Rows waiting on *time* (the settling window) and on a *file* (unread state unreadable) are unaffected: the former is advanced by the refresh itself and the latter by another app rewriting a file, neither of which depends on anyone being present.
3. **Having a device is not being able to answer** (CR-Fable-036, `tech-design.md` §1.5.1). A `tmux`/`ssh` session does have a controlling terminal, but its host can never hold the foreground, so the test is permanently false, the row entered the gate, and it booked a full two-product refresh every second. The predicate has to ask what the comment beside it had long said: not "is there a device" but "is there a host that could ever say yes".
4. **A row the user dismissed stayed in the gate** (CR-Fable-003). `MonitorStore.dismiss(_:)` records the row id in `dismissedSessionIDsByAgent` and re-runs the merge, and stops there — **no signal reaches the provider**. Both products' terminal gates therefore went on treating that row as a listed, unread entry, and `nextRefreshDeadline()` went on booking its 1-second re-check: for Claude Code each re-check is a terminal gesture read (`sysctl` + `devname_r` + `stat`, plus up to 16 levels of ancestry) and a three-state `isInFrontOfThem` sample, and for Codex a full snapshot (including a main-thread `NSRunningApplication` LaunchServices round trip). A user right-clicks one terminal row away and leaves that CLI at a prompt, and with nothing on the notch the app keeps running a two-product refresh every second, indefinitely. The fix sends the dismissal to the service that owns it: the record is still held only by the store — only it can distinguish "the user dismissed it" from "the Turn ended", `tech-design.md` §17 — but each `fetchSnapshot(dismissedRowIDs:)` carries that product's share down, so the service does not evaluate the row or build an entry for it, and `retain` drops any entry it already had. **The row is still reported**: not reporting it would tell the store that Turn had ended, which is what let CR-Fable-004's dismissal be forgotten and the row return to the notch on the next hook event.
5. **The membership deadline has nobody to clear it without hook observation** (CR-Fable-023). Once `threadListReadAt` is set, membership expiry unconditionally refills, while **the schedule that re-reads it is written only on the live-hook branch**. After Desktop quits that deadline is reported every 30 seconds, lands in the past, no refresh can move it, and it bottoms out on the store's 1-second floor — an empty-notch 1 Hz again. The same held for a membership request stopped by backoff: a retry marker is contractually reported as a reason to wake, and the no-hook branch never picks that request back up. The deadline is therefore reported only while the hook reducer still holds a Turn (which is also where `threadRecords`'s and `removeThreads(notIn:)`'s only consumers live), and the no-hook branch drops both reads that only the live-hook branch can consume or clear.

All five are one strengthened rule: **a deadline must be clearable not only in principle for that row, but by a refresh that will genuinely happen on this branch, in this machine state.**

**Deadline wake-ups must be refilled at the end of a refresh run, not inside the store's own loop.** Deadlines are *produced* by refreshes: a terminal row begins waiting on the user during the Stop-hook-driven refresh, and books its 1-second re-check at that moment. Yet the overwhelming majority of refreshes are watcher-driven rather than store-initiated. The earlier form was a `while` loop — refresh, compute a deadline, sleep to it — so a deadline booked by a watcher-driven refresh landed after the loop had already gone to sleep, on a sleep computed from a state with no terminal row in it, usually the 60-second heartbeat. The re-check was faithfully reported and faithfully ignored, and the row stayed on screen for up to a minute. The same missing refill also held up re-evaluating the disconnect grace period and retrying the quota read. `scheduleNextWake()` now hangs off the end of `startRefreshRunIfNeeded`'s run, which the watcher, Recheck and heartbeat paths all pass through, so a deadline produced by any refresh is genuinely slept to.

The store does not validate deadlines the service reports, so there is a second backstop: sleep duration has `minimumRefreshInterval` (1 second) as a **floor** and never rounds to 0. That bounds any escaped bad deadline to the 1 Hz that existed before polling was removed, rather than a whole core — the previous version without this floor measured 63% CPU, with the main thread stuck in `NSRunningApplication`'s synchronous LaunchServices round trip. It likewise carries no latency guarantee.

**The heartbeat is only a backstop and carries no latency guarantee.** Its sole reason to exist is two silent-failure classes known in this repository: `DirectoryChangeWatcher` does not re-attach after `open(O_EVTONLY)` fails or the directory is replaced (CR-018), and a deadline wake-up can be lost soundlessly to a cancelled task or a miscomputed deadline. No "updates are too slow" problem may ever be solved by shortening the heartbeat.

**But a wake-up is not itself a reason to re-read (CR-Fable-002).** That heartbeat, plus the Codex account reading due every 30 seconds, means this process wakes every 30–60 seconds regardless and asks **every** service for a snapshot in that pass. So any data source with "re-read once the cache is older than N" behaves, for any N below that interval, as unconditional sampling at that interval — `ClaudeCodeSessionRegistry`'s 30-second freshness did exactly this, launching `claude agents --json` every 30–60 seconds forever on an idle machine with no Claude Code open and the screen locked. Freshness is a ceiling on how stale an answer may get, not a reason to buy a fresh one nobody asked for. The rule is therefore: **with no edge reporting a change and no row on screen depending on it, the cached answer simply counts** — provided that answer was genuinely answered rather than an empty shell left when nobody replied. This is the same rule as the terminal rows' "never ask when no row is waiting", from the other direction: one says do not book a deadline when nobody is waiting, the other says waking is not spending. Costs and measurements in §6, decision in `tech-design.md` §15.1.

**Listed sessions are the other half of that rule (2026-08-26).** The above covers only an answered empty list; with rows in the list, the 30-second freshness still bought `claude agents --json` every 30 seconds, so a machine with Claude Code open sat on that cadence all day. What it actually buys is one thing: a row **might need to come down**, and of the routes to coming down only one reports no edge — a session `SIGKILL`ed, its record left on disk, with `~/.claude/sessions` firing nothing. That route needs a `pid` plus process start-time comparison, which the kernel answers directly: one `sysctl` per listed session, microseconds, no process. So the cadence still decides **when it may be asked** and the kernel decides **whether the answer is worth paying for** — `ClaudeCodeSessionRegistry.everyListedSessionIsStillAlive()`. Start times are anchored in place on every answered read and afterwards compared only against their own earlier readings, so a reused pid also counts as a ghost; a pid that cannot be anchored or read counts as "not still alive" and falls back to the command, which is the behaviour from before the change. A bonus: a ghost is now found at the next refresh rather than at the next freshness boundary — refreshes are hook-driven, so killing a busy session is seen the same second.

**The clock branch also needs a screen (2026-08-26).** A cadence is a guess about how stale an answer is, and with no display that guess is bought for nobody — the notch it would correct is not being drawn. Edges are exempt: an edge is someone reporting that the list is already wrong, which is evidence and must be answered whether or not anyone is watching. The screen waking is itself an edge already merged into `ClaudeCodeMonitorService.stateChangeEvents`, so the read skipped all night is bought the moment the user returns. The quota read (`claude -p "/usage"`) is the same and harder: both its numbers are drawn only in the expanded panel's footer, which the user must hover the notch to see — and since [`quota-footer-v2.md`](quota-footer-v2.md) they are behind a control inside it, so they are a click further away than that. With no screen it is not "probably unwatched" but **unwatchable**.

`claude -p "/usage"`'s cadence also widened from 5 minutes to **30 minutes**. That number is set by cost, not value: measured in Release 2026-08-25, one read is **2.53 s CPU, a 375 MB peak resident, 31.5K page faults and 35.5K context switches**, and it leaves a transcript on disk that nothing cleans. At 5 minutes, twelve hours is 142 launches and about 360 seconds of CPU — more than the app itself spends in the same period. What it buys is a 5-hour and a 7-day window drawn to the percent; the 5-hour one moves about 0.3% a minute at the fastest a person can spend, so half an hour of staleness is a few percentage points on whichever rule is furthest from its reset. The trust ceiling rose from 900 to 3600 seconds with it: it counted from the **last answer**, and the first failed attempt cannot happen until a whole freshness window after one, so 900 against 1800 would blank the quota on the first miss — exactly what the split exists to prevent. **Since 2026-09-09 it counts from the product's own stamp instead** ([ADR 0021](adr/0021-read-the-quota-from-the-record-the-command-leaves.md)): the figures are read from `cachedUsageUtilization` in `~/.claude.json`, which carries the `fetchedAtMs` of the fetch that wrote them, and 3600 is the same hour Claude Code's own reader of that key uses. The number did not move; what it is measured from did, and the new measure is the stricter one — a run that answered out of a cache it had failed to refresh used to reset the clock.

Installation health is the same: registration completeness answers a question that changes only when this app writes `hooks.json`, when the user asks for a Recheck, or when that file changes under us, so it too is not recomputed on a cadence. `CodexHookRegistrar.registration()` caches the last reading, the first two invalidate it directly, and an external edit is recognised at read time by comparing the watcher's `changeCount` — **with no backstop cadence** (`tech-design.md` §7.2). **Polling the configuration cannot answer the dimension that actually breaks anyway** — Codex records trust by hashing definition content, so a scan passing does not mean a hook will run (§8 of the technical design). Current activation is now checked separately through public `hooks/list`, rather than inferred from that scan or delayed until a Turn arrives ([connection checks](product-connections.md)).

Event consumption happens **once per pass**. `drainDeliveredEvents` takes the inbox wholesale and advances Turn state; the take is atomic, so a second read can only appropriate evidence the first should have been told about. It appears only on the snapshot path. `hookSetupStatus` reads only the persisted trust marker, and integration health returns with `MonitorSnapshot.setupStatus` rather than being asked again upstream.

### 2.1 The launch boundary: no cold-start sync

The product capability is strictly "sync the session list from this launch onwards". Everything before launch — running sessions, finished-unread sessions, sessions awaiting approval — is ignored until it produces its next lifecycle event.

**This is now an architectural property rather than a check.** Hook events no longer touch disk ([ADR 0015](adr/0015-hook-events-go-straight-into-the-reducer.md)): a payload comes down a socket into this process from a helper that ran moments ago, so **an arriving event is current by construction**. There is no backlog to classify because nothing is written down — `liveEventCutoff` and backlog classification were deleted with the event queue. The first event received after launch is this run's first event, and that is all.

The only thing left on disk is one `lastEventAt` line in `install.json`, which answers only "have these definitions ever been trusted" and is never restored as current runtime evidence: after a restart `hasObservedEvent` is true while `hasObservedLiveEvent` is false, and not one Turn is restored.

The App Server likewise produces no sessions: it supplies membership and metadata, adding titles and Projects to sessions whose identity live hooks established, and can never create a row on its own.

```mermaid
flowchart LR
    subgraph desktopRuntime ["Codex Desktop runtime"]
        desktop["Codex Desktop"] <--> desktopServer["App Server A\nDesktop's currently loaded threads"]
    end

    subgraph notchRuntime ["Notchline as implemented"]
        notch["LiveCodexMonitorService"] <--> notchServer["App Server B\nstandalone read-only subprocess"]
        helper["hook.sh\nsh + nc -U"] --> socket(["hook.sock 0600"])
        socket --> listener["AgentHookListener\nserial read queue, stamps arrival"]
        listener -.->|"PermissionRequest only:\nthe answer goes back up the same descriptor"| helper
        listener --> liveReducer["MonitoringRepository\nin-process MonitoredTurnState"]
        liveReducer --> notch
    end

    store[("the same persisted thread records")] --> desktopServer
    store --> notchServer
    desktopServer -.->|"measured: no cross-process current-state query\nloaded/list empty, always notLoaded, never inProgress"| notchServer
    notchServer -->|"one page of thread/list confirms the transport only\nalways publishes Ready with an empty set"| notch
```

State is judged in two stages, transport and snapshot: Disconnected only when `initialize` or the connection fails and the App Server does not answer; Connecting while the handshake has begun and the validating `thread/list` has not completed; and a successful `thread/list` confirms the transport and **always** publishes Ready with an empty set. That validation needs one page (`limit: 1`): it asks whether this transport can answer a real read, not which threads exist, and the paginated membership set has no consumer on this branch (CR-Fable-023, §6). `thread/loaded/list` is kept only as a lightweight liveness probe after a transport timeout, decides no business availability, and takes part in no membership set.

The collapsed drawing follows presence: `MonitorStore.presenceMarks` gives one mark per connected product and the UI draws one matrix each, **each running its own product's curve** rather than a shared summary status. With no product connected there is one grey mark naming no product; in that resting state the notched form drops the leading wing entirely, because the cut-out is already a shape on screen and a second, information-free shape beside it is pointless. **What the collapsed surface draws is one list rather than a switch** (`MonitorStore.compactDrawnMarks`, and `drawsCompactMarks` is only "is it empty"): the resting notched case is that list empty, and with `Hide Notchline` on ([`figma-design.md`](figma-design.md) §8.4) it narrows to the products holding a Turn the user has to attend to (`PresenceMark.hasATurnToAttendTo` — Approval needed, Input needed, or a Completed Turn including one buried under a running row). The panel is composed from that same list (`drawnMarkCount`, and `compactSessionColumnCount` counted over it), so the room the window makes and the marks the header puts in it cannot come apart. The notch-less form keeps the mark to hold its menu-bar position — except tucked, where `Hide Notchline` leaves a `4` pt lip with nothing drawn in it until a Turn to attend to brings the pill back (`MonitorStore.tucksCompactPill`, [`compact-view-v2.md`](compact-view-v2.md) §9.1) — and hover there only expands the pill sideways to expose the gear (`expandsToPillOnly`) rather than dropping the panel — there is nothing to put in one.

**The availability produced here is only half the collapsed status.** The other half is **presence**: whether that product is open right now, answered by the `NSRunningApplication` query the same refresh already makes (and on the Claude Code side by the active session list). Both must hold to count as connected and show `Connected`; otherwise `Disconnected`. `Connecting`, `Set up integration`, `Update required` and `Version unsupported` no longer appear collapsed and travel with availability into the expanded panel and Settings. The merge is a pure function in `MonitorAggregation.status`, and presence itself is `AgentSnapshot.presence`, a peer of availability rather than derived from it.

**Two counts hang off the mark, computed in the same merge as the status.** Besides fixing a `MonitorStatus` per connected product, `MonitorAggregation.marks` counts that product's own rows (`PresenceMark.sessionCount`) and its unfinished subagents (`PresenceMark.subagents`). Both look only at that product's own rows — the same filter as the status — so Codex's Turns are never counted into Claude Code's mark.

**The collapsed surface no longer draws any of that per product** ([`compact-view-v2.md`](compact-view-v2.md)). It draws **one aggregate mark** — `MonitorStore.status`, which is the most urgent status any product holds, in `NotchPalette.aggregateInk` rather than in a product's hue — and **two numerals beside it**: `MonitorStore.aggregateSessionCount` (every row on the list) over `MonitorStore.aggregateSubagentCount` (every subagent in flight, summed off `presenceMarks` rather than re-derived). The column is anchored to the mark's own edges, cap-top on its top edge and baseline on its bottom, so it is exactly `statusMatrixSize` tall and draws identically at every menu-bar height; it is billed `PanelMetrics.countsDigitWidth` per drawn digit. **The notched bar hugs it and the pill reserves two digits**, which is the two forms' one difference in composition: the bar is pinned to the cut-out, so a column opening moves the leading edge and the mark rides left with it while the group's far end stands still against the hardware; the pill is centred and fixed at `209`, so its ends are anchored and `PanelMetrics.pillMiddleWidth(trailing:)` — a subtraction, with no constant of its own — is what gives way. The trailing wing carries the reading alone: the badges left with the per-product marks, the reading freezes rather than leaving when the last turn ends (`MonitorStore.compactReadingSpan`'s second stamp, ~~drawn on a filled `ReadingGround`~~ on the same clear ground a running one takes), and a `4` pt dot in the sessions numeral's `#C7C7CC` stands in front of it for **either** finished turn the wing can have — one the mark is not drawing (`MonitorStore.buriesAFinishedTurn`, the *aggregate's* question, which no `PresenceMark` flag can answer) or the frozen reading's own. `CompactTrailingReading.drawsFinishedDot` is that union, read by the width composition and by the view alike, and the panel draws the same mark still in front of a finished row's reading. Both wings are still exactly as wide as what they draw, and the trailing one is still whole points, so the leading edge cannot feel anything the trailing side does.

**The expanded band draws the bar's own leading group and then decomposes it** ([`expanded-header-v2.md`](expanded-header-v2.md)). The mark and the totals stand where the collapsed bar puts them — at `12` and `32.6`, the same size, so expanding *adds* rather than replaces and the figure the eye was on does not move — and `12` after them comes one column per **working** agent (`MonitorStore.expandedAgentColumns`): that agent's session count over its subagent count, in its own lit ink over its own caption ink (`NotchPalette.countsInk(for:)`). Hue says which agent and brightness says which number, which is the one channel a `51.8` pt shoulder can afford. An agent with nothing at all has no column, the columns pack rather than hold a slot apiece, and with one working agent there is nothing to decompose at all — a lone column would repeat the totals digit for digit in a second ink, so the band draws the totals alone in grey. The subagent row is drawn when there are subagents *anywhere* and then every column fills it, with an en dash where an agent has none.

**The band reserves where the bar hugs**, which is the two forms' one difference in composition: the panel is sized from a baseline rather than from its contents, so a column gaining a digit inside it cannot widen anything and the room has to be there already (`PanelMetrics.agentColumnWidth`, two digits whatever is drawn). Its width answers to a **count of working agents** and to nothing that can be said in words — `PanelMetrics.expandedWidth(centerOcclusionWidth:workingAgentCount:)` doubles `expandedLeadingSideWidth` because the panel is centred — and that keeps it at the `520` baseline at every cut-out this product meets through four working agents. V1 was past the baseline at the second product, because a sentence was reserved on the leading side: the same object was two sizes depending on what happened to be open. `expandedNotchClearance` stays as the guard that the band clears the hardware and stops being the rule that decides a width.

**With no surface drawing a mark per product or a word, the V1 machinery for both is gone**: `marksWidth`, `markWidth`, `drawnMarksWidth`, the whole session-dot column and its view, `StatusReadout`, `SearchlightLabel` / `SweepingLabelView`, `expandedStatusReadoutWidth`, `statusLabelWidth` and `compactLeadingWidth`. The sweep itself survives on the session row's own body line (`SessionRowTextView`), which is where a searchlight still means something.

**The merge reads derived status.** `MonitorAggregation.status`, `marks` and `rowOrder` all pass through `effectiveStatus(of:)`, which answers two things: a row whose own Turn is Completed while a subagent it spawned still runs participates in the merge and the sort as Running; and a row one of whose subagents is stopped at an approval dialogue participates as Approval needed, beating the former but not the Turn's own Input needed (`CONTEXT.md`'s "derived status", `PRD.md` §6.2). The second holds whether or not the Turn is terminal. **There is a third thing, and only Claude Code can answer it**: when a row's own Turn is Completed, its subagents have wrapped up, and that Turn's `Stop` said "paused, waiting for background work to wake me" (a non-empty `background_tasks`), that row also participates as Running until the Thread's next terminal state says nothing is in flight — the 50–130 ms in between being exactly how long Claude Code takes to wake the parent Turn (measured 2026-08-23, CLI `2.1.241`), during which a count-only reading would flash `Completed`. **Both products produce such rows**: Codex through `spawn_agent`, and Claude Code's `Agent` call returning the instant the subagent starts. Otherwise it is the identity transform — a row with `runningSubagentCount` of zero is unchanged, whichever product produced it. **This derived answer never enters a row's rendering**: what a row draws still comes only from `MonitoredSession.status`, its own Turn's status. The **ground** of the row-end badge is the one exception, and a ground does not change what the row draws. So the collapsed state can read `Running` with no timer in the trailing wing, and that is correct: `longestRunningSessionStart` filters on `keepsTiming`, no Turn is timing at that moment, and that cell instead writes each product's subagent total.

**Launch does no cold-start sync.** Sessions can be created only by hooks received after this launch; sessions running, finished-unread or awaiting approval before it are ignored until their next lifecycle event. This is a capability boundary rather than a trade-off: measured (CLI `0.148.0-alpha.9`, on a genuinely in-flight Turn), a standalone App Server's `thread/loaded/list` is empty, threads are permanently `notLoaded`, `thread/list` contractually returns no `turns`, and `thread/read` never shows `inProgress` — so no supported read can answer **what state** Desktop is in right now.

**That sentence is about state, not content — a boundary measured 2026-08-25.** On the same standalone App Server, `thread/items/list` **can read items already produced by a Turn another process is running**, including an unfinished one: measured on CLI `0.149.0-alpha.4.3`, polling a Turn driven by a standalone `codex exec` every 1.5 seconds, commentary `agentMessage`s appeared in the first poll after they were printed and kept up thereafter. This does not contradict the paragraph above — it answers what this Turn has said, not whether this Turn is still running; in the same read the Turn's `status` is still `interrupted`, and `thread/turns/list`'s summary holds only a `userMessage` until the Turn ends. So it is used only to fill the row's body line, while membership and status still come only from hooks (`tech-design.md` §11).

**The Claude Code side follows the same rule for a different reason.** There it can be read: `claude agents --json` gives which sessions exist and a transcript's tail gives which are mid-Turn, and the product did rebuild pre-launch rows from that (`ClaudeCodeTranscriptReader.currentTurn`, removed 2026-08-19). It was removed not for cost but because that answer is wrong exactly where it matters: **while waiting on a user a transcript writes nothing**, so a rebuilt Turn can only be *Running*, and a session parked on a permission request at launch is drawn as working. Files cannot separate waiting from working, and guessing either way fabricates state (§7 rules 5 and 6), so there is no narrower version to keep. The cost is that those sessions wait for their next lifecycle event, as on the Codex side; what it buys is one launch-boundary sentence for both products rather than an exception on one side.

**Hooks are the only source of sessions, but not the whole condition for a row.** A hook answers whether there is a Turn and what state it is in; only the product can answer whether the Thread is a navigable root thread, and that test fails closed — no Thread means no row, the same as being handed one and judging it a subagent. The distinction was forced by Codex side chats: an ephemeral thread with its own thread id, firing Turn hooks as usual, yet never persisted, absent from `thread/list`, answered `-32600 "thread not loaded"` by `thread/read`, and openable by no deep link. The test could previously reject only a Thread it had **received**, so a side chat drew a *Project unavailable* row, was retired 10 seconds later by membership reconciliation, returned once at its end, and reported "archived, deleted, or no longer available" on click. Such refusals are now recorded: no row, not re-asked, and no longer paginating an entire history for a thread the product itself says does not exist. The cost is one local `thread/read` per row — measured, the thread is already persisted and readable when the first hook fires (2026-08-25, CLI `0.149.0-alpha.4.3`), so the normal path is one local round trip and does not wait for the full list ([ADR 0017](adr/0017-a-row-requires-a-thread-the-app-server-vouches-for.md)).

**And on the threads that rule exists to stop, the product says so itself before the App Server is asked (2026-09-09).** Every Codex hook event carries `transcript_path`, required and nullable (CLI `0.153.4`'s embedded JSON schemas, all twelve `*.command.input` titles), and a thread Codex will not materialise carries it as `null` on every one of them — `Thread.ephemeral` is documented "should not be materialized on disk". So an unwritten thread is now recognised on its **first** event: no `thread/read` for it, no `thread/items/list` behind the row it does not draw, and no membership sweep requested to look for it. That is what the refusal record used to buy a round trip later and re-buy once per metadata interval for as long as the side chat ran. It changes what is *asked* and not what is *drawn*: the row still requires a Thread the App Server hands over, and a thread nobody asked about has none. A build that stops sending the key, or sends it on fewer events, falls back to exactly the behaviour above — the discriminator simply stops firing.

**The click asks the same question (2026-08-26).** The re-confirmation before opening a row is also a `thread/read` for **that** Thread rather than a forced full pagination of every unarchived Thread. It was the latter, putting the user's entire Codex history on a click's critical path: the App Server answers `thread/list` by scanning and parsing the rollout files under `~/.codex/sessions` (replace `state_5.sqlite` with an empty database, leave only the sessions directory, and it still lists them all), so the cost grows with history and is paginated — measured on an isolated `CODEX_HOME` with CLI `0.149.0-alpha.4.3`, one full pagination is 51 ms at 50 threads, 335 ms at 199, 754 ms at 400 and **2215 ms at 799**, while one `thread/read` is a median of 1.4 ms. Everything else on the click path is negligible (`NSWorkspace.open`'s callback 94 ms, connecting a no-op). End-to-end A/B on an idle machine, same thread, same fixture (a real row staged over the hook socket, a real `CGEvent` click, timed to `didActivateApplicationNotification`), swapping only the app binary: a median of **220 ms** before (208–317) and **62 ms** after (56–69), the difference of the same order as this machine's full pagination — and this machine has only 47 unarchived threads. **Archiving is not in this gate**: it ends the row's monitoring lifecycle rather than the thread's reachability, and that lifecycle is already owned by the 30-second membership reconciliation, so a row the user can still see is one the last reconciliation still listed ([ADR 0018](adr/0018-the-click-asks-about-one-thread.md)).

A standalone App Server shares no in-process event stream with Desktop, and no supported read observes Desktop's current runtime, so launch produces no sessions and post-launch hooks are their only source. A fully shared runtime remains future exploration in [`technical-explorations/shared-app-server/README.md`](technical-explorations/shared-app-server/README.md) — only once such a topology holds is launch sync worth revisiting, and it must not be built on `status` or `inProgress`. Under no topology may events from before the launch cutoff be used to fill in current state.

## 3. Single-session status convergence

```mermaid
flowchart LR
    subgraph evidence ["Exact post-launch evidence"]
        userPrompt["UserPromptSubmit or a fresh active Turn"]
        inputOpen["request_user_input opens"]
        inputClose["PostToolUse with the same tool_use_id"]
        continuation["a resumed live hook carrying a new turnID"]
        approvalOpen["a fresh waitingOnApproval active flag"]
        activeAgain["a fresh active flag with no wait"]
        completedSignal["a live Stop, or terminal completed/failed/interrupted"]
    end

    subgraph gates ["Shared admission gates"]
        liveCutoff["received_at not earlier than the launch cutoff"]
        exactIdentity["exact threadID plus turnID match"]
        freshness["snapshot start not earlier than lastEventAt"]
        generation["retiredTurnIDs cannot be revived"]
    end

    subgraph reducer ["MonitoredTurnState, one reducer"]
        sessionStatus["SessionStatus, four values"]
        pendingInput["pendingInput"]
        pendingApproval["isApprovalPending"]
        completedSticky["Completed is a sticky terminal state"]
    end

    subgraph membership ["Membership and presentation"]
        memberGate["active always shown; Completed only while unread"]
        aggregate["Approval > Input > Running > Completed"]
        systemStatus["a non-ready system availability clears sessions"]
    end

    userPrompt --> liveCutoff
    inputOpen --> liveCutoff
    inputClose --> liveCutoff
    continuation --> liveCutoff
    completedSignal --> liveCutoff
    approvalOpen --> freshness
    activeAgain --> freshness
    liveCutoff --> exactIdentity
    freshness --> exactIdentity
    exactIdentity --> generation
    generation --> sessionStatus
    sessionStatus --> pendingInput
    sessionStatus --> pendingApproval
    sessionStatus --> completedSticky
    completedSticky --> memberGate
    pendingInput --> memberGate
    pendingApproval --> memberGate
    memberGate --> aggregate
    systemStatus -->|"outranks session-level status"| aggregate
```

```mermaid
stateDiagram-v2
    [*] --> Running: running signal
    Running --> InputNeeded: input needed signal
    InputNeeded --> Running: running signal
    Running --> ApprovalNeeded: approval needed signal
    ApprovalNeeded --> Running: running signal
    Running --> Completed: completed signal
    InputNeeded --> Completed: completed signal
    ApprovalNeeded --> Completed: completed signal
    Completed --> Completed: ignore later active or waiting signals
```

Key rules:

- Every hook type from before the launch cutoff has its business semantics discarded; there is no "a historical `Stop` may restore a terminal boundary" exception.
- Continuing after an interrupt in Desktop may create a new Turn without another `UserPromptSubmit`. A later live hook on the same Thread carrying an unretired new `turn_id` atomically replaces the current Turn and retires the old id immediately, so the resumed final `Stop` hits the new current Turn while late old events still cannot revive it.
- `Approval needed` is always established by a tool call's open/close interval, but Codex has **two** approval shapes, both closed in pairs by `tool_use_id`:
  - **A dedicated approval tool** (measured 2026-08-15, a network access approval): `PreToolUse(request_permissions)` opens a call spanning the entire human wait, closed by `PostToolUse` with the same `tool_use_id`; in this shape Codex sends **no** `PermissionRequest`, making it structurally identical to `request_user_input`.
  - **An ordinary tool approval** (measured 2026-08-15, a Bash command): Codex first announces the call with `PreToolUse` (`tool_name: "Bash"`, `tool_use_id: "exec-…"`), sends `PermissionRequest` about 30 ms later **carrying `tool_name` with a null `tool_use_id`**, and then waits on a person; after approval the `PostToolUse` with that `tool_use_id` arrives. So `PermissionRequest` borrows that tool's still-open call id as the wait's identity, closing still goes through the existing pairing, and no timing or timeout guess is introduced.
- `PermissionRequest` is still not evidence of a wait by itself: with no open call to pair with (or when the tool it names does not match the open call) the status is unchanged, and no wait that cannot be closed is created.
- **This section used to say "an automatically approved request receives its paired `PostToolUse` immediately, opening and closing within one batch, so it cannot linger as a false wait" — that was wrong**, and disproving it is what prompted the change. Measured 2026-08-22 (CLI `0.149.0-alpha.4.1`, `codex exec --approve-for-me`, non-interactive with nobody present to ask): `PreToolUse(Bash, exec-…)`, then `PermissionRequest(Bash, tool_use_id: null)` 10 ms later, and the paired `PostToolUse` **2.5 seconds afterwards** — automatic review is a model round trip plus the command's own execution. The borrowed-id wait spans that whole stretch, so the row reported Approval needed and reverted to Running on every reviewed call. Desktop-side automatic review is longer: `item/autoApprovalReview/started` to `completed` measured 2.1–5.9 s in the same day's Desktop log.
- **So a thread-level gate sits ahead of the approval interval: do this thread's approvals actually reach a person?** Codex Desktop's "Approval for me" (`guardian-approvals` agent mode) hands approvals to an automatic reviewer with only allow and deny and no exit back to a person (measured: its guardian prompt's Outcome Policy defines only those two values). The official `permission-request.command.input` schema has no field separating the two cases — `permission_mode` is `default` in both — so the evidence can only come from the thread: `CodexDesktopApprovalRoutingRepository` reads `.codex-global-state.json`'s `heartbeat-thread-permissions-by-id.<threadId>.approvalsReviewer`, and where the value is `auto_review`, `LiveCodexMonitorService` reduces that row's `approvalNeeded` to `running` when composing it. **Only a thread proven auto-reviewed is reduced**: an absent entry, an unrecognised value or an unreadable file all revert to prior behaviour, because the claim is "nobody will be asked", and absent evidence is not that claim being made. The reducer is untouched — what it proves is still "the permission pipeline opened on a still-open call", true under both settings; reading the setting into the reducer would make it know both events and a Desktop file, violating cross-source decision ownership. `request_user_input` is outside the gate: an automatic reviewer decides approvals only.
- **The gate asks about *this Turn*, not "this thread now".** It previously consulted the map while composing the row, while Desktop rewrites `heartbeat-thread-permissions-by-id` the instant the reviewer changes — yet the running Turn keeps the reviewer it started under and goes on asking a person one call at a time. Measured 2026-08-24: thread `01a03241` opened as `user` (22:32:13), was switched to `auto_review` at 22:37:35, and the five approval dialogues at 22:40:07, 22:40:28, 22:41:10, 22:42:10 and 22:42:28 were all answered by hand (including the `rm -rf` the user reported) while that Turn's rollout `turn_context.approvals_reviewer` — the real authority — stayed `user` throughout; `01a03130` had the same shape five hours earlier. So the answer is taken once and pinned by `TurnApprovalRoutingPin` **the first time that Turn is seen**, until that Turn leaves the reducer, with the next Turn asking again. **It is symmetric in both directions**: a thread switched to `user` mid-Turn also stays auto-reviewed for that Turn. The real authority is now read directly — `CodexRolloutTurnReviewerReader` reads that Turn's own `turn_context.approvals_reviewer`, with the map demoted to the fallback when it cannot answer.

- **A thread's rollout is not a fixed file, and the reading has to follow it (2026-08-31).** Codex writes a Turn resumed after an interrupt into a new rollout for the same thread — measured on thread `01a058c7` (CLI `0.151.0-alpha.7.2`): interrupted at `17:08:38.039`, new rollout at `…44.592`, its `turn_context` at `…46.229` and the resumed Turn's own hook 34 ms later. The path this app holds comes from `thread/read` and is cached for `threadMetadataRefreshInterval`, so the reviewer reading — made once per Turn — went to the file the *interrupted* Turn was written to, found that Turn's record, and gave no answer; recorded as final, the row spent the resumed Turn announcing *Approval needed* for every call Codex's own guardian decided. So an empty reading now carries the instant the App Server reported the path it looked in, and closes the question only when that instant is at or after the Turn's start; and a Turn new to a thread whose record predates it asks for the path again at once rather than waiting out the interval, one read per Turn. The record's own `turn_id` decides whether it is this Turn's, with the 2-second window kept for a build that stops writing one.
- **The fallback also has to ask when the map was written.** The map and the unread set live in the same `.codex-global-state.json`, a projection of Desktop's in-memory state persisted through a 500 ms trailing debounce shared by every persisted atom with no max-wait, which typing can starve indefinitely (measured 2026-08-26: 165 characters over 45.4 seconds produced one write). So **only a map written inside a short window at that Turn's start may count** (`DesktopApprovalRoutingSnapshot.currentAsOf` against `startedAt`, a 2-second window, `TurnApprovalRoutingPin`): one earlier may still name the reviewer the user just switched away from — in "switch the reviewer to yourself → type → send", the switch reaches memory, typing pins it there, and the map still says `auto_review`, so pinning it silences every dialogue that Turn genuinely raises — while one later describes "this thread now", the very thing the previous rule guards against. Neither end pins anything, so the next credible reading answers as usual; and Desktop writes this file at the start of every Turn (sending clears the composer, and the draft is a persisted atom), so normally that reading arrives about half a second after the Turn opens **and repairs the starved old value in passing**. With none arriving inside the window, the row shows approvals as reaching a person until the rollout authority overrides it — this adapter's consistent failure direction.
- **Approval and refusal close differently** (measured 2026-08-15, the same Bash approval approved and then refused): approval brings the paired `PostToolUse`, whereas **after a refusal that call never produces another event** — 67 seconds of silence and then the Turn's `Stop`. So a borrowed-id wait must also be closable by "activity on another call": Codex sends nothing while genuinely blocked on an approval dialogue, so a `PreToolUse`/`PostToolUse` for any **other** `tool_use_id` is evidence that a person has already answered. Only borrowed-id waits use that rule; `request_permissions` carries its own id and is guaranteed a closing event.
- **Codex asks a person in two shapes, and ~~only one of them is a wait~~ only one of them stops the Turn** (measured 2026-09-07, CLI `0.153.4`; the headline corrected 2026-09-08, when the other shape turned out to keep a person waiting without stopping anything). It ships two question handlers, and **the model decides which a Turn gets** — not a setting a user could be asked about. On an isolated `CODEX_HOME` with the hooks trusted by their own `currentHash`, `gpt-6-astra` (this machine's default) registered only `request_user_input_async` in Default mode, while `gpt-5.6-sol` registered the blocking `request_user_input`; and Plan mode gave the blocking one on `gpt-6-astra` too. So both reach the same user on the same day, by route rather than by configuration.
  - **`request_user_input` blocks.** `PreToolUse` carries its own `call_…` id and `{"questions":[{"header","id","question","options":[{"label","description"}]}]}`; the paired `PostToolUse` lands when the person answers, carrying `{"answers":{…}}`. This is the Input needed interval, and it is real.
  - **`request_user_input_async` does not stop the *model*, and 2026-09-08 established that this is not the same thing as nobody waiting.** The timing stands: its `PostToolUse` arrives **51 ms** after the open carrying `{"accepted":true}` whatever the person does, the Turn runs another tool and reaches its own `Stop`, and any answer arrives later as a **new user message**, which is a new Turn. Two conclusions drawn from that timing were wrong, and they are struck rather than deleted, because the measurement under them is sound and only the inference was not.
    - ~~Its arguments are `{"questions":[{"title": …}]}` — a different shape from the blocking tool's, with no field an answer could be written into.~~ **The title-only sample was a free-text question, not the shape.** The tool's own schema, read out of the bundled CLI `0.153.4` binary, documents `options` beside `title` — *"Suggested answers, in display order. Put the recommended answer first; the first option is preselected by default… Omit options for a free-text-only question"* — and the system prompt in the same binary tells the model to **prefer** multiple choice. So an async question carries the same labelled options the blocking one does whenever the model attaches them, and the one local sample that carried none (2026-09-06, `options: null` in both the rollout and Desktop's `thread_history_1.sqlite` projection) was the model choosing free text.
    - ~~What the person is owed is already delivered: Codex emits the question as its own assistant message, and it reaches the row inside the Turn's `Stop` as `last_assistant_message`.~~ **Only when the model happens to stop on the question.** The same system prompt tells it to "continue useful work that does not depend on the answer while waiting", and it does. In the Desktop Turn a user reported on 2026-09-08 the model asked its question, then went on to describe a SQL rewrite, so that Turn's last word — and therefore the Completed row's preview — is the rewrite, and the question is nowhere on the notch.
  - **The person's wait is real, has a clock, and can end without anybody answering** (read 2026-09-08 out of `ChatGPT.app` 26.901.51231's `app.asar`; not yet watched running, so it is a reading of shipped code rather than an observation of one). Both question tools reach the client as **one** App Server request, `item/tool/requestUserInput` (`{threadId, questions[{id, header, question, options[{label, description}], isOther, isSecret}], isBlocking}`), and Desktop branches on `isBlocking`: `true` waits for the person with no timer; `false` is handed to `requestUserInputAutoResolution`, which eventually answers **`{answers:{}}` on the person's behalf** — 60 s of foreground inactivity and then a 90 s countdown while that conversation is focused, or the 90 s countdown **immediately** when it is not. Snooze cancels it. Desktop derives thread status `waiting` from any outstanding request of that method, blocking or not. So the state this app draws as `Working…` is one Codex itself calls waiting, and a person who is looking anywhere else has about ninety seconds before the question dismisses itself.
  - **The card arrives by rollout, not by version.** It is gated on remote feature id `580984490` (`requestUserInputAsyncUiEnabled`) and built from `item/started` where `item.type === "agentMessage" && item.delivery === "async"`, so two users on the same Desktop build need not see the same thing: without the gate the question is only another assistant message, and with it there is a card carrying the options, a free-text field, Skip and Send.
  - **So the signal is neither of the two obvious ones.** `CodexHookVocabulary.signal` maps the async tool to `HookSignal.questionAskedWithoutWaiting`, which is a tool call that also asked a person something: it opens no wait and changes no status, and it keeps the question's own words on the turn (`MonitoredTurnState.questionAskedWithoutWaiting`), which `carriesRequest` now admits the body for. The row draws them — §7 of [`PRD.md`](PRD.md) — so the question stops being lost under the sentence the turn says next.
  - **What is still not claimed is a wait, and the reason is the closing edge.** `.inputWaitOpened` would put `Input needed` on the row, and **nothing on this channel could retire it**: `PostToolUse` closes the tool rather than the question, an answer arrives as the next `UserPromptSubmit`, and a Skip, a snooze and Desktop's auto-resolution are silent. A status this app cannot retire is worse than one it never showed, so the words are kept and the status is left alone. What could close it is open research, in [`technical-explorations/answering-codex`](technical-explorations/answering-codex/README.md) §3.6.1 and [`shared-app-server`](technical-explorations/shared-app-server/README.md) §7 Phase 2.
  - **The vocabulary matched the blocking name exactly, so the async one fell to the catch-all** — right by accident, and silently so. It is now an explicit case, and the default's direction is the safe one: a third variant lands on "ordinary tool call", which can under-report a wait but can never invent one. This is the concrete instance of the hazard [`tech-design.md`](tech-design.md) §7.1's matcher discussion names — a naming detail deciding whether a wait is observed, with a miss that says nothing.
- If a Turn calls no further tool after a refusal, the wait is closed by `Stop` and goes to Completed. The moment of refusal produces no observable event, so Approval needed still shows briefly between the user clicking deny and the next event; that is the boundary of observable evidence and is not papered over with a timer.
- The product cares only whether a Turn is still in progress: a live `Stop` and the App Server's `completed`, `failed` and `interrupted` all become Completed directly, with no `thread/read` to distinguish why it ended.
- The App Server takes no part in deriving status. A Thread payload contributes only the root-thread test, the title and the preview; measurement shows no field of it can express Turn-level runtime truth, so the former `activeFlags` correction mechanism was deleted outright rather than kept as dead code.
- A missing, timed-out or unknown-enum signal, or one failing the identity gates, triggers no state change; the current four-state value stands.
- **Read evidence is dated against the Turn's own terminal (`MonitoredTurnState.turnEndedAt`), never against `terminalBoundaryAt`.** The two stamps answer different questions and were one argument until 2026-08-29: the first is when the answer landed and so when it was there to be read; the second is when the *thread* stopped working, subagents included, and it exists only so a row is not snatched away in the instant its badge clears. A subagent's `SubagentStop` was measured 91 seconds past its parent's `Stop` (2026-08-22), and dating the reading against that discarded the user's actual read — Codex demanded an unread file written after an instant Desktop has no reason to write after, and Claude Code demanded a focus stamp, a return to the foreground or a terminal gesture later than a moment nobody was going to act at. A row the user had read then stayed on the notch until that product happened to display the session a second time. Both products, one cause ([ADR 0002](adr/0002-use-desktop-unread-state-for-monitor-membership.md)'s second addendum).
- Whether a terminal Turn stays listed is decided by `TerminalUnreadMembershipGate`. Only an authoritative unread snapshot from the current main file may add a hiding decision; a backup, last-known-good, or a parse failure may only conservatively keep. **And that snapshot must also be written after that Turn's end**: every unread snapshot carries the moment it is complete as of (`DesktopUnreadStateSnapshot.currentAsOf`, the main file's `modificationDate` on the Codex side), and one stopping before that Turn describes a moment when the Turn had not finished, so its silence is no evidence at all (measured 2026-08-26, see [ADR 0002](adr/0002-use-desktop-unread-state-for-monitor-membership.md)'s addendum). Such a row stays and waits for the next write on the 1-second re-check — waiting on a file rather than a user, so it keeps waiting through a locked screen.
- **Which rows the gate is asked about is one rule for every product, not one per Provider.** `TerminalUnreadRowFilter` walks a refresh's rows for all three: a row the user removed is still reported and judged by nobody (CR-Fable-003, CR-Fable-004); nothing is judged, and the gate is emptied, unless a finished row the user has not removed is listed (CR-Fable-041); a row nothing can speak for (`ReadGateVerdict.cannotBeAsked`) is shown and never enters the gate (CR-Fable-036); the gate is given the thread's status rather than the row's; and it is retained to exactly the rows judged. What a product supplies is only the verdict — Desktop's unread set for Codex, the five routes for Claude Code, the terminal's verdict for a CLI product. Until 2026-09-12 each of the three Providers carried its own copy of this loop.

## 4. App Server transport and recovery boundary

```mermaid
flowchart LR
    locate["CodexExecutableLocator"] --> launch["Process app-server --listen stdio://"]
    launch --> handshake["initialize → initialized"]
    handshake --> connected["connected generation"]
    connected --> request["JSON-RPC request ID"]
    request --> pending["pendingRequests continuation"]
    pending --> readQueue["serial readability queue"]
    readQueue --> buffer["AppServerStreamPump\nNewlineDelimitedMessageBuffer"]
    buffer --> stream["AsyncStream of ordered complete frames"]
    stream --> consumer["single consumer task\nJSON decoding off the actor"]
    consumer --> response["matched response"]
    response --> caller["LiveCodexMonitorService"]
    buffer -->|"one frame past the ceiling"| overflow["fail closed, rebuild the transport"]
    consumer -->|"decode failure"| diagnose["bounded diagnostic, no body recorded\nconnection kept"]

    pending -->|"business request timeout"| grace["3 s responseSequence grace"]
    grace -->|"any response meanwhile"| connected
    grace -->|"still nothing"| probe["one thread/loaded/list probe, 5 s"]
    probe -->|"succeeds"| connected
    probe -->|"also times out"| reset["rebuild the transport, hook reducer untouched"]
    reset --> launch
    overflow --> launch
```

Framing is the only link in this chain that depends on byte order, so it happens synchronously inside the readability queue `FileHandle` has already serialised, and never crosses an actor hop: independent tasks have no guaranteed order entering an actor, and one misordered chunk breaks every frame boundary after it while the leftover fragment keeps swallowing the next response. Past framing, every frame is self-contained and addressed by `id` so order stops mattering, which is why the most expensive step, JSON decoding, happens in a single consumer task off the actor, where it cannot block timeout handling, connection management or other responses. That consumer also guarantees stream end is ordered after every frame before it.

Recovery logic handles only "can this connection still work" and takes no part in deriving session status. An ordinary RPC timeout, a remote method error or a protocol error does not immediately turn current sessions to Disconnected; with a trustworthy snapshot in hand, `lastTrustedSnapshot` and the main thread's 3-second `ConnectionStabilityGate` together avoid a momentary flicker. While still Connecting at launch with initialisation confirmed unanswered there is no trustworthy snapshot to keep, so Disconnected is published directly without waiting out that gate.

## 5. Component responsibilities and code locations

First-run pages share one `Window` scene and a fixed `580 × 840` pt content area (`OnboardingLayout`). `OnboardingView` swaps only the current page inside a vertical scroll view; the shared navigation row stays outside it at the bottom right. Specimen stores are still created only when their page is first visited. Completing onboarding opens the `Settings` scene's window and closes this one (`ProductRootView`), because the three-pane Settings is drawn only in that scene. Page two places Recent below the expanded-panel tutorial, with a separately constructed non-watching queue store. Page three uses native segmented pickers for permission/question lessons and question examples; it contains no Recent topic. Its single-choice, multiple-choice and typed-answer examples reuse `OpenRow` over non-watching stores; `stageSpecimenAnswer` sets only in-memory draft state and refuses stores with services. The drawings remain non-interactive, and no answer is dispatched to a provider. Changing the question example replaces its view identity so the native text field cannot retain the previous example’s draft.

| Layer | Component | Single responsibility | Code |
| --- | --- | --- | --- |
| UI state | `MonitorStore` | Pull complete snapshots, merge refresh triggers, publish UI state, compute the top-level summary, remove rows on user intent (right-click on one row, in any state, recorded per product in `dismissedSessionIDsByAgent`, forgotten only once that product is visible and no longer lists that Turn, `tech-design.md` §17), and **hold what the list has let go of** — every row archived within `recentWindow`, keyed by Thread in `departuresByThread`, published as `recentDepartures` and filtered on read rather than evicted on a timer ([`expanded-panel-v2.md`](expanded-panel-v2.md) §2.5) | [`MonitorStore.swift`](../Notchline/Notchline/MonitorStore.swift) |
| Core orchestration (Codex) | `LiveCodexMonitorService` | Coordinate hooks, App Server, Project, unread state, caches, membership and degradation, composing the shared pieces — the hook transport, the presence reading, the read gate, `CodexUsageReader`, `CodexRolloutTurnEvidence` and `ThreadAdmission` — around the App Server lifecycle only it has | [`LiveCodexMonitorService.swift`](../Notchline/Notchline/LiveCodexMonitorService.swift) |
| Turn reducer and text | `MonitoringRepository`, `MonitoredTurnState`, `TurnPreviewStore` | Consume typed live evidence in source order, reject retired observation epochs, preserve exact and held Turn identity, reduce waits and subagents, and retain bounded current-Turn text. Projection changes and explicitly selected progress edges wake the panel; ordinary delta traffic never creates a second lifecycle reducer. Native payload decoding, hook trust diagnostics and descriptors are outside this actor. | [`MonitoringRepository.swift`](../Notchline/Notchline/MonitoringRepository.swift), [`MonitoringState.swift`](../Notchline/Notchline/MonitoringState.swift), [`MonitoringEvidence.swift`](../Notchline/Notchline/MonitoringEvidence.swift) |
| Hook evidence boundary | `HookEvidenceBoundary`, `HookPayloadDistiller`, `AgentHookVocabulary` | Select bounded fields before decoding, map native identities and signals, qualify text, project requests, and submit typed evidence. Track unreadable payloads, definition trust and first-live-event persistence; own native answer input and descriptors through `HookReplyRegistry`. Registration and helper bytes are unchanged. | [`HookEvidenceBoundary.swift`](../Notchline/Notchline/HookEvidenceBoundary.swift), [`HookIntegration.swift`](../Notchline/Notchline/HookIntegration.swift) |
| Hook transport (both products) | `AgentHookListener` | Transport only: bind a 0600 Unix domain socket, accept, read one payload, stamp arrival and hand it to the store. One payload per connection, with the writer's close as the frame end; **a serial read queue preserves order**, and the connection closes only after handover (the one piece of backpressure). One connection reads at most 16 MiB, a ceiling that bounds read-queue time per event rather than what the reducer can be told — field selection happens in the store before decoding, so fields that arrived whole before a cut still count. It selects no fields and writes no files | [`AgentHookListener.swift`](../Notchline/Notchline/AgentHookListener.swift) |
| Session identity (Claude Code) | `ClaudeCodeSessionRegistry` | Find a `claude` to run — the user's own install, then `PATH`, then **the copy Claude Desktop ships** at `~/Library/Application Support/Claude/claude-code/<version>/…`, newest version first by dotted integers, which is the only candidate a Desktop-only machine has (`tech-design.md` §15.1); run `claude agents --json` with single-flight reads; **a list that answered empty is held and never re-read on the clock**, with only edges, non-empty lists and failed attempts following the cadence (CR-Fable-002); freshness counts from the **last attempt**, and a failure keeps the previous list; **a session-directory change can truncate the freshness window** (`invalidate()`, never below `edgeFloor`, with an edge arriving mid-read not consumed by that read); it locates the array in stdout without assuming it owns the stream (balanced `[ … ]` spans handed to the decoder in start order, never trusting the first bracket, with an empty array taken last, CR-Fable-039; **a candidate array is accepted only if every entry carries `sessionId`/`pid`/`cwd`/`startedAt`, so a mixed array or one that is not a session list is rejected whole, and an empty array must also be alone on its line**, CR-Codex-001); and it **excludes this app's own quota-reading sessions** (`tech-design.md` §15.1) | [`ClaudeCodeSessionRegistry.swift`](../Notchline/Notchline/ClaudeCodeSessionRegistry.swift) |
| Session reading (every product) | `ProductSessionReading`, `SessionReading`, `ClaudeCodeSessionSource`, `SeparateSessionReading` | A product's presence and admission, **read together once per refresh** after its events are drained, with the sentence to say when presence is `unknown`; `MonitoringRepository.applying(_:to:)` holds the Turns to what an exact list vouches for, and only an exact list retires anything. **`ClaudeCodeSessionSource` is Claude Code's**, moved out of `ClaudeCodeMonitorService` on 2026-09-12: the registry read, read again on the spot when a Turn it does not name has moved since the reading began (`/clear` rotates a session id in place), the sessions-directory and record edges that invalidate the registry before anybody is woken, and admission only where the list is knowledge (`unknown` retires nothing). It holds the reading for the refresh, so every other Claude Code source — the read evidence's terminal route today — answers about the list that proved its rows exist, never a list looked up again; the click still asks the registry afresh. Antigravity's `AntigravitySessions` unions its CLI scanner — one kernel reading for both answers — with Desktop's running application, which vouches for the Desktop conversations observed while it runs; Codex speaks the same `ThreadAdmission` from its membership sweep; a product whose two answers are separate hands them in apart
| Codex Hook activation | `CodexHookActivation`, owned by `LiveCodexMonitorService` | Read public `hooks/list` and verify every managed definition before a Turn exists. File-change edges wake checks; only unresolved checks book a five-second retry. Verified answers are cached, requests single-flight and reset generations reject retired results. Setup evidence never enters the Turn reducer. See [connection checks](product-connections.md). | [`CodexHookActivation.swift`](../Notchline/Notchline/CodexHookActivation.swift) |
| Hook registration (Codex) | `CodexHookRegistrar` | Write `hook.sh`, add and remove this app's managed definitions in the user's `hooks.json`, and answer registration completeness (`absent` / `mismatched` / `complete`). **A definition is never rewritten once written** ([ADR 0014](adr/0014-the-codex-hook-definition-is-never-rewritten.md)); registration health is recomputed on our own writes and FSEvents edges rather than polled, and the edge is compared by count at read time rather than subscribed to (CR-028) | [`HookIntegration.swift`](../Notchline/Notchline/HookIntegration.swift) |
| Hook registration (any product without a trust step) | `ManagedHooksSetup` | Write the helper, add and remove this app's managed definitions in the product's settings file through the same strict editor, and answer registration completeness with `hasObservedEvent: true` because nothing has to be trusted after the write. Written for Claude Code as `ClaudeCodeHookSetup` and generalised on 2026-09-11: it takes any `AgentHookVocabulary`, whose `legacyCommandMarkers` say how earlier builds spelled that product's handlers. Shares `AgentHookHelper.prepare(at:answerWindowSeconds:fileManager:)` and `HookIntegrationPaths.readConfigurationRoot` with the Codex registrar, which keeps its own actor for the trust policy alone | [`ManagedHooksSetup.swift`](../Notchline/Notchline/ManagedHooksSetup.swift) |
| User configuration editing | `ManagedHooksConfiguration` | Strictly add and remove this app's definitions inside a user-owned configuration; never alter a structure it does not understand, and refuse wholesale when one it must write is such a structure | [`ManagedHooksConfiguration.swift`](../Notchline/Notchline/ManagedHooksConfiguration.swift) |
| Public protocol boundary | `CodexAppServerClient` | Subprocess, stdio JSON-RPC, handshake, request correlation, timeouts, liveness probe and transport rebuild | [`CodexAppServerClient.swift`](../Notchline/Notchline/CodexAppServerClient.swift) |
| Transport framing | `AppServerStreamPump` | Cut stdout into ordered complete frames inside the serial readability queue, failing closed on a single frame past the ceiling | [`CodexAppServerClient.swift`](../Notchline/Notchline/CodexAppServerClient.swift) |
| Pure parsing | `CodexSnapshotParser` | Root-thread test, title, preview, quota parsing and sorting; it derives no status, and its one **subtraction** is reducing `approvalNeeded` to `running` on an auto-reviewed thread (with the routing passed in by the orchestrator) | [`LiveCodexMonitorService.swift`](../Notchline/Notchline/LiveCodexMonitorService.swift) |
| Private Project boundary | `CodexDesktopProjectMetadataRepository` | Read and strictly validate the Desktop Project/Chats mapping | [`CodexDesktopProjectMetadata.swift`](../Notchline/Notchline/CodexDesktopProjectMetadata.swift) |
| Private unread boundary | `CodexDesktopUnreadStateRepository` | Read the unread set, tag its source authority, **report the main file's last write moment** (which the membership gate uses to refuse hiding decisions from a snapshot older than the Turn), and emit directory change events | [`CodexDesktopUnreadState.swift`](../Notchline/Notchline/CodexDesktopUnreadState.swift) |
| Private approval-routing boundary | `CodexDesktopApprovalRoutingRepository` | Read `heartbeat-thread-permissions-by-id.<threadId>.approvalsReviewer` from the same Desktop state, answering whether this thread's approvals reach a person. **It reports only threads proven `auto_review`**, with absence, unrecognised values and read failures all reverting to prior behaviour; it answers about "this thread now", while "this Turn" is pinned by `TurnApprovalRoutingPin` on the `LiveCodexMonitorService` side (the authority is each rollout's `turn_context.approvals_reviewer`, read by `CodexRolloutTurnReviewerReader` at the moment the Turn opens, when the record is about 1 KB from EOF rather than the median 32 KB it settles at). It has no watcher of its own — it shares a file with the unread set, whose directory watcher already wakes a refresh on each of its writes | [`CodexDesktopApprovalRouting.swift`](../Notchline/Notchline/CodexDesktopApprovalRouting.swift) |
| Private Turn-abort boundary (Codex) | `CodexRolloutTurnAbortReader` | Read `event_msg`/`turn_aborted` from the tail of a running Thread's rollout — the same file, and the same validated tail read, `turn_context.approvals_reviewer` is taken from. It is the **only** report Codex makes of a user pressing stop: no `Stop` hook, no `PostToolUse` for the call left open, and no App Server read that separates a stopped Turn from a working one. It answers about **one Turn**, names it, and may only end it ([ADR 0011](adr/0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md)'s 2026-08-29 addenda) — that Turn's subagent bookkeeping included, because the stop kills the `wait_agent` its subagents were going to report through while leaving them running; `reason` is deliberately not read, and no message text is decoded. Cached on `(size, mtime)`, so the ordinary refresh costs one `lstat`. Its edge is `CodexRolloutTurnEvidence.rolloutWatcher`, pointed at the rollouts of open Turns only and at nothing the rest of the time | [`CodexRolloutInterruption.swift`](../Notchline/Notchline/CodexRolloutInterruption.swift) |
| Turn evidence (per product) | `TurnEvidenceSource`, `CodexRolloutTurnEvidence`, `ClaudeCodeTurnEvidence` | What a product writes down about a Turn that no hook reports, handed to the reducer as facts and applied with the ordering guards any event gets ([ADR 0011](adr/0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md)): `settle` after admission, `watch(openTurnsIn:)` once the refresh's Turns are final, so a Turn just ended stops being watched in the pass that ended it, and `stopWatching()` when nothing is monitored. **Codex's** is the rollout — the held Turn a thread is really on, then a stop the user pressed — with the paths the App Server reported handed in per refresh; **Claude Code's** is the session list's stopped and busy words, a desktop-hosted session's interrupt record in its transcript, and Claude Desktop's log of a permission dialog closing, each read off the refresh's own session list, with the transcript and log watchers that bring a refresh round. Both moved out of their services on 2026-09-12; `HookProductProvider` applies any number in order | [`CodexRolloutTurnEvidence.swift`](../Notchline/Notchline/CodexRolloutTurnEvidence.swift), [`ClaudeCodeTurnEvidence.swift`](../Notchline/Notchline/ClaudeCodeTurnEvidence.swift) |
| Private read-state boundary (Claude Code) | `ClaudeCodeDesktopReadStateRepository` | Read Claude Desktop's session records, join identity by `cliSessionId`, take `lastFocusedAt` and `isArchived`, and take `sessionId` for the next row to join back; **no record means unknown, never unread**; emits account-directory change events ([ADR 0012](adr/0012-read-state-is-answered-per-product-or-not-at-all.md)) | [`ClaudeCodeDesktopReadState.swift`](../Notchline/Notchline/ClaudeCodeDesktopReadState.swift) |
| Which session is on screen | `ClaudeDesktopFocusLogReader` | The records log a session being **put** on screen and never being taken off, so after the user switches to a new session's composer the last-stamped session goes on impersonating the one on screen and its terminal row is retired unread. Claude Desktop's own log states both directions (`setFocusedSession: sessionId=…|null`), read backwards from the current tail and honouring only lines appended after this process started, and **in the orchestrator it is a veto only**: it can block a session the records claim but cannot nominate one they do not; unreadable means `unknown`, the behaviour from before this log ([ADR 0012](adr/0012-read-state-is-answered-per-product-or-not-at-all.md) rule 5) | [`DesktopDisplayedSession.swift`](../Notchline/Notchline/DesktopDisplayedSession.swift) |
| Read evidence (per product) | `ReadEvidenceSource`, `ClaudeCodeReadEvidence`, `TerminalReadEvidence` | A product's half of read state and nothing else: one verdict per row it is asked about (read or unread against a reading with an authority and an instant, or *cannot be asked*), and `forget()` when nothing is waiting to be read. Asked only when a finished row the user has not removed is listed, and only about rows the user has not removed (`TerminalUnreadRowFilter`, §3). **`ClaudeCodeReadEvidence` is Claude Code's five routes and the on-screen membership they keep across refreshes**, moved out of `ClaudeCodeMonitorService` on 2026-09-12; its terminal route is `TerminalReadEvidence` itself, asked about the process the refresh's own session list named (`ListedSessionProcesses`) rather than a list looked up again, since a second reading could launch a `claude` in the middle of the verdicts. `HookProductProvider` takes any source; Codex's verdict is Desktop's unread set, read with its other Desktop state and handed to the filter in one line | [`TerminalUnreadRowFilter.swift`](../Notchline/Notchline/TerminalUnreadRowFilter.swift), [`ClaudeCodeReadEvidence.swift`](../Notchline/Notchline/ClaudeCodeReadEvidence.swift) |
| Terminal read boundary (every CLI product) | `ControllingTerminalGestureReader`, `TerminalReadEvidence` | **Asked for every session, not only when the previous answer is unknown** (remote control puts one session in front of both), reading **two facts** at once: `sysctl(KERN_PROC_PID)` → controlling terminal device → `devname_r` → `stat`'s **access time** (the gesture), plus the same `sysctl`'s `e_ppid` walked upwards to see whether **the foreground process is an ancestor of this session** (whether it is in front of a person, at most 16 levels, reusing `DesktopReadingWatcher.systemScreenIsAvailable`). Both must hold to count as read — access time records that "the session read this device" rather than "a person did something", and Claude Code enables all-motion mouse reporting, so the pointer crossing an unfocused window advances it (ADR 0012's 2026-08-20 correction). **A surface not on screen receives nothing**, so it still holds per session rather than per application; no controlling terminal answers `nil` and such a row never enters the gate, while a host not in the foreground answers "unread" and such a row stays in the gate for the per-second re-check. **`TerminalReadEvidence` is that reading composed for a product that is not Claude Code**: the product supplies only `SessionProcessLocating` — which process a Thread runs in — and gets back one of three verdicts (read, unread, cannot be asked), which is what `HookProductProvider` judges a CLI product's finished rows on, and what Claude Code's terminal route is. What the terminal actually sends differs per product and is measured per product: Antigravity CLI's TUI enables neither focus nor mouse reporting, so its rows are retired by a keystroke and never by the pointer ([`antigravity-cli.md`](technical-explorations/multi-product-provider-architecture/antigravity-cli.md) §3.1) | [`ControllingTerminalGestures.swift`](../Notchline/Notchline/ControllingTerminalGestures.swift), [`TerminalReadEvidence.swift`](../Notchline/Notchline/TerminalReadEvidence.swift) |
| Application activation boundary | `DesktopActivationWatcher` | Use the public `NSWorkspace.didActivateApplicationNotification` to record **the moment** an application with a given bundle id returns to the foreground (transitions only, never "is it in front right now"), and emit it as an edge | [`DesktopActivationWatcher.swift`](../Notchline/Notchline/DesktopActivationWatcher.swift) |
| Is it in front of a person | `DesktopReadingWatcher` | The same public activation notification maintains "does that application hold the foreground now", minus three states that hold the foreground and mean nothing: `CGDisplayIsAsleep`, `CGSessionCopyCurrentDictionary`'s lock and console checks, and the screen saver's public distributed notifications. **The only test in the whole app that reads a state rather than awaiting a transition**, and therefore the only one that can retire an unread row; minimised, another display and another Space cannot be told apart ([ADR 0012](adr/0012-read-state-is-answered-per-product-or-not-at-all.md)) | [`DesktopReadingWatcher.swift`](../Notchline/Notchline/DesktopReadingWatcher.swift) |
| Path-set watching | `PathSetChangeWatcher` | Watch a path set that **changes at run time** and synthesise one event stream; shared by `ClaudeCodeSessionRecordWatcher` and the private read-state boundary | [`PathSetChangeWatcher.swift`](../Notchline/Notchline/PathSetChangeWatcher.swift) |
| Domain model | `MonitorSnapshot`, `MonitoredSession`, `MonitorAggregation` | Define the one data contract the UI consumes, and the aggregation priority | [`MonitorDomain.swift`](../Notchline/Notchline/MonitorDomain.swift) |
| Exact navigation (Codex) | `CodexDesktopNavigator` | Pre-flight the target and open the same Thread through the official deep link | [`CodexDesktopNavigator.swift`](../Notchline/Notchline/CodexDesktopNavigator.swift) |
| Navigation dispatch | `AgentNavigationRouter` | Hand a whole row to its own product's navigator; a product with no registered navigator fails under its own name rather than being handed to the first in the table | [`CodexDesktopNavigator.swift`](../Notchline/Notchline/CodexDesktopNavigator.swift) |
| Raising the host (Claude Code) | `ProcessHostNavigator`, `ProcessAncestryHostResolver`, `AppleEventsTerminalTabFocuser` | On click, ask `ClaudeCodeMonitorService` for that session's current pid (a finished session fails, which is the pre-click re-confirmation), then walk the process ancestor chain with `sysctl(KERN_PROC_PID)`'s `e_ppid` and `proc_pidpath` to decide the host: Claude Desktop among the ancestors means activate it, otherwise the nearest `.app` is the host terminal. A terminal with a `TerminalHostRegistry` entry (Terminal.app, iTerm2: the hosts whose dictionaries publish a tty) has that pane selected through its own public interface by the entry's `PaneLocator`, and one without has only its application activated ([ADR 0004](adr/0004-make-exact-desktop-navigation-a-release-gate.md)); the focuser owns consent, deadline and execution only ([`TerminalHostRegistry.swift`](../Notchline/Notchline/TerminalHostRegistry.swift)). Activation **follows the window to its desktop**: `WindowServerOccupancyReporter` first asks the window server whether that pid has a visible window in the current Space, and if not, this app takes the foreground itself (`ForegroundClaiming`) and then `hide()` and `activate()` — only the app ordering its own window front takes the user along, and only a request from an application that holds the foreground is honoured at all. **None of those three calls reports its own result**, `activate` least of all: it answers `true` for a request the window server declines, so the same window-server yes/no is asked again afterwards, and a raise that never arrives puts the host back and fails out loud instead of reporting a raise the user cannot see (`tech-design.md` §14.2) | [`ProcessHostNavigator.swift`](../Notchline/Notchline/ProcessHostNavigator.swift) |
| Process shape | `AppDelegate`, `NotchlineApp` | Runs as `LSUIElement` (`INFOPLIST_KEY_LSUIElement`, written in both Debug and Release configurations): no Dock icon, no ⌘-Tab, and no menu bar even when frontmost, so `⌘,` / `⌘W` / `⌘Q` do not exist (the product cost is in `PRD.md` §1 and §11). **The overlay is unaffected by this anyway**: it is a `.nonactivatingPanel` with `canBecomeKey` false and never relies on this app holding the foreground. What has to be made up for is the one launch that shows onboarding — an accessory app does not get the foreground at launch, so that window would open beneath someone else's, with a grey title bar. Measured, cooperative `NSApp.activate()` is **refused** at that moment, both called directly and a hop later once SwiftUI has put the window up (in both, the foreground stayed with the previous app, read via `lsappinfo front`, with Chrome frontmost and this app launched by `open`); `activate(ignoringOtherApps:)` does work, so it is used, and only while `hasCompletedOnboarding` is false — every other launch opens no window and leaves the foreground where it is (measured the same way). **The gear takes the same call**, for the same reason rather than a different one: the cooperative `NSApp.activate()` is a *request*, and it can be refused while returning as though it had not — measured at launch here, and recorded for a full-screen foreground in [`tech-design.md`](tech-design.md) §14.2. **The row click now takes it too**, and for a third instance of the same rule: an accessory application's request to activate *another* application is declined the same way, so a click that has to change desktop takes the foreground first and hands it straight on to the host (`tech-design.md` §14.2). A refusal on the gear is precisely the failure `SettingsWindowPresenter` exists to prevent: the window is ordered to the front of this app's own window list, this app stays behind, and the user sees Settings open underneath whatever they were already looking at. Ignoring other apps is what that path is entitled to do — it answers a click the user has just made on this app's own surface (`SettingsWindowPresenter.reveal`) | [`NotchlineApp.swift`](../Notchline/Notchline/NotchlineApp.swift) |
| Window | `OverlayPanelController` | NSPanel lifetime, target display, top anchoring, size and animation; it also owns "should this be on screen right now" — concealment **does not enter the store**, because both sides of the panel draw the same view tree, so publishing it would re-evaluate the whole overlay to change nothing (§6). **After every frame change it also re-asks whether the pointer is on the panel** (`MonitorStore.panelResized`): hover arrives through `NSTrackingArea`, and a tracking area speaks only while the pointer **moves**, so a window shrinking out from under a stationary pointer produces no exit — and none afterwards either, since the pointer is then outside the window and its movement is no longer that window's business. Folding the quota block hits this every time: it is a click (so the pointer is by definition still) and the amount withdrawn is far greater than the distance from the chevron to the panel's bottom edge (`56` against `14` with both products connected). Only the "left" direction is repaired: a panel **growing** over a stationary pointer is not an invitation, or a pointer left resting on the notch by `collapse()` would immediately reopen the panel over the full-screen window the concealment watcher closed it for. The same staleness costs a second thing: the tracking area's own record still reads "inside", so it swallows the next crossing back in and only resyncs on the crossing out after that — the first pass over the notch after a fold would do nothing and the panel would open on the second. A resize that stranded the pointer therefore arms a global mouse-moved monitor (`armPointerReentry`) that delivers that one entry and disarms as soon as the pointer is back over the panel. It is not a poll and not a redraw: the pointer is somewhere this window is not, so no event of this window's can report the return, and the handler is one rectangle test. Measured: a global monitor does see moves over this panel, because a non-activating panel that never becomes key is not where a mouse-moved event is delivered | [`OverlayPanelController.swift`](../Notchline/Notchline/OverlayPanelController.swift) |
| Should the panel be on screen | `OverlayConcealment`, `OverlayConcealmentWatcher` | Answer whether the target display still belongs to the user's desktop, testing exactly one thing: **the menu bar is not drawn** (an app or video is full-screen there, or the menu bar is set to auto-hide). It tests **where** the menu-bar window is rather than whether it exists: at this screen's origin is `drawn`, slid sideways during a Space switch is `sliding` (not reported, so the previous answer stands), and none at all is `away` (§7's "the one permitted poll"). Mission Control **does not hide the menu bar**, so it naturally falls on the "stays on screen" side, which is what the product wants (`PRD.md` §9.2.1), and the Dock's screen-filling window in the list exists but is not read. The test reads only owner, layer and bounds from the window list (none of which Screen Recording permission gates, unlike `kCGWindowName`), so it is a pure assertable function; the watcher reports edges only, numbering each sample so a stale reading overtaken en route is discarded, with the test and numbering done on the sampling queue and only a flipped answer returning to the main actor, the number carried through to the point of going on screen; with no screen the timer drops to a 60-second heartbeat and the overlay is put back on screen (§7) | [`OverlayConcealment.swift`](../Notchline/Notchline/OverlayConcealment.swift) |
| Views | `NotchOverlayView` | Render `MonitorStore` only, parsing no protocol and reading no file; terminal rows carry a `SecondaryClickCatcher` that claims only secondary clicks and still emits nothing but intent (`tech-design.md` §17) | [`NotchOverlayView.swift`](../Notchline/Notchline/NotchOverlayView.swift) |
| Product contracts | `AgentMonitoring`, `IntegrationConfiguring`, `AnswerDelivering`, `DiskFootprintReporting`, `AnswerHandle` | The contracts a product's module implements, and only the ones it has the capability for: every product observes (`AgentMonitoring`: identity, change stream, snapshot, next deadline, disconnect); a product that registers something configures; one whose requests can be answered from the notch delivers answers on an opaque `AnswerHandle`; one that leaves files reports its footprint. The store finds the optional three by conformance on the product's service and reads a missing one as "no switch to operate", "not delivered" and "leaves nothing". Until 2026-09-11 one protocol required all of them and `AgentRequest` carried a `HookReplyRegistry.Ticket` through the domain ([`tiered-support.md`](technical-explorations/multi-product-provider-architecture/tiered-support.md) §5.2) | [`ProductContracts.swift`](../Notchline/Notchline/ProductContracts.swift) |
| Quota reading | `UsageReading`, `CodexUsageReader`, `ClaudeCodeUsageReader` | How much of a product's limits is left, read on a clock of its own: what is held now (never waiting for a read), a read started behind it when stale and a screen could show it, the next deadline, and a sentence the user can act on. One shape for both shipping readers and a seam on `HookProductProvider`, which publishes `QuotaSnapshot.noneReported` for a product that hands in none. Codex's was six stored properties and three methods inside `LiveCodexMonitorService` until 2026-09-12; it reads only on the refresh branches that have just connected, since a read on a transport that is down would blank the figures for a failure that is not the account's | [`CodexUsageReader.swift`](../Notchline/Notchline/CodexUsageReader.swift), [`ClaudeCodeUsageReader.swift`](../Notchline/Notchline/ClaudeCodeUsageReader.swift) |
| Hook transport, wired once | `HookLifecycleSource`, `HookRegistrationSetup`, `HookTransportGate` | The three every hook-based product needs, connected the one way they connect: the setup that writes the registration and the helper, the `MonitoringRepository` its events land in, and the `AgentHookListener` whose delivery closure is that reducer's `deliver` and whose socket is the one the helper names. **All three Providers compose it**; a test still injects any of the three. The setup is a protocol with one conformer per trust policy — `ManagedHooksSetup` (compares the helper every refresh, status from the file alone) and `CodexHookRegistrar` (compares once per launch or when a `stat` finds the helper gone, binds the socket whatever the write says, status projected against a definition having fired) — so neither Provider wires a listener by hand. A product whose hooks run as registered refreshes through `gate(productName:)`: the helper before the status is read (a registration made while the app was closed is live either way, CC-021), then the status, then the socket, with the two sentences the settings card says when either stops the refresh. Codex reads the pieces itself, because its status combines registration, public activation evidence and legacy delivery evidence | [`HookLifecycleSource.swift`](../Notchline/Notchline/HookLifecycleSource.swift) |
| Shared product runtime | `ProductMonitoringRuntime`, `MonitoringLifecycleSource`, `HookProductProvider` | Source readiness, ordered evidence drain, one presence/admission reading, supplementary evidence, row content, read removal, diagnostics and usage. Hooks compose this runtime through a wrapper exposing configuration and answering; non-hook sources can use it without those capabilities. Codex retains its independent App Server lifecycle and the same shared reducer. | [`ProductMonitoringRuntime.swift`](../Notchline/Notchline/ProductMonitoringRuntime.swift), [`MonitoringLifecycleSource.swift`](../Notchline/Notchline/MonitoringLifecycleSource.swift), [`HookProductProvider.swift`](../Notchline/Notchline/HookProductProvider.swift) |
| Product registry | `ProductRegistry`, `ProductDescriptor`, `SetupDescription`, `ProductModule` | One value per product: its settings title, how its integration is set up (the file, the definition count read off the vocabulary, the trust step, what `Connected` may claim), and a factory for its Provider and navigator. `MonitorStore.makeShared` builds the services, the navigator table and the merged wake-up stream from this list; `ProductConnectionRows` draws one row per entry; every sentence Settings says about a product's file is derived here, so a count cannot go stale in prose (the tooltip said "five" for a product writing seven). `HookIntegrationPaths.live(for:)` takes the file from the descriptor. First step of [`tiered-support.md`](technical-explorations/multi-product-provider-architecture/tiered-support.md) §8 | [`ProductRegistry.swift`](../Notchline/Notchline/ProductRegistry.swift) |
| Settings window | `AppSettingsView`, `ProductSettingsCopy`, `FinderRevealTarget`, `MacOSWindowColor` | The macOS 26 settings in three toolbar panes (a `TabView` in the `Settings` scene; `SettingsPaneLayout` draws every pane at one fixed height, `SettingsWindowLayout.paneHeight`, with the closing row outside the scroll view): group cards drawn by hand, every control native, and the two-mode `Color / macOS Window` tokens (`figma-design.md` §8). The sentences a product row says are a value (`ProductSettingsCopy`, **one rule for every product, reading that product's own availability**) rather than computed properties on four views — the failure report beneath that row is the only thing in this window that exists to report failure, and a value can be asserted while a `body` cannot (CR-029). **How the window appears** belongs to `SettingsWindowPresenter`: every open centres it on **the component's screen** (`MonitorStore.selectedScreen`, matched to an `NSScreen` by display identifier, `PRD.md` §11), then activates the app with `activate(ignoringOtherApps:)` (the "Process shape" row above says why the cooperative call is not enough) and orders the window to the front. The component's screen rather than the focused one, first because everything this window changes is visible only in the notch, and second because that answer cannot change during window ordering — the focused screen read a step late becomes Settings' own. The placement algorithm is the pure, assertable `SettingsWindowPlacement.origin`. **Placement happens only while the window is invisible**, which is the shape of this path: `SettingsWindowTracker` hands the window over synchronously through an `NSView`'s `viewDidMoveToWindow` — there is no window at `makeNSView` time, and a hop later SwiftUI has already put it up, and that hop is the flash the user sees (measured: the window appears on the screen it was last closed on and jumps about 50 ms later); the presenter then observes **both** directions of `isVisible`, with the hide being the workhorse — it moves the window to the screen it should currently be on, so the next show is correct on its first frame. The `⌘,` and app-menu route no longer exists — this app runs as `LSUIElement` with no menu bar to hold that item (see the "Process shape" row) and the gear is the only entry — so observing `isVisible` is no longer a safety net for another entry point but simply where placement lives. What a product's ⓘ popover says is a value too (`ProductInfoContent`), and its `Show in Finder` — like the glyph on the Quota pane's transcripts row — follows the same "a value, not a `body`" path: `FinderRevealTarget.revealing(_:)` gives three cases — select this file, open this folder, nowhere to go (disabled) — and both product rows take their paths from `HookIntegrationPaths.live(for:)`, so the button and whoever writes that file cannot point at two different places | [`SettingsWindow.swift`](../Notchline/Notchline/SettingsWindow.swift) |
| Persistent motion | `NotchStatusMatrix`, `SearchlightLabel`, `SessionRowText`, `SessionDotColumnView` | Carry continuous animation on CALayer so the overlay need not re-render per frame (§6). The session column is the newest of them and the reason its marks are drawn on layers at all: its breath is a loop with no end, so §6 leaves it exactly one home. What stays in SwiftUI there is everything with a beginning and an end — the slot opening, the dot fading in and out — which §6 does not reach | [`NotchStatusMatrix.swift`](../Notchline/Notchline/NotchStatusMatrix.swift) |

Approval detail presentation (2026-09-07): `AgentRequestReading.approvalFields(in:)` projects structured arguments once at the hook boundary. `AgentRequest` carries those immutable fields through the existing snapshot; `RequestBodyLayout` measures them, and `RequestBodyView` draws the measured lines. The UI never reconstructs fields from flattened text or decodes a protocol. The existing wheel-driven viewport is retained, with the overflow count based on actual label/value line bottoms. This introduces no timer or continuous animation.

## 6. The rendering boundary for persistent motion

**No continuously running SwiftUI animation is allowed in the overlay.** Persistent motion is drawn on `CALayer` and evaluated by the render server.

This constraint comes from measurement rather than preference. The indicator and the label searchlight were both `TimelineView(.animation)`; measured in Release with the status pinned to `.running`, toggling one at a time:

| Configuration | CPU |
| --- | --- |
| Indicator off, searchlight off | 0.0% |
| Indicator off, searchlight on | 7.8% |
| Both on (the original) | 11.8% |
| Expanded panel plus two rows sweeping | 15.3% |
| Everything moved to Core Animation | 0.0%–0.4% |

Two conclusions are counter-intuitive enough to remember separately:

1. **Cost is not proportional to what is drawn.** Removing three layers of Gaussian blur saved 2 points of the 11.8%. The real expense is re-rendering the entire overlay every frame, including the custom `PanelContour` shape and all text measurement.
2. **Lowering the refresh rate does not help.** Capping the schedule at 30 Hz measured the same as the display's 120 Hz. Redraws are driven by the panel being marked as needing display rather than by the view's own tick, so however often the SwiftUI side wakes, the whole panel is repainted.

So the test is not "is this animation expensive to draw?" but **"does it tick continuously?"**

### Low-frequency content updates count too

This section originally read "the once-a-second timer is still an ordinary SwiftUI `Text` and is completely fine" — **that was wrong**, and measurement later overturned it. The processing-time readout changes once a second but was published from the store through `@Published`, and any publish on the store re-evaluates the whole overlay, measured at about 20 ms. Once a second is about 4% of a core, and that cost continues in a state like Approval needed which can wait on a user indefinitely — while nothing on screen changes but four characters.

The readout now subscribes to a tick SwiftUI does not observe (`MonitorStore.elapsedTick`) and draws itself into a layer; the store publishes `elapsedLayoutRevision` only when the readout's **drawn width** changes, which under monospaced digits is a digit count change, once a Turn rather than once a second. (It was the *reserved* width until the two collapsed forms stopped reserving; the signature is the same character count either way, so the publish rate is unchanged — what changed is that the publish now also moves the panel's edges, on both geometries.) The same scenario measured 4.7% → 0.0%.

The full form of the rule is therefore: **overlay re-render count should be driven by whether the layout changed, not by whether the content changed.** Content changes go to a layer, and only layout changes are worth disturbing SwiftUI. Continuous motion is merely the most extreme violation of it.

### What that rule costs: the window's list of publishes

Keeping the measurement off the path of every state is why the window cannot simply follow `objectWillChange`. `OverlayPanelController.frameChangingPublishers(of:)` enumerates the publishes that can move `MonitorStore.currentPanelSize`; everything else on the store re-renders the view without the window being asked for a frame at all.

**The enumeration is the failure mode, and it has been incomplete four times** — giving up the wings, a second product's marks, the quota table, and the Recent queue. Each is a control that nothing else republishes behind, so each redrew itself at its new size inside a window still sized for the state before. The queue is the clearest case: opening it drew its rows below the panel's bottom edge, folding it left the space they had occupied behind, and the only way to see either at the right height was to close the panel and open it again.

The symptom always looks like a view bug and never is. `MonitorStore` computes the right size throughout, and the store's own assertions — `openingTheTableGrowsThePanelItself`, `foldingTheQueueMovesThePanelWithoutClosingIt` — pass the whole time, because they ask `currentPanelSize` what it says rather than whether anyone was told. So the list is driven rather than reviewed: `everyChangeThatMovesThePanelReachesTheWindow` walks the controls that move the panel and fails on the first one that does not reach the window. A new control belongs in that table and in the list, in the same change.

### How to measure: `ps %cpu` will lie to you

All the numbers above were measured on a Release build with the status pinned, toggling one variable at a time. But **the method itself has a trap worth remembering separately: `ps %cpu` flattens brief bursts away.**

One expand/collapse transition measures about 92 ms of CPU (30 transitions in 60 seconds cost 2.97 s against a 0.21 s baseline with no toggling), roughly half a core during the animation. The same thing shows as 0.1%–0.3% on `ps %cpu`, effectively nothing — it is visible only by differencing cumulative CPU time (`ps -o time`).

Conversely, **steady-state cost reads accurately on `ps %cpu`**, which is how the table above was measured.

So: `ps %cpu` for steady state, cumulative CPU time for bursts. Choosing the wrong tool produces the false conclusion that there is no cost left.

### Expansion and collapse have one geometry animation (2026-09-07)

The window owns the resize. Sharing `PanelMotion`'s curve did not make
SwiftUI's independently interpolated header, body and background one object:
in a cropped Release recording, text and controls moved independently of the
surface. The body also entered with its own `−6 pt` offset.

`NotchOverlayView` groups the surface and content with `geometryGroup()` and
**does not apply a SwiftUI geometry animation to either the root or header**.
Only the body's opacity carries an explicit expansion/collapse animation. Animating
the root as well as the window was rejected: even with a shared geometry group,
the disappearing body could still drift inside the shrinking surface. One
framework owns intermediate geometry; the other draws the bounds it receives.

A SwiftUI removal transition also retained a subtree whose layout could drift
while the surrounding window narrowed. `OverlayBodyPresentation` instead keeps
the same live body mounted during its fade and unmounts it after `PanelMotion.duration`.
A cancellable, revision-guarded task performs that one cleanup, explicitly on
the main actor. Reopening cancels it; disappearance cancels it and releases the
body immediately. The closing body takes no clicks and is hidden from
accessibility. The closed panel retains no list and schedules no body work.

The expanded list, Recent section and footer also used `store.currentPanelSize`
for their widths. That is the **destination**, so the content laid itself out
wide before an opening window arrived, and narrow as soon as collapse began,
while its removal transition was still visible. The root now passes its actual
body width through `EnvironmentValues.overlayBodyWidth`; these views use that
presentation geometry. Standalone onboarding specimens keep their previous
store-based width when the environment value is absent. `OverlayGeometryTests`
checks the rendered live list at intermediate widths across both state changes
and checks the standalone fallback. It also checks fade-lifetime retention,
reopening cancellation and disappearance cleanup with the test clock.

The `200 ms` curve, hover dwells, window-frame driver, pointer reconciliation,
final geometry and layer-backed persistent motion are unchanged. There is no
resident timer, display link, snapshot cache or continuously animated SwiftUI
view; the single pending cleanup exists only during collapse.
Apple describes why a geometry group keeps subviews together in
[`geometryGroup()`](https://developer.apple.com/documentation/swiftui/view/geometrygroup()).

**Release measurement:** the same isolated overlay fixture, two visible Threads
(one Running and one Input needed), no monitoring services, on the built-in
notched display at a `38 pt` band. Each run warmed for two seconds, measured
20 seconds collapsed, then alternated 60 expansions/collapses at 0.5-second
intervals by changing `isExpanded` directly. Pointer callbacks and resize
reconciliation were disabled in both fixtures so a stationary pointer could
not override the sequence; hover dwell time is not part of the CPU figure.
CPU is the difference in `getrusage(RUSAGE_SELF)` user plus system
time; the transition figure subtracts the same run's idle rate. The final
baseline/candidate pair ran sequentially without recording or compiling
alongside it.

| Version | Idle CPU, 20 s | Net CPU per transition |
| --- | --- | --- |
| Before | 0.145 s | 86.89 ms |
| Presented widths and live-body fade | 0.148 s | 86.48 ms |

The final pair is effectively unchanged: **86.89 → 86.48 ms per transition**.
Idle CPU differs by 0.003 s per 20 seconds, about 0.02 percentage points of one
core. These samples show comparable cost, not a speed-up or a guarantee of
identical CPU use. The temporary body lifetime leaves no work behind when the
panel is shut. Screen recording was a separate visual check: titles and
controls kept their panel-edge insets in both directions, without the earlier
sideways drift during removal. This fixture does not measure whole-system
GPU/WindowServer energy, hardware vertical synchronisation or every external
display.

**Rejected:** replacing the existing frame driver with
`NSAnimationContext.animate` brought no demonstrated cost advantage in the
initial screening run (88.7 ms per transition, against that run series' original
77.7 ms); its use of the same SwiftUI animation type alone did not justify a
window-driver change. Those unpaired screening values are not the controlled
comparison above. Keeping the window driver also preserves its existing
interruption and delayed-wing behaviour. No non-public Codex dependency was
added or changed.

### The migrated mechanism is not bound to the current design

The indicator hands the SVG's `<animate values="…">` list straight to a `CAKeyframeAnimation` — linear calculation mode spreads N values across N−1 intervals, which is SMIL's own rule, so the curve is unchanged and only the evaluation moved to the render server. The label rasterises its glyphs once and lets Core Animation push a gradient mask across a highlighted copy; session rows additionally take over the trailing fade as their own layer mask, because SwiftUI's `.mask` over an AppKit host view is not reliable.

Track values, loop period, colour, size, cell ratios, glow layer count and radius, new states, label copy and font — changing any of those needs **no re-optimisation**. Label copy is free in particular: it is measured with the same `NSFont` metrics `PanelMetrics` uses to reserve width, so panel width follows automatically.

Only one case needs re-evaluating: motion that is no longer a **fixed loop plus animatable layer properties** but depends on live data per frame (streaming progress, a waveform), needs per-frame redrawing (particles, shaders), or changes its glyphs every frame.

### The one permitted poll: should the panel be on screen

The overlay follows the menu bar (`PRD.md` §9.2.1), and **nothing publishes that fact**. Measured one by one on macOS 26.5, what a process can ask about is its own state rather than the system's:

| Signal | Another app full-screen | Mission Control | Switching Spaces |
| --- | --- | --- | --- |
| `NSApp.currentSystemPresentationOptions` | `0`, unchanged | `0`, unchanged | not measured |
| `NSMenu.menuBarVisible()` | `true`, unchanged | `true`, unchanged | not measured |
| `NSScreen`'s `visibleFrame` / `safeAreaInsets` / `auxiliaryTopLeftArea` | unchanged | unchanged | unchanged |
| `NSApplication.didChangeScreenParametersNotification` | not measured | not measured | does not fire |
| `NSWorkspace.activeSpaceDidChangeNotification` | does not fire | does not fire | fires, but only **after** the switch has finished |
| The window server's own menu-bar window | **leaves the on-screen list** | still there | still there, **slid sideways** |
| The Dock's screen-filling window below the dock layer | absent | one per screen | absent |

Only the last three move, so the test reads the window list; and **the first five are simultaneously the list of subscriptions already tried** — the edge-triggered version simply never fires, so this can only be polled. Of the last three, only the menu-bar row is read: **Mission Control does not hide the menu bar**, so "follow the menu bar" judges Mission Control as staying on screen, which is the product's intended result (`PRD.md` §9.2.1). The last row stays in the table because it is the signal that Mission Control was once hidden on, and the only one that can see Mission Control at all — if it is ever to be judged again, start there rather than retrying the five above.

**Switching Spaces does not hide the menu bar; it slides it away.** Measured 2026-08-24: throughout the switch that screen's menu-bar window keeps its top edge and width and moves along x (from `x: 0` to `-1864` on an 1800 pt screen) until the next Space's own menu bar lands at the origin; the window server carries the overlay along by **the same displacement**. So the test reads not "is it in the list" but "where is it", in three states: at this screen's origin is `drawn`, elsewhere is `sliding` (a Space is moving and nothing is settled), and no candidate at all is `away`. `sliding` is not an answer, is not reported, and leaves the previous answer standing.

The earlier test required the menu bar to be at this screen's origin, so a full ~850 ms switch read as "the menu bar is gone" and the overlay was `orderOut` and `orderFrontRegardless`ed on every Space switch — the user saw it vanish during the switch and flash back on the new desktop; a slow trackpad swipe can keep the menu bar off the origin for 3.5 s (measured), and the overlay disappeared for that long. The `activeSpaceDidChange` row is exactly why a subscription cannot solve this: it arrives with the new menu bar, whereas this has to hold from the switch's first frame.

Candidates are matched to a screen by "top edge plus width", so one configuration needs guarding against: with two equally wide displays whose top edges align side by side, the neighbouring screen's stationary menu bar is geometrically indistinguishable from this screen's sliding one, and misreading it as `sliding` would leave the answer permanently unsettled with the overlay pinned over a full-screen video. The test therefore also takes the bounds of every display in use and **assigns a candidate sitting at another screen's origin to that screen**. That list is fetched only once `sliding` has already been read — `activeDisplayBounds()` costs 214 µs (Release, 3 displays), and `sliding` appears in only a few samples per switch, never in steady state.

It does not violate §7, because **nothing downstream re-renders**: sampling and the test both happen on a utility queue, and only **a changed answer** returns to the main actor, where it does nothing but `orderOut` / `orderFrontRegardless` one window. Neither the store nor any SwiftUI view sees this cadence.

**Moving the test off the main actor was because "does not re-render" is not "does not wake".** Each sample previously did an unconditional `DispatchQueue.main.async` with the comparison on the main actor — nothing downstream drew anything, but the main run loop could never sleep past 250 ms: 48,000 wake-ups a day, 345,000 over twelve hours, almost all concluding "unchanged". The state the test needs (the ticket number, the previous answer, which screen is being watched) now lives behind one lock in `OverlayConcealmentWatcher`, read and written by the sampling queue itself, and the main actor is woken only when the answer genuinely flips — a few times an hour on a normal day. The numbering rule is unchanged: a reading overtaken by a later sample is still discarded, and `sliding` still claims no number.

**Numbering queues the test, not the going on screen (2026-08-26).** A user ran Release for a day on another machine: the screen went dark, came back, they logged in again, and the overlay was gone — with no gesture able to recover it, since there is no Dock icon, no menu bar item and no window to summon, leaving only killing the process in Activity Monitor. The cause is the seam the previous paragraph left: one main-queue hop between the test and going on screen. The timer finished its test on its own queue and scheduled a `DispatchQueue.main.async` to go on screen; `sampleNow()` — called by both display-change and wake edges — tests and goes on screen **immediately** on the main actor, cutting ahead of that already-queued hop. The stale answer lands last, onto a state where `lastReported` has already been written to the new answer: the panel is `orderOut`ed while the watcher believes it is on screen, and every sample afterwards agrees with its own state and reports nothing. The number is therefore carried all the way to going on screen, and `apply(_:ticket:)` accepts only a number higher than the one already on screen. Waking is the one moment those two paths collide.

**With no screen the timer drops to a heartbeat.** A menu bar nobody can see occludes nothing, and this is the largest single item in the whole process's steady-state cost: a 45-second `sample` of a Release build on a real machine 2026-08-25 put **41%** of all on-CPU samples in this one call, and it had been running from `start(onChange:)` onwards, including through a locked night. Each tick now first reads `ScreenAvailabilityReporting.isAvailable()`: if false it `schedule`s the timer to a **60-second heartbeat** until an edge from `changeEvents()` (display wake, unlock, screen saver end, session returning to console, system wake) brings it back — sampling once immediately on return, because a display can sleep under one window arrangement and wake under another, and waiting out a whole interval would leave the overlay over a menu bar that is not there. `schedule` rather than `suspend()`: both have the same effect on wake-ups, and only the latter requires balancing, with an unbalanced `DispatchSourceTimer` crashing on deallocation.

**A heartbeat rather than `.distantFuture`, because two of those five edges are not guaranteed (2026-08-26).** `com.apple.screenIsUnlocked` and the screen saver ending are distributed notifications, another process's best effort; and `screensDidWake` often arrives while the session is still locked. Parking on a distant future bets the whole overlay on another edge arriving, and if none does, it never samples again. The heartbeat reads only the screen, never the window list: 107 µs a minute, with a 15-second leeway so the system may coalesce it into any other wake-up, buying "a missed notification costs at most a minute" rather than "a missed notification costs everything". This is also the backstop this section previously claimed and that parking on a distant future had quietly cancelled.

**The stopping side fails open: the overlay goes back on screen and the previous answer is forgotten.** A menu bar nobody can see occludes nothing, so a `concealed` carried into a dark or locked screen is not a fact about anything — but it would be **held**, keeping the panel off screen with every route back requiring first a notification and then a sample agreeing. The state this product must never reach is "it is gone and the user has no way to bring it back", the same reason `menuBarPresence` never hides when it cannot determine the display (`PRD.md` §9.2.1). The recorded cost is that waking to a full-screen window may leave the overlay over it until the wake edge's sample takes it away. Forgetting the old answer matters as much as going back on screen — keeping a `concealed` `lastReported` would make the first sample after waking agree with it and report nothing, leaving the overlay sitting on the full-screen window.

**Wake edges arm unconditionally, without consulting the reading (2026-08-26).** These edges are emitted by other processes around a transition this process observes from outside: `screensDidWake` arrives with the display while the session is still locked, and the unlock is announced by `loginwindow` rather than by the session dictionary `isAvailable()` reads. An edge that stops the timer on reading "no screen yet" bets the overlay on the **next** edge. The cost of arming unconditionally is one tick — the first tick always reads the screen, and an early edge simply stops it again — and it owes nothing to which of two processes goes first.

That reading has its own price, and it is dearer than the ratio suggests: `isAvailable()` costs 107 µs against the window list's 530 µs, only a 20% surcharge, but like the window list it is a **round trip to the window server**, and sampling it at 4 Hz measurably raised this process's Mach traffic by half (71/s → 107/s) in exchange for a state that changes a few times a day. So it is sampled at about **1 Hz** rather than every tick: the surcharge falls to 0.011% of a core, stopping is at most a second late, and that second cannot cost anything — nothing on screen could be drawn wrongly. The first tick after arming always reads, so a freshly zeroed counter cannot delay a stop that is due.

The zero-surcharge form would be making `changeEvents()` fire in **both** directions and reading only on its edges. That is deliberately not done: that stream is shared by two monitor services, and loosening its contract changes their refresh behaviour rather than this file's; and this poll is also the backstop for a lost notification.

What it buys is **zero** when there is no screen. At eight screenless hours in twelve, 0.21% of a core around the clock becomes 0.22% for four hours and 0.00% for eight — 91.6 seconds of CPU becoming 31.7. It reads the one `ScreenAvailabilityReporting` value rather than a subset of it (only `CGDisplayIsAsleep`, say), for the reason documented on that protocol itself: restating "awake, unlocked, on console" a second time is exactly how two halves start to drift.

Costs and choices: in Release, one `CGWindowListCopyWindowInfo` with 61 windows on screen is 723 µs, and 583 µs with `.excludeDesktopElements` (the menu-bar window the test needs is still there). The 250 ms interval is a **latency budget rather than a sampling rate** — it is how long the panel may remain after the menu bar starts leaving. That number was originally taken from Mission Control's expansion (about 350 ms of scaling, the tighter of the two scenarios; the menu bar's own fade is slower), and with only the menu bar left the budget is tighter than needed; it is not widened because one sample costs 583 µs and the saving would buy nothing. Together that is 0.1%–0.3% `%cpu`, or 0.25% by cumulative CPU difference — steady-state and cumulative methods agree here.

**583 µs is a floor, not a typical value.** Re-measured 2026-08-26 on a machine running Chrome, Xcode and Figma: 530 µs with 39 windows on an idle machine, and 2.0 ms with 49 windows under load — 0.21% to 0.80% of a core. The cost tracks on-screen window count and contention, so "the saving would buy nothing" holds only on a quiet machine; what actually holds it down is the two rules above (return to the main actor only on a change, stop when there is no screen) rather than this interval.

### A finite transition is not persistent motion

The test is "does it tick continuously", so a transition with **a beginning and an end** is not bound by this constraint: it finishes and disappears rather than repainting the overlay every frame until shutdown. Handing one status name over to the next is such a transition — the old reading fades out above the new one, one `CABasicAnimation`, evaluated by the render server, with `SweepingLabelView` not ticking itself and SwiftUI not re-evaluating the panel. (It was written for expanding and collapsing, which used to change the word as well as the room around it; the pill has since stopped abbreviating, so what hands a reading over now is the aggregate itself moving — [`figma-design.md`](figma-design.md) §6.4 / §9.1.)

That handover incidentally settled three things, all of which surface only when layout moves while content changes:

1. **A glyph layer is framed at its own raster size, never at `bounds`.** `CALayer`'s `contentsGravity` stretches by default, and `bounds` is animating underneath the label whenever the panel opens or closes — framed by `bounds`, a new reading is stretched to the old width and squeezed back by the animation. (The case that found it was collapsing from `Approval needed` to `Approval`, when the pill still abbreviated; the width is still animated and so is the hazard.) `ElapsedReadoutView` and `SessionRowTextView` were always framed by raster; only the status name was not, and it is the one label whose width is animated.
2. **The curve is declared in one place.** `PanelMotion` (`NotchStatusMatrix.swift`) gives `200 ms` / `cubic-bezier(0.22, 1, 0.36, 1)` in both SwiftUI and Core Animation form. The window (`OverlayPanelController`), the top bar (`NotchOverlayView`) and the label's fade each declared their own, kept in agreement purely by hand; the fade must end at the same moment as the width closing beneath it, so there cannot be a second opinion. There is **no second set of reduced durations** beside it: Reduce Motion is not supported and no path reads it ([`figma-design.md`](figma-design.md) §10). It was once declared as a `false` constant with no writer, making every reduction dead in production while tests passing the flag straight to a view still passed — a completely silent failure (CR-Fable-015) — and giving it a real writer only turned that into a second curve to keep in agreement by hand.
3. **The sweep is no longer reinstalled on every layout.** During the transition this view is laid out every frame, while the sweep's geometry depends only on glyph size — `SessionRowTextView` had long been written that way and the status name now follows. (No new performance measurement was taken and no number is claimed: what changed is the structure of one `CATransaction` commit per frame, not a measured steady-state cost.)

When one reading is a prefix of the other, the new reading **does not fade in**: the shared glyphs are the same pixels in the same place, and two layers only dim a word that never moved. Only genuinely different readings cross-fade both ways. No pair the aggregate can reach is a prefix pair now that the pill says the whole name — `Approval` / `Approval needed` was the pair — so the rule is kept for what it says rather than for a hand-over in play today. The copy rules are in `figma-design.md` §9.1.

### The Recent queue's clock, and what it deliberately does not do

Three wake-ups were considered for the queue and two were removed before they existed.

**Eviction takes none.** A row leaves the queue at five hours, and that is a filter applied as of `now` wherever the queue is republished rather than a timer counting towards it. Opening the panel is a republish, so a queue nobody has looked at for six hours is empty before it can be drawn, and **nothing at all runs while the panel is shut** — no task, no sleeper, no wake-up on the shared refresh loop's account.

**The readings take one, and only while they are the thing on screen.** The tick runs while the panel is open and the queue has members, and it sleeps to the next instant the panel is actually drawing, which depends on the fold. Unfolded, every age is drawn, so that is the next whole minute (or hour, past an hour) any member crosses from its own departure — not a flat minute, which would drift into crossing two boundaries in one wake-up and visibly skipping a reading, the same fault `MonitorStore.secondsUntilNextTick(after:now:)` avoids for the elapsed readout. **Folded, no age is drawn at all**, and the only thing that can change is the seam's own count — so the one instant worth waking for is a member's expiry, and a folded queue wakes at most once per member however long the panel is held open. Changing the fold cancels the parked wake-up and re-plans it, because it was booked against the other question.

**And nothing is published for a reading nobody is drawing.** `recentReadAt` moves only with the panel open and the queue unfolded; shut or folded, refreshes keep arriving and it stays where it was, so the collapsed bar never pays a re-render for a string that is not on screen. Both states re-read on the way back in.

**No Release measurement was taken, and none is claimed.** The bound is arithmetic rather than measured: at most one full overlay re-render per minute while the panel is *held open* with the queue unfolded, and zero in every other state. That is two orders of magnitude below the once-a-second readout this section moved to CALayer for costing 4.7%, on a surface that is open for seconds at a time — which is the reasoning for not paying the layer-backed price here, not evidence that it is free. Measuring it needs a queue with members on a live panel, which needs a row that has been vouched for and then archived; the same gap keeps the drawing itself unverified ([`expanded-panel-v2.md`](expanded-panel-v2.md) §9).

### The caret is the one thing that ticks, and it is AppKit's (2026-09-05)

The answer row has a text field in it, and a blinking caret is precisely the continuously running animation this section forbids: drawn from SwiftUI it would invalidate the panel — `PanelContour` and every text measurement — twice a second for as long as a row is open. So the field is an `NSTextView` (`AnswerFieldView`) hosted through `NSViewRepresentable`, with the caret drawn by the text system into its own layer, and **the text itself never reaches `@Published`**: `MonitorStore.answerProgress` is an ordinary stored property, and what SwiftUI is told is where the white ground is, which moves at most once a row. The placeholder is drawn by the text view too, for the same reason — a SwiftUI overlay would have to be told when the field stopped being empty, which is a publish per keystroke.

Measured on Release by diffing cumulative CPU time, which is the only way to read a burst here:

| State | CPU over the window |
| --- | --- |
| Collapsed, nothing open | `0.13` s in `20` s |
| A row open, the caret blinking | `0.12` s in `20` s |
| ~~`600` wheel events over a `60`-line body~~ | ~~`3.3` s, against `0.5` s for the same `600` events with nothing to scroll~~ **Withdrawn — the body was not scrolling. See below.** |

The first two are the same number, which is the finding: **the caret costs nothing**. ~~The third is the body's own scroller (`expanded-panel-v2.md` §2.4 rule 02), it predates the answer row, and it is about `4.7` ms of work per wheel event — a whole panel's worth rather than a translation. It is transient and user-driven, paid only while a finger is moving; `.equatable()` on the body was tried and bought nothing, so what is being re-done is not the sixty `Text` lines. Recorded here rather than fixed: it is a measurement this section is the home of, and the mechanism belongs to the panel's list rather than to answering.~~ The third measured a scroller that was not running, and the next section is what it was actually measuring.

### The wheel never reached the body, so every number about it was the list's (2026-09-05)

`4.7` ms per wheel event was **not** the body being translated. `WheelCatcherView.scrollWheel(with:)` was never called: over `600` wheel events posted onto an open row with a `60`-line command in it, the app was handed all `600` and the catcher saw **`0`**. The events went to the panel's own list `ScrollView` instead, which had nothing to scroll and drew nothing, and the body stayed on line one throughout — verified on Release by screenshotting the panel before and after.

**Why, exactly.** AppKit dispatches `scrollWheel` to whatever `hitTest` answers with. The catcher was declared as a `.background` of the body, so it sat *behind* the lines; SwiftUI answers a hit test with the frontmost hit-testable thing it finds, and a `Text` is hit-testable. Asking the panel's own content view at the event's `locationInWindow` returns `HostingScrollView`'s document container every time, with a responder chain of `PlatformGroupContainer > DocumentView > NSClipView > HostingScrollView > … > OverlayPanel`, and `WheelCatcherView` nowhere in it — although its frame does contain the point. Behind hit-testable content, a catcher is not a catcher.

This is the failure `answer-in-notch.md` §4.4 already describes and had attributed to the wrong cause: *"a second `ScrollView` inside the list's own chains against it and loses — measured 2026-09-05, the wheel reached the app and the body never moved"*. The symptom was recorded correctly, the nested scroller was replaced with a driven offset, and the symptom was never re-tested — so the replacement inherited it. **The house pattern was already right next door**: `SecondaryClickCatcher` is the same idea, drawn as an `.overlay` and giving back every event it has no business with from `hitTest`, and it works. The wheel catcher now does the same — over the body, `claims(_:)` taking the wheel and nothing else, and taking nothing at all where the body fits, so a short request is not the one place on the panel where the list cannot be scrolled.

**What it costs once it runs.** Release, one binary, the placement chosen by an environment variable so the two are measured back to back; `600` wheel events at `8` ms over a staged `60`-line command body, three runs each, medians:

| Configuration | CPU over `600` events | Per event | The catcher saw |
| --- | --- | --- | --- |
| As shipped: the catcher behind the body | `0.46` s | `0.77` ms | `0` — and nothing moves |
| Over the body, but the offset never written | `0.49` s | `0.81` ms | `599` |
| Over the body, the body actually moving | `1.03` s | `1.72` ms | `599` |
| A `3`-line body, which fits: the catcher declines | `0.35` s | `0.58` ms | `0` |

So the honest figure is **`1.7` ms an event, not `4.7`** — and the `0.77` ms the shipped build was paying bought nothing at all, because it was the list being asked to scroll a list that was already at its cap. Working, the scroller costs about `0.9` ms an event more than not working.

**Where that `1.7` ms is, and where it is not.** Every suspect on the list turned out to be innocent, and the cheap fix was tried again under conditions where it could have worked:

- **The `@State` does not invalidate up to the `NSHostingView`.** `NotchOverlayView.body` is evaluated **3** times over a whole `600`-event run, in every configuration. `PanelContour.path(in:)` is built about **673** times in every configuration *including the ones where nothing scrolls at all*, so it is not on this path either. The invalidation is exactly one view deep: `ScrollingRequestBody.body` runs once when the offset is never written and `600` times when it is.
- **`RequestBodyView.body` runs once or twice a run, never `600` times.** SwiftUI already skips it, which is why `.equatable()` bought nothing before and buys nothing now (`0.90`–`1.05` s against `0.99`–`1.02` s). The inference drawn from that was the wrong one: not re-evaluating the sixty lines is not the same as not re-doing them.
- **Something scales with the lines, and it is a minority of the cost.** With the body moving, `600` events cost `0.51` s at `10` lines, `0.88` s at `30`, `1.06` s at `60` and `1.35` s at `120`; a *declining* catcher scales the same way, `0.34` s at `10` lines against `0.61` s at `120`, because the hit test walks the same leaves on the way in. ~~What scales is SwiftUI's layout and display-list pass over the leaves under a changed offset.~~ **How much of the total that is was not measured until the fix below was attempted, and it is about a third** — see the floor in the next section.
- **The mask, the rail and the count are free.** Measured on one build at `300` delivered events: whole `1.014` s, no fade `1.073`, no rail or count `0.945`, neither `0.937`, `.drawingGroup()` `1.006` — every one inside the others' noise. The `LinearGradient` rebuilt per offset costs nothing measurable, ~~and flattening the body into one raster before translating it buys nothing.~~ **The raster's half of that is true of the body this measured and false of the body beside it** — it was a sixty-line command, and a question's option cards are a different kind of leaf; see *A raster buys nothing over lines and halves the cost of cards* below (2026-09-07).

~~**What would actually buy it back** is §7's own answer, and it is not applied here: drawing the lines into a `CALayer` and translating that, as `SessionRowTextView` already does for the row's title, takes the leaves out of both the render pass and the hit test.~~ **It was built, and it is three times worse.** That paragraph is left struck rather than deleted because it was the obvious answer and it is wrong; what follows is the measurement that settles it.

### The layer-backed body was built, measured, and abandoned (2026-09-05)

The lines were moved onto `CALayer`s — one glyph raster per line, only the lines the viewport can reach ever rastered, translated rather than rebuilt. It draws **pixel-identically**: masking out the pixels that move on their own (the header's matrix indicator, the field's blinking caret) leaves **zero** changed pixels across eight staged forms — a command short and long, a document, a question with options, a multi-select, an option-less question, a read-only row and a wrapped indent. It is also **three times slower**.

Release, `600` wheel events at `8` ms over a staged `60`-line command, medians of three, every run confirming all `600` reached the catcher:

| The body under the offset | Per wheel event |
| --- | --- |
| `Color.clear` at the same height — no text at all | `1.19` ms |
| Sixty `Text` views, which is what ships | `1.74` ms |
| Sixty glyph layers | `5.20` ms |

**The floor is the finding.** A body with no text in it, scrolled the same way, costs `1.19` of the `1.74` — so the sixty `Text` views are **`0.55` ms**, and the other `1.19` is the scroll machinery itself: the `@State` write, `ScrollingRequestBody.body`, the clip, and the event's own delivery. The most a perfect text implementation could ever return here is about half a millisecond, and this one spends `3.46` ms to chase it.

Four candidate causes were each measured and each ruled out, which is what makes the verdict a property of the shape rather than of this attempt:

- **Not the rasterising.** Drawing every line up front, so no raster happens during a scroll at all, costs `4.86` ms against `5.19`.
- **Not SwiftUI diffing the `[String]`.** Behind a reference compared by identity it is unchanged.
- **Not the fade.** Dropping the `mask` entirely changes neither version — `1.76` both ways for `Text`, `5.12` against `5.19` for layers — so a SwiftUI mask over an AppKit-backed view is not the trap here that it was for `SessionRowText`.
- **Not the content.** The layer version plateaus at `5.16`–`5.20` from sixty lines to a hundred and twenty, where the `Text` version goes on climbing (`1.80` → `2.17`). What is left is the fixed cost of updating an `NSViewRepresentable` inside a subtree that moves on every event, and no raster strategy touches it.

**What would be left to try, and why it is not being tried.** The remaining `1.19` ms floor is SwiftUI being told about the scroll at all. Removing it means the wheel writing straight to the layers and `@State` never moving — which means the fade, the rail and §4.4's count all become layer-drawn too, and the options, which take clicks, need a path of their own. That is a rewrite of a surface with its own design rules for about `1.4` ms during a gesture a person holds for a second or two. The measurement is recorded so nobody has to take this route twice; the `Text` views stay.

### The open row was measuring its own text on every read (2026-09-07)

Everything above is about a *gesture* on an open row. This is about the row simply being open, and it was the larger number by an order of magnitude: **opening an approval detail cost `0.66` s of CPU, one option click `0.29` s, and one keystroke `0.26` s** — Release, a four-option question, `proc_pid_rusage` diffed either side of the act.

`MonitorStore.openRowBody` was a computed property that ran `RequestBodyLayout.laidOut` — the whole body's text measurement, `14 ms` for that question — **on every read**. The panel is made of reads. The row's body, its position, its header and its accessibility sentence; the three heights the window is sized by (`openRowHeight`, `sessionListContentHeight`, `sessionViewportHeight`, and `expandedContentHeight` over them); `canSubmitCurrentAnswer`, on each of the three places `AnswerRow` reads it. Counted with a probe in `laidOut` on a Release build:

| The act | Full body layouts | CPU |
| --- | --- | --- |
| Open the row, first time after launch | `48` | `0.66` s |
| One option click | `26` | `0.29` s |
| One keystroke, the first | `22` | `0.26` s |
| Nineteen more keystrokes | `19` | `0.35` s |
| Scroll the panel past it, `120` wheel events | `24` | `0.44` s |
| The same scroll with no row open | `0` | `0.16` s |

Three separate mistakes, each fixed on its own terms.

**One layout per change, not one per read.** `openRowBody` now keeps the last layout beside the three things it is a function of — the request, the question index, the expanded descriptions — and re-runs only when one of them differs. Keyed on its own inputs rather than invalidated by hand: the width is a constant, the three inputs are the whole of it, and a cache that re-derives its key cannot be left stale by a route somebody forgot, which four scattered `didSet`s would be. A hit costs a string compare against storage the row is still holding, so it is a pointer test. `MonitorStore.bodyLayoutCount` exists for the test that pins this and nothing else: a cached layout and a recomputed one are the same value and differ only in what they cost.

**A keystroke was laying out a body to throw it away.** `AnswerGround.where(_:showing:carriesText:)` declared a `showing: RequestBodyLayout?` parameter and spelled it `_`. It never read one — the ground is decided by the shape the request asks in, which `answerRow(showing:)` answers without measuring a character — and `refreshAnswerGround()` filled it in with `openRowBody` on **every edit**. The parameter is gone.

**And the wrap itself was quadratic.** `AgentRequestReading.fit` measured every prefix of a line in turn: one `NSString.size(withAttributes:)` per character, over a string a character longer each time, at about `24 µs` a call. Width only grows with length, so the first length that overflows can be bracketed in `log n` measurements instead of `n`. The break is unchanged — the lines are byte-identical across `910` cases spanning five fonts, seven widths, both indent modes and a corpus of Unicode, emoji, tabs, URLs, unbreakable tokens and degenerate widths — and the question body's layout falls from `14.1` ms to `2.8` ms. `aWrappedLineIsTheLongestOneThatFitsAndNeverOverflows` pins the property that has to survive: the line fits, and one more character of what follows would not have.

### A raster buys nothing over lines and halves the cost of cards (2026-09-07)

With the layouts gone, scrolling a panel with an open question still cost `40%` of a core against `18%` for the same panel with the row shut, and sweeping the body itself `33%`. That residue is the leaves — which the 2026-09-05 measurement above already located, when it found `RequestBodyView.body` running twice per run while the cost scaled with the line count. `.drawingGroup()` on the body, *before* the offset, composites it into an image once and makes the scroll a layer transform.

That measurement said this buys nothing. **It was right about what it measured and wrong as a general statement**, and the difference is what is in the body. Release, `300` wheel events at `8` ms, one binary either way, two runs each:

| The open body | Plain | `.drawingGroup()` |
| --- | --- | --- |
| Sixty-line command — the 2026-09-05 shape | `2.20` ms/event | `2.07` ms/event |
| Four-option question | `2.32` ms/event | `1.12` ms/event |
| `1,529`-line document, the `128 KB` cap | `5.5` ms/event | `5.1` ms/event |

A stack of `Text` views rasterises to roughly what it costs to draw. An option card is a `Button` around a `RoundedRectangle` fill, a `strokeBorder` overlay and two nested stacks, and four of those are what the raster removes from every frame. So the rule is not "flattening buys nothing" but **flattening buys what the leaves cost, and a card is an expensive leaf**.

Verified rather than assumed, because §7 rule 12 is the class of change this is: pixel-identical against the same panel without it — `227` of `1.36M` pixels differing by more than `8/255`, every one of them option-card antialiasing, and `0` on the argument-field form; the same accessibility tree element for element, options still `AXButton`s carrying *Selected* / *Not selected*; options still clickable and single-select still moving the tick; hover across the cards unchanged at `11%`. On a body far past the viewport it costs `16 MB` of resident memory and buys nothing, which is the right way round — nothing is rasterised that the row is not drawing.

**What this leaves.** Scrolling a panel with an open approval now costs what scrolling it with the row shut costs, and the four acts stand at:

| The act | Before | After |
| --- | --- | --- |
| Open the row, first time after launch | `0.66` s | `0.16` s |
| One option click | `0.29` s | `0.04` s |
| One keystroke, the first | `0.26` s | `0.007` s |
| Nineteen more keystrokes | `0.35` s | `0.02` s |
| Scroll the panel past it, `120` events | `0.44` s | `0.17` s |
| Sustained sweep of that list | `40%` of a core | `15%` |
| — the same sweep with no row open | `18%` | `18%` |

~~**A long body is still expensive and this did not touch it.**~~ **It does now** — see below. `RequestBodyView` built a `Text` for every line the payload wrapped to rather than for the lines the `140`–`300` pt viewport can show.

### A body draws the lines near the viewport, not all of them (2026-09-07)

The hook boundary accepts `128 KB` (`answer-in-notch.md` §12.2) and the viewport shows eight lines, so a plan can arrive as fifteen hundred wrapped lines behind it — every one a drawn `Text`. Release, the same rig as above:

| The open body | Open it | `240` wheel events | Resident |
| --- | --- | --- | --- |
| `1,529`-line plan, before | `0.80` s | `2.09` s | `158` MB |
| `1,529`-line plan, after | `0.55` s | `0.51` s | `119` MB |
| Long argument fields, before | `0.46` s | `1.96` s | `168` MB |
| Long argument fields, after | `0.26` s | `0.49` s | `119` MB |
| Four-option question | `0.17` s | `0.31` s | unchanged either way |
| Sixty-line command | `0.16` s | `0.52` s | unchanged either way |

**The height does not change, which is what makes it invisible.** What stands in for the lines outside the window is their own height, so the body is exactly as tall as `contentHeight` either way — and the wheel's travel, the rail and §4.4's count are all measured from that. Nothing downstream knows this happens, and `RequestBodyView(layout:)` with no window still draws every line, which is what the tests pinning drawn height against measured height ask for.

**The window is a slab that moves in steps, and that is the whole of the design.** The viewport is the obvious window and it was measured being the wrong one: it changes every time the body moves by a line, and each change rebuilds the body and re-rasterises the `.drawingGroup()` above. With the viewport as the window, a four-option question went from `0.32` s to `0.50` s over `240` events and a sixty-line command from `0.55` to `0.67` — a regression on the common body to buy the rare one, which is the wrong way round. The slab is sixteen viewports snapped to eight, so:

- **A body shorter than the slab is not windowed at all.** Every question, and every command of a hundred-odd lines, draws exactly what it drew before, through the same view — confirmed by `RequestBodyView.body` still running twice over a whole sweep, as it did before the change.
- **A long one re-windows about once per eight viewports of travel**, which over a sustained sweep is once or twice rather than two hundred and sixty times.
- **The viewport is always well inside the slab**, so no offset can look at ground the body did not draw. `theDrawnSlabAlwaysContainsTheViewport` sweeps every offset a body can reach, on both viewport heights, for bodies either side of the slab.

Verified the same way the raster was: pixel-identical on all four body shapes at the top of the body, mid-scroll, clamped at the end, and walking back up across a slab boundary — `0` differing pixels every time. `aWindowedBodyDrawsWhatTheWholeOneDrewAndStandsAsTall` pins that in the suite by hosting both forms and comparing the viewport's own pixels.

**Every argument field is still built and only its lines are windowed**, because a field is one accessibility element carrying its whole label and value and takes those from the argument rather than from the drawn lines. Field counts are bounded by a tool's signature; line counts are bounded only by the payload.

**The accessibility trade, stated rather than buried.** The row's own label carries the complete body — unchanged at `123,844` characters on the `1,529`-line plan — so the whole request is still read out. What leaves the tree is a per-*wrapped-line* element for lines outside the slab: `1,582` elements became `112`, around wherever the body is scrolled. Those were fragments of wraps rather than sentences, and with §9.3's arrows declined the wheel is the only thing that moves the body, so a reader navigating by them could already reach only what a pointer had scrolled to.

### `proc_pid_rusage` reports mach ticks, not nanoseconds

`ri_user_time` and `ri_system_time` are documented in nanoseconds and are not, on Apple Silicon. On this machine the timebase is `125/3`, so the raw figures read **41.7× low**: `0.037` "seconds" against `ps -o time`'s `1.54`. Multiply by `mach_timebase_info`'s `numer/denom` and the two agree exactly. It is worth the conversion rather than shelling out to `ps` — `ps` has `10` ms resolution and this has the timebase's own — but an unconverted reading looks like a resounding "there is no cost here", which is the same false conclusion the `%cpu` trap above produces by a different route.

### Taking the keyboard means taking the application (2026-09-05)

`OverlayPanel` is a `.nonactivatingPanel`, and that was read as *this panel can hold the keyboard while the person's editor stays frontmost*. It cannot. With a row open the panel **is** `NSApp.keyWindow` and the field **is** its first responder — and every keystroke still went to whichever application was in front, while the global monitor watching for a click outside counted a click on the panel's own field as one and closed the row. An application that is not active does not receive keys, whatever its windows believe.

So latching activates this app for as long as a row is open and activates the previous application again when the row closes ([ADR 0020](adr/0020-the-panel-takes-the-keyboard-by-activating.md)). Two flags were in the way and each produced a symptom that looked like the same bug: `becomesKeyOnlyIfNeeded`, which makes AppKit refuse `makeKeyAndOrderFront` outright, and an `NSTextView` built with a `nil` text container, which takes the caret, receives `keyDown` and inserts nothing.

### The cursor is the same rule, and hover cannot pay that price (2026-09-06)

**Tracking scopes are separate (2026-09-09).** `PointingHandView` uses one
`.activeAlways` area for entry, exit and movement, and one `.activeInKeyWindow`
area for `.cursorUpdate`. AppKit explicitly excludes `.cursorUpdate` from
`.activeAlways`; the earlier combined area relied on an unsupported pairing.
Movement inside the background area reasserts the hand if another cursor
assignment followed entry. The key-window area participates in AppKit's cursor
pass above scroll-view cursor rectangles. Both areas follow the visible rect,
are replaced on layout, and pass clicks through. There is no timer or activation.
The tracking-scope and competing-arrow tests pin these two responsibilities.

A bounded native probe exercised the actual `NotchOverlayView` in a
non-activating panel, entering both About controls from all four sides, first
with the app inactive and the panel non-key, then with both active/key. Entry,
movement and exit had the expected cursor state in all 16 crossings. The same
probe also passed with the old tracking configuration, so it did not isolate
the reported bottom-entry failure. The correction removes the unsupported
scope pairing and adds recovery from a competing arrow; the regression test
pins that recovery independently of reproducing the original event ordering.


**`NSCursor.set()` is ignored outside the active application**, exactly as keys are. Measured on a panel built like `OverlayPanel` — non-activating, level `25`, accessory app: `mouseEntered` lands on time, `set()` returns, and the pointer in the next screenshot is unchanged; activate the application and the same call takes **with the panel still not key**, so the gate is activation rather than key status. It is why `PointingHandCursor` was right on every control inside an open row — those are latched, and latching activates — and wrong on the mark of a closed row, where the panel only ever hovers. Verifying the fixed half is what let the broken half ship.

The answer above is not available here. Hover browses (`answer-in-notch.md` §9.4), and taking the keyboard off the application the person is typing in to change a pointer image is not a trade this surface makes. So `BackgroundCursor` asks the window server's connection for the right to set a cursor from the background instead, and asks for nothing else: no activation, no key status, no keyboard. **The property is private** — `CGSSetConnectionProperty(_:_:"SetsCursorInBackground":_:)`, resolved through `dlsym` so a macOS that withdraws it answers `false` and the panel returns to the arrow it drew before, rather than failing to launch. `theWindowServerLetsAnInactiveApplicationSetTheCursor()` is what makes that withdrawal a failing suite instead of a silence, because nothing else about the panel would change.

### What the tests cannot protect

`NotchStatusMatrix` and the two layer-backed labels have tests asserting they are still driven by `CAAnimation` and still have their masks, so reverting them to SwiftUI fails to compile. But **adding a new continuous animation elsewhere in the panel is caught by nothing** — that dimension is held only by this section and by the comments on the views.

### Driving the panel to check it, and the two things that lie while you do

`answer-in-notch.md` §16's interaction half is verified by staging a request in a copy of the tree and driving real `CGEvent`s at a Release build. Two artefacts of that setup produce confident, wrong answers, and both cost an afternoon before being recognised:

- **A fixture store built with `preferences: nil` has not been through onboarding**, so the first-run `Window` scene is presented and `applicationDidFinishLaunching` activates the app for it. That window then holds key status: `NSApp.keyWindow` is `SwiftUI.AppKitWindow` rather than `OverlayPanel`, every keystroke goes to it, and an open row's field never sees one. It reads exactly like latching being broken. Give the harness a `UserDefaults(suiteName:)` of its own with `hasCompletedOnboarding` set, and the panel takes the keyboard six times out of six.
- **A command-line driver that touches AppKit becomes an application.** `NSWorkspace`, `NSRunningApplication` and the rest register the process, and it takes the foreground from whatever was there — so the tool measuring which application is frontmost is the reason the answer keeps changing. `NSApplication.shared.setActivationPolicy(.prohibited)` at the top of the driver stops it.

And a positive rule that falls out of both: **ask the app, not the workspace.** `NSRunningApplication.isActive` reported `true` for this app while `menuBarOwningApplication` named another and keystrokes went elsewhere. The reading that never disagreed with what actually happened is `NSApp.keyWindow` and its `firstResponder`, read from inside the process.

**A gesture aimed at a time window has to be aimed.** §6.3 holds an affirmative unarmed for `PanelMotion.duration`, which is `200` ms; a driver that settles the pointer for `350` ms before pressing, or waits `700` ms between keystrokes, will find every gesture accepted and conclude the gate does not exist. Both halves of it are real when the gesture lands at `40`–`50` ms.

**Nor can they protect where SwiftUI's hit test lands**, which is what let a wheel catcher sit behind the body it was meant to scroll for an entire release. `theWheelCatcherClaimsOnlyTheWheelAndOnlyWithTravel()` pins what the view answers when AppKit asks, and `theWheelCatcherCoversTheBodyItScrolls()` pins that there is a view of the right size for AppKit to ask about — neither can assert that AppKit asks *it* rather than the container above it, because that ordering is decided inside SwiftUI at dispatch time. The only thing that catches it is driving a real wheel event at a Release build and looking, which is what this section's harness is for.

Separately, `SearchlightLabel`'s font and `PanelMetrics.statusLabelFont` are two independent declarations of the same `NSFont`: change one and the drawn label no longer matches the panel width reserved for it.

### The arrival cost of hook events (after CC-015)

`MessageDisplay` raised Claude Code's event rate from once per tool call to **3.4 times a second while a Turn is speaking**, so this path was re-measured. Release build, real machine, burst method (differencing cumulative CPU time, "how to measure" above):

| Scenario | Result |
| --- | --- |
| Idle (no events) | `%cpu` median 0.0–0.1, RSS about 100 MB |
| The measured cadence (a delta every 0.29 s for 60 s) | `%cpu` mean 0.88, +0.65 over idle; RSS flat |
| 5000 `MessageDisplay` bursts × 3 rounds | median **2.06 ms/event** |
| The same 5000, discarded at the cwd check | median **2.06 ms/event** |
| The same 5000, with no cwd in the payload | median **2.07 ms/event** |
| 64 sessions × 10 × 60 KB deltas (about 38 MB of text) | the same 1.75 ms/event, RSS 140.5 → 140.8 MB |
| The event directory after about 36,000 events | **0 files**; the whole support directory 24 KB |

The three loads fall inside each other's noise, so the conclusion is unambiguous: **the per-event cost is entirely NWConnection setup and teardown plus HTTP parsing, and the preview path is not measurable.** That cost was already being paid for 11 other events before CC-015; this only raised how often it is paid. Reducing it further means changing the transport (reusing connections, say), and the connection is initiated by Claude Code's client rather than decided by this app.

**The connection is the reply channel, on one event per product.** ADR 0013 made the helper silent on both streams; [ADR 0019](adr/0019-the-helper-answers-on-the-stream-adr-0013-silenced.md) opens stdout on the one definition that registers a window a person can answer inside, and leaves it discarded at the call on every other. What makes that possible without a second connection or any framing is that Apple's `nc` half-closes on stdin EOF: the listener still reads to end-of-payload, and the same descriptor is still writable afterwards (measured 2026-09-05, along with `-w` being an idle deadline rather than a total one — `-w 3600` returned in 3.04 s against a server that answered after 3 s).

Measured against Claude Code 2.1.261 on the same day, this is not merely permitted by the schema but acted on: a decision written **6 s after** the product had already put its own dialogue on screen dismissed that dialogue and ran the tool, with nothing typed into the session; a `deny` carrying a `message` produced `Denied by PermissionRequest hook` and delivered the reason to the model as the tool's error. The product's dialogue appeared 0.32 s after the hook fired and did not wait for it, so **the notch is a second place to answer rather than the only one** — a person who walks to the product mid-decision finds the prompt there.

**The selection step was measured again after CR-030** (Release, same machine, medians): a 1.4 KB `PostToolUse` decodes whole in 5.0 µs and select-then-decode in 8.0–9.7 µs — 3 µs more per event, inside the 2.06 ms noise above; at 976 KB it is 416 µs → 89 µs, 4.7× faster; at 8.8 MB it is 3.6 ms → 5.2 ms, 1.4× slower (a byte scan past L2 becoming memory-bandwidth bound), and that size previously produced a whole dropped payload. A 16 MiB payload takes 55–75 ms from the client's first write to handover, still inside the helper's own `nc -w 1`.

The second-to-last row directly verifies that memory boundary: a 60 KB delta costs the same as a 120-byte one, because the folding function scans only the new delta and stops the moment the head is full — text length does not enter the cost. The last row directly verifies the "never write a file for a delta" design.

### The other dimension of event cost: how many Turns the reducer still holds (CR-Fable-008)

The table above measures cost **per event**, and that holds only while the reducer is empty. What genuinely grows over time is the other dimension: on every batch consumed, `MonitoringRepository` composes **every Turn it currently holds** into one string and sorts the lot (`renderedProjection()`, used to decide whether the rendered projection changed), and every refresh copies and sorts all Turns again (`snapshot()`). Both scale with what is held, not with rows on screen.

Measured in Release (`ENABLE_TESTABILITY=YES`, same machine, median of 300 samples, each entry carrying a 240-character — the maximum — prompt preview):

| Turns in the reducer | One event's drain through the refresh path | of which `snapshot()` |
| --- | --- | --- |
| 0 | 13.7 µs | 6.0 µs |
| 100 | 236.8 µs | 152.4 µs |
| 500 | 1.28 ms | 0.87 ms |
| 2000 | 5.26 ms | 3.62 ms |
| 5000 | 11.42 ms | 7.67 ms |

Cleanly linear: about **2.2 µs per held Turn per event**, of which the sorted snapshot is about 1.5 µs and the rendered projection about 0.7 µs. Against the previous section, the transport end is 2.06 ms/event — **so by 2000 entries the reducer alone is 2.5× more expensive than the transport**.

The problem is not those functions but that nothing on the Claude Code side ever **removed** an entry. Previews (`retainPreviews`) and the transcript cache (`transcripts.retain`) are both pruned by the live session list in the same refresh, while reducer entries were merely filtered out at row-building time by `guard let session = liveByID[turn.threadID]` — the screen was always right, and what grew was the work behind it. And it grows faster than "how many sessions a day": `/clear` and an in-session `/resume` swap the session id **in place**, so a long-lived CLI process leaves one dead entry per context clear. The memory itself is small (an estimated 100 KB–1 MB a week) but unbounded, and a menu-bar app's normal state is a month of uptime.

The fix calls the shared `removeThreads(notIn:snapshotStartedAt:)` in the same refresh against the same set, with the same guards as the Codex side: a reading that started earlier than some Turn's last event cannot see what that event reported and is not evidence the session is gone; plus a `newTurnReconciliationGrace` covering "the prompt hook arrived before the session record" — a desktop session is created by its first prompt. A third guard is unique to Claude Code: with presence `unknown`, **do not prune**. That is the state after `claude` fails consecutively to the trust ceiling, where the list is not an answered empty but nobody answering; rows are still not drawn, but nobody answering is not evidence for deleting state (`AGENTS.md` §6.2).

**One thing this change did not cover**: `MonitoredTurnState.retiredTurnIDs` still grows by one id per Turn on that thread. Its bound is that thread's own lifetime rather than the process's — a session still listed needs its entry anyway — so it is a separate problem and out of scope here.

### Launch CPU: today's tokens, first pass

For the first few seconds after launch `%cpu` spikes to around 100% and then falls to zero, all of it `ClaudeCodeTokenCounter.scan`'s first pass. `progress` is empty when the process starts, so **every transcript written today is read from byte 0** (42 MB on the measured machine); the 60-second re-scans afterwards read only newly appended bytes and are not in this cost bracket.

Sampling (`sample` stack capture) pointed at neither disk reading nor JSON decoding — decoding was 32 of 2821 hot samples — but at the newline-finding loop. The original was `for index in 0 ..< count where bytes[index] == UInt8(ascii: "\n")`: byte-by-byte iteration over an `UnsafeRawBufferPointer` is free only once the optimiser specialises it away, and unspecialised, every byte pays an `IndexingIterator.next()`, a `formIndex(after:)` protocol witness and a generic metadata lookup. Same 42 MB, same code, changing only the build configuration:

| Build | Original | With `memchr` |
| --- | --- | --- |
| `-Onone` | 3.08 s CPU | 0.08 s CPU |
| `-O` | 0.12 s CPU | 0.08 s CPU |

Whole-machine verification (Debug build, clean launch with the integration active): peak `%cpu` 68 → 99.8 → 84.8 with 3.87 s cumulative over 12 seconds; afterwards, a 21% peak and 0.70 s cumulative, the same as Release.

**This is recorded here not because "Debug should be fast"** — performance conclusions are always taken in Release (`AGENTS.md` §2) — but because **the cost of a hot path should not be decided by the build configuration**. A byte-by-byte Swift loop bets a factor of 26 on the optimiser, so the build local development runs all day carried a 3-second launch spike large enough to hide other things; `memchr` costs the same in both, and that dimension no longer relies on remembering to measure in Release. The method is still this section's: cumulative CPU differences for bursts, `sample` for hot spots.

The other half of the same rule is in the code: the per-line `"usage"` test uses a `static let` needle rather than constructing a `Data` per line.

### The ceiling on that pass: a budget, and why not "read less" (CC-009)

After `memchr` this path is no longer a spike, but it still has **no ceiling**: skipping by mtime, resuming from an offset and the `"usage"` pre-check all save constants, and what remains is proportional to how much Claude Code wrote today, which this app does not control. Re-measured 2026-08-20 (`-O`, 516 transcripts totalling 163 MB on the measured machine):

| Measured | Result |
| --- | --- |
| Disk read only, `F_NOCACHE` bypassing the page cache, all 163 MB | **0.16 s, about 1.0 GB/s** |
| The whole pipeline (`read(2)` + `memchr` + `"usage"` pre-check + decoding matched lines), all 163 MB | 0.37 s first pass, 0.26 s warm, about **440–630 MB/s** |
| Files written today (UTC), at 00:20 UTC | 72 totalling 4.3 MB |
| A whole UTC day's output (2026-08-20) | 334 files totalling 33.2 MB |

**A cold cache is not the problem** — the one link never measured in the issue, and measurement put disk reading at a sixth of the pipeline, with a cold read of every transcript ever taking 0.16 s. The real cost is the scan itself, so the ceiling is written in bytes and converted to time at 600 MB/s: **128 MiB per pass**, about 0.2 s of one core, roughly four times the heaviest measured day (33 MB). A pass exhausting the budget **stops where it is, keeps what it counted and returns "no figure"**, and the next pass resumes from the unfinished file — a file already scanned to its current size costs one `stat`, so a backlog drains within a few passes rather than restarting each time. The sum of half a transcript directory is a low number, and a low number looks like a quiet day, so none is given instead. The one exception is "a line longer than the whole budget": the budget applies between chunks, so a file that has not yet yielded a complete line keeps reading until it does, or that record would be re-read and missed on every pass. The overshoot is therefore one line, not one file.

The same change aligned the "today" line: the mtime comparison **uses UTC midnight rather than local calendar midnight**. Bucketing uses the record `timestamp`'s first ten characters (UTC), and the two lines differ by the zone offset, wrong in a different way in each direction: east of UTC (`+08`, say) the local day starts first, so files written in the UTC day's first eight hours are skipped while holding that day's records — a silent undercount; west of UTC the threshold is too loose, and measured at 00:20 UTC, local midnight admitted 277 files totalling 23.7 MB where UTC midnight admitted 72 totalling 4.3 MB.

Two cheaper routes were measured and rejected:

- **Searching backwards from the end for "where today starts"**, so a resumed old session need not re-read its history. The saving is measurable but small: on 2026-08-20, only 3.9 MB of the 33.2 MB (12%) sat before that day's first record. And it needs records to be time-ordered, which is **measurably false**: 160 of 517 transcripts have a timestamp going backwards, the largest by 4889 seconds (81 minutes), and 2 files go backwards even in their date prefix. Trading 12% for a silent undercount is the wrong direction.
- **Persisting `(size, offset, tokens)` to disk**, so a restart need not redo it. Redoing costs "how much was written today", about 55 ms on the heaviest day's 33 MB, and spending a state file, a set of invalidation rules and a new failure mode ("a stale offset undercounts") to save 55 ms does not pay.

### Launch CPU (2): a window nobody asked for, and two self-inflicted subprocesses

After that fix, launch was still a spike. Re-measured 2026-08-20 (Release, sampling cumulative CPU differences every 0.2 s after `open -a`, hot spots via `xctrace`'s Time Profiler under `--launch`): **0.62 s for this process, peaking at about 55%–86%**, and in that same second it started three subprocesses — `codex app-server` (about 0.4 s), `claude agents --json` (about 0.4 s) and `claude -p /usage` (about 0.9 s) — putting the machine's peak around 120%.

**Not one line of that 0.62 s is this app's code.** Classifying 533 one-millisecond samples by self time: `vImage` 84, `libswiftCore` 67, `libobjc` 60, `CoreGraphics` 40, and this app's binary 2 in total. By call tree the money goes to three places, all with one origin:

| Location | Samples | What it is |
| --- | --- | --- |
| `NSPersistentUIRestorer` → `AppWindowsController.makeMainWindow` | 73 | SwiftUI **building and laying out the settings window** at launch |
| `_NSTrackingAreaAKManager setCursorForMouseLocation:` → `NSCursor set` → `_AXFMouseCursorGenerator` | 89 (main thread) + 60 (`vImage` convolution on a worker) | The tracking-area pass the new window causes, landing in the system regenerating the pointer image. This bracket is only this expensive when **the user has customised their pointer** (`com.apple.universalaccess`'s `cursorIsCustomized = 1`), but what triggers it is this app opening a second window |
| `AG::Graph::UpdateStack::update` and friends | 31 | That window's view tree evaluating for the first time |

That is: a permanent notch component putting **the entire settings window** on screen at every launch, and paying half of launch CPU for it. Nothing required it — the same view is one `⌘,` away.

The changes and two measurements:

- **`WindowGroup` became `Window` with `defaultLaunchBehavior(.suppressed)`.** A `WindowGroup` opens a window at every launch, and **`defaultLaunchBehavior(.suppressed)` has no effect on the first group** (measured on macOS 26.5: both `.suppressed` and `.presented` hard-coded on a `WindowGroup` still open a window, and both take effect once it is a `Window`). Onboarding still has to appear uninvited, so launch behaviour is chosen by `hasCompletedOnboarding`. Result: **0.62 s → 0.32 s, peak `%cpu` 55 → 33**, with only the notch component's window on screen after launch.
- **This app's own usage read no longer invalidates the session list.** `claude -p "/usage"` is a real session that writes and deletes a `~/.claude/sessions/<pid>.json` on the way in and out; both edges told the registry the list was wrong, so every reading bought another `claude agents --json` — a Node process, about 0.4 s. Measured, the one 3.5 s after launch was exactly this. The directory edge now compares **entry names** first: if every name appearing or disappearing belongs to the `claude` this app started (the pid coming from its own `Process`, read from no file), it does not invalidate. Everything else — names unchanged, names unrecognised, directory unreadable — invalidates as before. Measured: that surplus `claude` after launch is gone.

One cost to record: moving the main window from `WindowGroup` to `Window(id: "main")` changes the key AppKit remembers the window position under, so the user's last placement is lost once.

### Steady-state CPU: a process tree re-run every 30–60 seconds (CR-Fable-002)

The two above are **launch spikes**. The largest steady-state item is something else, and it is not in this app's process, so `ps %cpu` on this app can never see it: `claude agents --json` was started every 30–60 seconds for the life of the process — on an idle machine, with no Claude Code session open and the screen locked.

The cause is §2's: the registry's freshness (30 seconds) is shorter than this process's slowest wake-up interval (the 60-second heartbeat; 30 seconds from the account read while the Codex integration runs), so the window has always expired by the time a wake-up lands, and "re-read on freshness" is equivalent to "sample unconditionally at the wake-up cadence".

It is not cheap. Measured here (`/usr/bin/time -p`, user + sys, including the reaped child; working directory `/`, as when this app starts subprocesses): **0.26–0.33 s CPU per run**, three runs at 0.33 / 0.27 / 0.26. And that command **starts the user's MCP servers** — the only reason `ClaudeCodeSessionRegistry.arraySpans` exists is to withstand what those servers write to its stdout — so each run is a process tree rather than a process, growing with the MCP configuration. At one run per 30–60 seconds that is **0.4%–1.1% of a core, forever**, plus fork/exec and Node's paging keeping the whole coalition out of deep idle.

What it buys, almost every time, is a repetition of "the empty list is still empty". And every route from empty to non-empty reports itself anyway: a session starting has its `~/.claude/sessions/<pid>.json` **created**, and creation fires a directory event (an in-place rewrite does not, `tech-design.md` §15.1), while a hook event naming a session absent from the list is itself evidence that session exists. So **a list that answered empty is held**, and every other case still follows the clock: a non-empty list is re-read on freshness (a `SIGKILL`ed session leaves its record and produces no edge, and only that command's own `pid` + `procStart` validation sees the ghost), a failed attempt is retried on freshness (which is the cadence `trustCeiling` counts three failures on), and edges never answer sooner than `edgeFloor`. The steady-state launch count on an idle machine is therefore **zero**.

Two costs to record. First, this path now genuinely rests on `~/.claude/sessions`'s directory edges rather than treating them as a latency optimisation — if the watcher fails silently, a session that is open but has never submitted a prompt will not light its mark on the notch until its first submission (whose hook event invalidates the list). Second, the quota read was not in scope then: `claude -p "/usage"` ran every 5 minutes and this section recorded it as "about 0.9 s" — **that number was wrong**, and re-measured in Release 2026-08-25 it is 2.53 s of CPU, next section.

### The real steady-state bill: the half outside the process (2026-08-26)

The previous section already wrote "it is not in this app's process, so `ps %cpu` on this app can never see it". This one finishes measuring that sentence, prompted by a twelve-hour Release run on a real machine: the process's own numbers were all normal — `%CPU` habitually under 1%, CPU time 4 minutes 45 seconds, 7 threads, 280 ports, 58.4 MB resident — while Activity Monitor's "average energy impact over the last 12 hours" read **214.42**. The two do not reconcile: as a rate, 214 is two cores saturated for twelve hours, while 4 minutes 45 seconds is 0.66%.

They do not reconcile because those two columns ask different questions. **The energy column aggregates by *application* and folds subprocesses under the application's row** — measured, expanding this app's row shows `codex` beneath it. More precisely it aggregates by resource coalition: this app and every subprocess it starts share one (measured `res=77602` for `codex app-server`, `claude agents --json` and `claude -p "/usage"` alike). Thread, port, CPU-time and context-switch figures count **this one process** only. So well over half of this app's real cost never appears in its own process row.

The twelve-hour bill once measured (Release, 2026-08-25, this machine; per-run subprocess costs from `/usr/bin/time -l`, counts derived from observed intervals):

| Work | Measured interval | Cost per run | 12-hour CPU |
| --- | --- | --- | --- |
| This app's own process | — | — | **285 s** |
| ↳ of which the menu-bar poll | 4 Hz | 0.53–2.0 ms | ~115–345 s (`sample` measured it at 41% of the process) |
| ↳ of which the transcript stat walk | 60 s | 27.3 ms | ~24 s |
| `claude agents --json` | 33–55 s | 0.29 s CPU / 187 MB peak | **~260–420 s** |
| `claude -p "/usage"` | 5 min 4 s | 2.53 s CPU / 375 MB peak | **~360 s** |
| `codex app-server` (resident) | — | 0.24% of a core | **~103 s** |

The `/usage` interval is not extrapolated: every read leaves a transcript in `~/.claude/projects/…-Notchline-agents-claudeCode-usage/` (`ClaudeCodeUsageTranscripts` explains why they are not deleted), and this machine's 418 of them are timestamped exactly 5 minutes 4 seconds apart.

The conclusion is that **about seven-tenths of the cost is in subprocesses**, in the worst possible shape: over a thousand Node launches in twelve hours, each allocating and releasing 190–375 MB. Process launch is the most expensive action per unit of work on macOS (dyld, JIT warm-up, page faults), and it keeps the whole coalition out of deep idle — which is how an app with a negligible-looking CPU percentage ends up beside a browser in the energy column.

Four changes, by benefit (each one's reasoning is in its own documentation comment):

1. **`claude -p "/usage"` widened from 5 minutes to 30 minutes**, with the trust ceiling moving 900 → 3600 seconds. 142 launches become 24.
2. **Listed sessions use a kernel liveness test** (`everyListedSessionIsStillAlive()`): while sessions are alive `claude agents --json` does not run at all, and the cost goes from a process tree every 30 seconds to a few `sysctl`s per refresh.
3. **Those two and the menu-bar poll all gain a screen gate**: with no display the first two do not run and the third parks its timer. A locked night goes from "runs anyway" to zero.
4. **The transcript walk uses `URL.resourceValues` with a batch prefetch during directory enumeration**: measured on this machine's 691 files, 27.3 ms → 3.2 ms per pass (8.5×), of which 3.2 ms is the directory enumeration itself and the stats are nearly free. Almost all of `attributesOfItem(atPath:)`'s time went to `_FileManagerImpl._extendedAttributes` — extended attributes and ACLs, not one byte of which is read here.

Re-measured on the real machine after the changes (Release, same machine, screen **awake** — the side where these gates benefit least; `top`, four 60-second windows):

| | Before | After |
| --- | --- | --- |
| `%CPU` | 0.5%–0.8% | **0.3%** |
| Idle wake-ups | about 0.37/s | **0** |
| Context switches | about 30/s | about 32/s |
| Mach syscalls | about 71/s | about 77/s |
| `claude` subprocesses | about 10 in 7 minutes | **0 in 7 minutes** |

Idle wake-ups reaching zero is the direct result of moving the test off the main actor — the main run loop is no longer woken every 250 ms to answer "unchanged". `claude` reaching zero is the liveness gate: this machine has live Claude Code sessions, and while they are alive that command need not run at all. The CPU move from 0.5%–0.8% to 0.3% includes the transcript walk's 24 ms, the parent-side cost of the processes no longer forked (`NSTask`, pipes, reaping), and those main-actor wake-ups. Mach traffic rising slightly is the screen gate's own round trip, sampled at 1 Hz; at 4 Hz it was 107/s, and that version was not kept.

The table **does not** measure the screen gate's real half — through a locked night every one of those items is zero, and this machine was in use while being measured.

Change 4 also holds down something that grows by itself: change 1's transcripts add a couple of hundred files a day, and they land in exactly the set that was being stat-ed every 60 seconds.

What remains: `codex app-server` is a resident subprocess untouched by this work, and the menu-bar poll still pays a little for its own gate reading **while there is a screen** (107 µs at about 1 Hz, 0.011% of a core) in exchange for zero when there is not — the arithmetic is in §7.

### Another pointless steady-state read: a read-state nobody will use (CR-Fable-041)

Claude Desktop's read-state reading (`ClaudeCodeDesktopReadStateRepository.snapshot()`) **can only change whether a terminal row stays** — `TerminalUnreadMembershipGate` passes any non-terminal row straight through and drops its entry. Yet `rowsStillWorthShowing` fetched it before looking at `rows`, so a list entirely of Running rows still walked the whole account tree, Desktop's focus log, the activation record and a terminal `stat` per row on every refresh, only to conclude "show them all". With a terminal row present, refresh is at 1 Hz (that is the re-check cadence), and under CR-Fable-036's `tmux`-pinned case it stayed there. **Rows the user dismissed do not count towards this test** (CR-Fable-003): they have left the list at the user's request and no reading will change that, so a list whose only terminal row is the one just dismissed skips the whole read, exactly like a list of Running rows.

Measured in Release (`ENABLE_TESTABILITY=YES`, same machine, a synthetic account tree, steady-state method):

| Records | One fully cached pass | One cold pass (every file opened) |
| --- | --- | --- |
| 41 (this machine's scale) | 0.28 ms | 3.2–4.1 ms |
| 512 (the cap) | 2.40 ms | 39–41 ms |

The pass is now wrapped in `autoreleasepool` as a whole, like `ClaudeCodeTokenCounter.todayTokens()`. **In steady state the difference is unmeasurable** — since directory names and three numbers come back in one `getattrlistbulk` (`tech-design.md` §1.5 rule 3), a cached pass no longer calls `attributesOfItem` per file and produces almost no bridged objects; the difference is entirely in **the pass that opened records**:

| Scenario | Resident growth without a pool | With a pool |
| --- | --- | --- |
| 512 records, one cold pass | +176–192 KB | 0 KB |
| A 41-record tree, 8 rewritten per pass, 200 passes | +288 KB | +16 KB |

They cost the same in time (0.278 against 0.278 ms; 2.40 against 2.40 ms), so the pool is free. **What actually saves the cost is the other half**: with no terminal row that whole pass does not run, and that is the list's most common shape.

One piece of bookkeeping that would go wrong if written elsewhere: the skipped pass must still clear screen membership and gate entries, because the original pass cleared them row by row for exactly such a list; and the test comes from `TerminalUnreadMembershipGate.isTerminal` rather than a second in-place `== .completed`, so that a future widening of the gate's definition cannot silently miss a case here.

### The third pointless steady-state read: a membership set nobody will read (CR-Fable-023)

The Codex version of the same rule, and the most expensive per run. With no post-launch hook observation yet established, the service still paginated every unarchived thread every 30 seconds and rebuilt the whole of `threadRecords` — while by product rule (`PRD.md` §3) that branch never produces a row, so that membership set has no consumer. To the user: with the Codex integration installed, working in Claude Code all day and never opening Codex Desktop, the `codex app-server` subprocess is resident anyway and is asked every 30 seconds to paginate this person's entire history, to answer whether the transport can perform one read.

Measured here (2026-08-25, a real `~/.codex`, Codex Desktop's built-in `codex` binary, 47 unarchived threads; burst method: `ps -o time` differences across calls, with the decoding side differenced by `getrusage` after compiling with `-O`):

| Shape | Response bytes | Subprocess CPU/run | This app's decoding CPU/run |
| --- | --- | --- | --- |
| Full pagination (`limit: 100`, one page here) | 61 KB | 0.14–0.16 s | 2.30 ms |
| One-page confirmation (`limit: 1`) | 1.1 KB | 0.01–0.02 s | 0.05 ms |

At one run per 30 seconds the subprocess side is **0.5% of a core, forever**, growing linearly with history (47 threads need one page here; the pagination threshold is 100); with the one-page confirmation it is 0.05%. This app's own half falls from 2.30 ms to 0.05 ms, unmeasurable in steady state, but it also stops rebuilding 47 `ThreadRecord`s every 30 seconds.

**The read that stays has a consumer, which is exactly the dividing line.** Whether the transport can answer a real read decides half of the collapsed `Connected` versus `Disconnected`, drawn on screen like the quota ring (and quota polling holds in this state for the same reason), while the membership set's consumers are all on the live-hook branch. So the confirming read stays but is capped at one page, and its freshness (30 seconds) is a **ceiling rather than a cadence** — `nextRefreshDeadline()` reports nothing for it, and it rides the wake-up the quota read would cause anyway (as in CR-Fable-002). It also **does not write the membership cache**: one page is not a membership set, and pairing a truncated `listedThreadIDs` with that moment's timestamp would make the next live-hook refresh retire every Turn outside that page as "not in the list".

## 7. Architectural constraints that keep this clean and neat

1. **One orchestration centre per product**: decisions spanning a product's data sources are concentrated in its Provider — `ProductMonitoringRuntime`, composed by `HookProductProvider` for Hooks or directly by another lifecycle source, with the product's evidence handed in as sources that decide nothing across one another, and `LiveCodexMonitorService` for Codex, whose App Server is a second lifecycle no other product has ([`tiered-support.md`](technical-explorations/multi-product-provider-architecture/tiered-support.md) §5.4, P4). The UI, the file adapters and the transport do not assemble state from each other.
2. **One Turn reducer**: hook events are decoded and projected at their boundary and typed observations enter only `MonitoringRepository`; replay, reordering, duplication and exact-identity rules are not scattered into the view layer. A second source may **retire** a Turn, but only inside this actor, behind an ordering guard, and it may **never open, name or describe** one: the four places are the shared `removeThreads(notIn:snapshotStartedAt:)`, the Codex side's `discardTurns()`, and `endTurnsForStoppedSessions(_:)` and `endInterruptedTurns(_:)`, the two `end…` being [ADR 0011](adr/0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md). `endInterruptedTurns(_:)` is fed by **both** products and that is the point: a Claude Code desktop session's interrupt record and a Codex rollout's `turn_aborted` say the same sentence — *this Turn is over* — and differ only in how they prove it, so they share one rule rather than each getting one. It is also the one that may retire more than a status: evidence that proves the Turn's subagents were cut off from it (`TurnInterruption.orphansSubagents`, Codex's stop) empties that Turn's subagent set as well — still retiring only, still inside this actor, still held to the Turn the record names, and still defaulting to changing nothing for every other reading. `discardTurns()` reads neither an event nor a list but **the producer itself**: a Turn is an assertion about what a process is doing right now, so a caller who knows that process is gone knows the assertion cannot still be true and can never be disproven — the event that would end it was the dead process's to send. It does not pick a Turn to end but retires every Turn the reducer then holds, so its ordering guard is not a comparison of event moments but a **position relative to the drain**: a changed PID retires before the drain, so the new process's events land in an emptied reducer; and when no process can be found it retires again after the drain, because a dying process's helper may still be in flight and that payload is no better vouched for than the Turn it belongs to (CR-Fable-007). The first of the four was once called only by the Codex side, so the Claude Code side never deleted a reducer entry (CR-Fable-008, cost in §6); both sides now call it once each in the **same** refresh that prunes previews and caches, on the same test — a list may end a Turn only when it can genuinely speak for it. This rule used to read "must not carry Turn identity", which wrote the character of the only evidence then available into the rule: the session-status reading genuinely holds no Turn identity. A desktop session's interrupt record does — it is the hook's `prompt_id` — and **evidence carrying identity is pinned tighter, not looser**: it can end only the Turn it names and does nothing when it names one the reducer does not hold, whereas an identity-free reading can only speak about "whichever is open now". So the rule became a constraint on capability (retire only) rather than on the shape of the evidence.
3. **One UI data contract**: layers above receive only `MonitorSnapshot`; availability, sessions, quota and diagnostic come from the same snapshot input.

   **The Recent queue does not weaken this, and it is worth saying why.** It looks like a second source — rows on the panel that are in no current snapshot — and it is not one: it is a fold over *successive* snapshots, holding rows this run itself drew and then watched leave, with the same standing as `dismissedSessionIDsByAgent` beside it. Nothing is queried, nothing is persisted, nothing is re-read at launch, and no row can enter it that did not arrive through this contract first. Its own arrow in is a transition rather than a difference: a row is archived because this app last saw its Turn terminal and its product was there to have read it — never because a list stopped mentioning it ([`expanded-panel-v2.md`](expanded-panel-v2.md) §2.5, §10.1).
4. **Private dependencies stop at the boundary**: `.codex-global-state.json`'s schema exists only inside the two read-only repositories, and the domain layer sees Project resolution and an unread set tagged with its authority.
5. **Recovery logic does not fabricate business state**: timeouts, liveness probes, caching and disconnect grace decide only whether to keep or rebuild a connection, and never guess Running, Approval, read or Project from a timer. (ADR 0012's rule 3 is not an exception: it reads three present states — which app holds the foreground, whether the display is awake, whether the screen is locked — none of which is a timer, and waiting itself removes no row. It genuinely overturns the same ADR's "transitions only" wording, with the reasoning and cost recorded there. The same ADR's terminal test is even less an exception: it reads a kernel record of an action that already happened, which waiting likewise does not produce — on a machine with nobody at it, that moment never moves.)
6. **The UI stays passive**: SwiftUI only displays and emits user intent; status parsing, navigation pre-flight, hook installation and file reading all have their own boundaries.
7. **Historical events carry no business semantics**: a history file proves only that a hook configuration once executed; the current session list comes only from a current runtime snapshot or from live events observed since this process started.
8. **"Busy" is not a reason to drop a request**: a boolean looks fine, but it is safe only when something is guaranteed to ask again, and that premise fails for edge-triggered signals.

   **But do not wrap every case in the abstraction either.** [`SingleFlightGate`](../Notchline/Notchline/SingleFlightGate.swift) is used only where there is no natural payload to serve as a dirty bit: store refresh (Recheck needs `hasCovered` to await its own request), and membership and metadata (a failure must keep the request across a backoff). The integration switch does **not** use it — `desiredIntegrationEnabled` is itself that pending record, and adding a gate would be a second copy of one fact, and two sources of truth are worse than one.

   The gate's failure semantics are deliberate: **a failed run never retries itself**. Letting it continue looks more thorough and is in fact an infinite retry loop with no backoff — that is how it was first written, measured at 1000 iterations without stopping; what stopped it then was a test in the caller, and the cancellation path went round the side of it. A failure only keeps the request, and when to retry is decided by the backoff and `nextRefreshDeadline`.
9. **When editing a user's file, parse rather than coerce**: change only the keys this app manages and preserve structures it cannot read; refuse wholesale, with an error, only when a key that must be written is already such a structure. Removal additionally does a full-document deep scan to confirm none of this app's commands survive in a shape it cannot change — if any does, deleting the helper is refused, or what is left is a dangling reference. The reasoning is CR-013: coercing something unrecognised into an empty dictionary replaces the user's file with our own.
10. **Text not touching disk is now purely a performance constraint**: `MessageDisplay` arrives up to three times a second, and a file per arrival is three disk writes plus three read-deletes a second, so it turns to memory before the write queue. The Codex-side socket is the historical version of the same sentence, when it honoured a product promise — that promise was deleted with PRD §7, and the socket remains only because it works. **This principle now answers only "is it worth writing", never "is it allowed"**: where text lives is an engineering judgement rather than a contract.
11. **Order-sensitive state does not enter an actor**: state machines requiring strict order, such as byte-stream framing, stay on the queue that already serialises them, and only self-contained, order-independent units are handed to an actor; conversely, CPU-heavy decoding does not stay on an actor, where it would block timeouts and connection management.
12. **Re-rendering is driven by layout change, not content change**: persistent motion in the overlay is drawn on CALayer, and so is the once-a-second readout; only "the drawn width changed" is published to SwiftUI (§6). The reasoning is that one SwiftUI publish costs the whole panel rather than the few characters that changed.

    **One reading is a stated exception: the Recent queue's age.** `recentReadAt` is published on a *content* change — `29m` becoming `30m` — rather than on a width change, so it costs a full overlay re-render. What bounds it is not the rule but the surface: it is published only while the panel is open **and** the queue unfolded, which is when that string is the thing on screen, and at most once per boundary any member crosses. Held open and unfolded that is one re-render a minute; shut, or folded, it is none at all, because neither state draws an age and the collapsed bar would be paying for a string nothing reads. The once-a-second readout could not be afforded this way and was moved to CALayer; a once-a-minute one on a hover surface can. **Unmeasured** — see §6.

## Question rendering boundary (2026-09-07)

Option titles and descriptions are measured in `RequestBodyLayout.Option` and those exact lines are drawn by `OptionRow`. The same value supplies card heights, viewport height and the fold counter — **and it is one value, laid out once per change**: `MonitorStore.openRowBody` caches it against the request, the question index and the expanded descriptions, because every one of those readers used to re-measure the whole body (2026-09-07, §6). The layout is of the whole body whatever is on screen; only the *drawing* is windowed to the lines near the viewport, and option cards are never windowed at all. Description disclosure changes layout but never answers the request. The existing wheel catcher translates the one shared body; options do not introduce nested scrollers or continuous animations. Its offset is clamped when a description changes and reset when the request or question changes.

`AnswerFieldView` continues to own per-character drawing. `MonitorStore` publishes a question-answer revision only when the draft crosses the trimmed-empty boundary, or when selection, disclosure or question state changes — and a keystroke that publishes nothing now also *measures* nothing, which it did not before: `AnswerGround.where` declared a laid-out body it never read, and every edit built one for it (2026-09-07, §6). The first boundary changes the affirmative's availability and whether selection emphasis is effective; ordinary typing within a non-empty draft does not publish a SwiftUI revision. Request identity is checked before retained draft state can be reused. These UI changes introduce no new provider, protocol parsing or non-public Codex dependency.


Package 5 Release burst measurement (`getrusage`, cumulative process CPU): 1,000 composition refresh/deadline cycles cost 0.40–0.88 ms with one parked reader (one actual read), and 3.21–3.46 ms with a reader due on every cycle (1,000 actual reads). The reader was in-memory; native I/O, full row construction and UI are excluded. This is not a pre/post comparison or idle-CPU measurement. The fixture checks that no stopped deadline remains. Sample details and the validation record are in [the handover](product-generalisation-plan.md#package-5-implementation-handover-2026-09-12).


## Generalisation conformance follow-up (2026-09-12)

Request identity now reaches the presentation contract as `AgentRequest.Identity`: repository epoch, Thread, native Turn, producer, request ID, optional native revision and occurrence UUID. Repeated identical observations and handle changes preserve the occurrence; changed bodies, native revisions and reopening receive a fresh one. Occurrences participate in the reducer's change projection, so an unchanged form name cannot hide a changed body. Standalone waits retain an optional tool-call association and never announce a fabricated call.

Scheduled source reads now run independently behind held evidence. `MonitoringSourceComposition` launches at most one read per source, excludes in-flight deadlines and emits a completion edge after storing the next deadline or failure backoff. Edges arriving during a read stay due. Stop cancels owned reads; old-generation completions cannot publish or restore deadlines. Sources still own protection of their cached values against cancellation-insensitive upstream completions. Start/stop hooks and ordinary held-value readers must remain short.

The follow-up's optimised source harness measured cumulative process CPU for 1,000 composition refresh/deadline cycles: **6.89–7.27 ms** with a parked reader and **18.65–20.91 ms** with one read due per cycle (three samples each). A simulated 200 ms read no longer held the refresh call. [The execution record](product-generalisation-plan.md#11-conformance-follow-up-2026-09-12) gives the baseline, compiler settings and limits; these are source-composition measurements, excluding native I/O and overlay rendering.

## Trae composition (2026-09-12)

`TraeProvider` composes one `ProductMonitoringRuntime` with `TraeSource` as lifecycle, session reading and row content. `TraeBridgeTransport` owns directory discovery, same-user socket validation, bounded newline framing and ordered `TraeEvidenceBoundary` processing on one serial queue. Only typed evidence/progress enters `MonitoringRepository`; no native schema reaches `MonitorSnapshot` consumers. There is no additional Turn reducer, answer channel or quota scheduler. `TraeReadEvidence` supplies per-candidate read judgements to the existing `TerminalUnreadRowFilter`.

The companion subscribes to Trae’s existing renderer stores and uses its product-owned client only to validate root identity, resolve the local Project and navigate. It never creates or disconnects an Aha client. Every lifecycle/request change is captured synchronously; adjacent content-only changes coalesce for 100 ms without overwriting a boundary. The queue holds at most 128 batches, the companion at most 512 observed Threads, and the transport at most 16 extension hosts. A batch has at most 128 changed Threads and 1 MiB; overflow fails closed. A 10-second transport/companion heartbeat and a 35-second lease manage connectivity only. They never infer business state. `MonitorStore` and the existing layer-backed readouts retain their rendering boundaries; this adds no continuous SwiftUI animation. See [the source and measurement record](trae-integration.md).


Trae read removal (2026-09-13) uses `TraeReadEvidence` and the shared membership gate. The optional per-window `read` query uses short-lived same-user sockets, leaving the lifecycle watch intact. At most 16 healthy peers are queried concurrently; unavailable peers contribute no proof. The transport rechecks peer generations and exact current Turn/message identity after the read. The renderer confirms the native focused main-window ID, document focus, selected terminal root and visible completion control. The source independently checks macOS foreground and screen availability. No Thread text is exported by this path, no historical Turn is admitted, and reading in another window does not transfer lifecycle ownership. The existing one-second user-wait recheck and two-second settling are reused; no new persistent DOM observer, animation or timer is introduced.

## Product connection evidence

Providers now own a `ProductConnectionMonitor` alongside their existing lifecycle sources. It single-flights bounded installation discovery, applies a presentation recovery interval and adds typed facts/notices to `AgentSnapshot`; it never supplies Turn evidence. `ProductConnectionPresentation` is the shared pure projection. Settings receives the latest connection reading even while the existing lifecycle stability gate retains rows. Saved monitoring intent is independent of native setup health. See [Product connection checks](product-connections.md) for invalidation, precedence and limitations.
