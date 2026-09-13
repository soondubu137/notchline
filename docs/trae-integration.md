# Trae local IDE integration

Implemented for the verified macOS Trae **3.5.91** build at **L5**, within the mode and request-form limits in [product support](product-support.md). This is a production companion implementation following the [feasibility record](technical-explorations/multi-product-provider-architecture/trae-desktop-l5-preflight.md), not a proposal to own Trae’s model connection.

## Setup and scope

Enable **Trae Desktop** in Notchline Settings, then reopen Trae’s windows. Notchline builds a VSIX from its bundled JavaScript and uses `/Applications/Trae.app/Contents/Resources/app/bin/trae` to install `notchline.trae-companion`. Turning the switch off removes that extension through the same CLI. Installation is separate from connection health. Nothing modifies Trae’s bundle, Hooks, authentication material or workspace configuration.

Supported: local IDE/V2 persistent root Threads, native Thread/Turn IDs, elapsed time from a known start, displayed titles and workspace folders, displayed root progress, ordinary manual `RunCommand` approvals and structured `AskUserQuestion` sets. A native `side_chat` is the persistent IDE root type; it is not Notchline’s temporary *Side chat*. Native `getSession` must confirm its ID, root ownership, local scope and type.

Excluded: SOLO, remote workspaces, Plan/Spec, child activity and rich permissions. An identified but unknown request uses the existing unsupported form and returns to Trae. No answer handle, read-removal source, quota, token counter, subagent source or cold-start recovery is supplied. Final rows retain the last displayed root words; native success, failure and cancellation all close the Turn without adding another status or reason label. Navigation returns to the exact observed Thread in its owning window and verifies selection; otherwise it reports only that Trae was raised. It never declares a Turn read.

Only a new native Turn observed after attachment may open a row. A baseline is not evidence of submission, and cannot admit an already-running or historical Turn. Native second-resolution creation times use a one-second boundary tolerance only when a previously unseen assistant first becomes a valid live Turn. Reconnection can correct a Turn already observed in the same application lifetime. A changed application process resets that lifetime. Finished rows remain until a new observed Turn, dismissal or the monitoring lifetime ending; Thread deletion is not an independent retirement source.

## Implementation and private dependencies

The current [official Hook reference](https://docs.trae.cn/ide_hook-configuration-reference), rechecked 2026-09-12, does not supply an equivalent displayed-content and faithful native-form observation stream. The normally installed companion uses Trae’s private `icube` proposed extension API and renderer modules. This dependence is explicit in [the registry](non-public-codex-integration-features.md#trae-desktop-local-ide).

`trae-extension.js` checks `product.json.appVersion` and streams SHA-256 over these application-relative files before exposing any socket:

| File under `Contents/Resources/app/` | SHA-256 |
| --- | --- |
| `modules/ai-agent/libai_agent.dylib` | `2e93b706d711574a717a985bc84c329aa903d9a75b4bcde83e01ce84d2450f6f` |
| `out/vs/workbench/workbench.desktop.main.js` | `a7a826e8191a386eb7c73bc3f6926924ef981f377721486c4480f0917b24276d` |
| `node_modules/@byted-icube/ai-modules-chat/dist/index.mjs` | `1198074030bb24e4b79f349c06ffc67b20feda642a9e35836c7194ed4c0fe7ac` |

The component listener is attached in its constructor because the title-slot component is not guaranteed to have a normal connected-element lifetime. It imports the application module by absolute path, resolves the **existing product-owned client**, and subscribes to the same session/message/plan stores and pending-request selectors the UI uses. It neither connects nor disconnects Aha. Its stop operation removes only its own subscriptions and timers.

`trae-projection.js` exports displayed root `thought`, never `reasoningContent`; hidden or child-owned entries cannot replace root content. Tool existence alone never opens a wait. The native pending selector, manual confirmation state and unconsumed result must agree. Ordinary command parameters are preserved, including `command_type`, which the live fixture initially exposed as an overstrict allowlist omission. Rich permission fields stay unsupported. Questions retain order, labels, descriptions, the native Others control, single/multiple selection, the 500-character custom field and the optional 1000-character additional-information field when the native feature flags include it. Original product wording is preserved; Notchline’s own instructions use British English.

The renderer captures every lifecycle/request edge synchronously. Adjacent content-only batches can merge for 100 ms; a new wait, resolution or Turn boundary cannot be overwritten by that merge. Native root/Project confirmation is asynchronous but generation-guarded. The source owns no more than 512 observed Threads and 128 pending batches; each batch changes at most 128 Threads. Overflow or incompatible data reports unavailable.

`TraeBridgeTransport` discovers at most 16 same-user mode-0600 endpoints under a mode-0700 Notchline directory. Newline framing, owner selection, duplicate/sequence checks and `TraeEvidenceBoundary` run on one serial queue. Frames are limited to 1 MiB and buffered input to 2 MiB. Only typed `MonitoringEvidence` and `MonitoringProgress` enter the shared `MonitoringRepository`. A 10-second heartbeat/discovery timer and 35-second lease control observation health alone. Missing fields, corruption, sequence gaps, incompatible versions and lost peers hide affected rows without resolving their requests or inventing a Turn end. A second window’s stale running baseline cannot reopen an already-ended Turn. Scope exclusions withhold navigation and content without changing native lifecycle state.

## Verification record — 2026-09-12

The normally installed extension was tested in an isolated Trae profile and Extensions directory, in an empty local Project, without development-extension or renderer-debug launch flags. The test-only command driver was injected solely into that temporary extension copy; production’s operation allowlist contains observation, lease/stop and exact-ID navigation only.

Real native acceptance covered two concurrent Threads, two successive Turns in each, streamed displayed progress, ordinary command confirmation, cancellation with a stale native confirmation record still present, two-question single/multiple-choice forms and optional additional information, native question skipping, completion, exact-ID navigation, observer disconnect and extension-host restart. A pending question survived disconnection and restart without a cancelled Turn. The final reconnect returned that pending question and the other Thread’s cancelled terminal state under their original IDs. The two test Threads were deleted afterwards and native `listSessions` confirmed total zero.

The persisted acceptance fixture keeps only the companion’s bounded wire projection, with the temporary workspace path replaced by `/Projects/Trae acceptance`; it contains no transcript, reasoning or credentials. Success/failure field validation and stale/unsupported cases are also covered offline. The fixture does not claim a live forced-failure experiment, multi-window navigation acceptance or broader mode coverage.

| Layer | Retained evidence |
| --- | --- |
| Native projection | [projection.test.cjs](../tests/trae/projection.test.cjs): scope, ownership, automatic confirmation, consumed requests, rich forms, question details and malformed input |
| Renderer ordering | [renderer.test.cjs](../tests/trae/renderer.test.cjs): content coalescing preserves boundaries, retired async callbacks cannot publish, queue overflow stops only the observer |
| Shared reducer and UI | [TraeConformanceTests.swift](../Notchline/NotchlineTests/TraeConformanceTests.swift): baselines, native replay, lifecycle/request identity, independent Threads/producers, reconnect, scope exclusion, stale-window correction, marker states and real opened-row sizing |
| Socket boundary | [TraeTransportTests.swift](../Notchline/NotchlineTests/TraeTransportTests.swift): real isolated Unix peer, fragmented frames, handshake/route ownership and corruption without false resolution |
| Native fixture | [displayed-3.5.91.jsonl](../Notchline/NotchlineTests/Fixtures/Trae/displayed-3.5.91.jsonl) |

The actual `OpenRow` SwiftUI was rendered and inspected for all three question pages and the long command body. The question controls were reading-only, question/request navigation remained available, optionality and text limits were visible, and the long command used the existing scroll/fold treatment. Settings was also rendered, including the fourth row and companion-specific help. It now scrolls within the display-height cap so lower controls remain reachable.

## Measured cost

Native Trae idle comparison used differences of cumulative `ps -o time` over its **isolated process tree**, not instantaneous `%cpu`. Over 20.11 seconds with the final observer attached, the 15 processes used 0.41 CPU seconds; over 20.13 seconds after detaching, they used 0.60 CPU seconds. The extension host contributed 0.01 and 0.03 CPU seconds respectively. An earlier observing sample used 1.52 CPU seconds and included 1.10 seconds in a renderer. These noisy process-tree readings do not establish a negative overhead or a precise companion-only percentage. They show no sustained observer-driven activity in the final idle sample; startup fingerprinting and active model work are not measured by this comparison.

Release (`-configuration Release ENABLE_TESTABILITY=YES`, retaining `-O`) measured the actual transport, JSON decoder, boundary and shared reducer in the test host. With a real isolated Unix peer attached and one pending request, the process consumed **0.051826 CPU seconds over 20 seconds idle** (about 0.26% of one core). Sending **1,000 fragmented progress frames** consumed **0.991126 CPU seconds over 12.19 seconds wall time**, about 0.99 ms CPU per frame. This is a cumulative `getrusage(RUSAGE_SELF)` difference and includes the test host and polling used to await the last frame; it is not an overlay hover measurement or a model-work measurement. The peer deliberately fragmented each line with a short delay, so the wall time is not a throughput claim. All 16 Trae tests present in that optimised run passed. The temporary measurement branch was removed after retaining these results.

Full Debug unit verification passed: **926 executions in 23 suites** with one Xcode runner (`-parallel-testing-enabled NO`). The earlier parallel run exposed four obsolete three-product assertions, now updated to the product registry and the actual set of Hook-configured products, plus two existing App Server `initialize` timeouts and one asynchronous draft assertion. Those three existing tests pass in this full run; their assertions and timeouts were not weakened.

Exact navigation additionally requests focus on the owning renderer window and requires `document.hasFocus()` together with the selected native ID. If either cannot be confirmed, Notchline reports only an application raise. A refused navigation leaves observation running. Multi-window focus is covered conservatively by the renderer fixtures, not claimed as live acceptance.

Final renderer/projection verification passed all **15 Node tests**. The final focused Release verification passed **17 tests** (before the additional Settings-state test, which is included in the complete Debug run). The production Release build was also checked without testability enabled.
