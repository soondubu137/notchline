# Trae read-removal feasibility

Implementation update — 2026-09-13: the bounded core below is implemented in companion 1.1.0. The current contract and validation results are in [Trae integration](../../trae-integration.md#read-removal--companion-110). Earlier observations and remaining native acceptance cases below are retained as research history; they do not replace the production contract.

Investigated on 2026-09-13. **Research only: no production implementation or support claim.** Terminology follows [CONTEXT.md](../../../CONTEXT.md).

## Finding and scope

The required signals are accessible in the installed Trae 3.5.91 renderer, in both IDE and IDE-hosted SOLO. A companion can associate the selected Thread with its exact native assistant message and Turn, observe completion and pending requests, and inspect whether the corresponding completion is displayed. Notchline can combine that evidence with macOS foreground and screen availability, then reuse its existing read-removal gate.

This establishes a viable implementation route, not complete native acceptance. The subsequent first-version scope in §7, corrected by the native window-identity validation in §8, includes multiple main windows and accepts conservative retention for unsupported visibility cases. Continuous foreground completion and actual screen lock remain implementation acceptance cases. Standalone SOLO/SoloLite was not exercised; these findings must not be extended to it. Read removal also does not establish SOLO progress or request-answering coverage.

The inspected application is the build pinned by [the Trae integration record](../../trae-integration.md). Its chat module fingerprint was `1198074030bb24e4b79f349c06ffc67b20feda642a9e35836c7194ed4c0fe7ac`. At the start of this research, [TraeProvider](../../../Notchline/Notchline/Products/Trae/TraeProvider.swift) supplied no `ReadEvidenceSource`.

## Target rules and evidence

| Rule | Evidence obtained | Remaining acceptance |
| --- | --- | --- |
| A Thread completes while another Thread is selected: retain | IDE native completion was observed with a different selected Thread. A later SOLO snapshot simultaneously showed a selected pending question and an unselected completed Thread. Exact identity prevents the latter from qualifying. | Exercise through the production read source in both modes. |
| Trae is in the background, even with the completed Thread selected: retain | Paired SOLO samples retained the same selected completed message and visible DOM. Native foreground changed from Trae to Finder; renderer focus changed to false. The composed predicate rejected the background sample. | Repeat completion itself under a controlled background interval in both modes. |
| Return to the owning window and display its completed Thread: remove | Fresh samples in IDE and SOLO each showed native Trae active, renderer focused, selected completed message visible and completion controls rendered. The real membership gate accepted the composed SOLO proof. | Complete native ownership acceptance with two Trae windows. |
| Watch a Turn finish in front: remove after the existing settling interval | Native completion preceded rendered completion controls. One SOLO observation had a 46 ms gap. Four additional gate checks verified render-pending retention, retention inside the interval, removal at two seconds and protection of a newer Turn. | Continuous native foreground throughout completion was not cleanly established. Verify end-to-end timing in both modes. |
| Trae is in front but its chat panel is hidden: retain | Hiding the IDE Secondary Side Bar unmounted the selected assistant DOM while selection and native completion remained. A completion was captured with renderer focus true and DOM visibility false. | Obtain a paired native-focus sample for this exact transition; repeat the equivalent hidden surface in SOLO. |
| Navigation only raises Trae without displaying the target: retain | Current navigation code supplies no read evidence. The candidate predicate separately requires selected identity and displayed completion, so application activation alone cannot qualify. | Exercise the actual raised-application fallback through the production source. |
| Running, Approval needed and Input needed: retain | A real SOLO `AskUserQuestion` remained pending with native Trae active and its form visible. The unchanged gate retained all three active statuses even when supplied positive read evidence. | A real manual approval was not induced in this experiment. |

“Visible” in the probe means a matching assistant root with positive intersection with the viewport and clipping ancestors, passing CSS visibility checks. Completion controls were checked for presence. This is sufficient to demonstrate the hidden-panel distinction, but is not a full scrolling or occlusion proof: production must check the completion-bearing region itself, rather than accepting a long assistant root whose earlier content alone intersects the viewport.

## Private signals verified

The existing companion already imports `@byted-icube/ai-modules-chat/dist/index.mjs`. The temporary probe used its existing webpack modules and product-owned client; it did not create or disconnect an Aha connection.

| Signal | Verified access |
| --- | --- |
| Selected Thread | `10678.Ok.getCurrentSession().sessionId`, with selection changes from `21868.O` |
| Current assistant and Turn | `57419.eA.lastAgentMessage.get(threadID)`, including message identity, `turnId`, status and completion time |
| Store changes | `22976.z.getStoreInstance().subscribe(...)` |
| Outstanding question / permission | `95259.D.get(threadID)` / `71788.rT.get(threadID)`; the question path was exercised live |
| Exact rendered assistant | `.turn__agent-message[data-message-id="..."]` |
| Completion render cue | `.assistant-action-bar` inside that assistant, combined with native terminal state |
| Scroll clipping | `.virtualized-message-list-view__scroller` and clipping ancestors |

The DOM's `data-turn-id` identifies the **user message**, not the native Turn. Matching it to a native Turn ID would reject valid readings or join the wrong objects. Join native Thread → assistant message → native Turn, then match the assistant's `data-message-id`.

The same identity selectors and assistant markers were observed across IDE and IDE-hosted SOLO. SOLO adds `showsoloaisidebar solo-mode` to the document body. These are version-specific observations, not a public interface.

## Focus, freshness and settling

Renderer focus alone is insufficient evidence in this test environment. During UI automation, `document.hasFocus()` sometimes remained true while macOS reported another foreground application. `IHostService.hasFocus` delegates to document focus; `hadLastFocus()` describes the last active Trae window and cannot replace current macOS foreground evidence. This experiment does not attribute the mismatch to ordinary, unautomated Trae use.

The reliable foreground/background comparison therefore used an on-demand renderer sample and separately read actual macOS Trae activation and screen availability. The localhost WebSocket was temporary diagnostic transport. No content-security setting was changed. The production transport should remain the existing companion channel.

An event-only implementation has a gap: actual application activation can occur without a new renderer focus edge. Request a fresh snapshot on native activation, screen availability changes and the shared scheduled recheck. Do not relabel an old renderer event with the current time. Correlate the reply with a request, owning peer/window, observation epoch and exact Thread/Turn/message identity; recheck native focus after the asynchronous reply. A focus transition during the request invalidates that attempt. The corrected first-version proposal uses native window identity and focus evidence (§8), not a single-window restriction; global application activation alone is still insufficient.

There is also a settling trap. The [existing gate](../../../Notchline/Notchline/TerminalUnreadMembershipGate.swift) immediately removes a row when previously observed unread evidence becomes read. If the short gap between native completion and rendering is reported as **unread**, watching a Turn finish can bypass the normal two-second settling interval. Report incomplete render evidence as unavailable, without claiming unread; a positively observed different Thread, background state or hidden panel can establish unread. This distinction passed an isolated check against the unchanged production gate.

Screen availability must veto a newly formed positive proof. Merely disabling refresh deadlines while locked does not protect a callback already in flight. Once a valid proof has retired a Turn, switching away must not resurrect it; a newer Turn needs its own evidence.

## Implementation route

1. Extend the version-pinned companion with bounded read observations and an on-demand query. Watch selection, relevant native state and the selected completion's render/visibility changes. Avoid scanning all historical messages or sending their text.
2. Preserve peer/window ownership and generation in the transport. A missing selector, changed schema, disconnected peer, mismatched Turn or stale response supplies no positive proof.
3. Add a Trae-owned `ReadEvidenceSource` composed by `TraeProvider`. Combine native foreground/screen state with the renderer proof. Produce per-candidate judgements; absence from an arbitrary partial set must never mean read.
4. Reuse [TerminalUnreadRowFilter](../../../Notchline/Notchline/TerminalUnreadRowFilter.swift), `TerminalUnreadMembershipGate` and shared scheduling. Keep navigation separate and the UI passive. Observe only while relevant terminal candidates exist, and dispose all observation on retirement/disconnect.

No production source, transport or registry was changed by this investigation. Implementation would extend private Trae dependencies and must update the [private dependency registry](../../non-public-codex-integration-features.md#trae-desktop-local-ide), integration record, architecture and support documents together.

## Validation limits and cleanup

An isolated Swift harness copied the production snapshot and membership-gate definitions unchanged and supplied real foreground/background probe metadata plus controlled inputs. **22 checks passed**, covering positive/negative readings, active statuses, unavailable and pre-completion evidence, immutable retirement within one Turn, native focus and screen vetoes, settling, and a newer Turn. This was not the full Notchline test suite and did not exercise a production Trae read source.

The live probe captured selected identities, statuses, pending IDs, visibility flags and timestamps. Scenario labels were not treated as evidence: several attempted background transitions were rejected when actual native focus disagreed. A temporary second window was opened and closed, but a clean native-active/other-window-focused pair was not obtained. One console snippet was accidentally submitted to a disposable test Thread; its native plan contained only a successful `finish`, with no command or file operation. That Turn was excluded from model-behaviour conclusions; its completed rendering was used only as a visibility specimen.

No Release CPU or wake-up measurements were made. The broad diagnostic mutation observer is not an acceptable production performance result. Before declaring support, validate targeted observer cost in Release, two-window ownership, scrolling to older content, hidden/minimised surfaces, actual lock/wake, lost peers, old epochs, native activation during asynchronous reads, and continuous foreground completion. Unknown cases must retain the row.

Both disposable Threads were deleted through Trae's native API and independently returned `chat session not found`. The original Thread and IDE presentation were restored. The temporary window was closed, observers unsubscribed, timers cleared, the diagnostic WebSocket closed and the probe global removed. Temporary captures and executables were discarded after recording these conclusions.

## 7. Bounded first-version scope after additional validation

The user accepted reduced edge-case coverage and asked to establish the useful core before implementation. This supersedes treating complete acceptance of the original table as a prerequisite to starting implementation. The initially proposed single-window restriction was subsequently rejected by the user and is withdrawn; the scope table below incorporates the additional multi-window validation in §8. Production code remains unchanged by this follow-up.

### Additional native observations

The follow-up used the already completed original Thread without submitting a prompt, reading its answer text into the probe, or changing any native Turn. Only selection/status metadata, DOM visibility booleans and window counts were returned. A temporary global held the read function; it created no persistent listener or background server.

| Observation | Result |
| --- | --- |
| Native main-window inventory | `20469.mc.getInstance().resolve(35007.k.IHostService).getWindows({includeAuxiliaryWindows:false})` returned one main window, then two while a disposable second window was open, then one after it closed. The second window was still at its workspace trust prompt: detecting it did not depend on its companion being loaded or its folder being trusted. |
| Completion visible in IDE | The selected native completed assistant matched exactly one DOM root; both that root and its completion action bar passed clipping and hit-testing checks. |
| IDE scrolled to older content | The same selected completed assistant root still passed visibility, and its action bar still existed in the DOM, but the action bar failed visibility. Checking the root alone would have accepted this sample incorrectly. |
| SOLO scrolled away from completion | The selected assistant and completion control remained identifiable, but neither passed visibility. |
| SOLO returned to the bottom | The same selected completed assistant and completion control both passed visibility. |
| Restore | The original Thread, IDE presentation and bottom reading position were restored. Native main-window count was one. The temporary window, timer, probe global and empty workspace were removed. |

The completion check intersected the element rectangle with the viewport and each clipping ancestor, required positive remaining area and CSS visibility, then used `document.elementFromPoint` at the intersection's centre to require a hit on that element or its descendant. This detects the tested scrolling case and provides a conservative same-document obstruction check. It does not claim whole-answer reading or full macOS window occlusion detection. A missing, obscured or unrecognised completion control means retention.

The initial window-count sample ran before the second window had finished opening and still returned one. A later sample was taken with the second window visibly open and returned two. The latter is the multi-window result; startup timing is not inferred from the first sample.

### Proposed first version

| Capability | Initial scope |
| --- | --- |
| Read removal | Local IDE and IDE-hosted SOLO, including multiple native Trae main windows. Require actual macOS foreground, an available screen, matching native activity and renderer window IDs, native and renderer focus, the correct selected native Thread/Turn/message, terminal state, no pending request, and a visible completion control. |
| Return to a completed Thread | Remove on a fresh positive observation through the existing membership gate. |
| Finish while in front | Use the existing two-second settling behaviour. Render-pending evidence remains unavailable; it must not fabricate an unread-to-read transition. |
| Background, another Thread, hidden panel, older content, pending request | Retain. Completion visibility adds useful protection without requiring full window geometry. |
| More than one native main window | Judge each candidate against the window actually displaying it. A different focused window cannot retire it; a focused window with a fresh matching completion may. An unavailable peer withholds only its proof, not every Trae reading. Window count is diagnostic, never a global veto. |
| Lost route, timeout, changed schema, stale generation, mismatched identity, failed window query | Supply no positive proof. Retain the affected row. |
| Unsupported completion rendering, unusual occlusion, minimisation and other Spaces | No additional coverage promise. Conservative retention is acceptable where the observed guards reject the surface. OS-level occlusion that leaves all guards positive remains an explicitly unverified limit. |

Use **on-demand queries through the existing companion channel**, rather than adding a broad mutation observer. The current `ReadEvidenceSource` composition and `terminalUnreadRecheckInterval = 1` already provide rechecks while a relevant terminal row is listed. Query only terminal candidates, inspect the selected message rather than the whole history, bound request size and timeout, and discard replies after disconnect or generation change. Do not issue renderer queries when the screen is unavailable or Trae is in the background. Native activation events can improve latency but are not needed to establish the initial polling route's feasibility.

The one-second value is the existing shared recheck setting, not a newly measured latency guarantee. This experiment measured neither production request round-trip latency nor Release CPU cost. Those belong to implementation validation using the actual companion path. No continuously running observer, new independent timer or SwiftUI animation is needed for this proposal.

### Work ready for implementation

1. Add a bounded, request-correlated read query to the companion, including native window identity/focus and the selected completion's visibility.
2. Add the Trae read-evidence boundary/source and compose it with the existing runtime. Preserve exact candidate identity, observation generation, native foreground/screen checks, settling and immutable retirement of the same Turn.
3. Test single- and multiple-main-window paths, background/different selection, scrolled/hidden completion, native window mismatch, active-status protection and stale/failed replies. Run full Swift tests and measure the actual query path in Release. Continuous foreground completion is an acceptance scenario for that vertical slice, not a reason for another broad preliminary investigation.
4. Update the product capabilities and private-dependency record with per-window evidence and conservative fallbacks. Auxiliary editor windows, exhaustive OS occlusion and standalone SOLO remain outside the verified scope.

## 8. Multiple main windows: native identity validation

The user explicitly requires multiple main windows in the first version. Rejecting all readings merely because two windows exist is not an accepted fallback.

### Native implementation and interfaces

The installed main-process bundle defines `getActiveWindowId` using the focused main window, falling back to the last active main window when none is focused. `IHostService.hadLastFocus()` compares that result to the calling renderer's native window ID. This confirms why the latter cannot independently prove foreground reading, but also identifies the native per-window comparison missing from the earlier experiment.

The following calls were verified live through the existing renderer container:

- `20469.mc.getInstance().resolve(35007.k.INativeHostService).windowId`: the calling renderer's native window ID.
- `INativeHostService.getActiveWindowId()`: focused-or-last-active main window ID.
- `INativeHostService.getWindowCountByState({isFocused:true,isVisible:true})`: counts from Electron native window `isFocused()` / `isVisible()` state.
- `IHostService.getWindows({includeAuxiliaryWindows:false})`: main-window IDs, used to verify both windows remained open during the experiment.

The additional native implementation is in `out/main.js`, SHA-256 `90fda6a0e5b4851a8a060afe1ebef3dbe69403934ab8f5669c98539b95acdf8d`. Production use must register and validate this private dependency alongside the renderer dependencies; a method's presence alone is not a supported public contract.

### Native observations

A temporary bounded observer sampled only window IDs, focus booleans, selected Thread ID and mode. The original renderer was window `1`; a disposable second main window was `6`. Neither native Turn was started nor any answer submitted.

| State observed from original window `1` | Open main windows | Native active ID | Native focused-window count | Original document focused |
| --- | --- | --- | --- | --- |
| Original IDE window active | `1` | `1` | `1` | `true` |
| Second main window active | `1, 6` | `6` | `1` | `false` |
| No native window focused | `1, 6` | `6` | `0` | `false` |
| Returned to original IDE window, second still open | `1, 6` | `1` | `1` | `true` |
| Original window switched to SOLO, second still open | `1, 6` | `1` | `1` | `true` |

The selected Thread in the original renderer remained unchanged throughout. Thus the first window can lose and regain reading eligibility while two windows remain open; global refusal is unnecessary. The zero-focus sample also directly demonstrates the last-active fallback: ID `6` remained available with no native focused window and must not count as a reading.

These observations validate the window-selection component. They are not a newly measured end-to-end row retirement or a simultaneous independent macOS-foreground recording; the separate macOS/screen gates and completion-visibility tests from earlier sections remain necessary.

### Per-window first-version design

Require a fresh sample whose renderer/native window ID equals the native active main-window ID, with native focus present and that renderer document focused. Also retain the independent macOS foreground/screen checks and exact Thread/Turn/message/completion-region checks. The main-window count does not affect eligibility. Unknown identity, no focus or mismatched identity produces no positive proof for that window.

Keep lifecycle ownership separate from the place where a Thread is read. The existing lifecycle boundary pins one peer as owner to order Turn events; the read source must not assume that the lifecycle owner is the only window where the user can display that Thread. Read queries can inspect the selected completion in each healthy peer, within a bounded request budget, and accept a fresh native-confirmed match for an existing candidate from the focused peer. They must never admit a historical Thread, reopen a Turn or move lifecycle ownership merely to obtain read evidence.

Correlate responses with the connection epoch and native window identity, not only the extension-host PID or socket path. Recheck focus after asynchronous work; conflicting or stale observations withhold the affected proof. Failure of an unrelated peer does not invalidate a positive, fully matched proof from the focused window.

Implementation acceptance must exercise two ordinary companion-bearing windows with distinct Threads, switching between them and returning to a completed Thread; the same Thread displayed in another window needs an additional identity/routing test. This follow-up used an empty second window at its trust prompt to isolate native focus, so it does not claim that the not-yet-written multi-peer read transport has already passed those cases.

The temporary observer and timers were removed, the second window was closed, and the original Thread and IDE mode were restored. The disposable workspace was deleted. No production code or installed companion changed.
