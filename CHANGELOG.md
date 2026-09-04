# Changelog

What each released version of Notchline contains, newest first.

Versions are `major.minor.patch` under [semantic versioning](https://semver.org), with a stage word while a version is not yet finished. The app draws both plus its build number — `Version 0.1.0 Alpha (1)` — on the first-run window and at the foot of Settings. The number in brackets is `CURRENT_PROJECT_VERSION` and rises with every build handed to anybody; it is what tells two people running the same `0.1.0` apart in a bug report. The stage word is deliberately not part of `MARKETING_VERSION`, which stays numeric-dotted so it remains a version macOS can validate and compare.

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
