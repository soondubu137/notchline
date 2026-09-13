# Product generalisation implementation plan

## 1. Purpose and handover

This is an authorised implementation plan, dated 2026-09-12, following an audit of commit `32a64e2`. It is not a claim that the planned interfaces already exist. An implementer, including Claude Code, should be able to resume using this document and the repository without the original conversation.

The objective is to integrate another coding-agent product, and its supported higher-level capabilities, by adding boundary adapters and composition code. Reimplementing ordering, Turn reduction, request selection, answer drafts, dismissal or aggregation for each product is not acceptable. A new native protocol still needs an adapter; generalisation cannot manufacture evidence the product does not provide.

The user authorised documenting all five work packages and implementing work package 1, then explicitly requested **work package 5 next**. On 2026-09-12 the remaining three were audited, re-ordered and implemented as 3, 4 and 2 (the audit record below says why), each with its own handover. All five are complete; §9's fixture landed with package 2. The rule that a package must not quietly broaden into another's scope still governs any later change here.

Read `../AGENTS.md` and `../CONTEXT.md` first. All paths below are relative to the repository root. Documentation and user-readable strings use British English. Use the current source and tests over an outdated line reference or this plan's proposed type names.

### Current execution record

| Package | Status | Completion evidence |
| --- | --- | --- |
| 1. Standardised evidence and Hooks separation | Complete | `MonitoringRepository`, `HookEvidenceBoundary`, `ProductMonitoringRuntime`; seven new conformance tests; final full suite: 858 definitions, 859 executions, zero failures or skips; committed with this document |
| 2. Requests identified independently of slots | Complete | `ProducerWaits`, `requestResolved`, derived status, ordered `requestsAwaitingAnAnswer`, `MonitoredSession.requests`, store pin and same-row advance; ten reducer tests, two store tests and the §9 synthetic product fixture; full suite: 901 test cases, zero failures or skips; committed with this update |
| 3. Structured answers and permitted operations | Complete | `AnswerOperations`, typed `AgentQuestionAnswer`, per-question constraints, boundary validation; eleven new conformance tests and one store test; full suite: 880 test cases, zero failures or skips; committed with this update |
| 4. Answer channels and delivery outcomes | Complete | `AnswerOutcome`, issuer-scoped `AnswerHandle`, registry windows and expiry, store single-flight and outcome notices; six channel tests and four store cases; full suite: 888 test cases, zero failures or skips; committed with this update |
| 5. Configuration and source lifecycle composition | Complete | `ProductSetup`, `MonitoringSourceComposition`, phased supplementary evidence; ten new tests; full suite: 868 definitions, 869 executions, zero failures or skips; committed with this update |

At the audited baseline, the full unit suite passed: 851 test definitions, 852 executions including dynamic parameters, zero failures or skips. This is historical evidence, not a substitute for running the suite after changes.

### Audit of packages 1 and 5, and the order of the rest (2026-09-12)

Packages 1 and 5 were re-read against their handover records after the `e2143af` baseline. The dependency direction holds: `MonitoringRepository`, `MonitoringState`, `MonitoringEvidence`, `ProductMonitoringRuntime`, `MonitoringSourceComposition`, `SupplementaryMonitoringEvidence` and `MonitoringLifecycleSource` reference no hook payload, vocabulary, path, listener, setup, install-state or descriptor type. There is one reducer; the old Hooks names are aliases. Their seventeen tests pass. Two observations are recorded rather than fixed, because neither breaks a shipping product:

- `ScheduledMonitoringSource.refresh(at:)` is awaited inside the refresh, one source after another, before the reducer is drained. No shipping source conforms yet; the usage readers keep their own behind-the-figures reads and only publish a deadline. A future conformer that reads slowly on this path would delay that product's rows, so a scheduled read must return quickly from held values and do its slow work behind them, as the usage readers do.
- A closed channel gate stops every source on each refresh that finds it closed and restarts them on the first refresh that finds it open. That is the intended shape; it is noted so the churn is not mistaken for a leak.

The three remaining packages were re-planned before starting. The plan numbers them 2, 3, 4, and the dependency runs the other way: package 2 restructures the reducer's wait slots, and it should be built once, around the final shape of what a request carries (package 3) and how its handle and outcome behave (package 4). Building 2 first would carry the string answer, the derived affordances and the ticket-backed handle into the new collection and then rewrite them. Packages 3 and 4 are boundary and contract changes with existing regression fixtures, and each corrects a live defect on its own: a selected option is indistinguishable from typed text equal to its label, a question drawn over a held Codex connection is offered `Submit` and then reported as *not sent*, and a socket write is reported as the product having acted. **The order is therefore 3, then 4, then 2**, with the cross-package fixture of §9 landing with package 2. Package 3 begins with this record.

## 2. What must remain true

1. There is one authoritative Turn reducer. All products use its ordering, identity, wait and retirement rules. Transport queues serialise bytes; the reducer serialises business state. Starting two Swift `Task`s in order does not establish delivery order.
2. Only positively observed live evidence opens a Turn. A historical file, elapsed timeout, running process or successful connection is not a submission. Supplementary evidence can retire a Turn or redeem an already-observed held start, but cannot invent a start from a record.
3. Preserve current duplicate, stale, retired-Turn and held-Turn guards. Preserve Codex's record-confirmed identity policy and Claude Code's continuation policy. Do not simplify either because a synthetic product needs less.
4. A subagent's own Turn ID must never replace its parent's Turn. Running subagents and their waits can outlive a parent Turn. Background-work pause evidence remains distinct from a terminal Turn's status.
5. Presence, observation health, Thread eligibility, current activity and read evidence remain separate facts. A failed read is not a trustworthy empty set.
6. Read removal affects only eligible terminal rows, follows product evidence, and does not archive the native Thread. Dismissal remains per Turn and suppresses unnecessary read checks.
7. `MonitorSnapshot` remains the presentation contract. SwiftUI does not parse payloads or operate transports. Overlay publications remain driven by layout/projection changes; message deltas must not create continuous SwiftUI updates.
8. Answering consumes only the request-bound channel. Native evidence, not successful submission, changes lifecycle state. Unknown forms remain reading-only or return to the product.
9. Preserve existing configuration bytes, helper behaviour, timeouts, backup rules, socket ownership and per-definition Codex trust. Refactoring must not require users to trust rewritten definitions.
10. Current support coverage is unchanged unless a separately verified change explicitly updates it. Antigravity's absent wait/cancellation evidence is not fixed by a more general interface.

## 3. Audited baseline implementation map

This table describes `32a64e2`. For the extracted implementation, start with the package 1 handover below; the old Hooks names are compatibility aliases, and `HookDeliveryInbox` has been replaced by `MonitoringEvidenceInbox`.

| Area | Files and symbols to inspect |
| --- | --- |
| Composition and capabilities | `Notchline/Notchline/ProductRegistry.swift`: `ProductDescriptor`, `ProductModule`; `ProductContracts.swift`: `AgentMonitoring`, `IntegrationConfiguring`, `AnswerDelivering`, `UsageReading` |
| Shared refresh | `HookProductProvider.swift`: `fetchSnapshot`, `nextRefreshDeadline`, `ProductSessionReading`, `TurnEvidenceSource`, `RowContentSource` |
| Hook transport | `HookLifecycleSource.swift`, `AgentHookListener.swift`, `ManagedHooksSetup.swift`, `ManagedHooksConfiguration.swift`, `ManagedHooksFileEditor.swift` |
| Payload interpretation and reduction | `HookIntegration.swift`: `AgentHookVocabulary`, `HookPayload`, `HookPayloadDistiller`, `HookDeliveryInbox`, `HookEventRepository`, `HookTurnState`, `AgentWaitSlots` |
| Product compositions | `ClaudeCodeMonitorService.swift`, `LiveCodexMonitorService.swift`, `Products/Antigravity/AntigravityHookVocabulary.swift`, `Products/Antigravity/AntigravitySurfaces.swift` |
| Supplementary evidence | `ClaudeCodeTurnEvidence.swift`, `CodexRolloutTurnEvidence.swift` |
| Read and navigation | `TerminalUnreadRowFilter.swift`, `TerminalReadEvidence.swift`, `ClaudeCodeReadEvidence.swift`, `CodexDesktopNavigator.swift`, `ProcessHostNavigator.swift` |
| Requests and answers | `AgentRequest.swift`, `RequestAnswering.swift`, `HookReplyRegistry.swift`, `MonitorStore.swift`: `takeAnswer`, `answer(to:from:)`, `send`, `answerLanded` |
| Regression fixtures | `Notchline/NotchlineTests/NotchlineTests.swift`, `HookProductConformanceTests.swift`, `HookTransportDialectTests.swift`, `AntigravityConformanceTests.swift`, `ManagedHooksShapeTests.swift` |

Codex retains a separate Provider because its App Server has its own connection and compatibility lifecycle. Do not force its transport management into the shared refresh by adding product switches. Its shared business rules must nevertheless use the same reducer and membership filter.

## 4. Work package 1 — separate standardised evidence from Hooks

### Problem and required outcome

At the baseline, `HookEventRepository` takes JSON and an optional Unix descriptor, reads installation records, interprets a vocabulary, reduces Turns and owns held answers. `HookProductProvider` requires a concrete `HookLifecycleSource` and its registration/socket gate. An SDK or event-stream product must imitate Hooks or assemble another runtime.

The required outcome is a typed live-evidence entry point and a reusable monitoring runtime that do not require a hook vocabulary, JSON envelope, hook configuration, helper or socket. Every shipping hook product must use this same entry point after boundary translation. Adding an unused protocol beside the old path does not complete this package.

### Responsibility boundary

- **Product boundary:** decode native data, establish native identity and eligibility, classify native events, project readable requests, qualify progress/final text, filter non-human/native internal activity, and apply native field aliases. Antigravity's local Turn identity stays here.
- **Hooks boundary:** distil bounded fields before expensive decoding, manage setup/trust and helper/socket lifetime, own native request bytes and held descriptors, and translate its vocabulary into typed evidence.
- **Shared repository:** ordered live-evidence inbox, current Turn state, deduplication/ordering/held-start rules, subagent aggregation, preview storage, standardised supplementary retirement and projection-change notifications.
- **Shared runtime:** obtain source readiness, drain evidence, read presence/admission, apply supplementary evidence, build rows, apply read removal, and produce snapshots. A hook wrapper may retain optional configuration and answer capabilities.
- **Product Provider:** compose these pieces. Codex still manages its independent App Server lifecycle.

### Implementation sequence

1. Read the complete reduction path and tests before moving it, including `reduceSubagentToolEvent`, `mutateExactTurn`, `adoptTurnsOnRecord`, `discardTurns`, previews and diagnostic counters. Record which branches are policy and which decode a native schema.
2. Introduce a `Sendable` evidence value with semantic signal, Thread/Turn/producer identity, observation time, optional qualified text, call correlation, projected request and relevant terminal facts. Keep native JSON and descriptor types out of this entry point. Optional data must remain optional; do not invent missing starts or text.
3. Represent the existing measured reduction policies independently of `AgentHookVocabulary`. The adapter chooses a policy; the reducer does not switch on product identity. This is not permission to expose arbitrary closures that mutate Turn state.
4. Move payload decoding, message-field aliases, request projection and installation/trust bookkeeping to the hook boundary. Preserve the fast preview path: bounded text folding, no per-delta actor task, no unbounded retained payload.
5. Move the actual state machine into the shared repository without rewriting its transitions. Keep a narrow hook facade if needed to preserve callers and tests. A compatibility alias or forwarding method must not become a second reducer.
6. Make the shared refresh accept a source readiness/lifecycle contract, rather than requiring a concrete hook transport. Preserve `HookProductProvider` as a composition wrapper if useful. Ensure a non-hook source can use the same row-building and membership path without implementing hook installation.
7. Preserve answer lifetime while moving the boundary. Package 4 will replace the ticket-backed `AnswerHandle` and boolean outcome; package 1 must not advertise that work as done. A narrow request-handle reconciliation callback may keep existing Hooks working without putting descriptor writes into the new reducer.
8. Route Codex, Claude Code and Antigravity through the standardised repository. Keep current native field interpretation, automatic-review filtering, registration contents and externally observable support unchanged.
9. Add direct typed-evidence conformance tests. A fixture must construct its repository/runtime with no hook paths or vocabulary, and must not use JSON serialization or `HookPayload` to submit evidence.

### Required verification

- Typed start → progress → end produces the expected row, metadata, timer and final preview through the shared runtime.
- Independent Threads remain independent. Duplicate and stale events cannot re-open or rename a newer Turn. Retired and held Turn cases retain their existing behaviour.
- Explicit stale observation-epoch evidence is rejected if an epoch mechanism is introduced; do not describe ordinary Turn-ID tests as epoch coverage.
- No historical state is loaded, and no configuration or socket is created by the non-hook fixture.
- A live wait and its matching resolution use the same reducer through both typed and Hooks paths. The single-slot limitation remains explicitly assigned to package 2.
- Subagent isolation, post-parent activity, request projection, held answer delivery/release and per-definition trust continue to pass existing tests.
- All current product conformance fixtures and the full unit suite pass. Inspect helper/configuration regression tests to ensure registration bytes have not changed.
- Inspect the dependency direction: the standardised repository must not reference `HookPayload`, `AgentHookVocabulary`, `HookIntegrationPaths`, `AgentHookListener`, `ManagedHooksSetup`, `HookInstallStateFile` or descriptor writes. The package-4 handle representation is an explicitly temporary exception, not a reason to leave socket ownership in the reducer.

### Rejected shortcuts

Do not introduce a nominal `Evidence` wrapper around `HookPayload`, require JSON from a typed source, add a fake hook configuration for a non-hook product, duplicate the reducer, move byte framing onto an actor, infer an end from silence, or replace current regression assertions with weaker smoke tests.

### Documents updated in the same change

Update `CONTEXT.md` and `AGENTS.md` where they identify the reducer/source boundary; `docs/system-architecture.md` and `docs/tech-design.md` for actual interfaces and ordering; `docs/product-support.md` and `docs/product-support-zh.md` together for their implementation/verification descriptions; and this execution record. Update `docs/PRD.md` only where an implementation statement becomes false; do not silently change product behaviour. Check `docs/non-public-codex-integration-features.md` and update any affected code links or descriptions. A refactor preserving the same private reads adds no new private capability, but renamed/moved implementations still need navigable links.

### Package 1 implementation handover (2026-09-12)

This is the package 1 completion record. Package 5, below, supersedes its temporary no-setup mapping, unrestricted supplementary-source interfaces and source-scheduling limitations.

The implemented entry point is `MonitoringRepository(policy:)`, `observationEpoch`, `submit(_:in:)` and `recordProgress(_:in:)`. A source captures its epoch at subscription and retains that token in its callbacks; `resetIntegrationObservation(clearTurns:)` rotates the token and rejects old lifecycle and content callbacks. The token does not identify an upstream process: native producer and Thread qualification remain the adapter/Provider's responsibility.

`MonitoringEvidence.swift` defines evidence, progress, measured reduction policies and the ordered inbox. `MonitoringState.swift` holds `MonitoredTurnState`, `MonitoringStateSnapshot`, semantic signals and bounded preview storage. `MonitoringRepository.swift` holds the sole reducer. `HookEvidenceBoundary.swift` is a compatibility extension and a boundary observer owning native decoding, request projection, installation trust and held replies. The old Hooks type names remain aliases in `HookIntegration.swift`, so existing product adapters and their tests still exercise the same implementation.

`ProductMonitoringRuntime` now owns the shared refresh and accepts `MonitoringLifecycleSource`. `HookLifecycleSource` implements that contract and `HookProductProvider` is a setup/answer-capable composition wrapper. A no-setup source can use the runtime with `.open(nil)`; the legacy snapshot maps this to `.active`. This does **not** complete package 5's product descriptor or Settings changes. Codex still owns its App Server orchestration, using the same typed reducer through the Hooks facade.

Seven permanent tests in `MonitoringEvidenceConformanceTests.swift` exercise a source without JSON, vocabulary, paths or sockets: runtime lifecycle/progress/final content, ordered batches and retired identities, stale epochs, request projection/resolution, subagent isolation, record-confirmed held starts, and tool activity that establishes neither a new Turn nor a hook-trust diagnostic. These fixtures passed in Debug and Release. The original full native suite also passed after extraction; the final combined suite result is recorded in the execution table.

Release burst measurement: `getrusage` cumulative process CPU around 2,000 submitted/drained lifecycle events, representing 1,000 sequential Turns; three fresh repositories per path. Typed entry: **7.48–8.71 ms**. Current Hooks decoding/boundary plus the same reducer: **28.35–29.79 ms**, excluding fixture JSON encoding. Both ended on the expected final Turn. These compare the two implemented paths, not pre-refactor performance; they do not measure socket latency, large request bodies, UI cost or idle CPU. The temporary measurement fixture and its output are removed after recording these conclusions.

Rejected: a second reducer, a nominal typed wrapper around native JSON, fake hook setup for a typed source, rewriting native registrations, and replacing the answer protocol as part of this package. Packages 2–5 remain outstanding. Current slot correlation, ticket-backed handles, boolean answer results, Settings assumptions and source scheduling limitations are explicitly preserved for those packages. No private native schema, discovery mechanism, write protocol or product support level changed.

## 5. Work package 2 — requests identified independently of slots

### Problem

`AgentWaitSlots` and the main Turn hold one approval, one input and one latest open call. Another request of the same kind overwrites the previous one. Separate subagent slots solve producer isolation, not concurrency within one producer. Correlation is tied to tool-call identity.

### Target contract

A request has a stable key scoped by product/observation epoch, Thread, producer and request identity; include Turn identity where native scope requires it. Distinguish a native request identity from the call it concerns. Store all live requests and select one for presentation separately. Keep the current one-request-at-a-time panel.

### Steps

1. Inventory all assignments to `pendingApproval`, `pendingInput` and `openToolUse`, plus all answer-handle retention paths. Include supplementary answered-approval evidence and post-parent subagent waits.
2. Introduce request-open, request-update/replacement, request-resolved and request-invalidated evidence keyed precisely. Specify whether a replacement keeps draft state; default to discarding drafts for a different request/revision.
3. Move native missing-ID/tool-call borrowing to product boundary correlation. Ambiguous correlation must fail closed. A new product with an explicit request ID must not fabricate a tool call.
4. Store a request collection per producer rather than one slot per kind. Re-derive status from lifecycle plus unresolved waits; resolution of one request cannot clear another. Preserve the current input-versus-approval precedence and parent/subagent rules unless an explicit reviewed decision changes them.
5. Extract deterministic selection for the one request the row opens. Preserve oldest eligible subagent approval selection; define stable tie-breaking and pin the open request while the user reads it.
6. Retain every live answer handle, not only the selected request's. Retire matching handles at resolution, supersession, Turn retirement or producer departure according to the request's actual scope.
7. Update draft, submission and notice identity in `MonitorStore`; a row ID alone cannot identify concurrent requests or replacement versions.

### Acceptance cases

Two simultaneous approvals on the same producer; two simultaneous input requests; mixed input/approval; identical native IDs under different producers/Threads; resolve the older request while a newer one remains; duplicate/out-of-order resolution; replacement during drafting; a subagent wait after parent completion; all handles retained while only one request is drawn; no native answer caused by merely switching the visible request.

Update `docs/answer-in-notch.md`, `docs/dual-agent-design.md`, `docs/PRD.md`, terminology where needed, system/technical design, coverage documents and the execution record. Do not claim newly supported native forms without runtime evidence.

### Package 2 implementation handover (2026-09-12)

Built last, after packages 3 and 4, so the collection was built once around the typed answer, the declared operations and the issuer-scoped handle.

`ProducerWaits` (`MonitoringState.swift`) replaces `AgentWaitSlots` on the Turn's own agent (`MonitoredTurnState.waits`) and on each subagent (`subagentSlots`): `openCalls`, `inputs` and `approvals` in arrival order, each wait carrying `requestID` — `MonitoringEvidence.requestID` where the product names requests apart from calls, else the call's id — beside the call it concerns. `open(_:)` replaces an entry wearing the same identity in its place; `closeCall(_:)` ends the waits about a call; `resolve(requestID:)` ends one request; `resolveInferredApprovals(exceptCall:whenInferring:)` and `endApprovals(before:)` are the existing Codex-refusal and answered-elsewhere rules over the whole collection; `withdraw(_:)` and `heldAnswerHandles` cover every request. The old accessors (`pendingInput`, `pendingApproval`, `openToolUse`, `pendingInputToolUseID`) remain as the oldest wait and the latest call, so every existing rule and test reads as before. `MonitoringSignal.requestResolved` is the one new evidence kind: a product that names requests resolves one by identity; hook products never emit it. `MonitoredTurnState.deriveStatus` derives the status from what is left — a question outranks an approval, a finished Turn absorbs both — which is `SessionStatus.transitioned(on:)`'s rules applied to a collection; the stepped transitions remain for the Turn's own terminal.

Borrowing stays in the reducer, because only the reducer holds the open calls, and it is the vocabulary's choice of signal that decides whether a product borrows at all: `ProducerWaits.callToBorrow(forTool:)` pairs an id-less approval with the one open call of its tool, or with the one such call that has no approval filed yet, and otherwise with none. That is narrower than the "latest open call" it replaces, which under two parallel calls of one tool filed the first dialogue under the second call and left it to be closed by the wrong `PostToolUse`; a wait that would be closed by the wrong event is worse than none, and the product's own dialogue is still in front of the person. Recorded in `docs/product-support.md` as the one narrowed rule.

Selection is `MonitoredTurnState.requestsAwaitingAnAnswer`: the Turn's own questions, then its own approvals, then running subagents' approvals; within a rank an answerable request before one only readable (a request just answered from here stays until the product says so and must not stand in front of one the person can still settle), then arrival order (a replacement keeps its place; subagents' by the instant they opened, then by agent), then identity. `requestAwaitingAnAnswer` is its first. `MonitoredSession.requests` carries the whole list and `request` its first, on both Providers; `renderedProjection` carries every live request's identity, form and answerability so a second arrival wakes the panel. `MonitorStore.openRequest` pins the request the drafts belong to while it is still among the row's, `closeARowWhoseRequestHasGone` moves on only once it is gone, `answerLanded` annotates nothing when the answered request is no longer among the row's live ones and opens the next answerable request on the same row (`openRow(_:showing:)`), and spent handles are pruned against every request. Drafts stay keyed by row and `AgentRequest.asked`, which package 3 already made a request-and-revision identity rather than a row identity.

The full unit suite after this package: 901 test cases, zero failures or skips. Acceptance cases: [RequestCollectionTests](../Notchline/NotchlineTests/RequestCollectionTests.swift) — two approvals and two questions on one producer resolved one at a time with the status standing; mixed question and approval; identical identities under two producers and two Threads; duplicate, unknown and out-of-order resolutions; a replacement in place; resolution by native identity leaving the call open; an id-less approval about two open calls failing closed and pairing once one closes or one is already asked; every connection retained while one request is drawn, and the answered one falling behind; selection stable under arrivals. In the main suite, `theOpenRequestIsPinnedWhileItIsStillAmongTheRows` and `answeringOneOfTwoRequestsOpensTheOtherOnTheSameRow` cover the store, and a subagent wait after parent completion was already pinned. [SyntheticProductConformanceTests](../Notchline/NotchlineTests/SyntheticProductConformanceTests.swift) is §9's cross-package fixture and passes through the shared runtime, reducer, selection, drafts, navigation dispatch and panel forms with nothing built for it: typed identities, two simultaneous requests under native ids, identical labels backed by distinct values, a choices-only question beside a free-text one, an asynchronous channel that can only report `uncertain`, deadline-driven progress, no quota, and a click reaching the navigator.

Rejected: a request-open/update/invalidated signal quartet (opening under a held identity is the replacement, `toolCallClosed` and `requestResolved` are the two resolutions a product has, and nothing consumes the difference between resolved and invalidated); moving borrowing to the boundary (it needs the open calls, which only the reducer holds); pairing an ambiguous approval with the oldest unpaired call (a guess, and a wait a wrong event closes); and a per-request draft table keyed beyond the row and the asked request. All five packages are complete. No native schema, registration bytes, private read, write contract or product coverage changed; the registry was checked and needs no entry.

## 6. Work package 3 — structured answers and permitted operations

### Problem

`MonitorStore.answer(to:from:)` turns selected options into labels joined with `", "`. `AgentQuestionAnswer` carries question text and one answer string. The adapter cannot recover selected IDs, distinguish a typed label from a selection, or safely encode an array. `AgentRequest.answerRow` derives permitted operations from form plus handle presence, so all answerable questions offer free text and approvals assume both grant and refusal.

### Target contract and steps

1. Preserve stable question and option identities separately from display text and order. Repeated labels and repeated question wording must be representable.
2. Carry a typed answer such as selected option identities, free text, and optional notes. Keep selections as a collection through the store. A product encoder performs its native final conversion.
3. Add per-request permitted operations and input constraints: grant/refuse, whether refusal accepts text, allowed choices, single/multiple selection, free-text availability and notes. This is granular capability data, not a runtime L1–L6 rank.
4. Keep presentation affordances derived from these operations. A readable form without a supported operation remains reading-only. Do not add arbitrary forms, persistent permission rules or new controls merely to make the model universal.
5. Move Claude Code's text-keyed answers and comma-joined selection encoding into `ClaudeCodeRequestAnswering`. Preserve existing output bytes and text/selection precedence for that product. Codex question answers must remain rejected on its current hook channel.
6. Validate submission against the current request identity/revision and permitted operation. Validate in the delivery boundary too; UI checks alone are insufficient.

### Acceptance cases

One option labelled `A, B` versus options `A` and `B`; duplicate labels with different IDs; duplicate question wording; arbitrary native IDs; typed text matching a label; a choices-only question; a request permitting no refusal note; unsupported operations never offered/sent; stale selections after replacement; native Codex and Claude Code encoder regression fixtures.

Update answer design, product coverage in both languages, technical design, the non-public registry if a native write contract changes, and the execution record. This package improves representation; it does not authorise new native operations.

### Package 3 implementation handover (2026-09-12)

Built after packages 1 and 5 and before 4 and 2, for the reasons in §1's audit record.

`AnswerOperations` (`RequestAnswering.swift`) is the per-request capability value: grant, refuse, refusal carries text, answers questions; `.decision`, `.questionAnswers` and `.readingOnly` are the three shipping shapes. It is declared where the connection is taken — `AgentHookVocabulary.answerOperations(forEvent:toolName:)`, asked only of the answering event: a decision on both products' `PermissionRequest`, a question set's answers on Claude Code's `AskUserQuestion` alone, nothing on Antigravity — carried on `MonitoringEvidence.answerOperations`, filed on the request by the reducer through `AgentRequest.answerable(by:)`, and kept on the ticket in `HookReplyRegistry`. A request built without a declaration takes its form's own operations, which is what a body read off a `PreToolUse` carries until the `PermissionRequest` that holds the connection re-files it. `AgentRequest.canBeAnswered` now needs the handle **and** a form the operations answer (`Form.permits(_:)`); `answerRow(showing:)` draws only the permitted answers — no refusal where none is, no field where a refusal takes no words or a question takes none — and `MonitorStore.send` and `MonitoringRepository.answer(_:on:)` both refuse an answer the connection was not declared for, the latter before composing bytes and without releasing the connection.

`AgentQuestion` carries its constraints beside its options: `allowsSeveralAnswers`, `acceptsFreeText` (true for both products), `acceptsNote` (Claude Code's `annotations`), and `nativeID` (Codex's per-question `id`, read as a string or number; Claude Code sends none). `id` remains the position, which is what the surface draws and the digit keys select; the plan's "stable identities separately from display text and order" is met by keeping the position as the surface identity and the product's identifier beside it, rather than by retyping every option and draft key. `AgentQuestionAnswer` is typed: the question as asked, the chosen positions in the product's order, or the trimmed words, plus a note; `fitsItsQuestion` is the one shape check every encoder makes. `MonitorStore.answer(to:from:)` produces it and `canSubmitCurrentAnswer` asks the same gate, so a stale tick or words on a choices-only question cannot leave the row. `AnswerProgress` keys drafts by `AgentRequest.asked` — the request stripped of its connection — so the same id wearing another body starts empty. `ClaudeCodeRequestAnswering.spelling(of:)` holds that product's `", "` join and its text-keyed `answers` object; Codex still returns nothing for a question. Output bytes for every previously encoded answer are unchanged.

The acceptance cases are [StructuredAnswerTests](../Notchline/NotchlineTests/StructuredAnswerTests.swift): an option labelled `A, B` versus `A` and `B`; duplicate labels; duplicate question wording (recorded as Claude Code's own text-keyed limitation, later answer winning); arbitrary native identifiers with a synthetic encoder; typed text matching a label; a choices-only question; a refusal that takes no words; unsupported operations neither offered nor sent, at the request, the mark word, the vocabularies and the boundary with a live socket pair; stale ticks and ill-fitting answers refused whole; the existing Codex and Claude Code encoder fixtures. The store's replacement case is `aTickDoesNotTravelOntoAReplacementWearingTheSameID` in the main suite.

One transport defect was found by the boundary fixture and fixed in the same change: a connection is held on the listener's queue before its evidence is appended to the inbox, and a drain kicked by the previous event could reconcile in that gap and close it, so the person's answer would later fail as *not sent*. `HookReplyRegistry` now reconciles only tickets whose evidence a drain has applied (`markReduced`, called from `HookEvidenceBoundary.didApply` for accepted and rejected evidence alike), and `MonitoringEvidenceInbox.reset` returns the evidence it drops so `resetIntegrationObservation` can release those connections through the new `MonitoringBoundaryObserver.didDiscard(_:)`.

Rejected: retyping question and option identities as strings (the position is already independent of label and text, and the churn reached every draft, key and specimen for no representational gain); a refuse-only or grant-only drawn row (represented, not drawn — neither product asks that way); a note field on the surface (the operation is represented and the encoder accepts it; nothing composes one); and inventing a key for duplicate question wording that the product would not read. Packages 2 and 4 remain outstanding: request collections and revisions, and the opaque handle with explicit delivery outcomes. No native schema, registration bytes, private read, write contract or product coverage changed; the registry was checked and needs no entry. Codex question answers remain rejected on its hook channel.

## 7. Work package 4 — answer channels and delivery outcomes

### Problem

`AnswerHandle` contains `HookReplyRegistry.Ticket`. The hook registry owns descriptors and native input, and `AnswerDelivering.answer` returns `Bool`. A successful local write, native acceptance, native rejection, expiration and an uncertain network result cannot be represented faithfully. The current failure notice assumes the product stopped waiting.

### Target contract and steps

1. Make the handle opaque and scoped to its issuer/channel lifetime. Native request IDs, descriptors, raw input and encoding context remain in the issuing channel. A stale handle from an earlier issuer/epoch cannot address a new request even if local counters restart.
2. Define explicit results: confirmed accepted (only where acknowledged), sent without native acknowledgement where that is all the transport proves, expired/invalidated, rejected with an appropriate explanation, unsupported operation, and uncertain delivery. Final names may vary, but these meanings must not collapse into a boolean.
3. Implement the existing Hooks path as one `AnswerChannel`. Socket write success proves that bytes were written, not that a remote product acknowledged an action. Preserve its actual guarantee in the result and documentation.
4. Specify single-flight and consumption rules per handle. Duplicate clicks cannot write twice. An uncertain result must not release a handle for an automatic retry; only a channel with verified idempotency/reconciliation may retry.
5. Make handle invalidation observable independently of Turn status. A request can stay readable while its answer channel expires. Preserve the rule that native evidence alone resolves the lifecycle wait.
6. Update `MonitorStore.send` and notices using the result and request identity, not just the row identity. A delayed result must not annotate a replacement request.
7. Add a synthetic asynchronous channel without file descriptors, and route it through the same draft/submission/result flow as Hooks.

### Acceptance cases

Successful socket write; peer gone; short writes and interrupted writes; duplicate answer; issuer restart reusing a native ID; expiration during drafting; native in-product answer invalidates the handle; asynchronous accepted/rejected/uncertain outcomes; timeout after bytes were sent; no blind retry; no optimistic lifecycle transition; completion arriving after another request occupies the row.

Update `CONTEXT.md`'s Answer/Answerable definitions, answer design, technical/system architecture, PRD delivery guarantees, coverage documents, and the registry if implementation of a private write path changes. Record actual transport guarantees rather than claiming universal acknowledgement.

### Package 4 implementation handover (2026-09-12)

Built after package 3, before package 2.

The plan's `AnswerChannel` is the existing `AnswerDelivering` contract — one method, one handle, now one `AnswerOutcome` — rather than a second protocol beside it. `AnswerOutcome` (`RequestAnswering.swift`) has the six meanings the plan requires: `accepted` (acknowledged; no shipping channel can claim it), `sent` (every byte written, nothing acknowledged — the Hooks channel's best), `expired(.peerGone | .timedOut | .notHeld)`, `rejected(String)` (for a channel that hears back; none does), `unsupportedOperation` (nothing written, nothing spent) and `uncertain` (part written; spent, never retried). `answerArrived` is true for the first two only. `HookReplyRegistry.write` maps `EPIPE`/`ECONNRESET`/`ENOTCONN` before any byte to `peerGone` and every other failure to `uncertain`; `answer` on a handle it does not hold is `notHeld`.

`AnswerHandle` (`ProductContracts.swift`) carries the minting registry's `issuer` beside its ticket; `AnswerHandle.unissued` is the fixture issuer and addresses nothing on a live channel. The registry mints handles in `hold(_:answering:permitting:expiringAt:)`, checks the issuer on every lookup, and records each connection's `expiresAt` — the payload's arrival plus `answerWindowSeconds`, the helper's `nc -w` window, which the product's registered timeout encloses by construction. `MonitoringRepository.drainDeliveredEvents` calls `withdrawExpiredAnswerHandles()` on every refresh, closing the descriptor and withdrawing the handle from its request while the request and the Turn's status stay; `nextAnswerExpiry()` is composed into `ProductMonitoringRuntime.nextRefreshDeadline` and `LiveCodexMonitorService.nextRefreshDeadline`, and the refresh that withdraws the handle consumes it. Native evidence alone still resolves the wait.

`MonitorStore.send` spends a handle once (`spentAnswerHandles`, pruned with the rows and released only by `unsupportedOperation`), and `answerLanded` takes the outcome, the answered request stripped of its connection, and the handle: an arrived outcome clears the draft and advances to the next request as before; every other outcome keeps the draft and says its own sentence on the preview line in the preview's ink — the peer gone, the window run out, nothing held, the product's own refusal, the operation not carried, or *Sent, but not confirmed — check in <product>*; and a result for a request the row no longer holds annotates nothing and clears nothing. The synthetic asynchronous channel is `AnsweringMonitoringStub.holdAnswers()` in the main suite, answering `accepted`, `rejected` and `uncertain` after a suspension through the same draft, submission and result flow.

The full unit suite after this package: 888 test cases, zero failures or skips. Acceptance cases: [AnswerChannelTests](../Notchline/NotchlineTests/AnswerChannelTests.swift) cover a successful write (`sent`, no status change, request stays readable), a peer gone before the write, a duplicate answer, a handle from another issuer with the same ticket number (and an unissued one) leaving the held connection untouched, a window that ran out during drafting — booked as a runtime deadline, withdrawn by the refresh, consumed — and the outcome vocabulary; `anAsynchronousChannelsOutcomeReachesTheRowWithoutARetry` and `aResultArrivingAfterAnotherRequestTookTheRowAnnotatesNothing` in the main suite cover the asynchronous outcomes, no second send in flight or after landing, and a completion arriving after another request occupies the row. Short and interrupted writes are handled by the registry's existing `EINTR`/short-write loop and reported as `uncertain` when a write fails after taking part; a socket pair cannot be made to short-write deterministically, so that branch is pinned by reading rather than by a fixture. A product timing out after the bytes were sent is unobservable on this channel and is documented as such rather than reported.

Rejected: a second `AnswerChannel` protocol identical to `AnswerDelivering`; watching a held descriptor for the peer going away (the helper half-closes its write side after the payload, so the read side is already at EOF); an automatic retry on any outcome; and keeping the boolean beside the outcome. Package 2 remains outstanding: request collections, revisions and selection, which is where a delayed result's request identity becomes a scoped key rather than the stripped request value used here. No native schema, registration bytes, private read, write contract or product coverage changed; the registry was checked and needs no entry.

## 8. Work package 5 — configuration and source lifecycle composition

### Problem

`IntegrationConfiguring` is optional but `ProductDescriptor.setup` and Settings still assume a managed hook file. Source changes are manually merged, and the shared deadline only includes usage and read removal. Some evidence sources receive the whole mutable reducer, leaving their authority limited mostly by convention.

### Target contract and steps

1. Model setup explicitly: no setup, managed local configuration, and other concrete setup requirements supported by a real adapter. Hide nonexistent setup actions. A no-setup product must not get a fake switch or file link.
2. Separate enabling observation from editing native configuration if both are needed. State what each switch does before changing its semantics. Preserve existing managed-file backups and narrow edits.
3. Give timed sources a next meaningful deadline and a change stream where required. Compose deadlines in the runtime; do not add an unconditional polling loop. A deadline must be consumed/advanced by a reachable refresh, with backoff after failure.
4. Specify source start/stop/reset ownership. Removing/disconnecting a product cancels readers and watchers and releases only resources owned by this app. Decide which last-trustworthy values survive a transient outage.
5. Narrow supplementary evidence sources to returning typed observations, with authority and observation time where needed, rather than receiving the unrestricted reducer. The runtime applies observations in one documented order. A supplementary source cannot acquire submission authority accidentally.
6. Keep product-level cross-source decisions in its Provider. Do not turn the source contract into an all-capabilities protocol requiring meaningless methods.

### Acceptance cases

A no-setup product reaches the panel without hook copy; a polling progress source updates at its deadline; a failed read backs off without a busy loop; source change signals coalesce; disconnect stops all owned work; reconnect does not replay old Turns; read checks park while the screen cannot be read; usage unavailability does not erase lifecycle state; removing one product does not affect another.

Update settings behaviour, artifacts, product coverage, system/technical architecture, PRD if a setting changes, and this record. Measure any scheduling/performance change in Release using the appropriate steady-state or cumulative CPU method.

### Package 5 implementation handover (2026-09-12)

`ProductSetup` is an explicit sum type: `.none` or `.managedHooks(SetupDescription)`. Only the latter provides a switch, configuration path, backup copy and Hooks instructions. `IntegrationSetupStatus.notRequired` represents absent setup without pretending installation succeeded. Settings derives no-setup status from observation availability. All shipping switches still edit exactly their existing native files; no independent observation switch or preference was added. Other setup variants should be added with a real adapter, rather than speculative login/permission interfaces.

`MonitoringSourceComposition` discovers the optional `ManagedMonitoringSource` capability on lifecycle, session, supplementary-evidence, content, read-evidence and usage sources. It deduplicates instances, merges their own `sourceChanges`, starts them before source reads and stops them in reverse order. Pure readers need no lifecycle methods. Existing extra product event streams remain supported for composition-specific events. Claude Code's session, evidence, read and quota sources now contribute their events themselves.

A `ScheduledMonitoringSource` implements `refresh(at:)`, updating its held evidence and returning the next meaningful deadline or nil. The runtime runs it initially, when due, or when its own source emits an edge; unrelated refreshes do not poll it. The composition counts edges before yielding so an edge arriving during a read remains due. It runs at most one scheduled read per instance, cancels pending tasks at stop, and never publishes a deadline for an in-flight read. Failures retain the source's prior values and retry after 5, 10, 20, 40 and at most 60 seconds, including when other sources emit events. A successful return clears the failure. Returning a deadline already consumed defers five seconds rather than spinning. These are recovery deadlines, never lifecycle evidence.

`TurnEvidenceSource` returns `TurnEvidenceBatch` through ordered `TurnEvidencePhase` readings. The batch's only authority is existing record confirmation, stopped-Thread evidence, exact interruption and answered-approval evidence. Observation times remain on the relevant facts; `TurnOnRecord` can redeem only the exact already-observed held start. It cannot submit or describe a Turn. Codex reads identity, applies it, then asks about termination of the resulting Turn. Claude Code applies lifecycle evidence before reading Desktop answers, preserving its avoidance of unnecessary log reads. `SupplementaryEvidenceApplication.settle` applies these values with the existing guards and rejects results from a reset observation epoch. Content sources receive `TurnMessageReading`, a read-only closure value, instead of a downcastable repository.

Explicit disconnect stops the channel, preserves boundary facts about unchanged setup (including previously observed hook trust), resets live observation and previews, invalidates old callbacks and stops source work. Removing a managed configuration also performs this shutdown immediately. A closed setup gate stops observation; a transient readiness failure preserves the reducer's last trustworthy Turns, while missing registration clears them. Deadlines are absent while stopped. The next explicit refresh reopens the channel and restarts the sources; old callbacks cannot replay old Turns. Runtime revision checks reject a suspended refresh that returns after disconnect.

For Claude Code this includes session/transcript/permission/read-state file watchers, session-list reads and quota reads. The directory watcher can pause without destroying subscriptions and rejects queued reattachment while paused. List and quota reads use generations so cancellation-insensitive completions cannot restore old state. Passive screen/application notifications and the buffered forwarding streams live with the product object; they perform no file reads or polling while stopped. Sources holding their own asynchronous work must cooperate with cancellation or invalidate its completion in `stopMonitoring`, as the native readers do; Swift task cancellation alone cannot stop arbitrary upstream code. Codex keeps its separate App Server connection lifecycle and uses the same restricted supplementary-evidence application. Its explicit disconnect/removal now also stops the Hooks listener and rollout source, resets live observation, drops the previous snapshot and parks deadlines; internal App Server reconnects retain their existing recovery behaviour.

Ten new permanent tests in `MonitoringSourceCompositionTests.swift` cover no-setup Settings, timed row content, failure backoff, consumed deadlines and deduplicated ownership, suspended reads at disconnect, independent products, source edges, cancelled native quota completion, watcher pause/resume and stale supplementary evidence after an epoch reset. Final full-suite counts are recorded in the execution table.

Release burst measurement used `getrusage` cumulative process CPU around 1,000 composition refresh/deadline cycles. A parked reader ran only once: **0.40–0.88 ms** across the emitted sample sets. A reader due on every logical cycle ran exactly 1,000 times: **3.21–3.46 ms**. Each set used three fresh compositions per path; the Xcode diagnostics emitted two such sets, and the result bundle reports one successful measurement test with no failures. These measure the composition with an in-memory reader, excluding native I/O, runtime row building and UI. They are not before/after or idle-CPU measurements. There is no new autonomous timer; stopped sources publish no deadline. The temporary fixture, logs and build outputs are removed after recording the result.

Rejected: fake Hooks setup for a native stream, a mandatory all-capabilities source protocol, unrestricted reducer access for supplementary readers, polling every source on unrelated events, and cancellation without guarding late native results. Packages 2–4 and native support coverage remain unchanged. No native schema, file location, configuration bytes, permission operation or answer delivery guarantee changed. The private integration registry records the narrowed evidence interface and source-lifetime changes.

## 9. Cross-package final conformance fixture

After all packages, add a synthetic product that deliberately differs from the shipping protocols. **Added 2026-09-12 with package 2**: [SyntheticProductConformanceTests](../Notchline/NotchlineTests/SyntheticProductConformanceTests.swift), which meets every clause below through the shared runtime and store and registers nothing.

- no Hooks, JSON payload imitation, configuration file or Unix socket;
- explicit native Thread/Turn/request/question/option identities;
- two simultaneous requests of the same kind on one producer;
- identical visible option labels backed by distinct values;
- choices-only input alongside free-text input;
- an asynchronous answer channel with uncertain delivery;
- optional deadline-driven progress and no quota capability.

It must use the existing shared runtime, reducer, request selection, draft handling, navigation dispatch and panel forms. Production changes should be confined to its adapters and registration after the contracts are complete. Do not register this fixture as a shipping product. Borrowing an existing `AgentKind` for isolated tests is acceptable; adding a dynamic plugin loader is not required.

## 10. Verification, commits and clean-up

Use a unique temporary DerivedData directory, then run:

```sh
xcodebuild test -project Notchline/Notchline.xcodeproj -scheme Notchline \
  -destination 'platform=macOS' -only-testing:NotchlineTests \
  -derivedDataPath /tmp/notchline-generalisation-UNIQUE
```

If sandboxing prevents `swift-plugin-server`, retry with the required system permission; do not edit previews or source code to bypass an environmental failure. Distinguish compilation, unit tests and actual product runtime measurements in delivery notes. Use Release for performance evidence; Debug timings are not performance evidence.

Before committing each complete package:

1. Run focused new fixtures and then the full unit suite. Keep meaningful negative and race/ordering cases.
2. Review the diff for unrelated changes, accidental native configuration changes and any duplicate reducer.
3. Update the documents listed for that package, keep the support translation in sync, and check registry links.
4. Record the actual implementation, test counts, failures/retries, remaining limitations and rejected alternatives in this plan and the commit body.
5. Remove temporary builds, logs and probes owned by this work. Preserve the user's unrelated files and worktree changes.
6. Commit the complete package directly on `master` under repository policy. Do not push without separate authorisation.

Resume at the first incomplete package. Re-read its execution record and current source before coding; never infer that a future package was completed merely because its planned type name appeared during an earlier refactor.
