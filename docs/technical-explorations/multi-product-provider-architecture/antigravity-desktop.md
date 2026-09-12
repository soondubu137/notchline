# Antigravity Desktop — the CLI's second surface, measured and built

The [support contract](../../product-support.md) lists Antigravity as one product with two surfaces, Desktop and the CLI, at **L3** on both. This record is what Desktop adds to [`antigravity-cli.md`](antigravity-cli.md) and what it changes; everything that document measured about the engine's hooks and transcript still holds, and is not repeated.

| Field | Value |
| --- | --- |
| Status | **Built 2026-09-12** as a second surface of `AgentKind.antigravity`: `AntigravitySurfaces.swift` (routing, sessions, row content, read evidence, navigator) and `AntigravityDesktop.swift` (the application, Project and view-record readers) under `Products/Antigravity/`, with the registry entry, `AntigravityConformanceTests` and `AntigravityDesktopRecordsTests`. Run end to end the same day against the real application (§8), which found one defect before commit (§5) |
| Product | Antigravity Desktop **2.13.0**, `/Applications/Antigravity.app`, bundle `com.google.antigravity`: an Electron shell over a Go `language_server` it spawns with `--standalone --subclient_type hub --app_data_dir antigravity`. State under `~/.gemini/antigravity/`; configuration shared with the CLI under `~/.gemini/config/`; logs in `~/Library/Logs/Antigravity/` |
| Source baseline | Local `master`, `c021e01` |
| Method | Strings and the embedded guide in the server binary, compared with `agy` 1.2.2's; the shell's `app.asar` and the renderer bundle its server serves, read for deep links and read-state writes; then turns driven in the running application through its own DevTools port (the shell always enables one, and its recording feature uses it), with this app's existing registration forwarding every event to a listener on this app's socket path and a poller recording the transcript, the read records and the summaries database at 10 ms. No file of the user's was edited; three short conversations were created in Desktop's `notchline` Project and left there |
| Question | What is Desktop to the CLI, what of the CLI's integration carries over, and what does Desktop need of its own? |
| Answer | **The same engine behind the same hooks file**, so the registration, vocabulary, translator and transcript reader carry over unchanged. Desktop needs its own answers to four questions the CLI answers from a process and a terminal — is it open, which Project, has it been read, where does a click go — and has an honest answer to each on disk or in the running-application list. It also loses one thing the hooks were assumed to give: **a cancelled Desktop Turn sends no `Stop`** (§3) |

Terminology follows [`CONTEXT.md`](../../../CONTEXT.md).

## 1. What Desktop is to the CLI

**One engine.** Desktop's `language_server` and `agy` are built from the same tree: both carry `third_party/jetski/cortex/customization/hooks/…` (the JSON hook loader, command executor, pre/post/stop hooks), the same transcript writer (`transcript_full.jsonl` under `brain/<id>/.system_generated/logs/`), the same guide text, and the same RPC surface (`RetrieveUserQuotaSummary`, `StreamCascadeReactiveUpdates` and the rest in equal counts). What `agy` has and the server lacks is the CLI shell — `cli/store/hooks_manager.go`, the TUI, print mode — and what Desktop adds is the Electron window.

**One configuration.** Both read `~/.gemini/config/`: `hooks.json`, `mcp_config.json`, and `projects/<id>.json`. Desktop's guide calls that directory the *global customization root* and says hooks are loaded from a customization root's `hooks.json`; the CLI's changelog calls the same file the one its TUI and backend share. **So a registration written for either observes both**, and one Settings switch is the only honest shape for it: two switches would write and remove the same named hook.

**Separate conversations.** Desktop keeps its own under `~/.gemini/antigravity/` (`brain/`, `conversations/<id>.db`, `annotations/<id>.pbtxt`, `conversation_summaries.db`), and although its server tries to index the CLI's — its log has `summaries_store: failed to load external trajectory` for every one of them — its sidebar's `CLI Project` section reads **`No conversations yet`**. A conversation id therefore belongs to exactly one surface, which is what lets the surface be a property of the conversation (`AntigravitySurfaceLedger`).

## 2. The hooks, re-measured on Desktop

With Notchline not running and this app's registration unchanged in `~/.gemini/config/hooks.json`, a listener bound to `agents/antigravity/hook.sock` (the app unlinks and rebinds that path at launch) received, for a Desktop turn:

- **The same events and fields.** `PreInvocation` with `invocationNum` 0 opens the turn and counts up per model call; `Stop` with `executionNum` 0, `fullyIdle`, `terminationReason` closes it. The five common fields are present, with **`workspacePaths` filled** for a conversation in a Project's folder, and `transcriptPath` under `~/.gemini/antigravity/brain/`.
- **The hook's parent is the server.** Ancestry `nc ← sh hook.sh ← language_server ← Antigravity ← launchd`: no terminal, and one server process for every conversation.
- **The timings the translator relies on.** The user's step reached the transcript 8–61 ms before `PreInvocation` 0 reached the listener, across four turns; a later model call's words were on disk before the next `PreInvocation`, as on the CLI; and the closing words were written 29–33 ms before `Stop` reached the listener in the turns timed with file modification times. A tool turn:

| t (s) | What happened |
| --- | --- |
| −0.05 | User step written |
| 0.00 | `PreInvocation` 0 |
| 2.26 | Model step with a `run_command` (`sleep 4`) — Desktop ran it without asking |
| 6.30 / 6.31 | Tool result step, then `PreInvocation` 1 |
| 7.64 | Second `run_command` |
| 11.72 / 11.73 | `PreInvocation` 2, tool result step |
| 13.29 | `Stop` (closing words on disk 33 ms earlier by modification time) |

`AntigravitySurface` reads the directory under `.gemini` in `transcriptPath`: `antigravity-cli` is the CLI, `antigravity` is Desktop, anything else (the guide's `antigravity-ide`) is declined as before. Until this change `antigravity/` was declined as a sibling, which is why Desktop drew nothing although its events were already arriving.

## 3. A cancelled Desktop Turn sends nothing

Clicking **Stop execution** two seconds into a `sleep 12` turn: no `Stop` hook, no further transcript step (the cancelled command's step is never appended), and nothing in the read record. The record of it that was found is in `conversation_summaries.db`, where the conversation's `status` goes to `CASCADE_RUN_STATUS_IDLE` and `not_fully_idle` to 0.

That column is **not used**. Sampled beside the hooks it lags them by up to a second in both directions — `IDLE` at a turn's first invocation and still `RUNNING` at its `Stop` — so ending a Turn on it would need ordering guards against its own lag, a watcher on a WAL database, and a private schema, to close one gesture. Under this product's rule for lower-level products (price a gap before closing it) the gap is declared instead: the Turn keeps `Working...` until the conversation's next Turn (whose boundary supersedes it), Desktop quitting (§4), or a right-click. It is also the first measurement of interruption on this engine; whether the CLI's `Ctrl-C` behaves the same is still open ([`antigravity-cli.md`](antigravity-cli.md) §4).

## 4. Presence and admission: the application's life

Desktop keeps no lock per conversation and runs every conversation in one long-lived server, so the CLI's kernel reading has nothing to find. What it does have is an application: **Desktop is open while `com.google.antigravity` is running** (`NSRunningApplication`, as Codex's presence is read), and **while it runs it vouches for every Desktop conversation this process has observed**, and for none once it has quit. `AntigravitySessions` unions that with the CLI's lock-holding conversations under one `.exactly` list, so each surface's departure retires only its own Turns, and the product is open while either surface is.

The ceiling: a conversation deleted in Desktop while its row is listed stays until the row's own exits, because the Desktop half of the list is "every observed Thread" rather than Desktop's own index. The pre-2.0 IDE used the same bundle identifier and data directory and is migrated away by Desktop's first-run wizard; an unmigrated one would be taken for Desktop, and was not measured.

## 5. Project: Desktop's own assignment

Desktop files every conversation under a named Project the user creates and renames (`~/.gemini/config/projects/<id>.json`, `name`), or under none — its sidebar's heading for those is **`Standalone`**, and the renderer spells "none" either as an empty id or as `outside-of-project`. Two Projects may share a folder. So a folder name may not stand in for one (L2), and `AntigravityDesktopProjects` reads the conversation's `project_id` out of `conversation_summaries.db` and the name out of that Project's file; an unreadable assignment is `Project unavailable`, never `Standalone`, and a reading that fails after one succeeded keeps the name the row had. A new conversation's row, `project_id` included, was in the database 34 ms after its first `PreInvocation` arrived.

**The defect the live run found.** The database is in WAL mode. Between Desktop's checkpoints neither `-wal` nor `-shm` exists, and a read-only SQLite connection cannot open a WAL database it would have to create them for: the first run logged `unable to open database file` and every Desktop row read `Project unavailable`. With no WAL on disk every committed row is in the main file, so that state is read with `immutable=1`, which asks for neither file and writes nothing. The same measurement showed the second half of the trap: while Desktop writes, new rows are in the WAL alone and the main file's modification time does not move, so the cached assignment is keyed on the main file *and* its WAL. Both are pinned by `aWALDatabaseIsReadBetweenCheckpointsAndWhileItIsBeingWritten`; macOS's own SQLite keeps an empty WAL after the last close, so that test removes it the way Desktop's engine does.

The CLI's rows keep the folder name: it has no Project object of its own (Desktop's placeholder for it, `CLI Project`, holds nothing).

## 6. Read state: Desktop's own view record

`annotations/<conversationId>.pbtxt` is a one-line text protobuf — `title:"…" last_user_view_time:{seconds:… nanos:…}`, with `marked_as_unread` when the user asks for it — and Desktop's sidebar draws its unread dot from it: unread when marked, or when the conversation changed after `last_user_view_time`. **When the renderer writes it**, read from 2.13.0's bundle and then watched on the file:

- moving from one conversation to another writes the one left, and the one entered if the window has focus — measured twice: leaving a finished conversation wrote a view time 23 s and 46 s past its Turn's end, the moment it was left;
- the window regaining focus writes the conversation on screen;
- starting a conversation writes it at submission.

It is **not** written while the user sits on a conversation whose Turn ends; that view is kept in renderer memory to draw the sidebar. `AntigravityReadEvidence` therefore retires a finished Desktop row when the record's view time is at or after the Turn's end and it is not marked unread, keeps a row whose record is missing or unreadable out of the gate (no re-check for a question with no answer), and hands CLI rows to `TerminalReadEvidence` unchanged. A Turn watched to its end in Desktop keeps its row until the user leaves that conversation, switches back to Desktop's window, or submits again.

## 7. Navigation: raise the application

The shell registers `antigravity://` and forwards every URL to the renderer, which acts on exactly one: host `teleport`, path `/ai_studio`. No supported route opens a conversation, so `AntigravityNavigator` raises Desktop and reports `raisedApplication` — the session itself was not reached — while CLI rows go to `ProcessHostNavigator` as before. Because a window regaining focus writes the on-screen conversation's view time (§6), a click that raises Desktop onto the row's conversation also reads it.

## 8. The live run

A Debug build of this tree, against the running Desktop, with a copy of the tree that printed each Antigravity snapshot to stderr (the screen was locked, so the panel could not be captured):

- `sleep 10` turn in the `notchline` Project: a row `notchline · <prompt> · running` **0.1 s** after the prompt was sent; its line became *"I am about to run the `sleep 10` command in the terminal."*, then *"I have launched the `sleep 10` command and will wait for it to finish."*; then `completed · finished`.
- The first build's rows read `Project unavailable` — §5's defect — and the fixed build's read `notchline` from the Project file.
- The finished row stood while its conversation stayed on screen; after switching Desktop to another conversation (view time written past the Turn's end) the next refresh listed no rows. A turn in that other conversation then drew its own row through to `completed · ok`.
- Read re-checks were not booked while the screen was locked, as designed; the retirement landed on the next refresh an event caused. Navigation could not be exercised with the screen locked and is held by `aDesktopRowRaisesDesktopAndACLIRowGoesToItsTerminal`. **No Release CPU figures were taken** for the new readers; per refresh they add one main-actor look at the running-application list and a `stat` per Desktop row, with SQLite and JSON reads only when those files have changed.

## 9. Not done, and not claimed

- **Approval and input waits.** Desktop ran every command in these turns without asking. A probe that would have made it ask (a write outside the workspace) was not run, so what Desktop shows for a wait and what it writes down about one are unmeasured. Its summaries carry `waitingSteps` (the renderer raises notifications from them), which is where L4 evidence would be looked for; the hooks alone still observe none.
- **Cancellation**, §3.
- **Desktop's generated title.** `annotations` and the summaries carry it (`Request To Say Hi`, 0.3 s after the first `Stop`); rows keep the prompt on both surfaces, which the contract allows and declares.
- **Quota.** The server exposes `RetrieveUserQuotaSummary` on a localhost port behind a CSRF token, and Desktop passes that token on the server's command line. Reading another process's arguments for a credential, or calling Google's quota endpoint with the user's OAuth token, is a decision for the user rather than an implementation detail, and nothing here does either.
- **Antigravity IDE** remains a sibling product, declined by its transcript directory.

## 10. NO-GO check

No Turn state is inferred from silence or from Desktop's `status` column; the Desktop half of admission retires a Turn only on the application having quit; no historical event is replayed; read evidence retires only a finished Turn and only on a record written after its end; nothing is written to any of Desktop's files; the DevTools port was a measurement tool and nothing in the product uses it. The non-public dependencies are registered in [`non-public-codex-integration-features.md`](../../non-public-codex-integration-features.md).
