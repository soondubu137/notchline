# Changelog

What each released version of Notchline contains, newest first.

Versions are `major.minor.patch` under [semantic versioning](https://semver.org), with a stage word while a version is not yet finished. The app draws both plus its build number — `Version 0.1.0 Alpha (1)` — on the first-run window and at the foot of Settings. The number in brackets is `CURRENT_PROJECT_VERSION` and rises with every build handed to anybody; it is what tells two people running the same `0.1.0` apart in a bug report. The stage word is deliberately not part of `MARKETING_VERSION`, which stays numeric-dotted so it remains a version macOS can validate and compare.

## Unreleased

### Changed

- **The Completed mark is the app's own logo.** The Terrace is drawn on this same 5×5 grid — a mass hanging from the top edge, columns `5 4 3 2 1` — so the crest frame is the mark itself, breathing once every `2.4 s` with its tall step held lit between crests. It replaces the bloom's cross. Fifteen lit cells against nine costs mean level, bought back in time at white. (`docs/figma-design.md` §4.1.)
- **One connected product is drawn like two.** A single product had a panel of its own: a flat list, a badge on each row, no heading and the panel's own top rule, all of it rebuilt the moment a second connected. There is one form now: one block per product at every count, its heading naming every row under it, the queue and an open row keeping their own badge. The panel is `316` where it was `300`. (`docs/expanded-panel-v2.md` §4.3.)

### Fixed

- **A read Codex thread leaves the notch again.** Codex Desktop `26.903.61454` moved its blue-dot set out of the renderer's atom map into a top-level `electron-thread-read-state-v1`, keyed by account identity above host, and deleted the key this app read. Every reading came back unreadable, and an unreadable reading may retire nothing — so a Completed Codex row stayed listed however thoroughly it had been read. Both shapes are read now. (`docs/adr/0002-use-desktop-unread-state-for-monitor-membership.md`.)

## 0.2.4 Alpha — 2026-09-09

**The app can say what it is, and a blank quota rule can say why it is blank.** A second control on the band opens the first region here that reports on this application rather than on the work passing through it — name, version, licence, repository. Underneath it, Claude Code's two rules had gone blank on a machine using Claude Code all day, and the app was right to draw them that way.

### Added

- **The panel can say what it is.** The band's trailing side takes a second control — the Notchline mark, left of the gear — and it replaces everything under the band with a fixed-height panel: the horizontal lockup, `Version 0.2.4 Alpha (8)`, the bundle's own copyright and licence notice, the repository's full address behind the GitHub mark, and a `Check for Updates` tile. Nothing running moves its height, collapsing does not close it, and only the mark does. No update mechanism is wired in, so that control is where one will land rather than a promise. (`docs/panel-v2.md`.)

### Changed

- **The quota figures come from Claude Code's own record rather than the sentence it prints.** The command still runs, on the same cadence, because the run is what makes the product fetch its usage — but the numbers are read from `cachedUsageUtilization` in `~/.claude.json`, as JSON. A shape change now fails as a decode instead of a percentage quietly going missing, the per-model window's model is a field rather than a label between brackets, and the hour those figures are trusted for is counted from the product's own timestamp.
- **Both seams draw one dot, in the label's own ink.** A `·` sits on its own x-height, `0.77` pt below the line the bar centres its contents on, so the `Recent` seam's hairline ran past its separator instead of through it. It is a drawn disc now, sized by what a retired row's own glyph rasterises to, since two sizes of one dot `36` points apart read as an accident. The block heading's disc — new in `0.2.3` at the hairline's `15%` white — gives that up for the caption's ink: one bar drawing two separators says the seams are two things. Neither count moves. (`docs/expanded-panel-v2.md` §2.2 and §4.2.)
- **A washed row's ground stands `2` off its own frame.** A heading takes all of its slack above the chip and none below, because the row beneath brings its own top padding — until a pointer arrives, that row's ground fills the whole `72`, and the two grounds meet along one edge. Two filled shapes sharing an edge read as a single shape with a notch cut out of it, which is neither of the things they say apart. The inset is on every row that draws a wash — live, open and retired — and no metric moves. (`docs/expanded-panel-v2.md` §4.2.)

### Fixed

- **Claude Code's quota rules had gone blank, and now say why when they cannot be drawn.** `claude -p "/usage"` prints the windows only when the CLI itself is signed in; a Claude Desktop-only machine has no CLI credential, so the same run answered with its session cost and every rule read `--` with nothing anywhere saying so. The footer's diagnostic now names `claude auth login`. (`docs/adr/0021-read-the-quota-from-the-record-the-command-leaves.md`.)
- **The pointing hand survives on the panel's own controls.** The `.cursorUpdate` area that makes the hand outrank the scroll view's arrow on a latched panel shared one tracking area with the background `.activeAlways` pair, and AppKit does not support that combination — so on an unlatched panel the hand was lost to whatever assigned an arrow next. They are two areas now: `.activeInKeyWindow` for the key window's cursor pass, `.activeAlways` for entry, exit and movement, with movement reasserting the hand rather than waiting for the pointer to leave and come back. Neither area polls or activates the app.

### Known limitations

Everything listed under `0.2.3` and earlier still stands, unchanged.

## 0.2.3 Alpha — 2026-09-08

**Two Codex rows that told the wrong story, and a panel carrying less air.** No new capability: what changed is what a Codex row says while a question is open or a reviewer is running, and how much room the expanded panel and the collapsed bar spend saying it.

### Changed

- **The live list is grouped by product.** While both products are connected the list draws one block per product that has a row — Codex first, then Claude Code, the order the quota footer already keeps — and the rows under it give their chip up and carry the Project alone. VoiceOver keeps the product on every row. A heading is never paid for out of rows: the viewport's cap grows by each bar drawn. The Recent queue is deliberately not grouped, because a retired row's whole reading is an age and those ages run in one descent a heading would restart. (`docs/expanded-panel-v2.md` §4.)
- **The panel opens on the first product's line, and its rows are less airy.** With a product block leading the list, the hairline under the band and the block's own rule were the same `1` pt of white at `15%`, `24` apart, saying nothing to each other; the block's — the one carrying a name — takes the job and very nearly the position. A live row keeps `8.5` above and below its three lines where it kept `12.5`, so the panel is `300` at every connected form where it was `324`, still three live rows and five retired ones before it scrolls. (`docs/expanded-panel-v2.md` §2.1 and §4.2.)
- **A block's heading draws a dot before its count instead of setting one.** `Codex · 3` put its separator in the caption's own ink — a third piece of text on a line already carrying a chip and a figure. It is a `3` pt disc at the hairline's `15%` white now, standing in the middle of the gap the glyph held, so the count has not moved. The Recent seam keeps its glyph: a word and a figure on one line is what that idiom is for. (`docs/expanded-panel-v2.md` §4.2.)
- **A finished turn is a dot in front of its timer, not a grey slab behind it.** The notch and the panel were saying one thing two ways. The tile is gone from both, the digits stop where they stopped, and the dot stands in front of them at `#C7C7CC` — breathing on the notch, still on a row, where a pulse per row would be the list moving under somebody reading it. Two consequences: the trailing wing opens by the mark's own `4 + 8` when a turn ends, and a running row's digits now end on the same column as a finished row's. (`docs/compact-view-v2.md` §4.2 and §4.3.)

### Fixed

- **A Codex question no longer disappears under the sentence after it.** Reported from a second machine: Codex Desktop held a question while the row beside it said `Working...`, with nothing to say anybody had been asked anything. The tool is `request_user_input_async`, which answers the model in 51 ms and lets the Turn carry on, so the question was overwritten within seconds. Its words are now kept for the rest of that Turn and drawn as the row's preview. The row deliberately still says `Working...`: an answer arrives as a *new* Turn, and a skip or an auto-resolution reaches this app as nothing at all, so a wait opened here could never be honestly withdrawn. (`docs/PRD.md` §7, `docs/tech-design.md` §9.2, `docs/system-architecture.md` §3.)
- **A finished Codex row is no longer taken over by the automatic reviewer.** Reported on a second machine running `0.2.2`: a turn ended and its row re-timed from `0:00`, showed the `Approve for me` reviewer's first prompt, and said `Running` for ever. A reviewer prompt arriving after the parent's own `Stop` was adopted as the thread's next turn, and nothing ever ends a reviewer's turn under the parent's id. A finished thread now holds such a prompt on the same terms as an open one, and the thread's rollout — which names the user's turns and never a reviewer's — promotes the real next turn. Claude Code is unchanged. (`docs/tech-design.md` §9.2.)

### Known limitations

Everything listed under `0.2.2` and earlier still stands, unchanged.

## 0.2.2 Alpha — 2026-09-07

**The licence travels with the app.** `0.2.1` put the source under the GPL and said so in the README, which is everything somebody who takes a clone needs. It said nothing to somebody handed the built app: the bundle carried neither a copyright line nor a copy of the terms, and both are asked for wherever the program itself is conveyed.

### Added

- **The bundle carries its copyright notice.** `NSHumanReadableCopyright` was empty in every configuration, so Finder's Get Info and the standard About panel had nothing to draw under the name. It now reads `Copyright © 2026 Yinfeng Lu. Licensed under GPL-3.0-or-later, without warranty.` — the same sentence the README's licence section uses, so the app and the repository say one thing.
- **`LICENSE` ships inside the app.** The FSF's verbatim text is copied to `Notchline.app/Contents/Resources/LICENSE`, the first entry the app target's resources phase has ever carried. A downloaded `.app` now holds the terms it is offered under instead of pointing at a repository the person holding it may never open.

### Changed

- **The README's licence section is a single notice.** It named the licence and then spent a sentence spelling out in its own words what that buys; the terms themselves say it, and saying it twice invites the two to drift apart. What is left is the holder, the licence, the absence of warranty and a link to the full text. The heading is `Licence` again, matching the badge above it and the spelling the rest of the documentation uses.

### Known limitations

Everything listed under `0.2.1` and earlier still stands, unchanged.

## 0.2.1 Alpha — 2026-09-07

**A licence, and a README that opens on the notch.** No behaviour changed; what changed is what somebody is allowed to do with the source, and what they see before they read a word of it.

### Added

- **Notchline is under the GNU General Public License v3.0 or later.** The repository carried no licence at all until now, which is the most restrictive state there is — default copyright, no permission granted to anybody for anything. `LICENSE` is the FSF's verbatim text, and the README says in its own words what it buys: the source may be used, studied, shared and modified, and a distributed build carries the same freedoms onward to whoever receives it. The choice of a copyleft licence over a permissive one is deliberate, and it is the one the closest comparable app ([Open Island](docs/comparisons/notchline-and-open-island.md)) already uses; the source-licence row in that comparison now reads `GPL v3 or later` on both sides.
- **The README opens on a recording of the notch.** The two figures under it say what the surface is made of and what a request looks like open, and neither can say *where any of it sits* — which is the first question a notch app has to answer. The hero is the screen recording at its full frame ratio for that reason: the top strip of a display, the compact bar above a code editor, a Claude Code question opening the panel, two answers picked and sent, and the panel collapsing back. Animated WebP, 323 frames, about a megabyte; how to rebuild it is in [`design/README.md`](design/README.md).

### Changed

- **The two plates in the answering figure hang from a shared top edge.** They were centred against each other, which slid each one half the height difference off that line and read as two panels at two heights. Both are a panel opened at the top of the screen, so the top edge is the one they actually share, and the shorter plate's difference falls under it as page.

### Fixed

- **The README's header lockup shows its `alt` text again.** An unterminated `width` attribute had been swallowing it.

### Known limitations

Everything listed under `0.2.0` and earlier still stands, unchanged.

## 0.2.0 Alpha — 2026-09-07

**An answer can now leave this app.** Until this version everything Notchline did was read-only: a request reached the notch, was named there, and was answered in the product that asked. It is now read *and* answered on the surface it arrives on, in every shape either product asks in — and the surface underneath it was redrawn around that. One hue, and it belongs to the user rather than to a product. A collapsed bar that reports on the work instead of on what is installed. A footer with no gauge. A list that keeps what it let go of for five hours. This is the minor version rather than a patch because the app's own standing sentence changed with it: it used to say Notchline only reads.

### Added

- **A request is answered in the notch, on either product.** Click the mark on a waiting row and the row opens onto the request itself: the command verbatim on the recessed ground machine text is drawn on, a plan set as prose, or a question's own options — never a paraphrase, because every word a person's answer will be recorded under is the product's own. An approval is granted, or refused with a reason typed into the row. A Claude Code question set is answered one question at a time and sent as a single `updatedInput`, with `multiSelect` ticking boxes, your own words replacing a selection, and the position in the set drawn because 63% of questions arrive in a call carrying more than one. The eleven steps between the bar knocking and the work resuming become eight, and three of the four removed belonged to another application — the screen surrendered, the dialogue found, the journey back. Designed in [`answer-in-notch.md`](docs/answer-in-notch.md), and verified against the real products rather than a stub: Claude Code `2.1.263` ran the `Bash` call this panel approved, and Codex `0.153.4` recorded its `permission-request` handler running for the 28,285 ms the decision took, having never asked its own client at all.
- **The answer travels back up the connection the request arrived on.** No port, no second channel, no compiled helper: the hook that announced the request holds its socket open and this app writes that product's own hook-output JSON onto its stdout. One registered event per product carries it — `PermissionRequest`, and nothing else, so the 99.8% of events where nobody is being asked keep the stricter silence [ADR 0013](docs/adr/0013-claude-code-hooks-run-a-helper-not-a-port.md) gave them, by construction rather than by remembering. The window a hook may be held for is registered with the definition: an hour on Codex, a day on Claude Code, each inside the timeout its own definition declares. [ADR 0019](docs/adr/0019-the-helper-answers-on-the-stream-adr-0013-silenced.md).
- **The panel takes the keyboard, and gives the application back.** A field is no use to a panel the keyboard does not reach, and `.nonactivatingPanel` turned out not to deliver one: the panel *was* the key window, with the caret in the field, while every keystroke went to whatever was in front. Latching now activates this app for the open row's lifetime and hands the previous application back on `⎋`, on a click outside, and when the row closes. [ADR 0020](docs/adr/0020-the-panel-takes-the-keyboard-by-activating.md). The keys are the field's while the caret is in it — anything printable, `⇧⏎`, `⏎`, `⎋` — and the panel's when it is not: `1`–`4` take a numbered option without submitting it, `←` and `→` walk a question set. The field no longer takes the caret unasked, which is what makes that a rule about focus rather than about what the field happens to be holding.
- **Recent.** A row that finishes and leaves the live list is kept for five hours under a seam in the list's own scroller, with a live count on the seam saying how many are down there. It is the number of rows the viewport *draws* before it scrolls, not the number the store holds, so a twelve-deep queue is drawn exactly like a five-deep one. The cost ends by itself: five quiet hours take the seam away and return the panel to its floor, which is the only region on this surface that disappears with nobody touching it.
- **First run has a third page, and the two controls are open on it.** Page two is what the notch draws; page three is what it does — a permission request open beside the row page two draws shut, a question with options open beside it, and the Recent queue. The two answer rows are not one shape and the page shows both: a permission has something to refuse and draws a field, `Deny` and `Approve`; a question has no refusal at all, because the text *is* the answer, so the field takes the space and one `Send` stands where two would.
- **A mark colour, and a name for the pill's middle.** Twelve near-neutrals, ordered farthest-from-both-products first. Handing the choice over is only safe because of what the palette is — the greyscale, rotated — so every entry shares one lit lightness and one unlit one, and a choice cannot change how bright the mark asking for a person is.

### Changed

- **No product owns a colour anywhere in this app.** There is one hue, the user picks it, and a product is named by a badge instead of by an ink. `codexInk` and `claudeCodeInk` retire, and with them the split marks, the diagonal cut and the per-agent decomposition the expanded band was built around: the band folds to one mark and two totals. What a colour was being asked to say — which product — was never the thing the surface is for, and it was saying it at every size including the one where it cannot be read. [`colour-v2.md`](docs/colour-v2.md).
- **The collapsed surface reports on the work, not on what is installed.** V1 spent a matrix, a session-dot column and a subagent badge on every product and grew about 49 pt for each one, on a surface whose container does not grow at all. There is now one matrix drawing the most urgent status any product holds, and two numerals beside it: every row on the list, over every subagent in flight. The notched bar is `304` at one product or five; the pill is `230` connected and `41` disconnected.
- **The four marks are redrawn, and `Running` turns instead of falling.** The rain is out — its column gaps were the whole of what made it fall, and they cost the state more light than it could spare. `Running` is the outer sixteen cells turning clockwise against the inner eight turning anticlockwise, one lap each, about a centre that holds still: two gears meshing, plainly driven and plainly going nowhere, which is the pair that state has to say at once. `Input needed` and `Completed` were redrawn twice more against how a peak is arrived at rather than only against lit area.
- **The expanded panel is `610` wide, and its two sections scroll apart.** The live list and the Recent queue had shared one scroller and one cap; each now folds and scrolls in its own viewport, behind a thin rail that is drawn only while its own section can actually move — the same rail the request body already had. The Recent seam and the footer's spend line — the same control drawn twice, which had agreed on nothing — are one control now: both `32` pt, both centred, both drawing their rule only while their own section is open. A row is traced at its edge rather than washed, every control is cut from one ink at six weights, and the pointer becomes a hand on a row that can be opened.
- **The quota footer has no gauge and no critical threshold.** One number at rest; a two-level table behind the control, grouped by product, in the order the product itself reports rather than any order this app prefers; each window named in its product's own words. A figure this app cannot read draws `--` in its own place and is marked in no other way. [`quota-footer-v2.md`](docs/quota-footer-v2.md).
- **The README is a product overview**, with the file inventory, the tiered-support plan for further products, and a source-level comparison against [Open Island](docs/comparisons/notchline-and-open-island.md) rather than a tour of the internals.

### Fixed

- **A Mac with Claude Desktop and no terminal `claude` is now watched.** Reported from a first install on a second machine: both integrations enabled, both switches blue, both cards reading connected, `~/.claude/settings.json` holding this build's hooks — and no mark, no row, and nothing from starting a turn, while Codex worked at that same moment. Installing the command is a separate item in Desktop's install hub, and the locator looked only where a person would have put it, so `locate()` returned nothing, presence never left `unknown`, and every hook event that did arrive died at the row gate for naming a session no list vouched for. Desktop's own copy of the CLI is now the last candidate. Nothing was wrong with what the user did.
- **A Codex question reaches the row as a question.** Codex ships two question tools and the model picks between them, so one user meets both. The blocking one sends the same `questions` shape `AskUserQuestion` does, while the reading looked for a top-level `question` or `prompt` — so every real Codex question fell through to the call's arguments and was drawn as a command on the ground reserved for machine text. Its async twin, which asks without stopping and returns `{"accepted":true}` in about 50 ms whatever the person does, is now an explicit case that announces no wait: adding it beside the blocking name would have drawn `Input needed` for 51 ms and taken it away again.
- **An open row closes when its Thread leaves the list**, instead of holding a request nobody can answer any more.
- **The wheel reaches a long request.** The catcher was drawn behind the body, and AppKit sends a wheel event to whatever wins the hit test, so behind hit-testable lines it never won one and the list scrolled instead. It is drawn over the body now, claiming the wheel and declining every other event.
- **Smaller drawing corrections**: a hidden wing no longer draws a timer out through the cut-out's edge, the pill's middle sits on its own baseline rather than half a slot below it, and a preference is no longer greyed out because the screen it is being set on cannot honour it.

### Performance

Measured on Release with `proc_pid_rusage` diffed either side of each act, and each change verified pixel-identical against the panel without it.

- **An open request stopped measuring its own text on every read.** `openRowBody` was a computed property running the whole body's layout on each of the panel's many reads — 48 full layouts to open a row, 26 for one option click, 22 for the first keystroke and one for every keystroke after. Opening an approval fell from `0.64` s of CPU to `0.16`, an option click from `0.29` to `0.03`, a keystroke from `0.27` to `0.006`. The line-breaking measurement behind it now brackets the overflow in log *n* steps instead of measuring every prefix, cutting one body's layout from `14.1` ms to `2.8`.
- **A long request draws the lines near the viewport, not all of them.** The hook boundary accepts 128 KB and the viewport shows eight lines, so a plan can arrive as fifteen hundred wrapped lines with a `Text` built for each. Opening one fell from `0.80` s to `0.55`, 240 wheel events over it from `2.09` s to `0.51`, and 158 MB resident to 119. Bodies shorter than the drawn slab — every question and every ordinary command — are not windowed at all and did not move.

### Upgrading from `0.1.x`

**One hook definition changed on each product, and the app asks to repair it.** An integration installed by an earlier build reads `Registration is out of date · turn the switch on to rewrite it` in Settings, and the switch writes the current definitions. **On Codex that repair then needs trusting**: Codex keys trust to a definition's content and silently stops executing a changed one, so run `/hooks` and trust it again, or approvals will keep arriving without the channel an answer travels back on. One definition of seven, and the value in it was chosen to be final.

### Known limitations

Everything listed under `0.1.2`, `0.1.1` and `0.1.0` still stands. The new capability adds four of its own, all of them boundaries rather than gaps waiting to be filled:

- **This surface cannot be operated from the keyboard alone**, and that is a standing property rather than a stage. The chord that would have opened the panel without the pointer was designed, costed and declined; the keys that shipped need a row already open, and opening one needs the pointer. Somebody who works without a pointer answers in the product exactly as they did before — nothing got worse, and nothing here is for them. Assistive technology reaches every control by its own actions, which never depended on key bindings. [`answer-in-notch.md`](docs/answer-in-notch.md) §13.3.
- **A Codex question is read here and answered there.** Codex's permission-request schema has no field an answer to a question could go in, and sending one anyway does not fail to answer — it fails the hook closed, which is worse than saying nothing.
- **A Codex Desktop approval is read-only.** It arrives as a `PreToolUse` that sends no `PermissionRequest` at all, and `PreToolUse` fires on every tool call, so a window a person could answer inside would be a window every tool call waits in.
- **An MCP server's own form cannot be answered from here.** Its shape is a JSON schema the server chose and this app has never seen; drawing a form from it is a different product from the one this is.

Two properties worth stating rather than leaving to be discovered: a held connection is a hook process the product is waiting on, released the moment the request settles, the app closes it, or the app goes away — and bounded by the registered window in every other case. And Claude Code raises its own dialogue about a third of a second after the hook fires, so the notch is a second place to answer rather than the only one; whichever answer arrives first is the one that counts. Codex, on the same measurement, puts the question to the hook and waits.

## 0.1.2 Alpha — 2026-08-31

**The word the surface says most of the time**, and a false `Approval needed` on a thread that had been approving for itself all along.

### Changed

- **The running state is called `Working...` on every surface.** The other three names — `Input needed`, `Approval needed`, `Completed` — say what is happening to the person reading them, while `Running` said what the machine was doing, and it is the state the surface spends most of its life in. The ellipsis is the part that earns its place: it is the only mark in the drawn vocabulary that says "and it has not finished", which is the whole of what separates this state from `Completed` at a glance. The state is still Running in the code and in every document about the state machine; only the word changed. It is `12` pt wider drawn and costs nothing reserved — `Approval needed` is still the longest thing the collapsed surface can say.

### Fixed

- **A Codex Turn resumed after an interrupt no longer asks for approvals the thread approves for itself.** Start a Turn, stop it with a double `Esc`, edit the prompt and send it again, and every reviewed call in that Turn was announced as a person being asked — on a thread that had been "Approve for me" from its first moment. Codex writes a resumed Turn into a *new* rollout file for the same thread, and the reviewer reading was made once per Turn against a path cached for up to ten seconds. It read the old file, found the interrupted Turn's record rather than this Turn's, and gave no answer — correctly, since that record is not this Turn's. Recorded as final, that emptiness cost the Turn its whole life: with no evidence either way, approvals reach the user. An empty reading is now final only when the path it looked in was reported at or after the Turn began, which is after the rotation, and a Turn new to a thread whose record predates it asks for the path again at once instead of waiting out the interval — 6.7 s of wrong row in the measured case. Separately, a `turn_context` record is matched to its Turn by the Turn id it carries rather than by falling within two seconds of the Turn's start, which the file a resumed Turn leaves behind can satisfy while naming the Turn the user interrupted.

### Known limitations

Those shipped with `0.1.1` and `0.1.0` still stand, with one addition inherited from the fix above: **an interrupted Codex Turn whose abort has not yet been read is lost when the user resumes it**, because the App Server now names the new rollout and the record is in the old one. It is overtaken rather than stuck — the resumed Turn's first event redeems the held prompt and replaces the row's Turn outright.

## 0.1.1 Alpha — 2026-08-31

**The collapsed surface, corrected against the hardware it sits on** — plus one navigation click that reported success without doing anything.

### Changed

- **The collapsed surface is now exactly as wide as what it draws.** Both forms gave up the room they were holding empty: a session-dot column per product mark whether or not that product had rows, and a `00:00:00` timer slot open in every state. A resting two-product notched bar is 290 pt where it was 301; the notch-less pill is 154 where it was 238, and 126 for a single product. Nothing was protecting a neighbour — no menu-bar icon is laid out from an overlay panel's frame — so what replaces the reservation is a displacement rule: a dot pushes the leading edge, a digit the trailing one, and each edge opens and closes on the same curve the mark inside it arrives and leaves on.
- **Every surface says the whole status name.** The pill drew `Approval`, `Input` and `Set up`; it now says `Approval needed`, `Input needed` and `Set up integration`, like the panel and the bar. It is the surface with the least context around it and the last one that should economise on the verb. It is sized for the word it is saying, except while a reading follows it.
- **The panel agrees with the notch instead of with the menu bar.** On a notched display its height is the cut-out's, not the taller band the menu bar occupies, so it no longer hangs two points below the hardware. Its lower corners are continuous curves rather than circular arcs, so the edge no longer stops being straight at a findable point. Its right edge sits on the cut-out's own, removing the 3 pt sliver of black that protruded past the notch when the trailing wing was empty.

### Fixed

- **Clicking a Claude Code row whose host is on another desktop.** The click did nothing at all: the host was not raised, the desktop did not change, and the panel collapsed as though it had worked. `NSRunningApplication.activate(options:)` answers `true` whether or not the window server honoured it, and it declines the request an accessory application makes for a host it has just hidden — so the failure was believed and the fallback below it never ran. The raise now asks for the foreground first, on the same entitlement the gear already uses for a click the user has just made, and reads each step's result from the state it should have produced rather than from the call's own answer.

### Known limitations

Those shipped with `0.1.0` still stand, with one addition measured while fixing the above: **a host whose window is full-screen cannot be reached.** A full-screen window is a desktop of its own and nothing public crosses into it. That click now fails out loud instead of claiming a raise. Codex rows escape this, because a deep link opens through Launch Services.

## 0.1.0 Alpha — 2026-08-29

**The first numbered build.** The product below is not new — this entry says what `0.1.0` is, not what changed inside it, because everything here predates the decision to start counting.

### What it does

- **Live status without another window.** The collapsed surface wraps a physical notch, or becomes a compact pill on a display without one. One 5×5 matrix per product tells `Running`, `Input needed`, `Approval needed` and `Completed` apart by motion rather than by colour alone, with a column of session dots, the most urgent state name, one subagent badge per product and the longest turn's elapsed time.
- **One list for both products.** Codex Desktop and Claude Code Threads share a single urgency-sorted panel on hover, each row carrying its Project, title, current-content preview, live reading and subagent count. Finished rows stay until they are read, navigated to, or dismissed with a secondary click.
- **Navigation back to the originating work.** A Codex row is confirmed still navigable before its official deep link is used. Claude Code rows raise Claude Desktop or the originating terminal; Terminal.app and iTerm2 select the exact tab when its tty is known.
- **Quota and daily usage.** The panel's footer draws Codex's primary rate-limit window, Claude Code's 5-hour and 7-day windows and today's token count, and folds down to the totals line. A reading that cannot be trusted is shown as unavailable rather than estimated.
- **Settings, and a first run that teaches the surface.** A switch per product writes only the lifecycle definitions Notchline needs into `~/.codex/hooks.json` and `~/.claude/settings.json`, backing each file up beside itself first, and takes them out again when off. Settings also choose the display, hide the collapsed wings, outline the panel for dark wallpapers, and pick how a row says which product it came from. First run teaches the bar and the panel from the product's own views rather than from pictures of them.

### Known limitations

- **Nothing from before launch.** The list starts empty on every launch and fills from live events; neither product can be asked what it was doing a moment ago in a way this app is willing to trust.
- **Exact navigation is Codex-only.** Returning to a Claude Code session raises its host — Claude Desktop, or the terminal and, where the tty is known, the tab. This is a declared capability boundary, not an approximation ([ADR 0004](docs/adr/0004-make-exact-desktop-navigation-a-release-gate.md)).
- **A lost `SubagentStop` leaves a row Running.** With `SubagentStart` seen and its close never arriving, that Thread stays Running until it leaves the list or the user right-clicks it away. Inferring the end from a timer is forbidden here, and the opposite error — saying `Completed` while work continues — is wrong every single time.
- **Codex hooks need trusting.** Codex keys trust to each definition's position in its file, so a first install or a changed definition has to be reviewed under `/hooks` and a Turn run before that row says `Connected`.
- **Nothing checks for updates.** There is no updater in the app; a new build replaces the old one.
- **macOS 26.5 or later**, on the display Notchline is set to.
