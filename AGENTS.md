# Codex in Notch — Agent Constraints

This file applies to the whole repository, including every subdirectory. Any agent working here must follow the constraints below.

---

## 1. What this project is

A macOS overlay that sits at the top of the screen. It summarizes, with minimal interruption, the Codex Desktop turns the user still needs to attend to, and offers a way back into the originating thread. Collapsed, it hugs the notch or menu bar; on hover it expands into a list of live monitored threads.

**Terminology comes before code.** Words like *thread*, *turn*, *monitoring lifecycle*, *current activity projection*, *unread terminal state*, and *integration availability* have precise definitions in this project. Read [`CONTEXT.md`](CONTEXT.md) before writing code, docs, or a commit message. Do not fall back on "task", "session", "run", or "recent threads" — those are explicitly banned alternatives.

The product surface and the docs are written in Chinese; commit messages and this file are in English. Match whatever you are editing.

---

## 2. Project and commands

| Item | Value |
| --- | --- |
| Project | `CodexInNotch/CodexInNotch.xcodeproj` |
| Scheme | `CodexInNotch` (the only one) |
| Targets | `CodexInNotch`, `CodexInNotchTests`, `CodexInNotchUITests` |
| Minimum OS | macOS 26.5 |
| Test framework | Swift Testing (`@Test` / `#expect`), not XCTest |
| Bundle ID | `com.yinfenglu.CodexInNotch` |

Build:

```bash
xcodebuild build -project CodexInNotch/CodexInNotch.xcodeproj -scheme CodexInNotch -destination 'platform=macOS'
```

Unit tests (152 cases today, a few seconds on a warm build):

```bash
xcodebuild test -project CodexInNotch/CodexInNotch.xcodeproj -scheme CodexInNotch -destination 'platform=macOS' -only-testing:CodexInNotchTests
```

Anything performance-related must be measured under **Release** (`-configuration Release`). Debug numbers mean nothing here.

**There is no CI and no lint configuration in this repository.** Running the tests locally before committing is the only gate — do not assume something else will catch it.

The scheme is not shared (`xcuserdata/` is ignored), so Xcode regenerates it on open. If a clean checkout ever reports "scheme not found", share the scheme into `xcshareddata/xcschemes/` rather than re-tracking user state.

---

## 3. Document map

Each document owns a specific scope. When a change lands in one of these scopes, update that document **in the same change**.

| Document | Authoritative for |
| --- | --- |
| [`CONTEXT.md`](CONTEXT.md) | Terminology. Any naming disagreement is settled here |
| [`docs/PRD.md`](docs/PRD.md) | Product contract: monitoring scope, state model, privacy, navigation, release gates, acceptance criteria |
| [`docs/figma-design.md`](docs/figma-design.md) | Visual and interaction spec, Figma file structure, legal component variants |
| [`docs/system-architecture.md`](docs/system-architecture.md) | The structure of the implementation **as it actually is**: refresh timing, component responsibilities, rendering and performance boundaries |
| [`docs/tech-design.md`](docs/tech-design.md) | Detailed design of interfaces, protocols, data flow, and failure recovery |
| [`docs/adr/`](docs/adr/) | High-impact technical decisions and their trade-offs (monitoring scope, unread semantics, Project identity, navigation gate, fail-closed behavior, snapshot rebuild) |
| [`docs/non-public-codex-integration-features.md`](docs/non-public-codex-integration-features.md) | Every feature that depends on non-public Codex implementation details (see §8) |
| [`docs/technical-explorations/`](docs/technical-explorations/) | **Open research, not decisions.** Do not treat anything here as implemented or approved |
| [`docs/development-guideline.md`](docs/development-guideline.md) | The end-to-end process: requirements → design → validation → implementation → release |

`docs/development-guideline.md` is deliberately local-only and not tracked in git, so that link resolves on the maintainer's machine and nowhere else. Everything else in the table is in the repository.

---

## 4. Where the issue list lives

Known issues are **not** tracked in documents inside this repository. The former `docs/current-issues.md` was migrated to a GitHub board and deleted on 2026-08-16:

- Board: <https://github.com/users/soondubu137/projects/2> (numbering convention, priority definitions, and fix order live in the board README)
- Issues: <https://github.com/soondubu137/codex-in-notch/issues>

The `CR-xxx` numbers carried over, and commit messages in git history reference them directly. File newly discovered problems as issues on the board — **do not reconstruct an issue-list file under `docs/`**. When fixing one, reference its number in the commit subject, e.g. `(CR-023)`.

Design conclusions, measured boundaries, and architectural constraints still live in `docs/`. Only the *open defects* moved.

---

## 5. How to work here

### 5.1 Branches and commits

- **Commit directly on `master`.** Do not create a feature branch unless explicitly asked. History here is linear and this is a solo project.
- **Only commit when asked, and only push when asked.** Those are two separate authorizations.
- One reviewed, complete change per commit. Do not bundle unrelated edits.
- Commit messages are in English:
  - The subject is imperative and describes the **outcome**, not the mechanism — `Stop the refresh loop spinning on a deadline it cannot clear`, not `Fix bug in refresh loop`.
  - The body explains **why**: what triggered it, what was measured, what was rejected, what limitation remains. If it turns out an earlier conclusion was wrong, say so in the body and say where it was wrong.
  - Append `(CR-xxx)` to the subject when the change closes a board issue.

### 5.2 The contracts are not binding

The design documents under `docs/` and the assertions in `CodexInNotchTests.swift` are **not constraints you have to honor**. If a better implementation requires breaking one, break it and update the contract in the same change.

Two conditions:

1. **State the conflict and the reasoning explicitly.** The judgment call should be visible, not silent.
2. **Prefer rewriting a test so it pins the real invariant** over deleting it. For example, "never calls `thread/read`" was rewritten as "never requests Turn detail" (`includeTurns: false`, no `thread/items/list`) — which is stronger than the proxy it replaced.

### 5.3 Before changing code

Read the existing implementation and the existing tests before proposing anything. Nearly every simplification-shaped thing in this repository is held in place by a measurement or an edge case — §6 of `docs/system-architecture.md` contains an entire passage overturning an earlier conclusion in that same document.

---

## 6. Architectural invariants

All nine are in [`docs/system-architecture.md`](docs/system-architecture.md) §7. These three groups are the ones most easily violated without realizing it:

### 6.1 Boundaries do not leak

- **One orchestration center.** Decisions spanning data sources belong in `LiveCodexMonitorService`. The UI, the file adapters, and the transport do not assemble state from each other.
- **One Turn reducer.** Hook events enter only `HookEventRepository`. Replay, reordering, duplication, and exact-identity rules do not get scattered into the view layer.
- **One UI data contract.** Layers above consume `MonitorSnapshot` and nothing else.
- **Private dependencies stop at the boundary.** The `.codex-global-state.json` schema exists only inside the two read-only repositories; the domain layer sees Project resolution and an unread set tagged with its authority, nothing more.
- **The UI stays passive.** SwiftUI renders and emits user intent. It does not parse protocols or read files.

### 6.2 State is never guessed

- **Recovery logic does not fabricate business state.** Timeouts, liveness probes, caching, and disconnect grace periods decide only whether to keep or rebuild a connection. They never use a timer to infer Running, Approval, read, or Project.
- **Historical events carry no business semantics.** A history file proves only that a hook configuration once executed. It cannot prove that any thread exists right now or is in any particular state. The current list comes only from a current runtime snapshot, or from live events observed since this process started.
- **Failures fail closed.** A parse failure must never be reported as a valid empty value, as `Chats`, or as any other success state. Thread status holds its last trustworthy value; only an unresponsive App Server justifies global Disconnected.

### 6.3 Concurrency

Order-sensitive state machines (byte-stream framing) stay on the queue that already serializes them — do not move them into an actor. CPU-heavy decoding does not stay on an actor, where it would block timeout and connection management.

---

## 7. Overlay rendering: the most expensive class of mistake here

**No continuously running SwiftUI animation is allowed in the overlay.** Persistent motion is drawn on `CALayer` and evaluated by the render server.

This is a measurement, not a preference (Release build, status pinned to `.running`, toggled one variable at a time):

| Configuration | CPU |
| --- | --- |
| Indicator off, searchlight off | 0.0% |
| Both on (original `TimelineView` implementation) | 11.8% |
| Expanded panel + two rows sweeping | 15.3% |
| Everything moved to Core Animation | 0.0%–0.4% |

The test is not "is this animation expensive to draw?" but **"does it tick continuously?"** Cost is not proportional to what is on screen: the real expense is re-rendering the entire overlay every frame, including the custom `PanelContour` shape and all text measurement. Removing three layers of Gaussian blur bought back only 2 points out of 11.8%. Lowering the refresh rate does not help either — redraws are driven by the panel being marked as needing display, not by the view's own tick.

**The full form of the rule: overlay re-render count should be driven by whether the layout changed, not by whether the content changed.** The once-a-second elapsed readout is subject to it too. It used to publish through `@Published`, and every publish re-evaluated the whole overlay at roughly 20ms — measured at 4.7%. It now subscribes to `MonitorStore.elapsedTick`, which SwiftUI does not observe, and draws itself into a layer; the store publishes `elapsedLayoutRevision` only when the readout's **reserved width** changes. Same scenario: 4.7% → 0.0%.

### How to measure: `ps %cpu` will lie to you

- For **steady-state** cost, `ps %cpu` is accurate. The table above was measured that way.
- For **burst** cost, you must diff cumulative CPU time (`ps -o time`). One expand/collapse transition measures about 92 ms of CPU but shows up as 0.1%–0.3% on `ps %cpu`, which reads as nothing at all.

Picking the wrong tool produces a confident "there is no cost left" that is simply false.

### What the tests cannot protect

Existing tests assert that `NotchStatusMatrix` and the two layer-backed labels are still driven by `CAAnimation` and still have their masks, so reverting them to SwiftUI fails to compile. But **adding a new continuous animation somewhere else in the panel is not caught by anything** — that dimension is held only by this section and by the comments on the views.

Separately, `SearchlightLabel`'s font and `PanelMetrics.statusLabelFont` are two independent declarations of the same `NSFont`. Change one and the drawn label no longer matches the panel width reserved for it.

---

## 8. Registry of Codex integrations without official public support

### 8.1 Mandatory rules

- Prefer, by default, Codex integration capabilities that are defined and publicly supported in the official documentation and current public schema: App Server, Hooks, public CLI/SDK interfaces, and official deep links.
- Any production feature that depends on **Codex implementation details not supported by official public documentation or public schema** must add or update [`docs/non-public-codex-integration-features.md`](docs/non-public-codex-integration-features.md) in the same change. Do not defer the registry update to a later task.
- **Do not register a feature merely because it is not implemented through the App Server.** Features built on official Hooks, official deep links, or other publicly supported interfaces do not belong in the registry unless the implementation also depends on additional private details.
- Non-public dependencies that must be registered include, but are not limited to:
  - Codex Desktop private files, state schemas, IPC, in-bundle resource paths, or undocumented fields;
  - bundle identifiers, file locations, payload fields, or process behavior not promised by official documentation;
  - behavior observed through reverse engineering or experiment that has not entered any official public contract.
- When changing an existing non-public feature's schema keys, file paths, protocol, version baseline, implementation, failure signals, conservative degradation, or code location, update the corresponding registry row in the same change.
- If an equivalent publicly supported capability appears later, migrate to the official interface and, in the same change, update or remove the registry row along with the old private implementation and its tests.

### 8.2 Minimum content per entry

1. What the feature is;
2. why the publicly supported interfaces cannot fully implement it;
3. how it is actually implemented.

Each entry should also record the dependency level, the signal that it has broken after a Desktop update, the conservative degradation behavior, and directly navigable code and test paths. Vague wording that conceals the real private dependency is not acceptable.

### 8.3 Implementation and verification procedure

1. Before implementing, check the official Codex documentation, the current public schema, and the existing registry to confirm the capability gap still exists.
2. While designing, keep publicly supported interfaces and non-public data sources clearly separated. Do not dress private behavior up as a public contract.
3. For private schema or file dependencies, add tests for success, absence, corruption, and version incompatibility, and behave fail-closed.
4. Before finishing, check that code, tests, the PRD, the technical design, and the registry agree, and verify that the registry's relative links still resolve.
5. State in the delivery notes whether this change added, modified, migrated, or removed a Codex integration lacking official public support. If it did none of those, say so explicitly after checking.

**A missing registry update means the change is not finished.**

---

## 9. Definition of done

A change is not finished until all of the following hold:

1. `xcodebuild test -only-testing:CodexInNotchTests` passes in full.
2. New logic has tests, and any old assertion that was broken has been rewritten to pin the real invariant rather than deleted.
3. Every document whose scope in §3 the change touched was updated **in the same change**.
4. If the change touches a non-public Codex dependency, the §8 registry is updated — or checked and explicitly declared not applicable.
5. Performance-related changes carry measured Release numbers, and state whether the steady-state or the burst method was used.
6. The diff contains no debugging code, temporary files, or unrelated edits.
7. The delivery notes say what changed, why, what was rejected, and what limitations remain.
