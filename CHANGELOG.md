# Changelog

What each released version of Notchline contains, newest first.

Versions are `major.minor.patch` under [semantic versioning](https://semver.org), with a stage word while a version is not yet finished. The app draws both plus its build number — `Version 0.1.0 Alpha (1)` — on the first-run window and at the foot of Settings. The number in brackets is `CURRENT_PROJECT_VERSION` and rises with every build handed to anybody; it is what tells two people running the same `0.1.0` apart in a bug report. The stage word is deliberately not part of `MARKETING_VERSION`, which stays numeric-dotted so it remains a version macOS can validate and compare.

## 0.1.0 Alpha — 2026-08-29

**The first numbered build.** The product below is not new — this entry says what `0.1.0` is, not what changed inside it, because everything here predates the decision to start counting.

### What it does

- **Live status without another window.** The collapsed surface wraps a physical notch, or becomes a compact pill on a display without one. One 4×4 matrix per product tells `Running`, `Input needed`, `Approval needed` and `Completed` apart by motion rather than by colour alone, with a column of session dots, the most urgent state name, one subagent badge per product and the longest turn's elapsed time.
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
