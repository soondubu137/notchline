# Product generalisation implementation plan

## 1. Purpose and handover

This is an authorised implementation plan, dated 2026-09-12, following an audit of commit `32a64e2`. It is not a claim that the planned interfaces already exist. An implementer, including Claude Code, should be able to resume using this document and the repository without the original conversation.

The objective is to integrate another coding-agent product, and its supported higher-level capabilities, by adding boundary adapters and composition code. Reimplementing ordering, Turn reduction, request selection, answer drafts, dismissal or aggregation for each product is not acceptable. A new native protocol still needs an adapter; generalisation cannot manufacture evidence the product does not provide.

The user authorised documenting all five work packages and implementing **work package 1 now**. Work packages 2–5 remain planned until separately undertaken. Do not quietly broaden package 1 into new request operations, concurrent-request presentation, recovery or a change in support level.

Read `../AGENTS.md` and `../CONTEXT.md` first. All paths below are relative to the repository root. Documentation and user-readable strings use British English. Use the current source and tests over an outdated line reference or this plan's proposed type names.

### Current execution record

| Package | Status | Completion evidence |
| --- | --- | --- |
| 1. Standardised evidence and Hooks separation | Complete | `MonitoringRepository`, `HookEvidenceBoundary`, `ProductMonitoringRuntime`; seven new conformance tests; final full suite: 858 definitions, 859 executions, zero failures or skips; committed with this document |
| 2. Requests identified independently of slots | Planned | None |
| 3. Structured answers and permitted operations | Planned | None |
| 4. Answer channels and delivery outcomes | Planned | None |
| 5. Configuration and source lifecycle composition | Planned | None |

At the audited baseline, the full unit suite passed: 851 test definitions, 852 executions including dynamic parameters, zero failures or skips. This is historical evidence, not a substitute for running the suite after changes.

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

## 9. Cross-package final conformance fixture

After all packages, add a synthetic product that deliberately differs from the shipping protocols:

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
