# Tiered support — what a product must do to be a row, and what a terminal must do to be focused

| Field | Value |
| --- | --- |
| Status | **Agreed 2026-09-11; implementation under way.** Supersedes §1.1 of [`README.md`](README.md) where the two disagree (§10 says where). Progress against §8: **P1 landed** the same day (`ProductRegistry`, one Settings copy rule, generated setup sentences, the composition root read from the registry). **P2's contract split landed** the same day: `AgentMonitoring` keeps observation only, `IntegrationConfiguring` / `AnswerDelivering` / `DiskFootprintReporting` are opted into, `IntegrationSetupStatus` replaces `HookSetupStatus`, and `AnswerHandle` replaces the ticket in the domain. Three things in §5.2 were **not** built and are recorded here rather than silently dropped: `AnswerDelivery` stays a `Bool`, because [`answer-in-notch.md`](../../answer-in-notch.md) §8 has two outcomes and no transport produces a third; `ProductModule` carries the service and the navigator only, the store finding the optional contracts by conformance, because no product yet supplies a contract from a second object; and `RuntimeCapabilities` (§5.3) waits for its first reader, a Tier 0 product or a Settings line, rather than shipping as a struct nothing consults. P2's setup unification landed as `ManagedHooksSetup` (the trust-step-free setup, generic over the vocabulary) beside `CodexHookRegistrar` (kept for its trust policy), sharing the helper write, the file read and the editor — two policies as two small actors rather than one actor over a flags value, which §5.4 had proposed and which would have been the switchboard §5.4 also warns against. **P3 landed** the same day: `TerminalHostRegistry` with a `PaneLocator` per entry, the focuser reduced to consent, deadline and execution, the negative-list test replaced by two registry tests, and PRD §10 amended from "scripting dictionary" to "own public interface". `PaneLocator` is an enum with one case rather than the protocol §6.3 sketched, because one mechanism exists; a command-line host adds a case and one runner branch. **P4 began** with the Release baseline and the destination rather than the migration: `HookProductProvider` is the skeleton of §5.4 (setup gate, transport gate, drain, admission, rows, snapshot) with presence and admission as its two seams, proven by `HookProductConformanceTests` — the Tier 0 and Tier 1 fixtures of §7, which is P0's harness at last. The two shipping actors are untouched; migrating them onto the skeleton concern by concern is the rest of P4, and the skeleton was built first so a third product (P5) does not wait on it. Two small reducer changes came with it: `AgentHookVocabulary.answering` is optional, and `HookTurnState.workingDirectory` carries the submission's `cwd` for a product with no Project of its own. **Release baseline before P4** (`288d19a`-era build of the tree at `d97e30c`, `ps -o time` deltas, one display, both integrations registered): launch 0.24 s CPU and 80 MB RSS; idle with no rows 0.34 s per 60 s; one running Claude Code row 1.08 s per 60 s; one Completed row 0.47 s per 60 s; 200 hook events 0.04 s CPU in 0.65 s wall; ten expand/collapse cycles 1.99 s. P4's migration commits are held to these. **First migration concern landed**: the hook transport wiring (setup, reducer, listener) is `HookLifecycleSource`, composed by `ClaudeCodeMonitorService` and `HookProductProvider`; Codex waits, because `CodexHookRegistrar` is not a `ManagedHooksSetup`. **P5 is blocked on this machine**: no third product is installed (checked for Gemini CLI, OpenCode, Cursor, aider, goose, amp), so proving the ladder needs one to be installed, which is the user's choice |
| Investigated | 2026-09-11 |
| Source baseline | Local `master`, `288d19a` (0.2.7 Alpha) |
| Question | Codex and Claude Code are each supported well and each supported differently, and every part of that support was written twice. What is the smallest ladder of promises a third product can climb, and what has to move in the code so that climbing it costs a module rather than a rewrite? Same question for terminals |
| Recommendation | Three cumulative tiers (Listed, Attended, Answerable) plus a declared set of independent capabilities; a product registry that drives composition and Settings; the `AgentMonitoring` protocol split into contracts a product implements only when it has the capability; the two provider actors decomposed into a shared runtime and product-owned evidence sources; a terminal-host registry replacing the one bundle-id switch. Prove it with one hook-based CLI at Tier 0 and one terminal with a public pane CLI |

Terminology follows [`CONTEXT.md`](../../../CONTEXT.md): a **Product** is user-visible, a **Provider** is its in-app adapter. Type names below are proposals unless they already exist in the code.

## 1. What the investigation found

The premise "we have no abstraction for multi-agent support" is half right, and the half that is wrong matters for where the work goes.

**The N-product seam already exists at the top.** `MonitorStore` fans out over an array of `AgentMonitoring` services in a task group and fans in through one pure function, `AgentSnapshotMerge.merge`, which sorts by `AgentKind` and flattens rows ([`MonitorDomain.swift`](../../../Notchline/Notchline/MonitorDomain.swift)). Navigation goes through `AgentNavigationRouter`, a dictionary keyed by product. The grouped list is `AgentKind.allCases.compactMap`, the quota footer is one `FooterRule` per connected product, the collapsed mark is one aggregate mark with no per-product hue, and every socket, helper and install record path is derived from `agent.rawValue`. `NotchOverlayView.swift`, 4,800 lines of UI, contains no product branch at all. In the whole app target there are **three** `switch` statements over `AgentKind`: `displayName`, `HookIntegrationPaths.live(for:)`, and the pair `installedMessage`/`removedMessage` in the store.

**The per-product cost is inside the provider, and it was paid twice.** `LiveCodexMonitorService` is 2,627 lines and `ClaudeCodeMonitorService` is 1,825, and each contains its own monitoring loop: presence with its own trust rule, refresh-deadline computation, read-state gate booking, interrupt evidence, quota scheduling, diagnostics accumulation and snapshot assembly. The only shared kernel is the Turn reducer, `HookEventRepository`, parameterised by `AgentHookVocabulary`. Everything around the reducer that a third product would also need was written once per product, in a different shape each time.

**Nothing declares what a product can do.** What Claude Code cannot do is expressed by absence: `NavigationOutcome.raisedApplication` instead of `.openedThread`, `AgentDiskFootprintReport.leavesNothing` as a protocol default, `isPausedForBackgroundWork` as an identity transform on Codex, `.updateAgent` as a status no Claude Code path can produce. Settings therefore hand-writes two `ProductSettingsCopy` factories with different control flow, and the Codex row reads the **merged** availability while the Claude Code row reads its own, so a ready Claude Code can make the Codex row say `Connected · compatible version` ([`integration-settings-behaviour.md`](../../integration-settings-behaviour.md) §4). The row's help text still says "five Codex lifecycle definitions"; there are seven.

**Hooks are baked into the domain contract.** `AgentMonitoring` requires `installHooks`, `removeHooks`, `hookSetupStatus` and `answer(_:on: HookReplyRegistry.Ticket)`; `AgentSnapshot.setupStatus` is a `HookSetupStatus`. A product observed through a server, an extension or nothing at all would implement four meaningless methods. The two setup writers, `CodexHookRegistrar` and `ClaudeCodeHookSetup`, share `ManagedHooksConfiguration` and `ManagedHooksFileEditor` (both product-free and good) but share no protocol, and `prepareHelper()` is duplicated between them nearly verbatim.

**The test suite has the seed of a conformance suite and one non-reusable harness.** `IntegrationMonitoringStub` and six sibling `AgentMonitoring` stubs take `agent:` and work for any product. `everyRegisteredHookDefinitionMapsToASignalForItsAgent` asserts that the vocabularies cover `AgentKind.allCases`, and would fail the moment a case is added without one. `AnyHookVocabularyCase` runs the same hook events through both products. Against that, `ClaudeCodeHarness` is 590 lines and Claude Code end to end, hook payloads are `[String: Any]` literals rebuilt in about fifteen local `deliver` closures, and one test pins `AgentKind.allCases == [.codex, .claudeCode]` on purpose.

**The terminal side is already generic except for one switch.** Host discovery walks process ancestry and takes the nearest `.app`, so Ghostty, kitty, WezTerm, Alacritty, Warp, and an editor's built-in terminal are all resolved today without a list. The tty comes from the kernel. Read state is the tty's access time plus "is the frontmost pid my ancestor", asked of every host identically. The one per-terminal branch in the app is `AppleEventsTerminalTabFocuser.script(forHost:device:)`, a `switch` over two bundle identifiers returning AppleScript, and the one test that knows the negative list hard-codes five bundle identifiers. There is no seam for a focus mechanism that is not AppleScript.

So the work is not "add an interface"; it is **move the per-product machinery below a line and put a declaration above it**.

## 2. The tiers

A tier is a promise to the user, phrased as what the notch does. Tiers are cumulative: a product's tier is the highest whose **every** requirement it meets. Everything a product does above its tier is a **capability**, declared and listed, never inferred. This keeps the number the user's remark needs ("Claude Code has only degraded navigation") honest: both shipping products are Tier 2, and the difference between them is a capability set.

### Tier 0 — Listed

*The row appears when you submit, changes when the work ends, tells you how long it has run, and takes you back to where the work is.*

Required of the Provider:

| Requirement | Meaning | Already shared? |
| --- | --- | --- |
| Identity | A stable Thread id and Turn id on every boundary, or a local correlation id proposed at the submission boundary and proven against overlap and retry ([`README.md`](README.md) §6.1). Root-Thread eligibility comes from the product, and only "yes" counts (ADR 0017); for a CLI, membership in the product's own live session list is the accepted form | The reducer's identity guards, yes |
| Positive boundaries | Turn started and Turn ended, observed live in this process. Success, failure and interruption may all collapse to ended; silence never counts as ended | Reducer, yes |
| Presence | Whether the product is open, from a kernel fact or a bounded-trust read with a stated ceiling (`tech-design.md` §15.1) | Per product today; §5.4 shares the running-application form |
| Setup | A way to inspect, install and remove the observation and report its health, **or** the declared answer "nothing to configure" | Two unrelated actors today |
| Row content | A project name (working-directory tail is permitted, `Untitled folder` failing that), a title with the prompt-truncation fallback `tech-design.md` §5 already allows, a start instant for the elapsed readout | Yes |
| Navigation | At least **raise the host** and report `raisedApplication`. A CLI gets this free from process ancestry; a desktop product needs its bundle identifier | Yes for CLIs, per product for desktops |
| Dismissal | Right-click removes the row; the Provider stops any per-row work for it | Store and gate, yes |

Not required, and not faked: wait detection, request content, automatic retirement on read, quota, live progress, subagents, Project identity, cold-start recovery.

**Presentation decision this tier forces.** An active Tier 0 Turn is drawn as `Running`, with the same mark and readout as today, and the product's Settings row states *Approvals and questions are not detected for X*. [`README.md`](README.md) §1.1 wanted an internal "attention unavailable" dimension so the kernel never paints confirmed work it cannot confirm. That is right about the kernel and wrong about the row: the row already carries exactly one mark and that mark is the timer (`dual-agent-design.md` §8), and Claude Code's degraded navigation set the precedent that a **declared** boundary is stated in Settings and in the sentence after the click, not drawn on the row (PRD §10, ADR 0004). The honest thing is to declare, not to invent a fifth look. Internally, the reducer keeps the distinction: a Tier 0 vocabulary that produces no wait signals simply never enters the wait states, and `RuntimeCapabilities.waits == .unsupported` (§5.3) is what Settings reads. PRD §6.1 gets one sentence.

A terminal Turn from a Tier 0 product retires only at the Thread's next submission, when the Thread disappears, or on dismissal. That is the lifecycle `CONTEXT.md` already defines for a Turn whose read state cannot be asked about.

### Tier 1 — Attended

*The row tells you when the work is waiting for you, shows you what it is waiting for, and stops asking once you have dealt with it in the product.*

Adds:

| Requirement | Meaning |
| --- | --- |
| Wait opened / resolved | Approval waits and input waits, each with a request identity the resolution can be paired to (`tech-design.md` §9.2). One of the two shapes is enough to enter the tier if the product only has one |
| Request display | The reading-only form for each wait the product has: `command`, `questions`, `document`, or `unsupported` with the sentence "answer in X" ([`answer-in-notch.md`](../../answer-in-notch.md)). Fields are projected once at the boundary, never reconstructed from text |
| Interruption | The user cancelling in the product ends the wait or the Turn (ADR 0011). Required here and not at Tier 0 because a stale `Running` is a nuisance and a stale `Approval needed` is a false call to action; this is exactly CC-019 |
| Human-answered evidence | Something says the wait was answered in the product, so the row returns to `Running` (Codex: activity on another call; Claude Code: agents status or Desktop's permission log) |

A permission event that is observational only (Gemini CLI's `Notification(ToolPermission)`, per [`README.md`](README.md) §3) can enter Tier 1 as a wait **without** any answer button; it cannot enter Tier 2.

### Tier 2 — Answerable

*You can answer from the notch, and a stale click can never answer the wrong thing.*

Adds:

| Requirement | Meaning |
| --- | --- |
| Answer handle | An opaque `AnswerHandle` bound to product, epoch, Thread, Turn and request, valid while the product is still waiting, consumed at most once (§5.2). For hook products it wraps the held connection exactly as `HookReplyRegistry.Ticket` does today |
| Encodings | Grant and refuse; answers and annotations where the product accepts them (`RequestAnswering`) |
| Delivery outcome | Delivered, not delivered, or unknown, reported on the row; a lost acknowledgement is not proof of non-delivery and is never retried blindly |
| Lifecycle stays native | A delivered answer changes nothing until the product's own evidence does (`answer-in-notch.md` §8) |

### Capabilities, declared independently of tier

| Capability | Values | Codex today | Claude Code today |
| --- | --- | --- | --- |
| Navigation | `exact` / `host` / `unavailable` | `exact` (deep link) | `host`: Desktop raised, or terminal pane focused where the host can name it (§6) |
| Read state | `authoritative` / `unsupported`; per host where the product has several | Desktop blue dot | Desktop record + focus log + foreground; terminal tty gesture + ancestry; `unsupported` under tmux/ssh |
| Project identity | `product` / `workingDirectory` | Desktop Project, `Chats`, never cwd (ADR 0003) | cwd tail (ADR 0009) |
| Title | `product` / `prompt` | Desktop name → preview → prompt | transcript title records → `Untitled` |
| Live progress | `pulled` / `pushed` / `unsupported` | `thread/items/list`, per-thread degrade | `MessageDisplay` deltas |
| Final answer text | yes / no | yes | no, by decision |
| Subagents | `counted` / `unsupported` | counted | counted, plus `isPausedForBackgroundWork` |
| Quota | typed measures: rate-limit windows, today's tokens; `unsupported`; `signedOut` | one window + today | up to three windows + today; `signedOut` on a Desktop-only machine |
| Interruption source | native / product status / transcript | rollout tail | agents status (terminal), transcript record (Desktop) |
| Auto-review subtraction | yes / no | yes (`approvals_reviewer`) | no equivalent |
| Cold-start recovery | `none` today for both | none | none |
| Disk footprint | `leavesNothing` / measured | leaves nothing | measured, with the Finder reveal |
| Version gate | can report `updateAgent` / `unsupportedVersion` | yes | never |

`unsupported` is a value, not zero, not `nil` and not `false`: a footer with no quota group for a product is drawn because the product said `unsupported`, not because a read failed.

### Where the two products sit

Both are **Tier 2**. Codex is Tier 2 with every capability except a version-independent presence read and `isPausedForBackgroundWork`. Claude Code is Tier 2 with `navigation: host`, `project: workingDirectory`, no final-answer text, no version gate, and two read-state sources instead of one. That sentence is the whole of what the user's remark about degraded navigation means, and today no type in the app can state it.

## 3. What a new product costs, before and after

Today, a hook-based CLI at Tier 1 needs: an `AgentKind` case and three `switch` arms; an `AgentHookVocabulary`; a `RequestAnswering` (even for a product that cannot answer, because the vocabulary requires one); a setup actor written from `ClaudeCodeHookSetup` by hand; a `HookIntegrationPaths` factory; an `AgentMonitoring` actor of one to two thousand lines copied from whichever existing service is nearer; an `AgentNavigating`; a settings block and a `ProductSettingsCopy` factory; two message strings; the composition edit in `makeShared`; a 600-line harness; and edits to the tripwire tests. Roughly three to four thousand lines, most of it the second copy of a loop that exists twice already.

After §5, the same product needs:

| File | Content | Size |
| --- | --- | --- |
| `Products/Gemini/GeminiProduct.swift` | The `ProductDescriptor`: name, rank, bundle identifiers, static capabilities, setup description, factory | ~60 lines |
| `Products/Gemini/GeminiHookVocabulary.swift` | Event names → `HookSignal`, request projection, managed definitions | ~150 lines |
| `Products/Gemini/GeminiAdmission.swift` | Root-Thread eligibility and the live session list, if the product has one | ~100–300 lines |
| `Products/Gemini/GeminiRequestAnswering.swift` | Only at Tier 2 | ~80 lines |
| Registry entry | One line in `ProductRegistry.builtIn` | 1 line |
| `NotchlineTests/Products/GeminiConformance.swift` | Instantiates the shared tier fixtures with this product's payloads | ~100 lines plus sanitised payloads |

Presence from a bundle identifier, hook transport, setup writing, the reducer, the read-state gate, the terminal-host raise, the Settings row, the install and remove sentences, the footer and the grouped list are all supplied by the shared code and the descriptor. Nothing in `MonitorStore`, `NotchOverlayView`, `SettingsWindow` or `HookIntegration` changes.

## 4. Design rules the refactor keeps

The invariants in `AGENTS.md` §6 and `system-architecture.md` §7 hold throughout, with two renamings recorded in §9:

- **One Turn reducer.** The kernel is the existing `HookEventRepository` logic behind typed observations; no product module reduces status. A Provider proves facts ("this Thread owns this Turn", "this request was auto-reviewed"); the kernel decides what changes.
- **Authority by operation, not by confidence.** Read evidence may retire a terminal Turn and never open one; metadata may retitle and never re-preview; transport health may change availability and never manufacture `Completed`.
- **Fail closed, declare rather than approximate.** A capability the current host cannot deliver reads `unsupported` or `unavailable`; it is never filled in from a heuristic.
- **The UI stays passive and sees one contract.** `MonitorSnapshot` grows a capability record and loses nothing.
- **No new continuous animation, no new per-product mark.** A third product costs a settings row and a footer group, never a change to the collapsed geometry (`expanded-header-v2.md` open item 03).

## 5. The refactor

### 5.1 A registry drives composition and Settings

```swift
struct ProductDescriptor: Sendable {
    let id: AgentKind                       // the enum stays; the registry decides what it means
    let displayName: String
    let rank: Int
    let desktopBundleIdentifiers: [String]  // presence and navigation; empty for a pure CLI
    let implemented: ProductCapabilities    // static: what the module implements
    let setup: SetupDescription             // for Settings copy, see below
    let make: @Sendable (ProductDependencies) -> ProductModule
}

struct SetupDescription: Sendable {
    enum Kind { case managedHooks(file: String, definitionCount: Int, trustStep: String?), nothingToConfigure, productExtension(name: String) }
    let kind: Kind
    let restoreAdvice: String               // today's `restoreDefinitionAdvice`
}

enum ProductRegistry {
    static let builtIn: [ProductDescriptor]  // Codex, Claude Code; a third is one element
}
```

`MonitorStore.makeShared` becomes `ProductRegistry.builtIn.map { $0.make(deps) }`, the navigator dictionary and the merged change stream fall out of the same map, and `defaultIntegrationAgent` with its no-argument spellings (`hookSetupStatus`, `integrationSwitchIsOn()`) is deleted: every integration accessor already takes an `AgentKind`.

`ProductConnectionRows` becomes a `ForEach` over the registry. `ProductSettingsCopy` becomes **one** function of `(SetupDescription, IntegrationSetupStatus, MonitorAvailability, AgentPresence, RuntimeCapabilities, diagnostic)`, reading that product's own availability, which fixes the merged-availability defect and the `.reviewRequired` fall-through in the same change. Help text, definition counts, file names and the install and remove sentences are generated from `SetupDescription`, so "five definitions" cannot go stale again. The diagnostic that reads `Codex data refreshed` on a Claude Code snapshot goes with it.

Ordering stays declaration order; `rank` is the descriptor's, and the tripwire test pins the registry's order rather than the enum's.

### 5.2 One protocol becomes five contracts

```swift
protocol ProductObserving: Sendable {           // Tier 0, required
    var agent: AgentKind { get }
    var stateChangeEvents: AsyncStream<Void> { get }
    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot
    func nextRefreshDeadline() async -> Date?
    func disconnect() async
}
protocol IntegrationConfiguring: Sendable {      // Tier 0, required; a `NothingToConfigure` value conforms
    func status() async -> IntegrationSetupStatus
    func install() async throws
    func remove() async throws
}
protocol ThreadNavigating: AnyObject {           // Tier 0, required; today's `AgentNavigating`
    func open(_ session: MonitoredSession) async throws -> NavigationOutcome
}
protocol RequestAnswering: Sendable {            // Tier 2 only; today's name, widened to the handle
    func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> AnswerDelivery
}
protocol UsageReading: Sendable {                // capability
    func usage() async -> QuotaSnapshot
}
protocol DiskFootprintReporting: Sendable {      // capability
    func diskFootprint() async -> AgentDiskFootprintReport
}

struct ProductModule {                           // what `make` returns
    let observing: any ProductObserving
    let configuring: any IntegrationConfiguring
    let navigating: any ThreadNavigating
    let answering: (any RequestAnswering)?
    let usage: (any UsageReading)?
    let footprint: (any DiskFootprintReporting)?
}
```

`HookSetupStatus` is renamed `IntegrationSetupStatus` with the same four cases; `HookReplyRegistry.Ticket` leaves `MonitoredSession`/`AgentRequest` behind an opaque `AnswerHandle` that wraps it for hook products and carries the stale-answer protection unchanged. `AnswerDelivery` is `delivered` / `notDelivered` / `unknown`, replacing the current `Bool`, because `answer-in-notch.md` §8 already distinguishes them in prose.

The store's fan-out loops over `module.observing`; answering asks `module.answering` and reads `nil` as "not a Tier 2 product", which is the same fact the row's capability record shows.

### 5.3 Capabilities ride on the snapshot

```swift
struct RuntimeCapabilities: Equatable, Sendable {
    var navigation: Navigation            // exact / host / unavailable
    var readState: ReadState              // authoritative / unsupported / temporarilyUnavailable
    var waits: Waits                      // observed / unsupported
    var answering: Answering              // available / unsupported
    var quota: Quota                      // available / unsupported / signedOut
    var project: ProjectIdentity          // product / workingDirectory
    var progress: Progress                // pulled / pushed / unsupported
    var subagents: Subagents              // counted / unsupported
}
```

Static capabilities (`ProductDescriptor.implemented`) say what the module can do; `AgentSnapshot.capabilities` says what this host, version and configuration deliver now, and is what Settings and the click sentence read. The two are separate because the same Claude Code module reports `quota: .signedOut` on a Desktop-only machine and `.available` elsewhere, and `readState: .unsupported` for a tmux session next to `.authoritative` for a Ghostty one. Equality on the snapshot is unchanged in kind, so the publish rule in `AGENTS.md` §7 is untouched.

### 5.4 The two provider actors become a shared runtime and product-owned sources

This is the expensive step and the one that makes the next product cheap. It is also the step `AGENTS.md` §5.4 warns about: nearly every line in these two actors is held in place by a measurement. It is done one concern at a time, each with the existing tests still passing, and Claude Code first because it has the harness.

```swift
actor ProductMonitorRuntime: ProductObserving {
    // owned: refresh deadlines, dismissed rows, terminal-gate booking, presence trust ceiling,
    //        diagnostics accumulation, snapshot assembly, single-flight, stability
    init(descriptor: ProductDescriptor,
         lifecycle: any LifecycleSource,             // typed observations in; hook socket + vocabulary is one implementation
         presence: any PresenceSource,               // .runningApplication(bundleIDs) shared; Claude Code's listing is another
         admission: any ThreadAdmitting,             // eligibility + metadata: App Server for Codex, agents list for Claude Code
         readEvidence: [any ReadEvidenceSource],     // Desktop records, terminal gestures (shared), or none
         interruption: (any InterruptionSource)?,
         usage: (any UsageReading)?)
}
```

What moves where:

| Today | Destination | Shared or product-owned |
| --- | --- | --- |
| `HookEventRepository` reduction, `AgentWaitSlots`, ordering guards | `MonitoringCore` (kernel) behind `Observation` values | shared |
| `HookEventRepository` delivery, trust bookkeeping, `HookReplyRegistry`, `AgentHookListener`, `AgentHookHelper`, `HookPayload` | `HookLifecycleSource`, one instance per hook product, parameterised by vocabulary | shared transport family |
| `CodexHookRegistrar`, `ClaudeCodeHookSetup` | one `ManagedHooksSetup` actor over `ManagedHooksConfiguration` plus a per-product policy value (trust hashing and never-rewrite for Codex; helper-first and strip-legacy for Claude Code); `prepareHelper()` once | shared, with two policy values |
| `desktopProcessIdentifier()`, `ClaudeCodeSessionRegistry.presence()` | `RunningApplicationPresence` (shared) and `ClaudeCodeSessionPresence` (product) | split |
| `CodexSnapshotParser.isEligibleRootThread`, `thread/read` metadata; `liveByID` membership | `CodexThreadAdmission`, `ClaudeCodeThreadAdmission` | product-owned |
| `CodexDesktopUnreadStateRepository`; `ClaudeCodeDesktopReadStateRepository` + focus log + reading watcher; `ControllingTerminalGestureReader` | `ReadEvidenceSource` conformers; the terminal one is shared by every CLI product | split |
| `CodexRolloutTurnAbortReader`; `ClaudeCodeTranscriptReader.interruption`, agents `activity` | `InterruptionSource` conformers | product-owned |
| `readAccountUsageIfNeeded`, `ClaudeCodeUsageReader` | `UsageReading` conformers | product-owned |
| `TerminalUnreadMembershipGate`, deadline arithmetic, `SingleFlightGate` use, diagnostics list | `ProductMonitorRuntime` | shared |
| `CodexAppServerClient`, the private Desktop repositories, `ClaudeCodeSessionRegistry`, transcript readers | unchanged, product-owned | product-owned |

The Codex hook `PreToolUse(request_permissions)` wake-up, the held-Turn settlement from the rollout, and the `MessageDisplay` diversion are the three behaviours `AgentHookVocabulary` flags today (`wakesOnToolCallOpened`, `settlesHeldTurnsFromRecord`, `messageDeltaEventName`). They stay as vocabulary declarations; the runtime asks the vocabulary, as the reducer does now. The rule from [`README.md`](README.md) §2 stands: these encode measured edge cases and must not grow into a switchboard, so a fourth flag needs a named invariant and a test, not a boolean.

Source groups, not package targets. One Xcode target keeps the build and the unshared scheme as they are; a `Products/<Name>/` folder per product and `Monitoring/{Core,Runtime,Transport}` folders give the dependency direction reviewers need. Package targets can follow once the boundary has survived a third product.

### 5.5 A hook product is one vocabulary, and the vocabulary is already the right shape

`AgentHookVocabulary` is the best artefact in the code for this exercise: every requirement on it is a measured per-product fact with its measurement in the comment. It stays as the hook family's adapter. Two changes: `answering` becomes optional (a Tier 1 hook product has none), and `agent` is supplied by the descriptor so the vocabulary cannot disagree with it. `everyRegisteredHookDefinitionMapsToASignalForItsAgent` iterates the registry's hook products instead of a hand-written array.

## 6. Terminal hosts

### 6.1 What is generic already, and what is not

Every Claude Code session hosted in a terminal gets, with no per-terminal code: its host resolved by process ancestry (`ProcessAncestryHostResolver`), including an editor's built-in terminal where the editor is the right thing to raise; its tty from the kernel; read state from the tty's access time and the foreground pid's ancestry; the raise sequence with the Space check; and the outcome sentence. All of that is Claude Code's today only because Claude Code is the only CLI, and it moves to the shared `ReadEvidenceSource` and `ThreadNavigating` for every CLI product in §5.4.

The one per-terminal branch is `AppleEventsTerminalTabFocuser.script(forHost:device:)`: Terminal.app and iTerm2 publish a tty in their scripting dictionaries and get their tab selected; Ghostty publishes a full dictionary with no tty; kitty, WezTerm and Alacritty publish none. `TerminalTabFocusing` receives `(device, HostApplication)` and its only implementation is AppleScript, so a host whose public interface is a command line rather than a dictionary has no way in, however precisely it can name a pane.

### 6.2 Terminal tiers

| Tier | Promise | Requirement | Hosts today |
| --- | --- | --- | --- |
| **T0 Raised** | The click brings the host application forward, onto the Space that holds it | An `.app` in the session's ancestry | Every terminal and editor; automatic |
| **T1 Focused** | The click selects the pane or tab the session is in | The host names a pane by **identity** — the controlling tty, or the shell pid this app already holds — through the host's **own public interface**, and can select it | Terminal.app, iTerm2 (AppleScript). Candidates: WezTerm (`wezterm cli list` reports a tty per pane, `activate-pane`), kitty (remote control matches a window by child pid; needs the user's `allow_remote_control`), tmux (`#{pane_tty}` then `select-window`/`select-pane`, followed by T0 on the attached client's host). **All three unmeasured**; each is a probe before it is a row in this table |
| **T2 Read** | A finished row leaves when you have been at that pane | The kernel tty access time, plus a host that can ever be in front | Every direct host. `unsupported` under tmux, screen and ssh, where the ancestry has no `.app`. A tmux adapter could restore it by naming the attached client's tty; unmeasured |
| Declared out of reach | A full-screen host | No public interface crosses into a full-screen Space (`tech-design.md` §14.2) | Unchanged |

T2 is listed for completeness because it is where multiplexers differ; for direct hosts it is not a tier a terminal has to climb.

### 6.3 A host registry replaces the switch

```swift
struct TerminalHostAdapter: Sendable {
    let bundleIdentifiers: [String]
    let displayName: String?                 // nil: take the bundle's
    let paneLocator: (any PaneLocating)?     // nil: T0 only
}
protocol PaneLocating: Sendable {
    /// Selects the pane holding `device` or owned by `shellPID`; `.unavailable` when the
    /// host cannot say. Never matches on title, working directory or geometry.
    func focusPane(device: String, shellPID: Int32, in host: HostApplication) async -> TerminalTabFocus
}
struct AppleScriptPaneLocator: PaneLocating   // Terminal.app, iTerm2: today's scripts, unchanged
struct CommandLinePaneLocator: PaneLocating   // a bounded subprocess with a deadline, for WezTerm-shaped hosts
```

`TerminalHostRegistry.builtIn` holds Terminal.app and iTerm2 with the AppleScript locator. `onlyHostsThatPublishATerminalDeviceAreScripted` becomes two tests: every registered locator names a pane by identity, and an unregistered host degrades to `raisedApplication`. Adding a T1 terminal is one registry entry, one locator, and one conformance fixture; the negative list is nobody's to maintain.

**PRD amendment, one sentence.** §10 permits pane focus "only through the terminal's own public scripting dictionary". The rule should read *through the terminal's own public interface, matching on the controlling tty or the shell's pid and never on titles, geometry or Accessibility*. A remote-control command line is the terminal's public interface as much as a dictionary is; what the rule protects is the identity match and the ban on GUI automation, and both survive. A locator that needs the user to enable something (kitty) reports `unavailable` when it is off, exactly as a denied Automation consent does today.

The Apple Events consent choreography (ask in the background, degrade the first click, treat refusal as final) stays in the AppleScript locator; a command-line locator has no TCC step and instead a deadline, the same 5 s race the scripts use.

## 7. Conformance suite

One generic harness, extracted from `ClaudeCodeHarness`: `ProductHarness(descriptor:, paths:, vocabulary:, clock:)` that stands up the module in a temporary root with its own socket, the real reducer and stubs for every source. Then fixtures per tier, each a function of the harness and the product's sanitised payloads:

| Tier | Fixtures |
| --- | --- |
| 0 | start → end; duplicate and old-epoch events; two windows on one Thread make one row; dismissal stops the gate; presence drawn from the declared source; install/remove idempotent, byte-equality no-op, unknown structures preserved; navigation reports the true outcome; a pre-launch event opens nothing |
| 1 | approval opened → resolved; input opened → resolved; interrupt with the dialogue open clears the wait; request fields projected once and equal across ticket changes (today's `approvalFieldsReachBothProductsAndSurviveTicketChanges`); an observational permission event produces no handle |
| 2 | stale handle answers nothing; delivery reported as `notDelivered` when the connection is gone; each encoding the product accepts round-trips; a delivered answer changes no status until native evidence |
| Capabilities | one fixture per declared capability, run only when declared; `unsupported` never renders as zero |
| Terminal T1 | the locator is asked with the tty and shell pid, never a title; an unregistered host raises |

The existing 764 tests stay; the ~150 that are structurally product-bound are unchanged, since the product modules keep their types. Sanitised payloads come from the fixtures the suite already carries; no user conversation is a fixture.

## 8. Migration, in reviewable commits

Each phase is a complete change with the suite green before commit; each exit is testable.

| Phase | Change | Exit |
| --- | --- | --- |
| **P0 Pin** | Extract `ProductHarness` from `ClaudeCodeHarness`; add the Tier 0–2 fixtures and run both products through them; make the vocabulary tests iterate a list built from `AgentKind.allCases` | Both products pass the same fixtures; no behaviour change; Release CPU baseline recorded (`ps -o time` diffs for hover and event bursts, sampling for idle) |
| **P1 Registry** | `ProductDescriptor`, `ProductRegistry.builtIn`, `makeShared` from the registry; Settings rows as `ForEach`; one `ProductSettingsCopy` reading per-product availability; generated help text and messages; delete `defaultIntegrationAgent` | A `IntegrationMonitoringStub`-backed test product registers, appears in Settings with generated copy, installs and removes, without editing any product switch. The merged-availability defect is gone and pinned |
| **P2 Contracts** | Split `AgentMonitoring` into the five contracts; `IntegrationSetupStatus`; `AnswerHandle` and `AnswerDelivery`; `RuntimeCapabilities` on `AgentSnapshot`; `ManagedHooksSetup` over two policy values with one `prepareHelper` | A test product with no answering and no quota compiles against no meaningless methods; Settings and the click sentence read capabilities, not absences |
| **P3 Terminals** | `TerminalHostRegistry`, `PaneLocating`, the AppleScript locator; the negative-list test becomes the two registry tests | Adding a locator for a stub bundle id needs no edit outside the registry and its fixture |
| **P4 Runtime** | `ProductMonitorRuntime`, one concern per commit in this order: presence, refresh deadlines, dismissed rows and gate booking, diagnostics, quota scheduling, read evidence, interruption, admission. Claude Code first, then Codex | Both provider actors are compositions; no Release regression against P0's baseline; the `AGENTS.md` §6 renamings in §9 land with the last commit |
| **P5 Prove** | One hook-based CLI at Tier 0, then see whether Tier 1 is reachable honestly (Gemini CLI is the candidate from [`README.md`](README.md) §3); one T1 terminal (WezTerm, if its CLI names a pane by tty as documented) | The product is a `Products/<Name>/` folder and a fixture file; the terminal is a registry entry and a locator. Whatever fails is recorded as a narrower tier, never as a heuristic in the kernel |

A product that requires a server rather than hooks (OpenCode) is the right **second** proof, after the cheap path is proven, because it tests `LifecycleSource` rather than the registry.

## 9. Contract changes, and the documents that carry them

| Current rule | Proposed | Documents |
| --- | --- | --- |
| "One orchestration centre: `LiveCodexMonitorService`" | One centre per product, `ProductMonitorRuntime`, with the product's sources as its inputs; still one reducer | `AGENTS.md` §6, `system-architecture.md` §1, §5, §7 |
| "Hook events enter only `HookEventRepository`" | Observations enter only the kernel; the hook source is one caller | same, plus the invariant tests |
| Provider is the whole adapter | Provider is the composition of a runtime and sources; **Tier** and **Capability** become defined terms | `CONTEXT.md` |
| Two-product Settings, prose counts | Rows and copy generated from `SetupDescription` | `integration-settings-behaviour.md` (§1/§2 become one section over the descriptor), `PRD.md` §11 |
| A Tier 0 active Turn's look | Drawn as `Running`; the boundary is declared in Settings | `PRD.md` §6.1, §12; `dual-agent-design.md` §8 |
| Pane focus only via scripting dictionary | Via the host's public interface, matching tty or shell pid | `PRD.md` §10, ADR 0004 addendum, `tech-design.md` §14.2 |
| `answer(...) -> Bool` | `AnswerDelivery` | `answer-in-notch.md` §8 |
| Support table in the README | Per product: tier and capability list; per terminal: T0/T1 | `README.md` |
| Private dependency registry | Unchanged rows; a new product adds its own section as Claude Code did | `non-public-codex-integration-features.md` |

`tech-design.md` §5 "Sources of truth" is still written Codex-first and becomes the one table a capability list would contradict; it should be reorganised per capability with a column per product in P1.

## 10. Where this departs from the earlier proposal

[`README.md`](README.md) is the reasoning this document builds on; four points differ.

1. **Numbered cumulative tiers plus capabilities**, rather than bands of functionality described by a label. The user-facing question is "how well is X supported", and a number answers it; the capability set keeps it honest.
2. **A Tier 0 active Turn is drawn as `Running` and declared in Settings**, rather than given an "attention unavailable" presentation. The row carries one mark; the precedent for a declared boundary is already shipped.
3. **Terminals are in scope** with their own registry and tiers; the earlier document did not address them.
4. **Package targets and an external Provider protocol are out of scope.** Source groups are enough for the dependency direction; nothing about the next product needs process isolation.

## 11. NO-GO conditions

Unchanged from [`README.md`](README.md) §9, restated for the tier ladder: a product enters no tier by inferring Turn state from silence, replaying historical hooks, mistaking another runtime for the user's, or creating permission prompts to observe them. A product enters Tier 1 only if a cancelled wait is observed as ending. A product enters Tier 2 only if a handle can be proven stale. A terminal enters T1 only on an identity match through its own public interface. When any of these fails, the product or host is recorded at the tier it earned.

No hook registration, application restart, answer operation or third-product probe was performed for this document. The private integration registry was checked: this proposal adds, modifies, migrates and removes no production non-public integration; §9 lists the updates implementation would owe it.
