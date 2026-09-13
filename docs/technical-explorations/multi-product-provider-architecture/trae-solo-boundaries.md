# Trae IDE-hosted SOLO: observed capability boundaries

Research and native acceptance, **2026-09-12**, Trae **3.5.91**. This record does not expand the shipped L5 declaration, add an answer channel or change production observation. [Terminology](../../../CONTEXT.md) and [the cumulative support contract](../../product-support.md) apply.

## Conclusion

**The SOLO view inside Trae IDE is not the standalone SoloLite platform.** In the tested window, the UI said SOLO while `67679.Ov()` returned `trae-ide`, the persistent root had `sessionType: side_chat` and `env: local`, and the assistant used `agentId: solo_agent`. The existing scope gate admits this combination. The earlier Node test labelled its `platform: lite` fixture “SOLO”; that label overstated what the test proved and now says “standalone SoloLite”. The [official IDE SOLO overview](https://docs.trae.cn/ide_solo-mode) also describes the IDE's mode switch; the [separate SOLO introduction](https://www.trae.ai/blog/new_solo_beta_0331) describes a different product surface.

The current companion can observe ordinary local SOLO lifecycle and context, and can read its structured questions. **This is not sufficient evidence for cumulative L5 in SOLO.** The native examples supplied no `thought` text, so all 22 captured production frames had `preview: null`, despite visible tool activity and a final answer. The command experiment ran inside Trae's sandbox without a manual confirmation wait. These limitations must not disappear behind a successful question demo.

## Test environment and method

Used the user's already-running Trae window, its normal installed companion and existing account. The application version and all three production SHA-256 fingerprints were rechecked and matched the pinned build. Created exactly two dedicated test Threads, with three Turns in A and two in B. Prompts prohibited reading or changing project files. The only executed shell command was `printf SOLO-B-COMMAND`. No permission setting, model selection, authentication material or application bundle was changed. The original Thread was not submitted to or deleted.

Native accessibility exposed the live question forms during this pass. The product's developer console provided temporary access to its already-owned V2 facade and stores. Submissions used `10678.Ok.directlySendToSideChat`, and the Plan experiment used `sendToAgent` with `enablePlanMode: true`. Answers and question skipping used the actual native form. Cancellation used the product's existing `chatSessionService.stopSession`. None of these test-driver operations was added to the production companion.

A bounded temporary wrapper around the installed reader's `emit` copied its actual outgoing snapshots while still forwarding every original event. An additional instance of the identical reader compared one pending-question baseline; it was separately stopped. Neither observer connected or disconnected Aha. A temporary loopback receiver accepted one-way exports only. The retained [22-frame fixture](../../../Notchline/NotchlineTests/Fixtures/Trae/solo-3.5.91.jsonl) contains only the companion's bounded wire projection, with the Project path replaced by `/Projects/Trae Solo acceptance`. It contains no native transcript, model configuration, reasoning or credentials.

The first question began before the Notchline instance used for the remaining observations attached. It appeared in a later baseline and was correctly not admitted as a new Turn. That initial missing row is not evidence that SOLO's widget failed. Later new Turns were observed by the production companion and the actual overlay reported Input needed alongside an independently completed Thread. Aggregate overlay counts were not used to identify individual Threads; native IDs and wire frames supplied that evidence.

## Native results

| Capability or boundary | Observed result |
| --- | --- |
| Ordinary local SOLO identity | `trae-ide`, persistent local `side_chat`, root `solo_agent`; no parent or remote identity was used |
| New Turn and metadata | Temporary assistant IDs produced no row. Valid native Thread/Turn/message IDs then appeared, followed by the native title and Project folder |
| Concurrent Threads | A remained at a real question while B started and completed its own command Turn; their identities and states remained separate |
| Success | B's command Turn reached native `completed`; A's answered first Turn also completed |
| Subsequent Turns | A's second and third Turns retained its Thread ID and acquired distinct Turn/message/request IDs |
| Questions | Two ordered questions, single and multiple selection, native Others, 500-character custom input and optional 1000-character additional information were present in both native form and projection |
| Answering in Trae | Selected Blue, both feature options and a short additional note in the native three-page form. The matching request disappeared before the Turn completed with `SOLO-A-DONE` |
| Question skip and replacement | Native Cancel set the third Turn's first request to `skipped`. The model then asked the same words again with a **new** request ID. The projection resolved the first and opened only the replacement; repeated wording is not repeated identity |
| Turn cancellation while waiting | Native `canceled` closed A's second and third Turns and exported an empty request collection, even where native question records/drafts remained visible |
| IDE/SOLO switching | Switched from SOLO to IDE and back during A's second question. The native form and overlay wait survived; this was one round trip in one window |
| Observer detach and recovery | Stopped only the production reader while A's second question was pending. Automatic reattachment returned the same Turn and request IDs, with native state still `in_progress`. Later cancellation remained observable |
| Exact navigation | The production Unix-socket `navigate` operation selected A from B and returned `ok: true` with developer tools closed; the native shape question was visibly selected. An earlier attempt with developer tools active returned `ok: false`. This does not prove navigation across multiple windows |
| Plan | B's second Turn carried `is_in_plan_mode: true`. The companion emitted an exclusion for B and no Plan Turn row. The separate store `planMode` selector was false, demonstrating why the message-level check matters. The test Plan Turn was then cancelled |
| Sandboxed command | `requires_approval: true` did **not** establish a manual wait. Trae ran the harmless command, recorded `now_run_mode: in_sandbox`, and reached success; no command-approval request was exported. The actual policy/selector must remain authoritative |
| Progress and final words | These examples had empty native root `thought`. B's visible final answer was present in `finish.params.summary`, which the production projector does not read. No frame supplied preview text. Lifecycle success is not progress/content acceptance |

## Boundaries not widened by these results

| Area | Current boundary and evidence limit |
| --- | --- |
| Manual command approvals in SOLO | Not established by this run. Existing IDE acceptance and synthetic ordinary-command tests remain relevant to the shared form but do not replace a live SOLO manual-wait experiment. No run policy was changed to force one |
| Rich permissions and unknown requests | Existing projection tests check conservative fallback. Sandbox recovery, network/path permission dialogues, browser handover, MCP permissions and document review were not induced live |
| Plan/Spec | Plan exclusion was observed live. Spec exclusion is covered by existing synthetic inputs; no live Spec document/revision workflow was tested |
| Child work | The gate excludes parented Threads, child-owned plan entries and child requests. No live SOLO delegation, background-child completion or child approval acceptance was performed |
| Other products and environments | Standalone SoloLite, web and remote execution remain excluded; no independent SOLO installation or remote workspace was tested. Agent/model variants beyond this window's Agent/Auto selection remain unverified |
| Answering from Notchline | Reading-only request operations and no answer handle. The test driver's native form actions do not establish L6 |
| Read removal, deletion, usage | No Trae read-removal, deletion-retirement, quota or token source is supplied. Exact navigation is not read evidence. Deleting a native Thread is not a promise that its retained monitoring row immediately retires |
| Recovery and failure | Reattachment in the same application lifetime was observed. Cold-start admission of an already-running Turn remains deliberately absent. Full Trae restart, extension-host restart in SOLO, multiple windows, forced native Turn failure and arbitrary crash/gap races were not tested in this pass |
| Cost | No Release performance measurement was made. Developer tools and the extra reader make these observations unsuitable for an overhead comparison |

The support decision therefore stays conservative: distinguish IDE-hosted SOLO from standalone SoloLite, record the verified lifecycle/question capabilities, and keep SOLO outside the cumulative L5 promise until progress delivery and its declared manual approval forms have appropriate native acceptance. Do not weaken the native scope/identity gates merely to change the level label.

## Retained checks and cleanup

[TraeSoloBoundaryTests.swift](../../../Notchline/NotchlineTests/TraeSoloBoundaryTests.swift) replays the actual production frames through the wire decoder, evidence boundary and shared reducer. It checks historical non-admission, independent completion, new Turn identity, reading-only questions, Plan route exclusion, request-preserving reconnect, skip/replacement identity and terminal request clearance. It does not turn missing native experiments into passing acceptance claims.

The existing 15 Node projection/renderer tests passed. Full Debug verification before adding the replay test passed **929 tests in 23 suites**. The first sandboxed build could not start tests because Xcode's Swift macro server returned malformed responses; the authorised unsandboxed rerun passed without changing assertions or source to suppress the failure. Final verification including the new replay test passed **930 tests in 24 suites** in 43.707 seconds of test execution; all **15 Node tests** also passed. This is functional verification, not a performance measurement.

Both created Threads were stopped and deleted. Native `getSession` returned not-found errors for both exact IDs, and the original Thread was selected again in SOLO. The original reader method was restored, the extra reader and lease timer stopped, export sockets closed, and temporary diagnostic references released. No `.trae` directory or project-file changes were created by the test Turns. Temporary receiver files, native extracts, logs and isolated DerivedData are removed after retaining the fixture and conclusions.

The non-public integration registry was checked. This work adds, modifies, migrates and removes **no production private integration**, Codex or Trae; it adds verification evidence for the existing Trae dependency only.
