# Notchline — Terminology

Notchline summarises, with minimal interruption, the Turns a user still needs to attend to, and offers a way back into the originating Thread. The monitored products are Codex Desktop, Claude Code and Antigravity (Desktop and CLI).

Words are settled here. Any naming disagreement in code, docs or commit messages is resolved against this file, and each *Avoid* list is banned wording, not merely discouraged wording.

## Products and adapters

**Product** — A monitored agent product; today Codex, Claude Code and Antigravity, the last at L3 with declared mode limits ([`docs/product-support.md`](docs/product-support.md) §5). A product is user-visible: row attribution and the footer's quota rules are per product. **A hue is not** — no product owns a colour anywhere in this app, and a product is named by a badge in the user's own theme ink ([`docs/colour-v2.md`](docs/colour-v2.md)). *Matrix hue* was on this list until that decision and is banned wording now, along with *product colour* and *product ink*.
*Avoid:* backend, data source, integration, agent.

**Provider** — The in-app adapter that translates one product's boundary signals into an `AgentSnapshot`, one per product. An implementation concept that never appears in user-visible copy. It can be a composition of `ProductMonitoringRuntime` with a lifecycle source and the product's **sources** handed in. A lifecycle source supplies typed live evidence to the single `MonitoringRepository`; Hooks decode and project that evidence in their own boundary, and `HookProductProvider` composes that source. Optional source ownership and scheduling are composed by the runtime; supplementary sources return restricted evidence values rather than receiving the reducer. Setup is explicit and independent of observation availability: a product with no setup has no configuration switch. The other sources are its session reading, its non-hook Turn evidence, its row content, its read evidence, its quota — each supplying evidence and none deciding across the others. Codex's Provider is its own, because its App Server is a second lifecycle beside its hooks.
*Avoid:* service, client, monitor.

**Support level** — The highest cumulative capability contract a product meets within its declared modes and request forms: L1 Lifecycle monitoring, L2 Context identification, L3 Progress monitoring, L4 Wait detection, L5 Request reading, L6 Request answering ([`docs/product-support.md`](docs/product-support.md)). It is derived from coverage, not a product rank or runtime status.
*Avoid:* Tier 0/1/2, Listed/Attended/Answerable as product tiers, full support.

**Capability** — A specific supported behaviour with a declared source, scope and conditions; read removal, navigation, quota and usage, final answers, subagents, recovery and terminal reasons are independent of support level. Coverage is supported, conditional, unsupported or unverified (not applicable only when the product has no such concept); runtime unavailability is a separate fact.

**Read removal** — The retirement of an ended Turn's monitoring row on read evidence attributable to its Thread. It does not archive or delete the Thread in its product.
*Avoid:* automatic archiving, read means archived.

## Threads and Turns

**Thread** — A long-lived conversation container that may hold many Turns.
*Avoid:* task, session, single request.

**Turn** — One processing cycle inside a Thread, opened by a user submission and closed by success, failure or cancellation.
*Avoid:* thread, task, run.

**Navigable root Thread** — A Thread that belongs to no other Thread and can be opened in its product under the same identity. **The product answers this itself, and only "yes" counts**: the product hands over the Thread and it passes the check. Never asking, or an answer of "no such thread", is not a yes ([ADR 0017](docs/adr/0017-a-row-requires-a-thread-the-app-server-vouches-for.md)).
*Avoid:* related thread, all local threads, subagent thread.

**Side chat** — A temporary branch opened inside a Thread, listed only in its parent's UI and gone when the app closes. **Each product has one; they differ in shape and reach the same conclusion — neither can become a row here.** Codex's is an ephemeral thread: it has its own thread id and fires Turn hooks as usual, but is never persisted, never listed, refused by `thread/read`, and has no deep link; its link to the parent exists only in Desktop's process memory. So it is not a navigable root Thread and cannot be filed under its parent (ADR 0017). Claude Code's is a read-only fork opened by Claude Desktop (`settingSources: []`, `persistSession: false`) that never reaches this app's observation surface at all — no hooks, absent from `claude agents --json`, no transcript. **That one is not stopped by a rule; it simply never speaks**, so no check is needed and none is written.
*Avoid:* sub-thread, temporary thread, subagent.

**Live monitored Thread** — A navigable root Thread holding a Turn still inside the monitoring lifecycle. It is one row of the expanded list.
*Avoid:* recent thread, historical thread, every unarchived thread.

**Monitoring lifecycle** — Starts at a user submission. Active Turns always continue unless the user dismisses the row; a terminal Turn ends once that product's desktop app records it as read, archived, deleted, or no longer navigable. A Claude Code Thread hosted in a terminal answers "read" from its own terminal (see *Unread terminal state*). A terminal Turn whose read state **cannot be asked about** — no desktop record and no controlling terminal — ends only at the Thread's next submission, when the Thread disappears, or on manual dismissal. **Manual dismissal** is a right-click on the row; it applies to a Turn in **any** state, ends only that one Turn's row, deletes no Thread, stops no Turn, and claims nothing about the user having read it. It was once terminal-only, on the argument that a running Turn has nothing to dismiss yet — which left a row no gesture could remove whenever a Turn was stuck open, and made quitting the app the only exit.
*Avoid:* execution lifecycle, fixed retention, last N.

## Snapshots and events

**Current state snapshot** — The complete observation formed at launch, reconnect or correction, from the current activity projection together with unread terminal state. It decides the current Thread list and their statuses.
*Avoid:* historical event replay, cached old list, last event seen.

**Current activity projection** — Updated continuously at Turn start, wait and end boundaries; it holds only the exact Thread and Turn identities active right now. Terminal and historical objects are not members.
*Avoid:* historical event, stale Running cache, recent-activity list.

**Live lifecycle event** — A lifecycle change occurring during this monitoring run, able to update the current state snapshot incrementally.
*Avoid:* history log, persisted state, full snapshot.

**Historical lifecycle event** — A one-off record of a lifecycle change from before this run. The record proves only that a hook configuration once executed; it cannot prove any Thread exists now or is in any state.
*Avoid:* state awaiting recovery, launch snapshot, historical Stop state.

**Unread terminal state** — The Turn has reached a terminal state but its Thread has not been looked at. **Evidence is sourced per product**, and a product that supplies none keeps a finished row until its Thread's next submission, the Thread going away, or a right-click. Codex uses Desktop's unread set (the blue dot). Claude Code uses any one of five paths, which are one sentence in five shapes — *while the answer was in front of the user, the user did something only a person does*:

1. Claude Desktop's record of when it last put that Thread on screen is later than the Turn's end (archiving included);
2. after the Turn ended, Claude Desktop returned to the foreground and that Thread was the last one it displayed;
3. Claude Desktop holds the foreground now, the screen is awake and unlocked, and that Thread is what is on it;
4. the Thread once sat on Claude Desktop's screen carrying a finished Turn, and Desktop has since put a different Thread there;
5. **for a Thread hosted in a terminal, without asking Claude Code:** the Thread's **controlling terminal's access time** is later than the Turn's end. Typing, that surface taking the foreground and that surface losing it all make the kernel stamp it, while a surface that is not on screen receives no byte.

Path 3 **asks nothing of the user**, which makes it the only path that can retire a row nobody read: at the moment a Turn ends, the person watching and the person who submitted and walked away are identical on every signal, so the product stops telling them apart and asks instead whether the answer is sitting on a screen someone may be looking at — accepting that whoever walked away loses the notification. Path 5 holds per Thread rather than per app, so that half needs no equivalent of path 3 and has none.

**The five are peers; any one of them means read.** A Thread with remote control on sits in front of both a terminal and Claude Desktop, read by a different gesture on each side, so demoting path 5 to a fallback behind the others would leave a row read in the terminal on the notch forever. **Only a Thread with neither a desktop record nor a controlling terminal** (`-p` with output piped away) is unanswerable: its terminal state is neither read nor unread, and such a row never leaves on read ([ADR 0012](docs/adr/0012-read-state-is-answered-per-product-or-not-at-all.md)).
**Antigravity's CLI conversations use path 5 and nothing else**, since the CLI has no desktop application to keep a record: the conversation's process is the one holding its presence lock, and its controlling terminal answers for it. The gesture is narrower than Claude Code's because the product asks its terminal for less — measured 2026-09-12, its TUI enables neither focus reporting nor mouse reporting, so a keystroke or a paste is the whole of what stamps the access time, a returning glance stamps nothing, and the pointer cannot stamp it at all. **Antigravity Desktop's conversations use the product's own record instead** — the view time Desktop writes per conversation when the user leaves it, refocuses its window on it or starts one — with Desktop's own rule: read once viewed after the Turn ended and not marked unread ([`antigravity-desktop.md`](docs/technical-explorations/multi-product-provider-architecture/antigravity-desktop.md) §6).

*Avoid:* recently completed, brief terminal state, notch unread.

## Status

**Thread status** — The product status of a live monitored Thread's current Turn. Four values only: Approval needed, Input needed, Running, Completed — which is also the summary and sort priority order ([`docs/PRD.md`](docs/PRD.md) §6.2). A missing, timed-out or unknown signal creates no fifth status; the last trustworthy value is held. The four are one vocabulary shared by both products: a status one product can observe and the other cannot would make that vocabulary lie on the other (see *Terminal reason*).

**Running is the one value whose name and whose drawn word differ: every surface says `Working...`.** The term stays Running here, in the code (`MonitorStatus.running`, `SessionStatus.running`) and in every document reasoning about the state machine, because that is what the state *is* and renaming the case would rename the four transitions with it. What changed is the word on the surface, and only because the other three names say what is happening to the person reading them while this one said what the machine was doing. The ellipsis is the part that carries its weight: it is the only mark in the drawn vocabulary that says "and it has not finished", which is exactly what separates this state from Completed. So a sentence about the state machine says Running and a sentence about what the user sees says `Working...`, and neither is loose usage.
*Avoid:* integration status, Idle, Disconnected, Unknown, Error, Cancelled; `Working...` as the name of the state, Running as the word on a surface.

**Derived status** — The answer to "what is going on with this Thread now", computed from Thread status plus accompanying data. It is not a fifth status: Thread status answers for **this one Turn**, derived status answers for **this Thread**. They diverge in three places, all caused by subagents, and **both products reach them** (Codex forks with `spawn_agent`; Claude Code's `Agent` tool call returns the moment the subagent starts, so a Turn on either side can reach `Stop` while work it forked is still running):

- **Still working** — the Turn is Completed while a subagent runs on. Thread status is Completed (the Turn did end); derived status is Running (the Thread is indeed still working).
- **Someone was asked** — a subagent is stopped at an approval dialogue. Derived status is Approval needed, which beats the case above but does not beat the Turn's own Input needed. **That last clause is an exception to the priority table, not an application of it**: the table ranks which of two rows matters more (Approval first), whereas here two readings of the same row compete, and since neither product emits an event when an approval is declined, the question that arrived later is the one still standing. This holds whether or not the Turn is terminal — the dialogue may open before or after the main agent finishes.
- **Stopped, waiting on its own work** — the Turn is Completed, subagents have wrapped up, and that Turn's `Stop` meant "paused" rather than "finished". Derived status stays Running until the Thread's next terminal state says nothing is in flight. **Only Claude Code reaches this**, because only it can say so: its `Stop` carries `background_tasks`, documented precisely so a hook can tell "the session ended" from "the session is paused, waiting for background work to wake it", and the measured gap before the parent Turn wakes is only 50–130 ms. Without this case, the row would write Completed and then write Running back inside that 50 ms — a state the Thread never occupied.

Only the rules already asking that second question read it: summary status, product markers, list sorting, and the terminal-unread membership gate. **What a row draws never reads it** — a row reports its one Turn. The single exception is the **brightness** of the trailing cell, which does not change what the row draws and only says whether this Thread is waiting on a person.
*Avoid:* fifth status, Thread status, unqualified "Running".

**Terminal reason** — Why a Turn reached Completed: it finished normally, or it failed with a failure type. This is accompanying data, not a fifth status — Claude Code's `StopFailure` can report failure and Codex's hooks report none at all, so making it a status would make Codex rows look as though they never fail. The row's marker is unchanged; the reason is shown as text, subject to the preview switch.
*Avoid:* Failed status, fifth status, Error.

## Connectivity

**Presence** — Whether a product is open right now, independent of whether this app can observe it. Sourced per product: Codex by whether the app is running, Claude Code by whether the active-session list is non-empty — with no app to ask, the session list is the presence signal — and Antigravity by whether Antigravity Desktop is running or an `agy` process holds a conversation's presence lock open, read off the kernel. **Presence answers only "is it open", never "what is it doing"**: presence draws the matrix and the Turn reducer lights it, and the two must not be recombined. It has three values — open, not open, and unknown; unknown is what it takes when the only source of an answer has been failing past the trustworthy limit, and like "not open" it does not amount to Connected.
*Avoid:* availability, connection state, whether any thread is running.

**Connected** — A product that is both **open** and **observable**. These are independent facts and may contradict each other — open but with hooks unregistered is an ordinary first run — so only both together count as Connected.
*Avoid:* open, integration available, Ready.

**Integration availability** — Whether the live observation and navigation contract between this app and one product holds. Established per product.
*Avoid:* thread status, quota status, global availability.

**Summary status** — The single status shown at the top, merged from all live monitored Threads across products. With Threads present in any product, it takes the value by Thread priority; with no Threads anywhere, the collapsed state has just two values — `Connected` if any product is connected, `Disconnected` if none is. Integration availability no longer speaks in the collapsed state; it explains itself in the expanded panel and in settings.
*Avoid:* global thread, connection state, Idle.

**Disconnected** — As a **summary status** it means "no coding agent is connected", not "no coding agent is open" — something open but out of reach is genuinely disconnected. As a fact about **one product** it means that product's live monitoring integration is no longer reliable and so cannot produce its Thread set trustworthily; its rows then disappear, indistinguishable from "that product has no Threads", because for the user the conclusion is the same. Losing observation is a transition, not a state: the rows drain first and only then does the whole fall to `Disconnected`. ~~Each matrix falls to its own extinguished colour first, keeping its hue, so it stays visible which product went dark.~~ Void twice over: there has been **one** aggregate mark for every product at once since [`docs/compact-view-v2.md`](docs/compact-view-v2.md) §2, and it has no product hue to keep since [`docs/colour-v2.md`](docs/colour-v2.md). One product going dark is now visible in its rows leaving and in nothing else.
*Avoid:* single-thread unknown, quota unavailable, preview unavailable, global disconnect, no agent open.

## Content

**Project** — The grouping a Thread belongs to, resolved per product. In Codex it is the Thread grouping the user creates and manages in Codex Desktop, which may span one or more repositories; **a Codex Thread's Project must never be inferred from `cwd`, the Git root or a path name**, as those do not map one-to-one onto a user-managed Desktop Project ([ADR 0003](docs/adr/0003-use-codex-desktop-project-identity.md)). In Antigravity Desktop it is the Project Desktop files the conversation under, read from Desktop's own records and never from the folder, or `Standalone` when it is filed under none; in Antigravity CLI, which has no Project object, it is the workspace path the product supplies, with an explicit missing-name fallback when absent. In Claude Code it is simply the Thread's working directory (`cwd`): the hook payload states it directly and transcripts are filed by it, so it is a grouping that genuinely exists in that product rather than an approximation read off a path ([ADR 0009](docs/adr/0009-resolve-project-per-product.md)).
*Avoid:* repository, workspace, mock grouping.

**Chats** — The set of Codex Desktop Threads belonging to no Project.
*Avoid:* default Project, unknown Project.

**Thread title** — The name displayed for a Thread, sourced from that product's title metadata or its explicitly permitted prompt-derived fallback. A missing title follows the product's declared fallback rule; a folder name is not a Thread title ([`docs/product-support.md`](docs/product-support.md) §5).
*Avoid:* folder name, repository name, mock title.

**Processing time** — Wall-clock elapsed time matching what Codex Desktop shows for the current Turn, including time spent waiting on a person and time the device spent asleep.
*Avoid:* model compute time, active execution time, thread age.

**Current content preview** — A short fragment of the prompt, progress, error or final answer the product has already shown the user. Raw reasoning and tool detail are not in it because this channel never fetched them, not because they are forbidden ([`docs/PRD.md`](docs/PRD.md) §7).
*Avoid:* agent thinking, raw reasoning, full body.

**Primary quota window** — The rate-limit window the current Codex Desktop account marks as primary, expressed by the single quota ring.
*Avoid:* token balance, total quota, tightest window.

## Asking and answering

**Request** — What one agent is asking a person, in the product's own words: a command to grant, a document to accept, a question with options, or a question with none ([`docs/answer-in-notch.md`](docs/answer-in-notch.md) §2.1). It is a thing the *product* composed and this app only draws — the app never annotates it, never marks a command as dangerous, and never summarises it.
*Avoid:* prompt, dialog, permission, approval payload.

**Answer** — What the person gave back: a grant, a refusal carrying what to do instead, or the answers to a question set. It travels on the hook connection the request arrived on and is written in that product's own schema ([ADR 0019](docs/adr/0019-the-helper-answers-on-the-stream-adr-0013-silenced.md)).
*Avoid:* decision, response, permission grant, approval.

**Answerable** — Said of one request, and true exactly when a connection is being held open for it. Not a property of a product, a status or a form: a request whose connection has closed is read, and the row says so.
*Avoid:* actionable, interactive, live.
