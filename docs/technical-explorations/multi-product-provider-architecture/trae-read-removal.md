# Trae read-removal feasibility

Investigated on 2026-09-13. **Research only: no production implementation or support claim.** Terminology follows [CONTEXT.md](../../../CONTEXT.md).

## Finding and scope

The required signals are accessible in the installed Trae 3.5.91 renderer, in both IDE and IDE-hosted SOLO. A companion can associate the selected Thread with its exact native assistant message and Turn, observe completion and pending requests, and inspect whether the corresponding completion is displayed. Notchline can combine that evidence with macOS foreground and screen availability, then reuse its existing read-removal gate.

This establishes a viable implementation route, not complete native acceptance. Multi-window ownership, continuous foreground completion, actual screen lock and several visibility boundaries still need controlled acceptance. Standalone SOLO/SoloLite was not exercised; these findings must not be extended to it. Read removal also does not establish SOLO progress or request-answering coverage.

The inspected application is the build pinned by [the Trae integration record](../../trae-integration.md). Its chat module fingerprint was `1198074030bb24e4b79f349c06ffc67b20feda642a9e35836c7194ed4c0fe7ac`. The existing [TraeProvider](../../../Notchline/Notchline/Products/Trae/TraeProvider.swift) still supplies no `ReadEvidenceSource`.

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

An event-only implementation has a gap: actual application activation can occur without a new renderer focus edge. Request a fresh snapshot on native activation, screen availability changes and the shared scheduled recheck. Do not relabel an old renderer event with the current time. Correlate the reply with a request, owning peer/window, observation epoch and exact Thread/Turn/message identity; recheck native focus after the asynchronous reply. A focus transition during the request invalidates that attempt. Multi-window focus must be verified before release; global application activation alone is never sufficient.

There is also a settling trap. The [existing gate](../../../Notchline/Notchline/CodexDesktopUnreadState.swift) immediately removes a row when previously observed unread evidence becomes read. If the short gap between native completion and rendering is reported as **unread**, watching a Turn finish can bypass the normal two-second settling interval. Report incomplete render evidence as unavailable, without claiming unread; a positively observed different Thread, background state or hidden panel can establish unread. This distinction passed an isolated check against the unchanged production gate.

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
