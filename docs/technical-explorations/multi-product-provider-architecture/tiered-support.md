# Provider architecture and support migration

**Support contract replaced on 2026-09-12.** [Product support](../../product-support.md) owns the six cumulative levels, request coverage and independent capabilities. This document retains the architecture proposal, implementation history and measurements; proposed types below are not a second support contract.

| Field | Value |
| --- | --- |
| Status | **Architecture agreed 2026-09-11; implementation history below. Support classification replaced 2026-09-12 by [product-support.md](../../product-support.md).** Progress against §8: **P1 landed** the same day (`ProductRegistry`, one Settings copy rule, generated setup sentences, the composition root read from the registry). **P2's contract split landed** the same day: `AgentMonitoring` keeps observation only, `IntegrationConfiguring` / `AnswerDelivering` / `DiskFootprintReporting` are opted into, `IntegrationSetupStatus` replaces `HookSetupStatus`, and `AnswerHandle` replaces the ticket in the domain. Three things in §5.2 were **not** built and are recorded here rather than silently dropped: `AnswerDelivery` stays a `Bool`, because [`answer-in-notch.md`](../../answer-in-notch.md) §8 has two outcomes and no transport produces a third; `ProductModule` carries the service and the navigator only, the store finding the optional contracts by conformance, because no product yet supplies a contract from a second object; and `RuntimeCapabilities` (§5.3) waits for its first reader, a product without wait detection or a Settings line, rather than shipping as a struct nothing consults. P2's setup unification landed as `ManagedHooksSetup` (the trust-step-free setup, generic over the vocabulary) beside `CodexHookRegistrar` (kept for its trust policy), sharing the helper write, the file read and the editor — two policies as two small actors rather than one actor over a flags value, which §5.4 had proposed and which would have been the switchboard §5.4 also warns against. **P3 landed** the same day: `TerminalHostRegistry` with a `PaneLocator` per entry, the focuser reduced to consent, deadline and execution, the negative-list test replaced by two registry tests, and PRD §10 amended from "scripting dictionary" to "own public interface". `PaneLocator` is an enum with one case rather than the protocol §6.3 sketched, because one mechanism exists; a command-line host adds a case and one runner branch. **P4 began** with the Release baseline and the destination rather than the migration: `HookProductProvider` is the skeleton of §5.4 (setup gate, transport gate, drain, admission, rows, snapshot) with presence and admission as its two seams, proven by `HookProductConformanceTests` — the lifecycle/context and wait/request-reading fixtures of §7, which is P0's harness at last. The two shipping actors are untouched; migrating them onto the skeleton concern by concern is the rest of P4, and the skeleton was built first so a third product (P5) does not wait on it. Two small reducer changes came with it: `AgentHookVocabulary.answering` is optional, and `HookTurnState.workingDirectory` carries the submission's `cwd` for a product with no Project of its own. **Release baseline before P4** (`288d19a`-era build of the tree at `d97e30c`, `ps -o time` deltas, one display, both integrations registered): launch 0.24 s CPU and 80 MB RSS; idle with no rows 0.34 s per 60 s; one running Claude Code row 1.08 s per 60 s; one Completed row 0.47 s per 60 s; 200 hook events 0.04 s CPU in 0.65 s wall; ten expand/collapse cycles 1.99 s. P4's migration commits are held to these. **Held, at `bba79af`**: measured back to back against a Release build of `d97e30c` from a worktree, same script, nothing else running — idle no rows 0.37 s before and 0.38 s after per 60 s; 200 hook events 0.05 s and 0.05 s; ten expand/collapse cycles 2.10 s and 1.96 s; one running row 0.40 s and 0.51 s. The one-Completed-row window is not usable as a regression signal the way it was staged: it read 0.47, 1.30, 1.14 and 0.32 s across four runs with no relation to the binary, because the staged row was this very Claude Code session, whose Desktop record and transcript change as the session works and whose read-state re-check therefore does variable work. A future run stages that row from a FIFO-fed `claude -p` in a real Terminal window instead. **First migration concern landed**: the hook transport wiring (setup, reducer, listener) is `HookLifecycleSource`, composed by `ClaudeCodeMonitorService` and `HookProductProvider`; Codex waits, because `CodexHookRegistrar` is not a `ManagedHooksSetup`. ~~**P5 is blocked on this machine**: no third product is installed (checked for Gemini CLI, OpenCode, Cursor, aider, goose, amp), so proving the ladder needs one to be installed, which is the user's choice~~ **P5's product half landed 2026-09-11** with Antigravity CLI 1.2.2 (`agy`), installed by the user that evening, with **lifecycle/context support**: [`antigravity-cli.md`](antigravity-cli.md) is the measurement and the build. The ladder held, and two seams it had not anticipated were cut first, one commit each: a managed hooks file may keep this app's events under a name of its own with bare handler lists (`ManagedHooksConfiguration.containerKey`, `ManagedHookDefinition.Shape` — a group under one of that product's lifecycle events disables every handler of the named hook, silently); and a product whose payloads name neither their event nor their Turn gets `HookRegistrationDialect` (the helper announces the event it was registered for) and `HookPayloadTranslating` (the vocabulary translates, and may propose a local Turn identity at the one boundary §6.1 of the README allows). The product is `Products/Antigravity/`, one descriptor, one enum case and a conformance file; `RuntimeCapabilities` still waits, and its first reader turned out to be one sentence, `ProductDescriptor.declaredBoundary`, shown under the Settings row. `ClaudeCodeNavigator` is `ProcessHostNavigator`, since a CLI's rows go back to a terminal the same way. L4 wait detection is not reachable honestly there — nothing in its hooks observes a wait, and a headless auto-denial fires nothing — and the terminal with pane focus of P5 is not started. **P5's product half was then taken end to end through a Release build**, the exit §8 asks for: the registration the switch writes is one `agy` loads, a turn draws a row, and clicking it focuses the Terminal window that conversation runs in. It cost what P4's baseline costs — idle with three products 0.26 and 0.27 s per 60 s against a 0.34–0.38 s baseline, 200 hook events 0.03 s against 0.04–0.05 s, one running row 0.38 s against 0.40–0.51 s — and found one defect no test could have: `HookProductProvider` answered `QuotaSnapshot.unavailable`, the *single-window* form, so the footer drew a `-- left` line under a product that has no window, where [`quota-footer-v2.md`](../../quota-footer-v2.md) §5 asks for the outer row alone. `QuotaSnapshot.noneReported` is the empty-window value and the Provider answers it. That is the third seam this phase found, and like the other two it was in the shared code rather than in the product. **Extended 2026-09-12**: the row's title. L2's row content asks for "a title with the prompt-truncation fallback", and this product had been shipping `Untitled` because no payload carries a prompt — so it was below its own tier on the one thing a person reads first. The transcript the payload already names carries it, read at the boundary and once more at the turn's end if the first read was too early (`antigravity-cli.md` §2.1). The fourth seam, and again shared: a late prompt fills a blank title and never overwrites one. **Extended again the same day**: read state. A row without wait detection stood on the notch until the conversation's next turn however thoroughly it had been read, which §2 had written as the tier's lifecycle and is really the lifecycle of a product that cannot be asked — so the fifth seam is `TerminalReadEvidence`, the terminal read source §5.4 always meant to share, composed by `HookProductProvider` from the reader Claude Code already uses and the process the product already names (`antigravity-cli.md` §3.1). It costs a product nothing it does not already supply, and it cost this one a 1 Hz re-check whose price is in that document's §7 **P4 closed 2026-09-12**, in eight commits and in §8's order except that admission came before interruption, because Claude Code's interruption evidence reads the session list admission takes. Every concern is now one shared piece: presence (`RunningApplicationPresence`, which Codex reads too, pid and presence in one look), which rows the read gate is asked about and the deadline it books (`TerminalUnreadRowFilter`), the transport and the reasons a refresh stops (`HookLifecycleSource` over `HookRegistrationSetup`, so Codex's registrar plugs in), quota (`UsageReading`, with Codex's reads moved into `CodexUsageReader`), read evidence (`ReadEvidenceSource`), admission (`ProductSessionReading`, `ThreadAdmission` for Codex too) and non-hook Turn evidence (`TurnEvidenceSource`). **The exit is met for the two products observed through hooks alone and departs for Codex, deliberately.** Claude Code is a composition of `HookProductProvider` — `ClaudeCodeMonitorService` is now the composition root of six sources, and the 590-line harness runs through it unchanged — and so is Antigravity CLI. Codex composes every shared piece but keeps its own actor: beside its hooks it runs an App Server under a cool-off, whose unsupported version and transient failures are availabilities of their own and whose background reads decide which Threads have rows, and folding that second lifecycle into the runtime is the switchboard §5.4 warns about. OpenCode, §8's server-backed second proof, is where a `LifecycleSource` beside hooks would be designed against two products rather than one. Three behaviours changed and are stated where they changed: Claude Code's card stopped repeating every reducer diagnostic twice and stopped telling the user to paste a registration a switch now writes; a closed integration also stops the permission-log watch; and the runtime judges rows while presence is `unknown` (publishing none), so a list that stops answering no longer resets what was read. §5.4 *As built* maps the proposal's names onto the code. **Held against the baseline**, measured back to back in two pairs, in both orders, against a Release build of `896052e` (the tree before P4's remaining concerns) — real home, all three integrations registered, `ps -o time` deltas, the staged row posted to the socket for the measuring session while that session sat inside one foreground command so its own record could not move: launch 0.35 / 0.33 s CPU before against 0.34 / 0.30 s after, 81–83 MB either way; idle with no rows 0.44 / 0.46 s per 60 s against 0.44 / 0.43; one running Claude Code row 0.56 / 0.54 against 0.56 / 0.54; **one Completed row waiting to be read 1.48 / 1.49 against 1.50 / 1.51** — the window that exercises the moved read gate, read evidence and session source every second, and stable this time because of how it was staged; 200 hook events for an unlisted session 0.67 / 0.67 s CPU against 0.67 / 0.61. The expand/collapse cycles were not repeated: P4 changed no view and no store code, and a hover's refresh is the same `fetchSnapshot` the windows above already price |
| Investigated | 2026-09-11 |
| Source baseline | Local `master`, `288d19a` (0.2.7 Alpha) |
| Question | Codex and Claude Code are each supported well and each supported differently, and every part of that support was written twice. What is the smallest ladder of promises a third product can climb, and what has to move in the code so that climbing it costs a module rather than a rewrite? Same question for terminals |
| Recommendation | Six cumulative support levels with scoped request coverage and independent capabilities ([product-support.md](../../product-support.md)); a product registry that drives composition and Settings; the `AgentMonitoring` protocol split into contracts a product implements only when it has the capability; the two provider actors decomposed into a shared runtime and product-owned evidence sources; a terminal-host registry replacing the one bundle-id switch. Prove it with one hook-based CLI with lifecycle/context support and one terminal with a public pane CLI |

Terminology follows [`CONTEXT.md`](../../../CONTEXT.md): a **Product** is user-visible, a **Provider** is its in-app adapter. Type names below are proposals unless they already exist in the code.

## 1. What the original investigation found

The premise "we have no abstraction for multi-agent support" is half right, and the half that is wrong matters for where the work goes.

**The N-product seam already exists at the top.** `MonitorStore` fans out over an array of `AgentMonitoring` services in a task group and fans in through one pure function, `AgentSnapshotMerge.merge`, which sorts by `AgentKind` and flattens rows ([`MonitorDomain.swift`](../../../Notchline/Notchline/MonitorDomain.swift)). Navigation goes through `AgentNavigationRouter`, a dictionary keyed by product. The grouped list is `AgentKind.allCases.compactMap`, the quota footer is one `FooterRule` per connected product, the collapsed mark is one aggregate mark with no per-product hue, and every socket, helper and install record path is derived from `agent.rawValue`. `NotchOverlayView.swift`, 4,800 lines of UI, contains no product branch at all. In the whole app target there are **three** `switch` statements over `AgentKind`: `displayName`, `HookIntegrationPaths.live(for:)`, and the pair `installedMessage`/`removedMessage` in the store.

**The per-product cost is inside the provider, and it was paid twice.** `LiveCodexMonitorService` is 2,627 lines and `ClaudeCodeMonitorService` is 1,825, and each contains its own monitoring loop: presence with its own trust rule, refresh-deadline computation, read-state gate booking, interrupt evidence, quota scheduling, diagnostics accumulation and snapshot assembly. The only shared kernel is the Turn reducer, `HookEventRepository`, parameterised by `AgentHookVocabulary`. Everything around the reducer that a third product would also need was written once per product, in a different shape each time.

**Nothing declares what a product can do.** What Claude Code cannot do is expressed by absence: `NavigationOutcome.raisedApplication` instead of `.openedThread`, `AgentDiskFootprintReport.leavesNothing` as a protocol default, `isPausedForBackgroundWork` as an identity transform on Codex, `.updateAgent` as a status no Claude Code path can produce. Settings therefore hand-writes two `ProductSettingsCopy` factories with different control flow, and the Codex row reads the **merged** availability while the Claude Code row reads its own, so a ready Claude Code can make the Codex row say `Connected · compatible version` ([`integration-settings-behaviour.md`](../../integration-settings-behaviour.md) §4). The row's help text still says "five Codex lifecycle definitions"; there are seven.

**Hooks are baked into the domain contract.** `AgentMonitoring` requires `installHooks`, `removeHooks`, `hookSetupStatus` and `answer(_:on: HookReplyRegistry.Ticket)`; `AgentSnapshot.setupStatus` is a `HookSetupStatus`. A product observed through a server, an extension or nothing at all would implement four meaningless methods. The two setup writers, `CodexHookRegistrar` and `ClaudeCodeHookSetup`, share `ManagedHooksConfiguration` and `ManagedHooksFileEditor` (both product-free and good) but share no protocol, and `prepareHelper()` is duplicated between them nearly verbatim.

**The test suite has the seed of a conformance suite and one non-reusable harness.** `IntegrationMonitoringStub` and six sibling `AgentMonitoring` stubs take `agent:` and work for any product. `everyRegisteredHookDefinitionMapsToASignalForItsAgent` asserts that the vocabularies cover `AgentKind.allCases`, and would fail the moment a case is added without one. `AnyHookVocabularyCase` runs the same hook events through both products. Against that, `ClaudeCodeHarness` is 590 lines and Claude Code end to end, hook payloads are `[String: Any]` literals rebuilt in about fifteen local `deliver` closures, and one test pins `AgentKind.allCases == [.codex, .claudeCode]` on purpose.

**The terminal side is already generic except for one switch.** Host discovery walks process ancestry and takes the nearest `.app`, so Ghostty, kitty, WezTerm, Alacritty, Warp, and an editor's built-in terminal are all resolved today without a list. The tty comes from the kernel. Read state is the tty's access time plus "is the frontmost pid my ancestor", asked of every host identically. The one per-terminal branch in the app is `AppleEventsTerminalTabFocuser.script(forHost:device:)`, a `switch` over two bundle identifiers returning AppleScript, and the one test that knows the negative list hard-codes five bundle identifiers. There is no seam for a focus mechanism that is not AppleScript.

So the work is not "add an interface"; it is **move the per-product machinery below a line and put a declaration above it**.

## 2. Support levels and capabilities

The authoritative requirements are now [product-support.md](../../product-support.md) §§1–5: L1 Lifecycle monitoring, L2 Context identification, L3 Progress monitoring, L4 Wait detection, L5 Request reading and L6 Request answering. The level is derived from the highest cumulative coverage in the declared modes and request forms; higher-level capabilities can be supplied independently without claiming the intervening levels.

Codex Desktop has L6 coverage for ordinary `PermissionRequest`; its synchronous questions and `request_permissions` are reading-only. Claude Code has L6 coverage for its declared request forms. Antigravity CLI has L3 coverage with mode and update-timing limits. Read removal, navigation, quota and usage, final answers, subagents, recovery and terminal reasons are independent capabilities. The full product and request matrices live in that contract, not in a second table here.

**Why the old definition was replaced.** The first tier bundled identity, metadata and host navigation, while the next combined wait detection and request reading. It left progress outside the ladder and hid the difference between those separate behaviours. There is no direct numeric conversion: the original minimal hook fixture has lifecycle/context support; its request-reading extension still has no progress and therefore does not establish cumulative L5. The Antigravity product acquired its title and progress in later changes and now meets L3.

Admission, presence, setup health and a usable return route remain common entry requirements. The existing Running presentation for products without wait signals remains unchanged, with that boundary declared in Settings. An ended row with no read evidence stays until the next submission, the Thread disappearing or dismissal; that is a read-removal limitation, not a property of a support level.

## 3. What a new product costs, before and after

Before the migration, a hook-based CLI with wait and request-reading support needs: an `AgentKind` case and three `switch` arms; an `AgentHookVocabulary`; a `RequestAnswering` (even for a product that cannot answer, because the vocabulary requires one); a setup actor written from `ClaudeCodeHookSetup` by hand; a `HookIntegrationPaths` factory; an `AgentMonitoring` actor of one to two thousand lines copied from whichever existing service is nearer; an `AgentNavigating`; a settings block and a `ProductSettingsCopy` factory; two message strings; the composition edit in `makeShared`; a 600-line harness; and edits to the tripwire tests. Roughly three to four thousand lines, most of it the second copy of a loop that exists twice already.

After §5, the same product needs:

| File | Content | Size |
| --- | --- | --- |
| `Products/Gemini/GeminiProduct.swift` | The `ProductDescriptor`: name, rank, bundle identifiers, static capabilities, setup description, factory | ~60 lines |
| `Products/Gemini/GeminiHookVocabulary.swift` | Event names → `HookSignal`, request projection, managed definitions | ~150 lines |
| `Products/Gemini/GeminiAdmission.swift` | Root-Thread eligibility and the live session list, if the product has one | ~100–300 lines |
| `Products/Gemini/GeminiRequestAnswering.swift` | For supported answer operations | ~80 lines |
| Registry entry | One line in `ProductRegistry.builtIn` | 1 line |
| `NotchlineTests/Products/GeminiConformance.swift` | Instantiates the shared capability fixtures with this product's payloads | ~100 lines plus sanitised payloads |

Presence from a bundle identifier, hook transport, setup writing, the reducer, the read-state gate, the terminal-host raise, the Settings row, the install and remove sentences, the footer and the grouped list are all supplied by the shared code and the descriptor. Nothing in `MonitorStore`, `NotchOverlayView`, `SettingsWindow` or `HookIntegration` changes.

**Measured against the estimate, 2026-09-11.** Antigravity CLI with lifecycle/context support cost two files under `Products/Antigravity/` (~430 lines, the larger half being the measurements written as doc comments), one 25-line descriptor, one enum case and a ~330-line conformance file — [`antigravity-cli.md`](antigravity-cli.md) §5. Nothing in `MonitorStore`, `NotchOverlayView` or `HookIntegration`'s reducer changed; `SettingsWindow` changed by one line. ~~The reducer claim held for one day~~: on 2026-09-12 the third file (`AntigravityTranscriptReader.swift`, ~110 lines) took **six lines of the shared reducer** with it — a prompt arriving after its Turn opened fills a blank title and may never rewrite one. That is a shared rule and not this product's special case, and it is a no-op for the two products that name their prompt on the event that starts the turn; it is priced here because "nothing in the reducer" was the estimate's headline and is no longer true. What the table above did not price was the product's *file*: a container of this app's own and bare handler lists, which the shared configuration editor had to learn once (P5's first commit), and a payload that names neither event nor Turn, which the transport had to learn once (its second). Both are now seams, so the next product that needs them pays nothing. **Read state, added the same day, priced the other way round**: `TerminalReadEvidence` is ~95 shared lines and `HookProductProvider` grew ~120 (the gate, the verdict pass, one deadline), against **one argument** in this product's descriptor. The next CLI product pays that one argument and nothing else, which is what §5.4's "shared by every CLI product" was a promise to make true.

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
protocol ProductObserving: Sendable {           // observation, required
    var agent: AgentKind { get }
    var stateChangeEvents: AsyncStream<Void> { get }
    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot
    func nextRefreshDeadline() async -> Date?
    func disconnect() async
}
protocol IntegrationConfiguring: Sendable {      // observation, required; a `NothingToConfigure` value conforms
    func status() async -> IntegrationSetupStatus
    func install() async throws
    func remove() async throws
}
protocol ThreadNavigating: AnyObject {           // observation, required; today's `AgentNavigating`
    func open(_ session: MonitoredSession) async throws -> NavigationOutcome
}
protocol RequestAnswering: Sendable {            // optional answer operations; today's name, widened to the handle
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

The store's fan-out loops over `module.observing`; answering asks `module.answering` and reads `nil` as "no answer operation". This is a proposed module shape; as built, the store discovers `AnswerDelivering` by conformance. Neither shape assigns a cumulative support level.

### 5.3 Coverage and runtime availability are separate

The earlier `RuntimeCapabilities` sketch was not built. [Product support](../../product-support.md) now defines coverage per mode and request form; it must not collapse approvals, questions, request reading and answering into three product-wide booleans. Read removal, navigation and every usage measure retain their own scope and conditions. A future machine-readable representation must derive levels from that coverage and report live availability separately.

Today the Provider publishes actual state through `AgentSnapshot`, optional contracts represent available operations, and `ProductDescriptor.declaredBoundary` supplies the Settings limitation sentence. No support-level field or runtime capability matrix is implemented. A signed-out quota source is not unsupported, a failed read is not zero, and an expired answer handle makes that request reading-only without changing the product's documented level.

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
| `CodexDesktopUnreadStateRepository`; `ClaudeCodeDesktopReadStateRepository` + focus log + reading watcher; `ControllingTerminalGestureReader` | `ReadEvidenceSource` conformers; the terminal one is shared by every CLI product — **built 2026-09-12 as `TerminalReadEvidence`**, a value over the existing reader plus the product's own `SessionProcessLocating`, composed by `HookProductProvider` and first used by Antigravity CLI | split, the terminal half done |
| `CodexRolloutTurnAbortReader`; `ClaudeCodeTranscriptReader.interruption`, agents `activity` | `InterruptionSource` conformers | product-owned |
| `readAccountUsageIfNeeded`, `ClaudeCodeUsageReader` | `UsageReading` conformers | product-owned |
| `TerminalUnreadMembershipGate`, deadline arithmetic, `SingleFlightGate` use, diagnostics list | `ProductMonitorRuntime` | shared |
| `CodexAppServerClient`, the private Desktop repositories, `ClaudeCodeSessionRegistry`, transcript readers | unchanged, product-owned | product-owned |

The Codex hook `PreToolUse(request_permissions)` wake-up, the held-Turn settlement from the rollout, and the `MessageDisplay` diversion are the three behaviours `AgentHookVocabulary` flags today (`wakesOnToolCallOpened`, `settlesHeldTurnsFromRecord`, `messageDeltaEventName`). They stay as vocabulary declarations; the runtime asks the vocabulary, as the reducer does now. The rule from [`README.md`](README.md) §2 stands: these encode measured edge cases and must not grow into a switchboard, so a fourth flag needs a named invariant and a test, not a boolean.

**As built (P4, closed 2026-09-12).** `ProductMonitorRuntime` is `HookProductProvider`, and it is the runtime for a product observed through hooks alone rather than for every product (Codex, above, is the departure). `LifecycleSource` is `HookLifecycleSource` over `HookRegistrationSetup`, whose two conformers are the two trust policies. `PresenceSource` and `ThreadAdmitting` are read together as `ProductSessionReading`, because a product with a list answers both from it; `SeparateSessionReading` keeps them apart for one that does not. `InterruptionSource` is `TurnEvidenceSource`, which also carries an approval answered in the product's own window and the Turn a Codex thread's rollout says it is on. `ReadEvidenceSource` and `UsageReading` are as proposed, and one seam was not proposed: `RowContentSource`, a product's project, title and line and whether a Turn draws a row at all. The dismissed-rows and gate-booking rules the table lists under the runtime are `TerminalUnreadRowFilter`, shared by Codex as well. A product's sources may hold the reading its refresh took (Claude Code's session source does) so that none of them asks the registry a second time mid-refresh.

Source groups, not package targets. One Xcode target keeps the build and the unshared scheme as they are; a `Products/<Name>/` folder per product and `Monitoring/{Core,Runtime,Transport}` folders give the dependency direction reviewers need. Package targets can follow once the boundary has survived a third product.

### 5.5 A hook product is one vocabulary, and the vocabulary is already the right shape

`AgentHookVocabulary` is the best artefact in the code for this exercise: every requirement on it is a measured per-product fact with its measurement in the comment. It stays as the hook family's adapter. Two changes: `answering` becomes optional (a reading-only hook product has none), and `agent` is supplied by the descriptor so the vocabulary cannot disagree with it. `everyRegisteredHookDefinitionMapsToASignalForItsAgent` iterates the registry's hook products instead of a hand-written array.

## 6. Terminal hosts

### 6.1 What is generic already, and what is not

Every Claude Code session hosted in a terminal gets, with no per-terminal code: its host resolved by process ancestry (`ProcessAncestryHostResolver`), including an editor's built-in terminal where the editor is the right thing to raise; its tty from the kernel; read state from the tty's access time and the foreground pid's ancestry; the raise sequence with the Space check; and the outcome sentence. All of that is Claude Code's today only because Claude Code is the only CLI, and it moves to the shared `ReadEvidenceSource` and `ThreadNavigating` for every CLI product in §5.4.

The one per-terminal branch is `AppleEventsTerminalTabFocuser.script(forHost:device:)`: Terminal.app and iTerm2 publish a tty in their scripting dictionaries and get their tab selected; Ghostty publishes a full dictionary with no tty; kitty, WezTerm and Alacritty publish none. `TerminalTabFocusing` receives `(device, HostApplication)` and its only implementation is AppleScript, so a host whose public interface is a command line rather than a dictionary has no way in, however precisely it can name a pane.

### 6.2 Terminal navigation and read coverage

Terminal navigation and read removal are independent axes in [product-support.md](../../product-support.md) §4. The old T0/T1/T2 host ladder is replaced by named outcomes so read evidence does not imply pane targeting.

| Capability | Requirement | Current scope |
| --- | --- | --- |
| Raise host | An application in the process ancestry and a reachable Space | Direct terminal and editor hosts; full-screen hosts remain out of reach |
| Focus matching tab/pane | The host's public interface names it by tty or shell pid and can select it | Terminal.app and iTerm2 through AppleScript, subject to Automation consent |
| Remove an ended row on read evidence | The Thread's controlling terminal records a qualifying gesture and its host is in front | Direct hosts only, with product-specific gestures. Unsupported for the current tmux, screen, ssh and pipe cases |

WezTerm, kitty and a tmux attached-client adapter remain unmeasured candidates from the original investigation. A public pane API must be validated before a host is listed as supporting focus; such an API does not itself establish read removal.

### 6.3 A host registry replaces the switch

```swift
struct TerminalHostAdapter: Sendable {
    let bundleIdentifiers: [String]
    let displayName: String?                 // nil: take the bundle's
    let paneLocator: (any PaneLocating)?     // nil: raise host only
}
protocol PaneLocating: Sendable {
    /// Selects the pane holding `device` or owned by `shellPID`; `.unavailable` when the
    /// host cannot say. Never matches on title, working directory or geometry.
    func focusPane(device: String, shellPID: Int32, in host: HostApplication) async -> TerminalTabFocus
}
struct AppleScriptPaneLocator: PaneLocating   // Terminal.app, iTerm2: today's scripts, unchanged
struct CommandLinePaneLocator: PaneLocating   // a bounded subprocess with a deadline, for WezTerm-shaped hosts
```

`TerminalHostRegistry.builtIn` holds Terminal.app and iTerm2 with the AppleScript locator. `onlyHostsThatPublishATerminalDeviceAreScripted` becomes two tests: every registered locator names a pane by identity, and an unregistered host degrades to `raisedApplication`. Adding a terminal with pane focus is one registry entry, one locator, and one conformance fixture; the negative list is nobody's to maintain.

**PRD amendment, one sentence.** §10 permits pane focus "only through the terminal's own public scripting dictionary". The rule should read *through the terminal's own public interface, matching on the controlling tty or the shell's pid and never on titles, geometry or Accessibility*. A remote-control command line is the terminal's public interface as much as a dictionary is; what the rule protects is the identity match and the ban on GUI automation, and both survive. A locator that needs the user to enable something (kitty) reports `unavailable` when it is off, exactly as a denied Automation consent does today.

The Apple Events consent choreography (ask in the background, degrade the first click, treat refusal as final) stays in the AppleScript locator; a command-line locator has no TCC step and instead a deadline, the same 5 s race the scripts use.

## 7. Conformance suite

[Product support](../../product-support.md) §6 defines the L1–L6 and independent-capability verification requirements. Tests exercise evidence and behaviour; a fixture that omits a lower-level feature is not proof of a higher cumulative level.

`HookProductConformanceTests` runs the real shared Provider and reducer over a temporary root with synthetic vocabularies, presence and admission. Its lifecycle/context fixture and its reading-only approval extension deliberately need no fake quota, read state or answer transport. Neither fixture supplies progress, so the second proves wait/request-reading capabilities independently rather than L5.

`AntigravityConformanceTests` adds product payloads, L2 metadata and L3 progress boundaries, as well as read-removal conditions. Existing request projection and answer-delivery tests cover L4–L6 behaviour for Codex and Claude Code. Native payloads, cancellation and stale-answer cases remain required per supported form. Terminal locators are tested with tty/shell identity and honest host-raise degradation. Runtime measurements remain separate from these unit fixtures.

## 8. Migration, in reviewable commits

Each phase is a complete change with the suite green before commit; each exit is testable.

| Phase | Change | Exit |
| --- | --- | --- |
| **P0 Pin** | Extract `ProductHarness` from `ClaudeCodeHarness`; add the lifecycle, context, wait, request-reading and answer fixtures and run both products through them; make the vocabulary tests iterate a list built from `AgentKind.allCases` | Both products pass the same fixtures; no behaviour change; Release CPU baseline recorded (`ps -o time` diffs for hover and event bursts, sampling for idle) |
| **P1 Registry** | `ProductDescriptor`, `ProductRegistry.builtIn`, `makeShared` from the registry; Settings rows as `ForEach`; one `ProductSettingsCopy` reading per-product availability; generated help text and messages; delete `defaultIntegrationAgent` | A `IntegrationMonitoringStub`-backed test product registers, appears in Settings with generated copy, installs and removes, without editing any product switch. The merged-availability defect is gone and pinned |
| **P2 Contracts** | Split `AgentMonitoring` into the five contracts; `IntegrationSetupStatus`; `AnswerHandle` and `AnswerDelivery`; `RuntimeCapabilities` on `AgentSnapshot`; `ManagedHooksSetup` over two policy values with one `prepareHelper` | A test product with no answering and no quota compiles against no meaningless methods; Settings and the click sentence read capabilities, not absences |
| **P3 Terminals** | `TerminalHostRegistry`, `PaneLocating`, the AppleScript locator; the negative-list test becomes the two registry tests | Adding a locator for a stub bundle id needs no edit outside the registry and its fixture |
| **P4 Runtime** | `ProductMonitorRuntime`, one concern per commit in this order: presence, refresh deadlines, dismissed rows and gate booking, diagnostics, quota scheduling, read evidence, interruption, admission. Claude Code first, then Codex | Both provider actors are compositions; no Release regression against P0's baseline; the `AGENTS.md` §6 renamings in §9 land with the last commit. **Closed 2026-09-12**: Claude Code is a composition, Codex composes the shared pieces around its App Server (§5.4 *As built*, and the status above for why) |
| **P5 Prove** | One hook-based CLI with lifecycle/context support, then see whether L4 wait detection is reachable honestly (Gemini CLI is the candidate from [`README.md`](README.md) §3); one terminal with pane focus (WezTerm, if its CLI names a pane by tty as documented) | The product is a `Products/<Name>/` folder and a fixture file; the terminal is a registry entry and a locator. Whatever fails is recorded as narrower coverage, never as a heuristic in the kernel |

A product that requires a server rather than hooks (OpenCode) is the right **second** proof, after the cheap path is proven, because it tests `LifecycleSource` rather than the registry.

## 9. Contract changes, and the documents that carry them

| Current rule | Proposed | Documents |
| --- | --- | --- |
| "One orchestration centre: `LiveCodexMonitorService`" | One centre per product, `ProductMonitorRuntime`, with the product's sources as its inputs; still one reducer. **Landed with P4**: `HookProductProvider` for a hook-only product, `LiveCodexMonitorService` for Codex | `AGENTS.md` §6, `system-architecture.md` §1, §5, §7 |
| "Hook events enter only `HookEventRepository`" | Observations enter only the kernel; the hook source is one caller | same, plus the invariant tests |
| Provider is the whole adapter | Provider is the composition of a runtime and sources; **Tier** and **Capability** become defined terms. **Landed with P4** | `CONTEXT.md` |
| Two-product Settings, prose counts | Rows and copy generated from `SetupDescription` | `integration-settings-behaviour.md` (§1/§2 become one section over the descriptor), `PRD.md` §11 |
| An active Turn without wait detection's look | Drawn as `Running`; the boundary is declared in Settings | `PRD.md` §6.1, §12; `dual-agent-design.md` §8 |
| Pane focus only via scripting dictionary | Via the host's public interface, matching tty or shell pid | `PRD.md` §10, ADR 0004 addendum, `tech-design.md` §14.2 |
| `answer(...) -> Bool` | `AnswerDelivery` | `answer-in-notch.md` §8 |
| Support table in the README | Per product: level, request coverage and independent capabilities; per terminal: host raise, pane focus and read evidence separately | `README.md` |
| Private dependency registry | Unchanged rows; a new product adds its own section as Claude Code did | `non-public-codex-integration-features.md` |

`tech-design.md` §5 "Sources of truth" is still written Codex-first and becomes the one table a capability list would contradict; it should be reorganised per capability with a column per product in P1.

## 10. Where this departs from the earlier proposal

[`README.md`](README.md) is the reasoning this document builds on; four points differ.

1. **Six cumulative levels, scoped requests and independent capabilities**, rather than bands of functionality described by a label. The user-facing question is "how well is X supported", and a number answers it; the capability set keeps it honest.
2. **An active Turn without wait detection is drawn as `Running` and declared in Settings**, rather than given an "attention unavailable" presentation. The row carries one mark; the precedent for a declared boundary is already shipped.
3. **Terminals are in scope** with their own registry and independent navigation/read coverage; the earlier document did not address them.
4. **Package targets and an external Provider protocol are out of scope.** Source groups are enough for the dependency direction; nothing about the next product needs process isolation.

## 11. NO-GO conditions

Unchanged from [`README.md`](README.md) §9, restated for the support contract: a product earns no level by inferring Turn state from silence, replaying historical hooks, mistaking another runtime for the user's, or creating permission prompts to observe them. L4 wait-detection coverage requires that a cancelled wait is observed as ending. L6 answer coverage requires proof that stale handles cannot deliver an answer. A terminal supports pane focus only on an identity match through its own public interface. When any of these fails, the product or host is recorded with its verified coverage.

No hook registration, application restart, answer operation or third-product probe was performed for this document. The private integration registry was checked: this proposal adds, modifies, migrates and removes no production non-public integration; §9 lists the updates implementation would owe it.
