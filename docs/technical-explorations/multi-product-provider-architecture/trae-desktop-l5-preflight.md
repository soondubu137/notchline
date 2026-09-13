# Trae Desktop — preliminary validation towards L5

Status: **research only, 2026-09-12**. No Trae Provider has been implemented and no support level is awarded. The target is cumulative **L5**, initially for command approvals and structured questions in explicitly verified Desktop modes. Document review and other permission forms need separate coverage decisions.

The terminology is defined in [CONTEXT.md](../../../CONTEXT.md); the acceptance contract is [product-support.md](../../product-support.md). This report adds no production private integration and changes no current product coverage.

## 1. Conclusion

**L5 is technically achievable for Trae 3.5.91's tested local IDE/V2 mode**, covering ordinary manual command approvals and `AskUserQuestion` forms with multiple questions, single/multiple selection and product-added text fields. This is a feasibility conclusion, not an awarded or shipped support level. §12 establishes normal extension installation without a debugging port, live displayed-data reads, genuine Hook delivery, exact Thread selection, and safe store-listener removal and reattachment.

The viable route is a version-pinned companion extension that observes Trae's existing renderer store and reuses its product-owned client for identity and metadata checks. Public Hooks can supply submission and request hints. **Neither public Hooks alone nor persisted-message snapshots alone are sufficient.** A live question remained visible while its persisted read returned only the user message; renderer data supplied the missing current request. Raw Aha connection ownership remains rejected because disconnecting it stopped the observed Turn twice (§10).

The remaining work is production implementation and acceptance: boundary/reducer ordering, bounded observation, unknown-schema and version rejection, installation/settings, reading-only UI integration, and Release cost measurement. SOLO, Plan/Spec, document review, remote execution, richer permission forms and subagent requests remain outside the verified scope.

Three shortcuts were ruled out for this installation: ordinary SQLite reads of the conversation database fail; the existing macOS accessibility tree exposes no text or stable identifiers; and the observed local listening ports are not the AI engine. Those findings led to the in-process companion bridge validated in §12; they do not establish a standalone public local API.

## 2. Baseline and isolation

| Item | Observed value |
| --- | --- |
| Installed application | `/Applications/Trae.app`, version and build `3.5.91`, bundle identifier `com.trae.app` |
| Distribution | Product configuration names `Trae`, application `trae`, data folder `.trae`, URL scheme `trae` |
| AI engine | `Contents/Resources/app/modules/ai-agent/libai_agent.dylib`, loaded in an Electron native utility process |
| Chat implementation | `Contents/Resources/app/node_modules/@byted-icube/ai-modules-chat/dist/index.mjs` |
| Product data | `~/Library/Application Support/Trae/ModularData/ai-agent/` |
| Existing Hooks | Neither `~/.trae/hooks.json`, `~/.trae-cn/hooks.json` nor this checkout's `.trae/hooks.json` existed at inspection time; the discovered `agent-hooks.log` was empty |

Claude Code was editing the shared checkout during this investigation. It already had modifications in request models, Hooks, the reducer, the store, the overlay, tests, the Xcode project and `docs/product-generalisation-plan.md`. This investigation writes only this new research document. It does not edit those files, use the Git index, launch Notchline, run an Xcode build, change Claude configuration or register Hooks in the shared checkout. §12 registers observational Hooks only in a disposable Project. The first pass submitted no Turns; the follow-up in §10 used a separate Trae profile and disposable Project, with user-assisted login. Only that disposable instance was restarted during onboarding. No full-suite result is claimed, and no commit was made while preserving the concurrent workflow.

A bounded macOS accessibility reader was compiled in a unique temporary directory. Only read APIs were invoked; it neither focused a window nor changed accessibility settings. Offline parser checks executed isolated classes extracted from the installed chat bundle with synthetic inputs and inert dependencies. They did not load the whole application module or call its live transport. Temporary apparatus was removed after recording the results.

Revalidation fingerprints, SHA-256:

| Installed file, relative to `Trae.app/Contents/Resources/app/` | Digest |
| --- | --- |
| `modules/ai-agent/libai_agent.dylib` | `2e93b706d711574a717a985bc84c329aa903d9a75b4bcde83e01ce84d2450f6f` |
| `out/vs/workbench/workbench.desktop.main.js` | `a7a826e8191a386eb7c73bc3f6926924ef981f377721486c4480f0917b24276d` |
| `node_modules/@byted-icube/ai-modules-chat/dist/index.mjs` | `1198074030bb24e4b79f349c06ffc67b20feda642a9e35836c7194ed4c0fe7ac` |

## 3. Public Hooks: useful, but insufficient on their own

The [official Hook reference](https://docs.trae.cn/ide_hook-configuration-reference) documents `UserPromptSubmit`, `Stop`, tool pre/post events and asynchronous notifications. Inputs carry a session identity and workspace context; tools also carry an invocation identity and arguments. Notifications distinguish approval, questions, document review and browser interaction. Notification output cannot answer a request. `Stop` can be blocked by another Hook and must not automatically be treated as final completion.

The reference lists neither a live displayed-message event nor a transcript path. Closing text alone does not establish L3. It also does not establish a complete resolution channel for every refusal or cancellation. A pre-tool event alone is not a user wait.

The documentation describes the CN configuration location. This installed distribution uses `.trae`; its workbench contains `.trae/hooks.json` and a global relative `hooks.json` definition. The correct global location and enablement must be verified against this distribution before registration. Importing Claude Hooks is supported by the documentation, but should not be used to route Trae into Notchline's Claude product: attribution and event namespaces must remain distinct. No Claude configuration was imported. §12 subsequently enabled only disposable Project Hooks and verified their delivery; global registration remains untested.

The installed engine contains the documented notification names and Hook input-building implementation. That initially confirmed shipped code only; §12 supplies actual delivery evidence for the tested local IDE mode.

## 4. Transport and local-read probes

| Probe | Result | Consequence |
| --- | --- | --- |
| Read-only SQLite connection, then `SELECT count(*) FROM sqlite_master` | `file is not a database`; file lacks the normal SQLite header | No ordinary transcript/database reader is available through this route. SQLCipher implementation and migration strings occur in the engine, consistent with encryption; the precise database format was not independently decoded |
| Process and socket inspection | AI utility PID `9880` had no observed listening TCP endpoint; `127.0.0.1:51000` belonged to the CKG utility, `127.0.0.1:20802` to the extension host | These ports cannot be claimed as a Trae conversation API. Neither was sent speculative requests |
| Native accessibility inspection of running Trae | Trusted access; successful window read; one window; 12 nodes: one window, eight groups, three buttons; no static text values and no identifiers | Existing AX exposure cannot supply current progress or request identity. This does not prove AX remains unavailable after a future explicit accessibility-mode change |
| Bundled `ctx-cli --help` and `ls --help` | ContextFS file commands, with `context://` paths | No conversation-list or event-subscription interface was established. Help output alone does not rule out useful context paths |
| Workbench transport inspection | `createLocalAhaRpcClient` calls Electron's `ahaIpc.connect("ai-agent")`; preload obtains `ahaIpc` from the product's customised Electron | The live route is in-process/private IPC, not a demonstrated standalone socket protocol |

The workbench wraps requests with a generated channel ID and `client_info.connect_session_id`; its transport uses `request` and `request_stream`. The chat adapter maps logical operations to native methods:

| Logical operation | Native service/method found in the installed chat module |
| --- | --- |
| List Threads | `lite.list_chat_sessions` |
| Read Thread / status | `lite.get_chat_session` |
| Read messages | `lite.get_messages` |
| Subscribe to a Thread | `lite.subscribe_events` |

These mappings were initially source-verified and were subsequently live-called in §10. The same bundle contains an older `chat` service path. A legacy-created Turn was readable through `lite.get_messages`, but its `lite.subscribe_events` observer received no live events. A Turn submitted through the current V2 chat implementation did emit them. Operation names alone do not establish coverage across modes or generations.

The subscription facade accepts a `lastEventId`, but its presence does not prove replay is correctly forwarded through every adapter. Cold-start recovery and gap-free reconnection remain unverified.

There is an additional reason to test this in isolation: engine diagnostics include a chat handler that stops a chat when its RPC disconnects. The §10 probe reproduced Turn cancellation when disconnecting its native connection. The §11 reader avoids owning or disconnecting that connection. Independent reader lifetime must be tested per transport, not inferred from an API name.

## 5. L3: content exists, display attribution remains a gate

The installed chat module declares `metadata`, `text_message`, `plan_item`, `session_title_message`, `done`, `error`, `tool_call_cancel` and `plan_item_revoke`, among other events. These are internal event names, distinct from official Hook names.

The text parser separates `content` into `proposal` and `reasoning_content` into `proposalReasoningContent`. The inspected text-event handler updates the inline store; this alone is not proof that ordinary Desktop agent Turns use that same handler. The plan-item route carries `thought`, tool data and separate `reasoning_content`, and updates the conversation store. Some messages have `hide`/rendering flags or belong to other producers.

The metadata parser retains session ID, message ID, a native Turn index and a timestamp. The stream layer also uses the user-message identity and `reply_to_message_id`. Plan-item routing uses `task_id`, `agent_run_id` and parent relationships. **These identities must be mapped, not conflated.** A root row cannot be created merely because an event names a session, and a child's text cannot replace the parent's current preview.

The §10 experiment obtained a real update before completion, correlated its Thread/Turn identities and matched its selected text against Trae's rendered DOM. This is one tested IDE path, not complete L3 conformance. Never fall back from absent displayed text to reasoning, hidden content or a previous Turn.

## 6. L4/L5: promising schemas and important traps

### Commands and permission requests

`IPlanItemParser` preserves distinct plan-item and tool-call IDs, tool parameters, results, `confirm_info`, producer identity and `meta.llm_toolcall_id`. A `RunCommand` is normalised to `run_command`. Confirmation values include `unconfirmed`, `confirmed`, `skipped` and `canceled`; automatic-confirmation information is separate.

**The parsed outer status is initially `running` even when `result.status` is already `success`.** An offline execution reproduced this. A Provider must use native result and confirmation semantics, not map that outer field directly to Running or an open wait.

The renderer also reads permission-specific fields for paths, networks, command prefixes, MCP tools and the reason for asking. An L5 command preview cannot silently omit those fields when they are the actual request. Automatic review and fallback to manual confirmation require separate cases; an unconfirmed intermediate object is not automatically a request currently shown to the user.

### Structured questions

The question renderer consumes a question collection with `header`, `question` and `options`; labels, descriptions, multiple selection and user-supplied text have explicit handling. `request_user_input` is normalised to `AskUserQuestion` with `_fromRequestUserInput`, and that flag changes presentation behaviour. Question answers appear in different places while pending and after results arrive. The UI also contains skipped/timed-out states.

Offline preservation of a question collection is useful schema evidence, but does not validate every rendered form. Required questions, optional questions, multiple selection, custom text, skipped questions, cancellation and replacement still need actual Turn observations. Do not convert an unknown question shape into an ordinary approval.

### Resolution, revocation and identity

`PlanItemRevokeStreamParser` uses `reply_to_message_id`, `task_id` and a collection of `plan_item_id`/producer identities to remove specific items. `ToolCallCancelStreamParser` resolves several ID aliases: tool-call ID, plan-item ID, item ID and `meta.llm_toolcall_id`. Its helper rejects a different request ID in the offline check.

**Do not reuse the product's event handlers as a monitor.** The cancellation handler can invoke a shell-command cancellation adapter; the plan-item handler can send an automatic confirmation for certain background work. Only decode and project evidence in a future Notchline boundary. A passive observer must never execute these side effects.

A native cancellation event is not yet proof of how a particular approval refusal, question skip or document-review cancellation resolves. Those paths need pairing with their opening event and matching identity. Late results must not clear a newer request.

The private command `icube.chat.getSessionRunningStatus` returns `WaitingInput` when no session ID is supplied, and the same vocabulary is used when a conversation is ready for another user message. It cannot by itself establish Notchline's Input needed state.

### Documents and other forms

The installed `NotifyUser` card reads `file_paths` and `explanation` and opens documents through a separate document-view route. The Hook notification does not itself establish the full reviewed document. Before promising L5 for Plan/Spec review, resolve the exact document and revision, preserve the product's wording, and observe replacement and withdrawal. Browser interaction and richer permission forms remain separately unverified.

## 7. Executed offline checks

Four isolated native classes were evaluated from the installed module: `IPlanItemParser`, the text parser, `PlanItemRevokeStreamParser` and `ToolCallCancelStreamParser`. Only parsing and identity helpers were invoked. Superclasses and dependencies were inert; no renderer event handler, network request or product state mutation was executed.

**14 checks passed**, using synthetic inputs:

1. Plan-item ID and tool-call ID remain distinct.
2. Session and producer IDs survive projection.
3. `RunCommand` normalises to `run_command`.
4. Command arguments and confirmation fields survive.
5. Outer `running` can coexist with a successful result.
6. An ordinary tool gains no invented confirmation object.
7. Single- and multiple-selection question shapes survive the plan parser.
8. `request_user_input` is explicitly translated and marked.
9. Display-text and reasoning fields remain separate.
10. Revocation retains valid item identities and filters entries without IDs.
11. A malformed native revocation collection becomes empty in the native parser.
12. Cancellation matching accepts source ID aliases.
13. Cancellation matching rejects a different request.
14. Cancellation IDs are deduplicated and non-string IDs filtered.

These checks establish selected behaviour of shipped decoding code. They are **not** Notchline conformance tests, real Hook payload fixtures, a live L3/L5 demonstration or a performance measurement. In particular, Notchline must not copy the native empty-on-malformed behaviour as a successful empty state: corruption cannot clear a known request.

## 8. Next validation sequence and acceptance gates

| Order | Experiment | Required evidence |
| --- | --- | --- |
| 1 | Establish a passive read connection in a disposable Trae profile/window and disposable Project | Read only list/message/status operations or a bounded observer bridge; independent connection lifetime; no secret extraction, no production bundle patch; detaching cannot affect the Turn |
| 2 | Observe one normal Turn with text before a delayed harmless tool | Current Thread/Turn identity, displayed-text correspondence and measured update delay; final text alone fails |
| 3 | Observe two concurrent Threads, then two Turns in one Thread | No cross-Thread content, no old-Turn leakage, declared ordering/deduplication and correct producer/root admission |
| 4 | Enable a project-scoped capture Hook only in the disposable Project | Actual distribution-specific configuration and enablement; start, final completion, cancellation, retries and a Stop blocked by another Hook; no Claude Hooks import |
| 5 | Trigger one command approval and one question set | Faithful original command/question/options; positive request opening; approve/answer in Trae, refuse/skip, cancel and replace; each clears only its matching request |
| 6 | Exercise additional request forms independently | Explicit coverage for path/network/MCP permissions, document review and browser interaction; unknown forms return to Trae |
| 7 | Integrate and measure | Provider conformance, malformed/absent/version-incompatible sources, epoch rejection, concurrent requests, and Release CPU cost under normal observation |

After §11, the preferred candidate is bounded snapshot reads through the product-owned client. The external reader's lifetime was exercised through CDP; a normally installable bridge is still a **proposal**. Ordinary extension access, startup attachment without debugging flags and resource cost remain unverified. Do not implement the §10 raw connect/disconnect pattern in Notchline. Application patching and taking over a Turn's owning connection are not acceptable substitutes.

Conditional implementation shape: a Trae-specific lifecycle boundary and content/request sources composed by `ProductMonitoringRuntime`, submitting typed evidence to the single `MonitoringRepository`. Official Hooks and private readers stay separate. Re-check the shared interfaces after Claude Code's concurrent work finishes; this report does not assume its request/answer changes are complete.

**L5 is attainable only if the passive content and resolution gates pass.** Once ordinary approvals and questions meet every preceding level, declare exactly those modes and forms at L5, with other forms explicitly unsupported or unverified. Navigation initially returning to the host, read removal, quota, final answers and cold-start recovery remain independent capabilities; none should delay the decisive L3/L5 experiment merely to raise the level label. L6 answering is outside this work.

## 9. Revalidation pointers

Use targeted reads of the installed files; do not depend on minified variable names or byte offsets after an update.

| Evidence | Search anchors |
| --- | --- |
| Version/distribution | `Contents/Info.plist`; `Contents/Resources/app/product.json` |
| Native transport | Workbench `createLocalAhaRpcClient`, `getAiAgentRpcClient`, `TransportManager`; `out/vs/base/parts/sandbox/electron-browser/preload.js` |
| Chat API mapping | Chat module `chat.getMessages`, `chat.subscribe`, `buildRequest` |
| Content and identities | `IMetadataParser`, `IPlanItemParser`, `textMessageCanBeShow`, `IPlanItemStreamParser` |
| Request resolution | `PlanItemRevokeStreamParser`, `ToolCallCancelStreamParser`, `confirm_info`, `permission_request_reason` |
| Questions/documents | `params?.questions`, `_fromRequestUserInput`, `NotifyUser`, `file_paths` |

If a Trae private route is implemented, document its private dependencies and degradation alongside the support declarations and relevant contracts. The existing [non-public Codex integration registry](../../non-public-codex-integration-features.md) specifically covers Codex; it is not automatically a Trae registry. This research adds, modifies, migrates and removes no production private integration, and changes no Codex dependency.

## 10. Isolated live validation, 2026-09-12

### Scope and method

Six real Turns were submitted across three disposable Threads: one legacy-path command Turn, three V2 question Turns in one Thread, and a V2 command Turn followed by a question/skip Turn in another. The installed UI was in IDE mode with the native `solo_agent`; this is not a validation of the separate SOLO UI, Plan/Spec, remote workspaces or every account configuration.

The test used a unique directory under `/private/tmp`, separate `--user-data-dir` and `--extensions-dir`, disabled extensions, an empty Project and an ephemeral loopback debugging port. Electron CDP evaluated bounded requests in that disposable renderer; no application bundle was patched. Login was completed by the user. Request construction stayed inside Trae, using its own authentication context; no credential was exported to a probe file or retained in this document. Original Trae PID `9869` was still running from its original start time at the closing check. Claude processes and the shared source files were not targeted.

This was profile isolation, not a complete operating-system sandbox: Trae still has product-controlled shared locations such as `~/.trae`. No Claude Hooks were imported. The only model-requested shell commands were `sleep 12` and `printf NL-COMMAND-C`; no source edits were requested. The first command's recorded execution timing did not establish a twelve-second delay, so it is not used as latency evidence.

The observer sent JSON-RPC `request` / `request_stream` over `vscode.ahaIpc.connect("ai-agent")`, independently of the UI's request submission. Requests used the product's envelope builder. Success required checking both nested response codes; a malformed envelope returned a parse error, and an invalid Thread ID returned an explicit not-found error. A signed-out list call failed validation rather than proving an empty account. This debugger-assisted route is a laboratory interface, not a deployable standalone transport.

### Results

| Probe | Observed result | Implication |
| --- | --- | --- |
| Legacy/current implementation comparison | Legacy `chat` Turn persisted readable messages but produced no observed `lite` subscription events. V2 submission produced `rpc.stream.<streamId>` packets | Declare coverage by the actual submission path; do not combine legacy read success with V2 event assumptions |
| Live progress | V2 metadata arrived 169 ms after submission; `NL-PROGRESS-B` and question parameters arrived at 2,914 ms; unconfirmed request data followed at 3,014 ms. The Turn was still pending when the DOM showed the same progress text and question/options | Positive evidence for current-Turn displayed text, not just final text. These are one sample's arrival times, not transport-latency or performance guarantees |
| Identity | Metadata carried Thread ID, native Turn ID, assistant message ID and `reply_to_message_id`. Plan items separately carried plan-item, tool-call, task and producer IDs. Subsequent Turns in the same Thread used new message and request IDs | Identity mapping is feasible; a session-only cache is insufficient |
| Request reading | `AskUserQuestion` carried the exact question, header, option labels and descriptions; the rendered form also provided custom text and a cancel action | Ordinary single-question reading is demonstrated. Multiple-question, multi-select and custom-answer fidelity remain unverified |
| Snapshot during a wait | `get_messages` returned an `in_progress` assistant containing the progress and pending question. Native Thread status was `8` (`Waiting`) | A newly attached reader can recover this particular pending request; historical membership must still be gated by current native state |
| Subscribe during an existing Turn | A fresh subscription replayed event IDs `1`–`6` before delivering the later answer result | Replay exists in this case. IDs restarted at `1` in a later Turn in the same Thread; deduplicate with Turn identity and observation epoch. `lastEventId` resume semantics and gap-free recovery remain unverified |
| Answer in Trae | The ordinary product decision API accepted the selected option. The matching plan item changed to `confirmed` / `success` after 123 ms; `done` reported `completed` after 1,279 ms. Trae displayed `NL-DONE-B3` | Positive request-resolution evidence. Timing starts immediately before the test's answer API call, not a user click. This tests the source, not Notchline L6 |
| Question retry and skip | A malformed question failed validation; the model generated a new request ID. The probe initially selected the failed item and received code `2000000` (`no pending confirmation`), leaving the real request pending. Selecting the unique pending ID succeeded; it became `skipped` / `skipped` after 180 ms and `done: completed` after 2,151 ms | Failed/generated tool items must not open waits. Never select the first plan item or clear a replacement on a stale operation. Actual skip resolution is observed |
| Command false-positive control | `printf NL-COMMAND-C` had `requires_approval: true`, yet ran in the sandbox without a manual answer. Its result was successful and `confirm_status` was `confirmed`, with `auto_confirm: false` | Neither `requires_approval` nor `auto_confirm: false` proves a visible approval. A genuine manual command-approval opening/refusal remains unverified |
| Native disconnect, twice | Closing the observer's Aha connection changed the active question Turn to `Stopped` / `canceled`; Trae displayed `Manually stopped`. The second attempt used a distinct generated logical connection ID and reproduced within the 2.5-second check | **Failed passive-observer lifetime gate.** The exact native ownership mechanism remains unresolved; a separate returned connection object does not prove a separate lifecycle |
| Narrow detach attempts | Sending the source-derived `rpc.stream.cancel.<id>` notification preserved the pending Turn, but that supposedly cancelled stream later received seven packets. Calling `off("message", sameCallback)` also preserved the Turn, but the callback count later rose from 10 to 17 | Neither attempt demonstrated actual unsubscribe. Do not report these as successful safe detachment or assume observer resource release |
| Terminal-state precedence | After cancellation, the retained plan item still said `unconfirmed` with a running tool result, while the assistant was `canceled`. After one completion, the renderer's Thread cache temporarily retained Running while the assistant and a fresh native read established completion | Terminal evidence must invalidate pending requests for its Turn; retained request fields and renderer caches are not authoritative current state |

The disconnect experiments were intentionally confined to disposable Turns. They establish an observed effect, not a claim that all Aha consumers have this behaviour. The local listener and cancellation failures may involve native bridge semantics; their cause needs investigation before choosing a bridge architecture.

### What remains before L5

The next gate is **safe observer attachment and detachment without closing or replacing the product's connection**. A product-owned bridge that fans out immutable observations is a candidate, provided an external reader's disconnect leaves the native owner untouched and the observer resources are actually released. No such bridge was built or validated here. The direct debugger/native-connect prototype must not be shipped.

After that, validate real manual approvals, multi-question and multi-select forms, replacement/cancellation, concurrent Threads and producers, root navigation/admission, Hook delivery on this distribution, and loss/recovery ordering. Public Hooks remain a useful candidate boundary but were not installed or exercised in this follow-up. No cumulative L3 or L5 level is awarded, no support table is changed, and no Release cost or full-suite pass is claimed.

Cleanup completed: the three test Threads were deleted and a native Project list returned zero remaining Threads. The verified disposable main process exited; its profile, Project, extensions and debugging apparatus were removed, along with both known test-created sandbox traces. Original Trae PID `9869` remained running. Only this research document is retained in the checkout; no Git index operation, source change or build was performed.

## 11. Snapshot-only bridge validation, 2026-09-12

This follow-up submitted three Turns in two new disposable Threads: a two-question request, a manually declined command, and a manually approved command in the same command Thread. The question and first command were pending concurrently. The application version and all three §2 fingerprints were rechecked and unchanged. A fresh profile, extensions directory, empty Project and ephemeral debugging port were used again. Login restored automatically through the product; the probe did not copy credentials. Shared product state therefore remains outside the profile-isolation guarantee.

### Observation lifetime

The read route used Trae's existing V2 API client: `chat.getSession` and `chat.getMessages`, mapped by the installed adapter to `lite.get_chat_session` and `lite.get_messages`. There were **no probe calls to native `ahaIpc.connect`, subscribe, disconnect, listener registration or listener removal**. The product continued to own its transport. Each external Node reader opened a CDP connection, requested a bounded snapshot and closed the CDP connection when the response arrived. Only selected identity, status, displayed-text and request fields were returned; reasoning and credentials were excluded.

Twelve separate reader processes completed normally while the same question remained `Waiting` / `in_progress` / `unconfirmed`. Their native two-operation read durations were 13–26 ms, median 20.5 ms. These are small-history request durations in a running development probe, **not Release CPU measurements or a proposed polling budget**.

One further external reader was terminated with `SIGKILL`. To keep its CDP response outstanding deterministically, the renderer delayed that response for eight seconds after completing its native read. A fresh reader still obtained the same pending request; renderer timestamps subsequently confirmed that the delayed evaluation finished. This proves that killing the external reader during an outstanding debugger response did not cancel this Turn. It does not test forced cancellation inside a native RPC, an application crash, every reconnect race or a long-lived production bridge.

This result narrows the §10 blocker: **raw native disconnection is unsafe, but an external reader need not own that native connection**. No claim of working native unsubscribe is made. One other CDP call returned `Promise was collected` during a view switch; the next read succeeded. An unavailable read must preserve the last trustworthy state, never become an empty Thread list.

### Request and attribution results

| Validation | Observed result | Boundary consequence |
| --- | --- | --- |
| Snapshot schema | The V2 API returned `content.messages` entries tagged with `type` and a nested `plan_item`. The wrapper's `id` differed from the nested plan-item ID | Decode the observed schema explicitly. Do not use a wrapper/message ID as a request ID or assume that the raw native and adapter-returned shapes are identical |
| Multiple questions | One pending request contained a single-choice colour question and a `multiSelect: true` shape question, with original labels and descriptions | Both questions belong to one request; preserve their order and per-question selection mode |
| Rendered form | Trae's form state mapped these to `single` and `multiple`; navigating to the second page showed the shape question, descriptions and checkbox inputs | Multiple-selection presentation was inspected in the actual disposable UI, not just inferred from a Boolean |
| Product-added content | The renderer added an `Others` option and a third, optional free-text question: “Is there any additional information you’d like to provide? (Optional)” | Raw tool arguments alone do not describe the complete form. The form schema carried `maxLength: 1000`, while the displayed Others counter was `0/500`; field-specific limits need explicit mapping |
| Form answer | Trae's own existing form callback submitted Green, both Circle and Square, and `NL-BRIDGE-NOTE` as optional text. The matching native result retained all three answer entries, became `confirmed` / `success`, and the Turn completed | Multi-question, multiple-selection and optional-text result preservation are demonstrated for this form. This remains a source test, not a Notchline answer implementation |
| Actual manual approval | Setting `AI.toolcall.v2.ide.command.mode` to `alwaysAsk` wrote only the disposable profile's `User/settings.json`. The command request had `unconfirmed`, `run_mode: alwaysAsk`, `now_run_mode: manual`; Trae displayed the exact command with Run and Skip | Positive manual-wait evidence is now available, unlike the §10 automatic sandbox example. Other permission modes still need their own presentation and wait predicates |
| Concurrent Threads | The question Thread and command Thread independently returned native status `8` with distinct Thread, Turn, assistant, user-message and request IDs and their own progress markers | Cross-Thread correlation was checked on two concurrent waits. Simultaneous streaming, subagents and same-Thread concurrent requests remain unverified |
| Decline one request | Skipping the first command produced `skipped` / `skipped` and a completed Turn; the other Thread retained its pending question unchanged | Resolving one Thread must not clear another Thread's request |
| New Turn, old request | A second command Turn in the same Thread had a new native Turn ID and request ID; the first command remained historical and skipped. A stale decline using the first request ID returned code `2000000` and left the new request unconfirmed | Reject stale identity; do not select the first retained plan item or derive current requests from history alone |
| Manual approval outcome | Approving the second command, `printf NL-BRIDGE-COMMAND-B2`, produced `confirmed` / `success`, exit code `0`, and a completed Turn with `NL-BRIDGE-DONE-B2` | Both manual command decline and approval resolution now have live source evidence. No persistent permission rule was granted |

The question form was navigated and answered only in the disposable window. Reads used a separate channel from the product actions used to generate and resolve the test requests. No source file, Hook registration, production bundle or Notchline runtime was changed.

### Remaining gate

The next useful experiment is **normal installation and attachment without CDP**, using a product-owned bridge with an explicitly restricted read interface. Static inspection of the bundled IM bridge found an `icube` proposed-API dependency and messaging-specific commands; it did not establish an ordinary extension API for listing and reading arbitrary Trae Threads. No messaging connection or forwarding was enabled. Absence from this inspection is not proof that no suitable extension interface exists.

Before declaring L5, also pin the renderer's added question fields and constraints, root-Thread admission/navigation, version/schema rejection, pagination and current-state consistency, observation during reconnect, and sustained cost under Release. The experiment establishes a viable ownership pattern and more request coverage, not a shipped Provider or complete support-level conformance. Public Hooks, Plan/Spec/document review and richer permission forms remain unverified. The existing Codex private-dependency registry is unchanged and not applicable to this Trae-only research.

Cleanup completed: both test Threads were deleted and the native Project list returned zero remaining Threads. The verified disposable main process exited, and its profile, Project, extensions directory and probe scripts were removed. The reported command trace was already absent at cleanup. Original Trae PID `9869` remained running; no Trae process referenced the disposable directory at the closing check. Only the research document is retained; no source build, test-suite run, commit or index operation was performed.


## 12. Normally installed bridge and remaining source validation, 2026-09-12

### Installation and ownership

A minimal VSIX was installed into a fresh, explicit extensions directory with its own profile and empty Project. The manifest declared `enabledApiProposals: ["icube"]`. This distribution accepted it without `--enable-proposed-api`, `--extensionDevelopmentPath`, or `--remote-debugging-port`. The extension reported the embedded VS Code API version `1.107.1`; the application version remains `3.5.91`. Probe iterations modified only this disposable extension directory. No application bundle was patched, no debugger connected, and no messaging/IM connection was configured.

The private `vscode.icube.defineComponent` and title-component messaging interfaces loaded a small renderer component. That component reused the existing V2 client and read the existing displayed-data stores. Its extension host exposed a local Unix socket with mode `0600`, bounded requests and an operation allowlist. Test-only commands generated, resolved and deleted known fixture Threads; these are experimental controls, not a proposed L5 write interface.

The current title slot left the component detached from the DOM. Registering its message listener in the constructor worked; registering only in `connectedCallback` did not. Native widget messaging still retained and reached the component. This is a private host dependency, not a public extension guarantee or an invisible-widget API promised by Trae. Conversely, `getWebSocketRpcClient('ai-agent', {})` actually returned `$makeRPCClient not implemented`; an exported API name does not prove a usable transport.

An extension-host restart initially timed out after changing the component tag while reusing its script URL. A distinct versioned script URL restored the bridge. Subsequent reads recovered the same displayed pending request after the isolated extension host exited; the renderer and native AI owner stayed running. Production attachment needs a readiness handshake, a new observation epoch, versioned component loading and explicit cleanup. A timeout must report an unavailable read rather than an empty list.

### Live results

Four real Turns were submitted across three disposable Threads in this pass: a question cancelled before Hooks were enabled, another question later skipped, an approved command and a second command Turn cancelled in the same Thread. The two Hook-enabled request Threads were pending concurrently.

| Check | Result and implementation consequence |
| --- | --- |
| Normal reader lifetime | Twelve socket reads completed while the first question remained pending; a client also closed immediately after sending a read, and a new client still saw `in_progress`. Native two-call read durations were 44.5–58.3 ms. These are fixture request durations, not Release CPU measurements |
| Hook enablement | Only the temporary Project's `.trae/hooks.json` was enabled through the isolated profile's Hook configuration. `global_hooks_enabled` and `global_import_claude_enabled` stayed false; `import_claude_folders` stayed empty |
| Actual Hook delivery | Both the skipped question and approved command emitted `UserPromptSubmit`, `PreToolUse`, the corresponding `ask_user_question` / `permission_prompt` notification, `PostToolUse`, `Stop` and `idle_prompt`. The later cancelled command emitted submission, pre-tool and permission notification, but no Stop was observed before cleanup. Renderer/native terminal evidence is necessary for that cancellation |
| Hook identity | Payloads carried `session_id`, `agent_id`, `agent_type` and workspace context. Tool Hooks and request notifications shared a `call_…` invocation ID, distinct from the native plan/tool IDs. No native Turn ID was present in these Hook payloads. Correlate at the boundary; never equate those namespaces |
| Persistence lag | For the Hook-enabled question, native status stayed `3` and `getMessages(page_size: 50)` returned just its user message, while the product displayed the pending question. The renderer store contained its native assistant, Turn, request, options and `NL-INSTALL-PROGRESS`. This was not repaired by following the returned cursor. Hook enablement coincided with the case; its causal mechanism is not established |
| Displayed-data source | The product's session, message and plan-item stores returned current data for both concurrent Threads, including the Thread not currently selected. No reasoning content was exported. The raw `thought` field is eligible only with the product's visibility and producer rules; the experiment does not authorise displaying every plan item |
| Real store observation | Subscribing to the underlying store captured the next command Turn's native identity, displayed text, manual request and later cancellation. The store proxy binds function-valued properties: reaching `chatStore.subscribe` through that proxy failed; the source-defined underlying store instance worked |
| Detachment and recovery | The observer held 78 bounded diagnostic records. Calling its returned unsubscribe left the command `Waiting` / `in_progress`; navigating another fixture caused no increase in that count. Reattaching and deliberately cancelling the command produced terminal callbacks. This proves actual listener release and reattachment without native transport ownership, unlike §10's failed unsubscribe attempts |
| Transitional state | Observation briefly saw a Running Thread with its old completed assistant, then a temporary assistant without a native Turn ID, then the real assistant/Turn 44 ms later in this sample. A Thread status or temporary message must not become a new correlated Turn by itself |
| Same-Thread separation | The second command had a new user-message, assistant-message, Turn, plan-item and tool-call ID. Its `agent_run_id` was reused from the preceding Turn. Producer identity alone is therefore insufficient as a Turn or request key |
| Resolution | Native approval completed `printf NL-INSTALL-COMMAND` with exit code zero. Trae's existing question-form skip callback resolved the question whose persistence lagged. Both later had completed assistants and matching resolved requests. Cancelling the second command yielded `canceled` with an explicit end timestamp while retaining an old `unconfirmed` plan item; terminal evidence invalidates that request |
| Root identity and return | Both fixture Threads were present in native listing and accepted by native `getSession`. The renderer reported no parent and native type `side_chat`; switching by exact ID returned the matching current Thread. This native type denotes the tested persistent IDE root Thread, not the glossary's ephemeral Side chat. Admission must use the product's identity/parent facts, not the word “side” |
| Metadata | Native `getProject` required `project_id`, not `local_project_id`. Its result supplied a Project identity and `extra_info.folder`, but no human-readable Project name. Initial IDE support should explicitly declare a workspace-folder label, with missing-data rules, rather than claim a product-owned name. The Thread title is supplied by Trae |
| Pagination | In the two-Turn Thread, `page_size: 1` returned the latest assistant; `page_size: 50` returned both user/assistant pairs in chronological order. `total` was 2, not the four-message count; `total_messages_count` was a separate field. Following the full page's returned cursor yielded an empty page. Validate progress and identities rather than treating a non-empty cursor or `total` as proof of further assistant content |
| Invalid identity | An unknown 24-character Thread ID produced a native not-found error propagated as failure, not a successful empty snapshot |

Store event times demonstrate ordering in a single fixture. The probe observed the entire underlying store and retained repeated records from both Threads; its callback volume is not a production design or cost estimate. A Provider should observe the relevant projections, coalesce content changes, preserve boundary ordering and release its own subscriptions. It must never dispose Trae's stores or native connection.

### Complete question presentation

The actual form exposed two ordered questions, single and multiple selection respectively, original labels/descriptions, an added `Others` option, and an optional additional-information field. Twelve offline checks against the shipped pure question projector also passed: they exercise the projection and previous-answer handling, not live end-to-end conformance.

The projected schema says `maxLength: 1000`, but the choice form's Others input defaults to 500 characters. Preserve field-specific constraints rather than copying the shared schema value everywhere. The additional-information field also depends on the product configuration and the `_fromRequestUserInput` form variant; do not unconditionally add it to every question. A future reading-only boundary must use these verified renderer rules, include optional/required and selection semantics, and reject an unrecognised shape. The notch offers return-to-Trae controls, not answer controls, at L5.

### Scoped L5 feasibility and implementation handover

| Cumulative obligation | Evidence available; work still needed in Notchline |
| --- | --- |
| L1 | Live submission Hooks, native identities, displayed-data boundaries and explicit terminal reasons are available. Implement event/epoch ordering, temporary-ID rejection, elapsed-time origin and manual dismissal; cancellation cannot depend on Stop alone |
| L2 | Native Thread titles and Project/workspace identity are readable. Declare the folder-label source and missing-data behaviour explicitly |
| L3 | Live displayed progress is readable and store changes are observable. Filter hidden/other-producer text and publish bounded, coalesced updates |
| L4 | Genuine manual-command and question waits, in-product resolution and cancellation have positive evidence. Project request collections by full identity and invalidate from the owning Turn's terminal evidence |
| L5 | Ordinary manual commands and structured questions, including multiple questions/options and product-added text fields, have readable source data. Implement faithful reading-only presentation and send unknown forms back to Trae |

**Proceeding to implement this scoped L5 integration is justified.** It requires an explicit private Trae adapter: the companion extension APIs, component messaging, bundle module identifiers, displayed-store schema and native `lite` reads are version-dependent. Pin the installed version/fingerprints, validate the expected operations and schemas, and fail closed on mismatch; no live downgrade-on-update mechanism was implemented or tested by this research. Snapshot data must be checked against current displayed/native identity before correcting state. Public Hooks are supplementary and do not repair every missing progress/request source.

Keep these outside the initial claim: legacy submission paths, SOLO/Plan/Spec, document review, remote execution, richer permissions and subagent requests. Simultaneous multiple pending requests within one Turn, long-history recovery and arbitrary crash/gap races remain unverified. Read removal and quota remain independent, undeclared capabilities. A working companion prototype does not establish Notchline installation UX, Provider/reducer conformance, rendering correctness, Release cost or test-suite success; those are implementation acceptance work, not missing evidence that the tested request content can be obtained.


Cleanup completed: the first fixture Thread was deleted before the Hook pass; the other two were deleted at the end, and native listing returned zero remaining Threads. The store observer was released and temporary Project Hooks disabled. The verified disposable main process exited; no Trae process retained its profile path. Its profile, Project, extensions, VSIX files, scripts and captured output were removed. The one recorded command trace was already absent. Original Trae PID `9869` retained its original start time. The application version and all three §2 fingerprints were rechecked and unchanged. Only this research document is retained; no source edit, Xcode build, full-suite run, Git index operation or commit was performed by this investigation. No production private integration or Codex dependency was added, modified, migrated or removed.
