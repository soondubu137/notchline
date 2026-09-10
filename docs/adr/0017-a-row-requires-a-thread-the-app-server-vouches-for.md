# A row requires a Thread the App Server vouches for

A Hook Turn becomes a row only once the App Server hands over its Thread and that Thread passes the navigable-root-Thread check. "Not asked yet" and "asked, and there is no such thread" are different facts, but for drawing a row they have one answer: **no row**. This is the fail-closed form of [ADR 0001](0001-monitor-desktop-navigable-root-threads.md), whose check could only reject a Thread it had actually **received**, and defaulted to admitting whatever it could not.

## What triggered it: Codex side chats

A Codex Desktop side chat is a temporary branch inside a Thread, opened in a right-hand tab, listed only as "Side chats" under the parent's summary panel and never in the sidebar. Desktop's own copy is explicit: temporary, gone when the app closes, deleted irrecoverably on close, and expiring. It is forked from the parent with `ephemeral: true` and `sideConversation: true`, and the injected developer instructions open with "You are in a side conversation, not the main thread" — no main-line work, no subagents, no unrequested changes to the workspace.

Measured 2026-08-25 (Desktop's built-in CLI `0.149.0-alpha.4.3`):

- it has its own thread id and fires Turn hooks as usual — which is how it used to draw a row;
- it is **never persisted**: no rollout in `~/.codex/sessions`, no row in `state_5.sqlite`, nothing in `.codex-global-state.json` (`thread-tab-routes-v1:` persists other tab kinds);
- a standalone App Server **cannot reach it**: `thread/list` omits it and `thread/read` answers `-32600 "thread not loaded"`. Desktop's own app-server is started over stdio (`~/.codex/ipc/ipc.sock` belongs to the Electron main process, not the app-server), so the in-memory `forkedFromId` / `sessionId` parentage is readable through no external interface;
- **no deep link can open it**: the whole bundle only ever constructs `codex://threads/<id>`.

So it can neither stand as its own row (no Project, no title, nowhere to go on click) nor be folded into its parent's row (the parent cannot be asked for).

## What the row looked like before the fix

Hook arrives → a *Project unavailable* row is drawn → about 10 seconds later membership reconciliation retires a Turn that never appeared in any list and the row vanishes → the side chat's last hook creates the Turn again and the row returns as Completed → clicking it yields "this thread is archived, deleted, or no longer available". Three symptoms, one root cause: the check could only reject what it could see.

The incidental cost sat in the same place: a Hook thread absent from the last list triggered another **fully paginated** membership reconciliation on every refresh — for a thread that would never appear in one.

## Costs

- **A row waits for one local `thread/read`.** It no longer appears on the same beat as the Hook. The wait is measured: by the time `UserPromptSubmit` fires, the rollout file and the state-database row are already written and a standalone App Server reads it immediately (2026-08-25, CLI `0.149.0-alpha.4.3`), so the normal path is one local round trip and does **not** wait for the expensive full list. Older Codex (no `thread/read`) degrades to waiting for a list.
- **The notch is silent while a side chat runs**, including when it wants input or approval. Accepted: it is open in the window the user is already looking at, it is read-only by design, and this app could not offer a way back to it regardless — which is half the reason a row exists.
- **The App Server moved from decoration to gate.** The old division had Hooks providing low latency and the App Server only decorating. Now a row needs its assent. The practical impact is smaller than it sounds: with the App Server unreachable no new row could be drawn anyway (that path holds the last trustworthy snapshot).

## The product answers first (2026-09-09)

Codex's hooks carry the answer this ADR paid a round trip for. Every one of CLI `0.153.4`'s twelve `*.command.input` schemas **requires** `transcript_path` and allows it to be null, and a thread Codex will not materialise carries the null on every event it fires (measured 2026-09-09 on Desktop `26.903.61454` / CLI `0.153.4`, with a live side chat and an isolated `thread/fork {ephemeral: true}` probe; a persisted thread carries its rollout path). The protocol schema says why: `Thread.ephemeral` is "should not be materialized on disk", and a thread Codex is not writing down is one it will not hand over.

So the reducer records it (`HookTurnState.threadHasNoTranscript`) and the service asks nothing about such a thread: no `thread/read`, no `thread/items/list`, and no membership sweep requested to look for it. The three costs above are unchanged for every real thread, and none of them is paid here.

Three properties keep it honest:

- **It decides what is asked, never what is drawn.** A row still requires a Thread the App Server hands over. A thread nobody asked about has no Thread, so this reaches the row builder as the same absence a refusal did — this ADR's rule, unweakened.
- **Silence is not an answer.** The key not arriving means an older build, and leaves the thread on the ordinary path. Every test in the suite that predates this sends no `transcript_path` at all, and none of them changed.
- **The latest answer wins.** A path retracts a null. Nothing measured produces one on a thread that has already answered null; the rule is written that way so that an event Codex delivers under this thread's id but belonging to a nested agent — which names *that* agent's file — can do no worse than put the thread back on the path it was on before.

## No wording, no error codes

The rejection test is "`thread/read` returned a remote error", reading neither its text nor its code: whatever the reason, a thread the App Server will not hand over is a thread this app cannot navigate to. That also keeps Codex's error wording out of [`non-public-codex-integration-features.md`](../non-public-codex-integration-features.md). A transport failure (timeout, connection reset) is not an answer, is not recorded, and is asked again at the next refresh.

## Status

Implemented. Rejections are recorded, so they are not re-asked every refresh and no longer paginate all of history for a thread the product itself says does not exist; and since 2026-09-09 a thread whose hooks say `transcript_path: null` is not asked about at all. Tests: `aThreadTheAppServerRefusesDrawsNoRowAtAnyPointInItsTurn`, `aThreadTheProductWritesDownNowhereIsNeverAskedAbout`, `aThreadIsWrittenDownNowhereOnlyWhileTheProductSaysSo`, `aSessionThatStopsRenderingStopsSchedulingWakeUps`, `idleToRunningDoesNotWaitForSlowThreadList`.

Subagents are unaffected: Codex stamps subagent hooks with the **parent** Thread's identity, so they already land on the parent's row, and the parent is an ordinary Thread that can be handed over.
