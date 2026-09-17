# Notchline — Agent Constraints

This file applies to the whole repository, including every subdirectory.

## 1. What this project is

A macOS overlay at the top of the screen. It summarises, with minimal interruption, the Turns from Codex Desktop, Claude Code, Antigravity (Desktop and CLI), and Trae Desktop (local IDE) that the user still needs to attend to, and offers a way back into the originating Thread. Collapsed, it hugs the notch or menu bar; on hover it expands into a list of live monitored Threads.

**Terminology comes before code.** *Thread*, *Turn*, *monitoring lifecycle*, *current activity projection*, *unread terminal state*, *presence* and *integration availability* have precise definitions here. Read [`CONTEXT.md`](CONTEXT.md) before writing code, docs or a commit message, and honour its banned alternatives.

Language: every user-readable string — accessibility labels, diagnostics, Info.plist usage descriptions — is British English. `CONTEXT.md`, this file, the README, commit messages and tracked documents under `docs/` are English, except for the user-requested Simplified Chinese translation `docs/product-support-zh.md`; the untracked `docs/development-guideline.md` is Chinese. Keep `docs/product-support.md` and its Chinese translation in sync. Match whatever you are editing.

## 2. Project and commands

| Item | Value |
| --- | --- |
| Project / scheme | `Notchline/Notchline.xcodeproj`, scheme `Notchline` (the only one) |
| Targets | `Notchline`, `NotchlineTests`, `NotchlineUITests` |
| Minimum OS | macOS 26.5 |
| Bundle ID | `com.yinfenglu.Notchline` |
| Unit test framework | Swift Testing (`@Test` / `#expect`), not XCTest |

```bash
xcodebuild build -project Notchline/Notchline.xcodeproj -scheme Notchline -destination 'platform=macOS'
xcodebuild test  -project Notchline/Notchline.xcodeproj -scheme Notchline -destination 'platform=macOS' -only-testing:NotchlineTests
scripts/check-doc-links.py
```

A version is cut and published by `scripts/release/cut-release.sh <version>`: write its `CHANGELOG.md` section first, and read the script's header for the rest. The script builds and signs through `scripts/release/build-release.sh` on the tagged cut commit. It needs the `Notchline Release` certificate and Sparkle's EdDSA key in the login keychain, which `scripts/release/create-release-identity.sh` created once. Never create either a second time ([ADR 0022](docs/adr/0022-update-through-sparkle-signed-with-our-own-certificate.md)). The feed, `appcast.xml`, is read by every shipped copy from `master` and must not move.

The unit suite takes a few seconds on a warm build. Anything performance-related must be measured under **Release** (`-configuration Release`); Debug numbers mean nothing here.

**The unit suite has no CI, and there is no lint configuration.** Running the tests locally before committing is the only gate for code. The one GitHub Actions workflow, `.github/workflows/doc-links.yml`, runs `scripts/check-doc-links.py` on every push to `master` and every pull request. It fails when a relative link in tracked Markdown does not resolve, and it counts only tracked files, so a link to something `.gitignore` keeps local (such as `tests/`) fails too. Run it locally after moving, renaming or deleting a file that a document links to.

The scheme is not shared (`xcuserdata/` is ignored), so Xcode regenerates it on open. If a clean checkout reports "scheme not found", share the scheme into `xcshareddata/xcschemes/` rather than re-tracking user state.

## 3. Document map

Each document owns a scope. A change landing in one of these scopes updates that document **in the same change**.

| Document | Authoritative for |
| --- | --- |
| [`CONTEXT.md`](CONTEXT.md) | Terminology; any naming disagreement is settled there |
| [`docs/product-support.md`](docs/product-support.md) | Six cumulative support levels, request-form coverage and independent product capabilities |
| [`docs/PRD.md`](docs/PRD.md) | Product contract: monitoring scope, state model, previews, navigation, release gates |
| [`docs/dual-agent-design.md`](docs/dual-agent-design.md) | How the two products share one surface: attribution, quota, subagent counts |
| [`docs/colour-v2.md`](docs/colour-v2.md) | Colour: there is one hue, the user picks it, and no product owns one. The badge that names a product, and what the band stopped decomposing |
| [`docs/answer-in-notch.md`](docs/answer-in-notch.md) | Answering a request on the notch: every shape the two products ask in, what an opened row draws for each, the selection rule, the pointer-first version that ships and the keyboard half deferred behind it, and the reading-only form that ships before a write path exists |
| [`docs/cover-the-words.md`](docs/cover-the-words.md) | `Privacy Mode`: what the surface covers while somebody else is looking at the screen, the gesture that turns it on, and why a covered panel waits for a click |
| [`docs/updates-on-the-notch.md`](docs/updates-on-the-notch.md) | How an update is told and installed: the dot on the About mark, the About panel's thirteen states, the relaunch that waits for a waiting request, and the Updates pane |
| [`docs/quota-footer-v2.md`](docs/quota-footer-v2.md) | The quota footer without a gauge: one number at rest, one line when a window is close, and the two-level table behind the control |
| [`docs/panel-v2.md`](docs/panel-v2.md) | The three V2 decisions composed: what the expanded panel is made of, how big it is in every state, and the five places the three drafts contradicted one another |
| [`docs/figma-design.md`](docs/figma-design.md) | Visual and interaction spec, Figma file structure, legal component variants |
| [`docs/system-architecture.md`](docs/system-architecture.md) | The implementation **as it actually is**: refresh timing, responsibilities, rendering and performance boundaries, the architectural invariants |
| [`docs/product-generalisation-plan.md`](docs/product-generalisation-plan.md) | Executable five-package generalisation plan, implementation status and handover acceptance cases |
| [`docs/trae-integration.md`](docs/trae-integration.md) | Trae local IDE companion: pinned build, request scope, private source and native acceptance |
| [`docs/tech-design.md`](docs/tech-design.md) | Interfaces, protocols, data flow, failure recovery |
| [`docs/product-connections.md`](docs/product-connections.md) | Product discovery, monitoring intent, setup integrity, connection checks and Settings presentation |
| [`docs/integration-settings-behaviour.md`](docs/integration-settings-behaviour.md) | What the settings toggles actually do to the user's hook configuration |
| [`docs/artifacts.md`](docs/artifacts.md) | Every file this app creates or edits, inside its container and outside it |
| [`CHANGELOG.md`](CHANGELOG.md) | What each released version contains, and the known limitations it ships with |
| [`docs/adr/`](docs/adr/) | High-impact decisions and their trade-offs |
| [`docs/non-public-codex-integration-features.md`](docs/non-public-codex-integration-features.md) | Every feature depending on non-public Codex implementation details (§7) |
| [`docs/technical-explorations/`](docs/technical-explorations/) | **Open research, not decisions.** Nothing here is implemented or approved |
| `docs/development-guideline.md` | The end-to-end process. Deliberately local-only and untracked |

## 4. Where the issue list lives

Known issues live on a GitHub board, not in this repository — the former `docs/current-issues.md` was migrated and deleted on 2026-08-16.

- Board (numbering, priorities, fix order): <https://github.com/users/soondubu137/projects/2>
- Issues: <https://github.com/soondubu137/notchline/issues>

The `CR-xxx` numbers carried over and git history references them. File newly found problems there — **do not reconstruct an issue list under `docs/`** — and append the number to the commit subject, e.g. `(CR-023)`. Design conclusions and measured boundaries still belong in `docs/`; only open defects moved.

## 5. How to work here

### 5.1 Branches and commits

- **Commit directly on `master`.** No feature branch unless asked; history here is linear and this is a solo project.
- **Commit a significant change as soon as it is finished, without being asked** — once it builds and the tests pass. Trivial edits in passing can wait for the change they belong to.
- **Pushing is a separate authorisation and still has to be asked for.** Committing is not.
- One reviewed, complete change per commit; no unrelated edits bundled in.
- Commit messages are English. The subject is imperative and names the **outcome**, not the mechanism — `Stop the refresh loop spinning on a deadline it cannot clear`, not `Fix bug in refresh loop`. The body explains **why**: what triggered it, what was measured, what was rejected, what limitation remains. If an earlier conclusion turned out wrong, say so and say where.

### 5.2 The contracts are not binding

The documents under `docs/` and the assertions in `NotchlineTests.swift` are not constraints you must honour. If a better implementation requires breaking one, break it and update the contract in the same change, under two conditions:

1. **State the conflict and the reasoning explicitly** — the judgement call should be visible, not silent.
2. **Prefer rewriting a test so it pins the real invariant** over deleting it. "Never calls `thread/read`" became "never requests Turn detail" (`includeTurns: false`, no `thread/items/list`), which is stronger than the proxy it replaced.

### 5.3 Leave nothing behind

A task is not finished while its scaffolding is still on the machine. Remove probe scripts, captured output and throwaway tests — keep the *conclusion* in a commit body, a document or a test that stays, and delete the apparatus. Remove transcripts and session folders left in `~/.claude/projects/` by any `claude` this task started, and temporary trees under the session scratchpad. Anything belonging to the user rather than to the task is not covered: ask first.

### 5.4 Before changing code

Read the existing implementation and its tests first. Nearly every simplification-shaped thing here is held in place by a measurement or an edge case — §6 of `docs/system-architecture.md` contains a passage overturning an earlier conclusion in that same document.

## 6. Architectural invariants

The full list lives in [`docs/system-architecture.md`](docs/system-architecture.md) §7 and is authoritative. These are the ones most easily violated without noticing:

- **One orchestration centre per product.** Decisions spanning a product's data sources belong in that product's Provider: `ProductMonitoringRuntime` composed by `HookProductProvider` for a product observed through its hooks alone, or directly by another lifecycle source, with the product's sources (Claude Code, Antigravity), and `LiveCodexMonitorService` for Codex, whose App Server is a second lifecycle beside its hooks. A source supplies evidence and decides nothing across sources; supplementary sources return restricted evidence values, never receive a mutable reducer. Optional source ownership and deadlines are composed by the runtime. UI, file adapters and transport do not assemble state from each other.
- **One Turn reducer.** Live boundary adapters submit typed `MonitoringEvidence` only to `MonitoringRepository`; Hooks decode and project at `HookEvidenceBoundary`, never inside that reducer. Source queues preserve delivery order and observation epochs reject callbacks from a retired subscription. A second source (a `TurnEvidenceSource`, an admission list) may *retire* a Turn, but never open, name or describe one, and only inside that actor with its ordering guards.
- **One UI data contract.** Layers above consume `MonitorSnapshot` and nothing else.
- **Private dependencies stop at the boundary.** The `.codex-global-state.json` schema exists only inside the two read-only repositories; the domain layer sees Project resolution and an unread set tagged with its authority.
- **The UI stays passive.** SwiftUI renders and emits user intent; it does not parse protocols or read files.
- **State is never guessed.** Timeouts, liveness probes, caching and disconnect grace periods decide only whether to keep or rebuild a connection — never to infer Running, Approval, read or Project.
- **Historical events carry no business semantics.** A history file proves only that a hook configuration once executed. The current list comes only from a current runtime snapshot or from live events seen since this process started.
- **Failures fail closed.** A parse failure is never reported as a valid empty value, as `Chats`, or as any other success. Thread status holds its last trustworthy value; only an unresponsive App Server justifies global Disconnected.
- **Editing the user's files parses, never coerces.** Touch only the keys this app manages and preserve structures you do not understand.
- **Order-sensitive state machines stay on the queue that serialises them** (byte-stream framing) — not in an actor. CPU-heavy decoding does not stay on an actor, where it would block timeout and connection management.

## 7. Overlay rendering: the most expensive class of mistake here

**No continuously running SwiftUI animation is allowed in the overlay.** Persistent motion is drawn on `CALayer` and evaluated by the render server. The measurements behind this — and the full rendering boundary — are in `docs/system-architecture.md` §6; the headline is 11.8% CPU for two `TimelineView` animations against 0.0%–0.4% for the same motion on Core Animation.

The test is not "is this animation expensive to draw?" but **"does it tick continuously?"** Cost is not proportional to what is on screen: the expense is re-rendering the whole overlay every frame, including `PanelContour` and all text measurement. Removing three layers of Gaussian blur bought back 2 points of 11.8%, and lowering the refresh rate bought nothing.

**The full rule: overlay re-render count is driven by whether the layout changed, not by whether the content changed.** The once-a-second elapsed readout obeys it too — published through `@Published` it cost 4.7%; subscribing to `MonitorStore.elapsedTick` (which SwiftUI does not observe) and drawing into a layer, with `elapsedLayoutRevision` published only when the readout's **reserved width** changes, it costs 0.0%.

**A readout that goes *absent* is a layout change that the width signature cannot see.** `0:09` → nothing → `0:00` is one width from end to end, so nothing asks for a re-render and the untimed dot stays for the rest of the Turn. The rule the store keeps instead: a Turn with a known start is never answered "not timed" — a start later than the last tick means the shared tick has not caught up, so it is clamped to the Turn's own start (`MonitorStore.readableNow`).

### How to measure: `ps %cpu` will lie to you

Steady-state cost reads accurately on `ps %cpu`. **Burst cost does not** — diff cumulative CPU time (`ps -o time`) instead. One expand/collapse transition is about 92 ms of CPU but shows up as 0.1%–0.3%, which reads as nothing at all. Picking the wrong tool produces a confident "there is no cost left" that is simply false.

### Panel state is written on the main actor, and only Release can prove it

Every property the overlay renders from must be written on the main actor. `@Published` sends `objectWillChange` from `willSet`, so a write off the main thread lets SwiftUI re-render *before* the property is stored: `body` reads the previous value and nothing invalidates it again. The panel then draws the wrong state until an unrelated publish repairs it — measured as a collapsed notch carrying the expanded header's gear where its timer belongs, on roughly one hover burst in three.

**The annotations do not give you this.** `MonitorStore` is `@MainActor` and the hover action is started from a `@MainActor` method, but under `SWIFT_APPROACHABLE_CONCURRENCY` the task body is `nonisolated(nonsending)` and the optimiser elides the hop back. Work that resumes from a suspension and then touches store state needs an explicit `await MainActor.run { … }`.

Nothing in `NotchlineTests` can catch this: the elision is an `-O` behaviour absent in Debug, and `@testable import` needs `-enable-testing`, which Release does not build with. `hoverExpansionIsWrittenOnTheMainActorWhenTheDwellWakesOffIt` pins the invariant against a wrongly-placed write and nothing more. The Release reproduction is manual and worth keeping: run the Release app, post one `UserPromptSubmit` payload into `agents/claudeCode/hook.sock` so a row is timed, drive the pointer on and off in bursts of 1–3 passes with dwells jittered across 0.08–0.55 s, settle, and screenshot the collapsed panel. A status label or gear on a 39 pt panel is the failure — on a notched display the label hides behind the cut-out, so the trailing-wing gear is the visible half. Unfixed it appeared three times in ten bursts; fixed it survived a hundred and twenty.

### What the tests cannot protect

Tests assert that `NotchStatusMatrix` and the layer-backed readouts are still driven by `CAAnimation` and still have their masks, so reverting them to SwiftUI fails to compile. **A new continuous animation elsewhere in the panel is caught by nothing** — that dimension is held only by this section and the comments on the views. The font warning that stood here retired with `SearchlightLabel`: no surface draws a status name any more, so there is no second declaration of the panel's label font to drift from a reserved width. What replaced it is the same hazard one step along — `PanelMetrics.countsSessionFont` is measured for the width *and* drawn into the glyph raster, so it is one declaration by construction, and the pill's rotating name and the buried-finish dot are layer-backed for the same reason the readouts are: a SwiftUI cross-fade every five seconds, or a breath on any curve, re-renders the whole overlay.

## 8. Codex integrations without official public support

Prefer Codex capabilities that are publicly defined and supported: App Server, Hooks, public CLI/SDK interfaces, official deep links.

Any production feature depending on **Codex implementation details not covered by official public documentation or public schema** must add or update [`docs/non-public-codex-integration-features.md`](docs/non-public-codex-integration-features.md) in the same change. That includes private files, state schemas, IPC, in-bundle resource paths, undocumented fields, bundle identifiers, payload fields or process behaviour not promised by documentation, and anything learnt by reverse engineering that has not entered a public contract. **Do not register a feature merely for not going through the App Server** — features on official Hooks or deep links belong there only if they also depend on private details.

Each entry states what the feature is, why the public interfaces cannot deliver it, and how it is actually implemented, plus the dependency level, the signal that a Desktop update has broken it, the conservative degradation, and navigable code and test paths. Vague wording that conceals the real private dependency is not acceptable.

Procedure: confirm the capability gap still exists before implementing; keep public interfaces and private sources clearly separated in the design; for private schema or file dependencies add tests for success, absence, corruption and version incompatibility, and fail closed; before finishing, check that code, tests, PRD, tech design and registry agree and that the registry's relative links resolve (`scripts/check-doc-links.py`). When an equivalent public capability appears, migrate and remove the old row, implementation and tests together. Say in the delivery notes whether this change added, modified, migrated or removed such an integration — and if it did none of those, say so explicitly after checking.

**A missing registry update means the change is not finished.**

## 9. Definition of done

1. `xcodebuild test -only-testing:NotchlineTests` passes in full.
2. New logic has tests, and any broken assertion was rewritten to pin the real invariant rather than deleted.
3. Every document whose §3 scope the change touched was updated in the same change.
4. If the change touches a non-public Codex dependency, the §8 registry is updated — or checked and explicitly declared not applicable.
5. Performance-related changes carry measured Release numbers and state whether the steady-state or the burst method was used.
6. The diff contains no debugging code, temporary files or unrelated edits.
7. The delivery notes say what changed, why, what was rejected, and what limitations remain.
