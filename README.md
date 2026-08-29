<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="design/assets/07-readme/notchline-readme-header-dark.png">
    <img src="design/assets/07-readme/notchline-readme-header.png" width="360" alt="Notchline">
  </picture>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2026.5%2B-lightgrey" alt="macOS 26.5 or later">
  <img src="https://img.shields.io/badge/built%20with-SwiftUI%20%2B%20AppKit-orange" alt="SwiftUI and AppKit">
  <img src="https://img.shields.io/badge/dependencies-none-blue" alt="No third-party dependencies">
</p>

**Notchline is a macOS overlay that turns the strip of screen around the MacBook notch into a live summary of the coding-agent Turns you still need to attend to.** It monitors Codex Desktop and Claude Code, shows which conversations are running, waiting on you, or finished and unread, and takes you back to the one you click.

<!--
HERO DEMO PLACEHOLDER

Recommended visual:
A 6–10 second screen recording or GIF of the top of a real MacBook display.

Composition:
- Crop to a wide horizontal strip covering roughly the top 20–35% of the macOS screen, so the
  physical notch is centred and unmistakable and enough desktop remains for scale.
- Sequence: start at rest (the collapsed bar hugging the cut-out, one status matrix per connected
  product, elapsed time at the right); submit a prompt in a terminal so a row starts timing; move
  the pointer onto the notch so the panel drops open with two or three rows and the quota footer;
  move the pointer away and let it collapse.
- Two products connected, so both matrix hues appear and rows carry their product attribution.
- Clean desktop: notifications off, no personal files, no unrelated windows, plain wallpaper.
- No device mockup and no perspective — a real screen recording of the real app.
- Suggested final width for GitHub: 1600–2000 px.

What it should communicate: this is not a window and not a menu-bar item; it lives in the notch,
it is legible without being opened, and opening it is a hover rather than a click.
-->

---

## Overview

Coding agents spend a lot of their time waiting for you — for an approval, for an answer to a question, or for you to come back and read what they produced. That state is invisible unless the window is in front of you, and with several conversations running across Codex Desktop and Claude Code, keeping track of them means cycling through windows and terminal tabs.

Notchline puts that one question — *what still needs me?* — on the strip of screen the menu bar already occupies. Collapsed, it is the notch itself plus two small wings: a status matrix for each connected product on the left, and the longest running Turn's elapsed time on the right. Each product's matrix animates a distinct pattern per state, so the notch is readable at a glance without any text. On a display with no physical notch it draws the same information as a black pill sitting in the menu bar.

Pointing at it drops an expanded panel: one row per live Thread, showing its Project, title, a preview of what the agent is currently saying, elapsed time, and a subagent count. Clicking a row returns you to that conversation in the product that owns it. Notchline is strictly an observer — it never sends input, grants approval, cancels, archives or deletes anything, and clicking a row never marks it read.

It is not a Dock app and not a menu-bar extra. The process runs as `LSUIElement`: no Dock tile, no ⌘-Tab entry, no application menu. The notch is the only permanent interface, and settings are reachable through the gear in the expanded panel.

<!--
SCREENSHOT PLACEHOLDER — Resting State

Recommended visual:
A still screenshot of a clean macOS desktop, cropped to the top ~25% of the screen.

Composition:
- Both product matrices visible in the leading wing with no rows listed (the connected-but-idle
  state), the notch centred, plenty of empty menu bar either side.
- No pointer in frame — this shot is about how the app looks when nobody is interacting with it.
- Keep enough of the desktop and wallpaper that the reader can see it occupies the menu-bar band
  and nothing more.

What it should communicate: persistent, small, and quiet.
-->

---

## Features

### One surface for two products

Codex Desktop and Claude Code are monitored through one shared vocabulary and one list. Rows from both interleave by urgency and each says which product it belongs to — by default a coloured product name on the row's caption, with three other presentations (name only, badge, colour bar) selectable in Settings. Hue always means *which product*; brightness always means *whether a person is needed*. The two channels never swap.

### Four statuses, and nothing else

Every row is `Approval needed`, `Input needed`, `Running`, or `Completed`. That is also the summary priority order: the collapsed state shows the most demanding state across everything being monitored. A missing, timed-out or unrecognised signal never creates a fifth status — the row holds its last trustworthy value. Failures travel as accompanying text rather than as a status, because Codex's hooks cannot report them and a `Failed` status would make Codex rows look as though they never fail.

### A collapsed state you can read without reading it

Each connected product draws a 4×4 matrix whose animation encodes the state. The patterns are distinct in shape as well as in colour, so the notch stays legible at a glance and under Reduce Motion:

<table>
<tr>
<td><img src="docs/assets/matrix-running.svg" width="260" alt="Running: a beam sweeps clockwise around the matrix and each cell fades behind it"></td>
<td><img src="docs/assets/matrix-approval.svg" width="260" alt="Approval needed: the whole matrix flashes twice in quick succession, then holds dark"></td>
</tr>
<tr>
<td><img src="docs/assets/matrix-input.svg" width="260" alt="Input needed: a lit column steps from left to right above a dim, unmoving bottom row"></td>
<td><img src="docs/assets/matrix-completed.svg" width="260" alt="Completed: one slow wave crosses the matrix diagonally, then the matrix rests"></td>
</tr>
<tr>
<td><img src="docs/assets/matrix-idle.svg" width="260" alt="Connected with no monitored Turn: dim and static"></td>
<td></td>
</tr>
</table>

Beside each matrix, a short column of dots counts that product's rows (capped at three, the third stretching into a bar for "more"). The trailing wing carries the longest unfinished Turn's elapsed time, and one numeral badge per product counting still-running subagents — its ground inverting to bright when one of them is stopped at a dialogue.

### Rows that go away by themselves

A `Completed` row stays until the product that produced it says you have seen it. That evidence is sourced per product and is never guessed from timing: Codex uses Desktop's own unread set (the blue dot); a Claude Code session hosted in Claude Desktop uses Desktop's own record of which session it last put on screen; a session hosted in a terminal uses the kernel's access time on that session's controlling terminal, which advances on a keystroke, a focus change or the pointer crossing that surface — combined with a check that the terminal's application actually holds the foreground on an awake, unlocked screen. A right-click removes a finished row manually; it deletes nothing and claims nothing about having read it.

### Navigation back to the exact conversation

Clicking a Codex row re-confirms the thread still exists (`thread/read`, without turns), then opens the official `codex://threads/<id>` deep link. Clicking a Claude Code row walks the process ancestry from that session's pid to find its host: Claude Desktop gets activated; a terminal that publishes a tty in its own scripting dictionary (Terminal.app, iTerm2) gets the exact tab selected; one that does not (Ghostty, kitty, WezTerm, Alacritty) gets the application activated. In all cases, if the host's windows are all on another Space, Notchline takes you to that Space rather than handing the menu bar to a window you cannot see.

### Rate limits and today's usage

The expanded panel's footer draws one quota rule per connected product — Codex's primary rate-limit window read over the App Server, Claude Code's 5-hour and 7-day windows read from the CLI — plus a combined token total for the day. Unreadable values show as unavailable rather than being estimated from anything else, and the block can be folded away.

<!--
SCREENSHOT PLACEHOLDER — Expanded State

Recommended visual:
A still screenshot of the panel dropped open, cropped to the overlay plus a band of desktop.

Composition:
- Both products connected, with three rows spanning three different states — one attention state
  (Approval needed or Input needed), one Running with a live preview line and elapsed time, and one
  Completed. At least one row carrying a subagent badge.
- The quota footer visible with both products' rules and the daily token line.
- Keep the notch and the top screen edge in frame so the relationship to the collapsed form is
  obvious; crop tightly enough that the 11–13 pt row text stays readable on GitHub.
- Non-sensitive demo data only: neutral project names, no absolute home paths, no account details,
  no real prompt text worth reading.

What it should communicate: the expanded panel is the same object as the collapsed bar, dropped
open — same top edge, same black, more information.
-->

### Settings, and what they touch

A single-panel settings window with three groups: **Products** (a master switch per product that installs or removes its hook registration, plus a health line and a re-check), **Display** (which connected display carries the overlay, `Hide the wings` to collapse onto the cut-out alone, `Outline the panel` for a hairline edge on dark wallpapers), and **Session list** (how rows attribute their product). Turning a product on edits that product's own configuration file, touching only Notchline's keys and keeping a copy of the file as it was immediately before.

<!--
SCREENSHOT PLACEHOLDER — Settings, Products group

Recommended visual:
The settings window, or the Products card cropped from it, in light mode.

Composition:
- Both product switches on and reporting healthy status lines.
- Crop out or replace anything showing the user's home directory, account, or machine name.
- Native macOS window chrome intact — this is the one part of the app that is a conventional
  window, and the screenshot should show that it looks like one.
-->

---

## Motivation

The band of screen either side of the notch is unusually valuable. It is always visible, it is never covered by an ordinary window, and it is already where people look for system state. What sits there today is the menu bar, which is mostly empty in the middle third — exactly where the hardware cut-out is.

The interaction problem came first, though. Running several agent conversations at once means several of them are, at any moment, blocked on a person, and there is no cheap way to find out which. A menu-bar icon can carry one glyph. A notification interrupts and then disappears. A window has to be brought forward, which is the very thing you are trying to avoid. What was missing was something *persistent*, *peripheral*, and *readable without being opened* — closer to a dashboard light than to an app.

That shaped most of the product decisions. The collapsed state carries no text on a notched display, because a pattern is faster to read than a word. Expansion is a hover rather than a click, because the surface should cost nothing to consult. There are no action buttons on rows, because a surface you glance at is the wrong place to approve a command. And the app deliberately shows nothing from before it launched — a list that might be wrong about who is waiting for you is worse than a list that starts empty.

It is also, frankly, a study in how much engineering a genuinely persistent UI surface demands. A window that is on screen all day cannot afford a continuously ticking animation, a per-second re-layout, or a polling loop, and almost every architectural decision in the repository traces back to that.

---

## Requirements

| | |
| --- | --- |
| **macOS** | 26.5 or later (`MACOSX_DEPLOYMENT_TARGET = 26.5`) |
| **Xcode** | 26.6 or later |
| **Hardware** | Any Mac. A built-in notch is optional — a notch-less display gets a content-width pill in the menu bar instead |
| **Dependencies** | None. AppKit, SwiftUI, Combine, Core Animation, Core Image, OSLog and BSD system calls only; no Swift Package Manager or CocoaPods packages |
| **To monitor Codex** | Codex Desktop installed, with a `codex` executable Notchline can locate |
| **To monitor Claude Code** | The `claude` CLI on `PATH`, and/or Claude Desktop |

### Permissions

Notchline requests **no Accessibility permission and no Screen Recording permission**, and this is a design constraint rather than an accident — several capabilities that would have been easier with them were built differently or declined instead.

The one permission it may ask for is **Automation (Apple Events)**, and only at the moment you click a Claude Code row hosted in Terminal.app or iTerm2, so it can ask that terminal which tab holds the session's tty and select it. Declining raises no error and produces no second prompt: the row then just activates the application, exactly like a terminal that cannot report a tty.

### Installation

**There is no packaged release, no signed build and no download.** Notchline has not reached a first release; the only way to run it is to build it from source:

```sh
git clone https://github.com/soondubu137/notchline.git
cd notchline
open Notchline/Notchline.xcodeproj      # then ⌘R
```

or, from the command line:

```sh
xcodebuild build -project Notchline/Notchline.xcodeproj -scheme Notchline -destination 'platform=macOS'
```

The scheme is not shared (`xcuserdata/` is git-ignored), so Xcode regenerates it when you open the project. Code signing is set to automatic; a local development signing identity is enough for running it on your own machine.

---

## Usage

**First run** opens a three-step onboarding window — what is monitored, exactly which local data will be read, and a confirmation before anything is installed. Nothing touches your Codex or Claude Code configuration until you say so. Every launch after that opens no window at all; only the overlay appears.

**Connecting a product.** Each product has its own switch in Settings. Turning it on writes Notchline's hook definitions into that product's configuration (`~/.codex/hooks.json` or `~/.claude/settings.json`) — seven event definitions for Codex, thirteen for Claude Code — and a small helper script that forwards each event to a Unix domain socket in Notchline's own container. Codex additionally requires you to trust the new definitions under `/hooks` inside Codex; Claude Code has no trust step. Turning the switch off removes only Notchline's own definitions and leaves everything else in the file untouched.

**Reading the notch.** Collapsed, each connected product draws a matrix whose animation names the most demanding state it has; the right end shows the longest unfinished Turn's elapsed time and any subagent counts. With nothing connected, the notched form draws nothing at all.

**Opening the panel.** Rest the pointer on the collapsed surface — roughly 150 ms of dwell — and the panel drops open. It collapses 250 ms after the pointer leaves. There is deliberately **no keyboard shortcut to open or close it** (see [Design notes](#design-notes)), and no ⌘, / ⌘Q either, since an `LSUIElement` app has no menu bar for them to live in.

**Acting on a row.** Left-click returns you to that conversation. Right-click on a finished row removes it, with no menu and no confirmation — it deletes nothing and changes no state in the product. Rows in the other three states ignore right-click. There is no approve, answer, cancel or archive action anywhere in the panel.

**Quitting** is the `Quit` button in the settings window, which is reached through the gear at the right of the expanded panel's top bar.

---

## How It Works

Notchline is one process with a single chain from a product's boundary signals to the pixels on the notch:

```text
hook events / App Server / local records
        ↓
HookEventRepository  (the one Turn reducer)
        ↓
LiveCodexMonitorService  (the one orchestrator)
        ↓
MonitorSnapshot  (the one UI data contract)
        ↓
MonitorStore  (@MainActor, the only UI state source)
        ↓
OverlayPanelController (NSPanel)  +  NotchOverlayView (SwiftUI)  +  CALayer motion
```

<!--
ARCHITECTURE DIAGRAM PLACEHOLDER

Recommended diagram:
A minimal engineering diagram of the runtime, drawn in the same flat style as the text
diagram above (Mermaid rendered to SVG is fine; docs/system-architecture.md already
contains a full Mermaid source that can be trimmed down).

It should show, left to right:
- Two boundary columns: Codex (hooks → helper → socket; codex app-server subprocess over
  stdio JSON-RPC; Desktop's private state file, read-only) and Claude Code (hooks → helper →
  socket; `claude agents --json`; `claude -p /usage`; Claude Desktop's records; the controlling
  terminal's access time).
- Both hook sockets converging on one AgentHookListener and one HookEventRepository.
- LiveCodexMonitorService as the single point where those sources are combined.
- One MonitorSnapshot crossing into MonitorStore on the main actor.
- The presentation split: NSPanel geometry on one side, SwiftUI view tree on the other, and
  CALayer-backed motion as a third box that bypasses SwiftUI entirely.

Keep it monochrome and unstyled — no cloud shapes, no gradients, no icons.
-->

**Events arrive by hook, over a socket.** Each product runs a four-line `sh` helper once per lifecycle event, which pipes the whole payload into a `0600` Unix domain socket in `~/Library/Application Support/Notchline/agents/<product>/`. `AgentHookListener` is transport only: one payload per connection, the writer's close as the frame end, a serial read queue to preserve arrival order, an arrival timestamp, and a size ceiling. Payloads never touch disk — they go straight into an in-memory reducer, so there is no event queue, no preview cache and no session state file to go stale.

**One actor reduces Turns.** `HookEventRepository` is the only place a Turn can be opened, named or described, for both products. It consumes events by exact identity, refuses replayed events from before this launch, and holds each session's streaming text as a 240-character head. Other sources may *retire* a Turn — a session list that no longer contains it, a dead producer process — but only inside that actor, behind an ordering guard, and never to create one.

**One orchestrator combines sources.** `LiveCodexMonitorService` is where hook evidence meets the Codex App Server, Desktop's Project and unread state, Claude Code's session registry and read-state adapters, caches, membership reconciliation and degradation policy. Everything above it consumes a single `MonitorSnapshot`; the UI parses no protocol and reads no file.

**Codex is read over its public App Server.** Notchline launches its own `codex app-server --listen stdio://` subprocess and speaks JSON-RPC over stdio, using six read-only methods (account, rate limits, usage, thread list, loaded list, and `thread/read` always with `includeTurns: false`). Framing is a state machine that stays on the serial readability queue that already orders it, while decoding deliberately runs off the actor so it cannot block timeouts and connection management.

**Nothing is polled that can be watched.** There is no refresh loop. Refreshes are driven by four edge sources merged into one stream — the store's own "the rendered projection changed" signal, FSEvents-backed directory watchers on the configuration and state files, an invalidation signal every background read must emit when it lands, and the next due deadline the service reports — plus a 60-second heartbeat that exists only as a backstop for two known silent-failure classes. Deadlines have a hard rule behind them: a deadline may only be reported if a refresh that will actually happen, on this branch, in this machine state, can clear it. Five separate 1 Hz busy loops were traced to violations of that rule and are recorded in `docs/system-architecture.md` §2.

**Work stops when nobody can see it.** Anything whose only purpose is to correct something drawn on screen is gated on the screen being available (display awake, session unlocked and on console, no screen saver) and on there being a row that depends on it. A locked overnight machine goes from a wake-up per second to none, and the reads skipped all night are bought at the first refresh after the screen comes back — the screen returning is itself one of the edges.

**The overlay is a non-activating panel.** A borderless `NSPanel` with `.nonactivatingPanel`, `canBecomeKey` false, at `.statusBar` level so it sits one above the menu bar and is never yielded for; `canJoinAllSpaces`, `fullScreenAuxiliary` and `stationary` keep it in place across Spaces. Its geometry comes from `NSScreen`: `safeAreaInsets` plus `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` decide whether a display has a usable notch, the collapsed height is the larger of the menu-bar band and the camera housing so the panel fills the bar it sits in, and the notched form anchors to the cut-out's trailing edge rather than the display's midpoint, because a fraction of a point against black hardware is a visible seam.

**Persistent motion never goes through SwiftUI.** The status matrices, the searchlight on the status label and the once-a-second elapsed readout are all drawn on `CALayer` and evaluated by the render server. The rule that produced this is not "is this animation expensive to draw" but "does it tick continuously": measured in Release, two `TimelineView` animations in the overlay cost 11.8% CPU against 0.0%–0.4% for the same motion on Core Animation, because the cost is re-evaluating the entire overlay every frame — panel contour, text measurement and all. The elapsed readout follows the same rule from the other direction: it subscribes to a tick SwiftUI does not observe, and publishes to SwiftUI only when the *reserved width* of the readout changes.

---

## Design notes

**Why an `NSPanel` and not a window or a status item.** A status item gets one glyph in a fixed slot; this surface needs a variable-width band that can grow into a panel. A regular window activates the app and takes keyboard focus. A non-activating panel at status-bar level can be permanently on screen, above the menu bar, across every Space, without ever stealing the foreground from what you are actually working in.

**Why there is no `Escape` to collapse.** The panel is `canBecomeKey: false`, so keystrokes go to whichever app holds the foreground — which, since the panel is opened by hover, is always some other app. A local event monitor never fires. The two ways to make it work were both measured and both rejected: letting the panel become key means it swallows *every* keystroke, including after it collapses (a person's typing disappearing into a notch overlay); a global key monitor requires Accessibility permission, which this app does not take. The panel already collapses 250 ms after the pointer leaves, and the pointer is by definition on it while it is open.

**Why the panel follows the menu bar rather than judging what is on screen.** The rule is one sentence — wherever the menu bar is drawn, the panel is — evaluated per display. A full-screen video on the built-in display hides it; the same video on an external display does not. Mission Control, App Exposé and Space switching all keep the menu bar drawn, so the panel stays: Mission Control is where people go to see what is running, which is exactly what this surface says. When the target display cannot be determined it stays visible, because a panel left over a film is a blemish while a panel that vanishes has removed its own only entry point.

**Why the pointer is re-asked after every resize.** `.onHover` is an `NSTrackingArea`, and a tracking area only speaks when the pointer *moves*. A panel that resizes out from under a stationary pointer never delivers the exit, so the store thinks it is still hovered and the area thinks the pointer is still inside — meaning the next genuine entry is swallowed too, and the notch does nothing on the first pass. The controller re-answers "is the pointer on the panel" against the frame it is heading for, and arms a one-shot global mouse-moved monitor to deliver the entry the tracking area is about to lose.

**Why main-actor writes are explicit even where the annotations say they are.** `@Published` sends `objectWillChange` from `willSet`, so a write off the main thread lets SwiftUI re-render *before* the value is stored — `body` reads the old value and nothing invalidates it again. Under `SWIFT_APPROACHABLE_CONCURRENCY` the optimiser can elide the hop back to the main actor in a task body started from a `@MainActor` method, so the annotations alone are not enough; work resuming from a suspension and then touching store state uses an explicit `await MainActor.run`. The symptom was a collapsed notch drawing the expanded header's controls, on roughly one hover burst in three, and only in Release.

**Why the app never edits a configuration file it does not understand.** Installing a product's integration is a read-modify-write on a file the user owns. Notchline copies the bytes it just read to a `.notchline-backup` beside the original before every write, touches only its own keys, preserves any structure it cannot interpret, writes atomically at `0600`, and reads back to verify. Where a key it must write is already a shape it cannot safely modify, it refuses with an error rather than coercing — an earlier version's coercion of an unrecognised value into an empty dictionary would have replaced the user's file with its own. Removal additionally deep-scans the whole document to confirm no command of Notchline's survives anywhere before deleting the helper it points at.

**Why Codex hook definitions are appended and never rewritten.** Codex keys hook trust on `<path>:<event>:<group index>:<handler index>`. Rewriting the file to tidy it renumbers the groups and silently invalidates definitions the user had already trusted. So an install that finds the registration already complete writes nothing at all.

**Why there is no cold-start sync.** Anything running, waiting or finished-unread before Notchline launched is ignored until it produces its next lifecycle event, and the reasons differ per product. On the Codex side it is a capability boundary: measured against a real in-flight Turn, a standalone App Server reports every thread as not loaded and no in-progress Turn, so any startup list would be a guess. On the Claude Code side it was genuinely implementable and was removed anyway: a transcript writes nothing while a session waits on a person, so a rebuilt Turn could only ever be drawn as `Running` — and a session parked on a permission request appearing as busy work gets wrong the one question this product exists to answer.

---

## Known limitations

These are the constraints the implementation actually has, separated by kind.

**Capability boundaries — these are not scheduled to be fixed, because the products do not expose what would be needed.**

- **No cold-start sync.** Turns already active, waiting or completed before Notchline starts appear only after a new lifecycle event on that Thread. See the design note above.
- **Side chats are never rows, in either product.** Codex's is an ephemeral thread that fires Turn hooks normally but is never persisted, never listed, refused by `thread/read`, and connected to its parent only inside Desktop's process memory — so it can be neither its own row nor folded into its parent's. Claude Code's is a read-only fork Claude Desktop opens with no settings loaded, so it fires no hook and never reaches Notchline at all.
- **Claude Code navigation is degraded by design.** Codex opens the exact thread. Claude Code raises the host: Claude Desktop for a desktop-hosted session, the exact tab for a terminal that publishes a tty (Terminal.app, iTerm2), and the application alone for one that does not (Ghostty, kitty, WezTerm, Alacritty). No supported way to open a specific Claude Code session exists.
- **A Claude Code Turn with neither a Desktop record nor a controlling terminal cannot be answered for.** `claude -p` with output piped away is the case: its finished row has no read signal at all and stays until that Thread's next submission or a manual right-click dismissal. Sessions inside `tmux`, `screen` or `ssh` fall into the same category — their process chain reaches only `launchd`, so no host application can ever hold the foreground.
- **One deliberate cost in the read rules.** A Claude Code Turn that finishes while Claude Desktop is in front on an awake, unlocked screen is treated as read about two seconds later — because at the moment a Turn ends, someone watching and someone who submitted and walked away are identical on every available signal. Whoever walked away loses that one notification.

**Dependencies on undocumented behaviour.**

- A number of features — Codex Project identity and unread state, approval routing, Claude Code thread titles, quota figures, interrupt evidence, read state and subagent handling — read local data or observe host behaviour that is not covered by public documentation or schema. Every one is read-only, fails closed, and is registered with its version baseline, its breakage signal and its degradation in [the integration registry](docs/non-public-codex-integration-features.md). A host update can break any of them.
- Verification baselines are specific: Codex Desktop `26.810.50856` / CLI `0.148.0-alpha.9`, later rows on `26.818.41509` / `0.149.0-alpha.4.1` and `26.820.60940`; Claude Desktop `1.30096.5` and Claude Code CLI `2.1.233`–`2.1.241`. Behaviour on other versions is untested.

**Scope, and things that are simply not there.**

- One account on one Mac. No history, no search, no sync, no persistence of anything you see — restart the app and the list starts empty.
- No packaged, signed or notarised release exists yet, and no automatic updates.
- Multi-display handling exists and is real (per-display concealment, a remembered target display, a fallback while that display is disconnected), but it has not been exhaustively exercised across every arrangement, resolution and scaling combination.
- `Hide the wings` is available only on displays where the cut-out's exact position and width can be measured. Notch-less displays and displays reporting a notch with no occlusion width get the row disabled, with a caption explaining which case applies.
- Some panel geometry and animation behaviour depends on `NSScreen` and Core Animation details that can shift between macOS releases; the deployment target is macOS 26.5 and nothing below it has been tested.
- Quota reads on the Claude Code side run a real `claude -p "/usage"` session every 30 minutes, which leaves a ~3.4 KB transcript on disk that nothing cleans up (about 160 KB a day while the app runs). Notchline measures that folder and shows the size in Settings with a `Show in Finder` button, but deliberately never deletes it — the folder-naming rules can collide with a real project directory. See [`docs/artifacts.md`](docs/artifacts.md).
- There is no CI and no lint configuration. Running the test suite locally is the only gate.

---

## Project status

Notchline is under active development and has **not** reached its first release. The core experience is functional end to end — hook integration, live status for both products, automatic row removal on read evidence, navigation, quota, settings and onboarding all work — and the repository is past 250 commits with a 538-case unit suite behind it.

What keeps it pre-release is mostly the surface between this app and two products that are themselves moving: several features depend on host behaviour verified against specific versions, and the version matrix has not been re-established broadly. Open defects and priorities are tracked on a GitHub board rather than in this repository:

- Board: <https://github.com/users/soondubu137/projects/2>
- Issues: <https://github.com/soondubu137/notchline/issues>

Documents under [`docs/technical-explorations/`](docs/technical-explorations/) are open research, not commitments. Of the four, three record work that shipped and one — [sharing a single Codex Desktop App Server instance](docs/technical-explorations/shared-app-server/README.md) — is explicitly unverified and must not replace the current path before a successful spike.

---

## Development

```sh
# Build
xcodebuild build -project Notchline/Notchline.xcodeproj -scheme Notchline -destination 'platform=macOS'

# Unit tests (Swift Testing — @Test / #expect, not XCTest)
xcodebuild test -project Notchline/Notchline.xcodeproj -scheme Notchline \
  -destination 'platform=macOS' -only-testing:NotchlineTests
```

The unit suite runs in seconds on a warm build. Two things are worth knowing before you run it:

- **`xcodebuild test` launches the real app.** A macOS unit-test bundle has no executable of its own; it is injected into a host, and this app is its own host. Startup is therefore gated on `AppProcess.isHostingTests`, so the test process draws no overlay and binds no hook socket — without that gate, a test run takes apart whatever copy of Notchline is already running on the machine.
- **Performance work must be measured in Release.** Debug numbers mean nothing here. Steady-state cost reads accurately on `ps %cpu`, but burst cost does not — one expand/collapse transition is about 92 ms of CPU and shows up as 0.1%, which reads as nothing. Diff cumulative CPU time (`ps -o time`) instead.

Before changing anything, two files are worth reading first: [`CONTEXT.md`](CONTEXT.md), which settles the vocabulary (*Thread*, *Turn*, *monitoring lifecycle*, *presence*, *unread terminal state*) and lists the wording each term bans, and [`AGENTS.md`](AGENTS.md), which carries the working constraints — including the rendering rule that no continuously running SwiftUI animation may exist in the overlay.

---

## Repository structure

```text
Notchline/
├── Notchline/            # The app target — 39 Swift files, no third-party code
├── NotchlineTests/       # Swift Testing suite, 538 cases
└── NotchlineUITests/     # XCUITest scaffolding (launch tests only)

docs/                     # The written contracts
├── PRD.md                # Product contract: scope, state model, navigation, release gates
├── system-architecture.md# The implementation as it is: timing, responsibilities, measurements
├── tech-design.md        # Interfaces, protocols, data flow, failure recovery
├── figma-design.md       # Visual and interaction spec
├── dual-agent-design.md  # How two products share one surface
├── artifacts.md          # Every file this app creates or edits, inside its container and out
├── non-public-codex-integration-features.md   # Undocumented dependencies, with breakage signals
├── adr/                  # 18 architecture decision records
└── technical-explorations/  # Open research — not decisions, not commitments

design/                   # Brand marks, app icon, menu-bar template, matrix state animations
CONTEXT.md                # Terminology; naming disagreements are settled here
AGENTS.md                 # Working constraints for this repository
```

Inside the app target, the layering is: `MonitorStore` (main-actor UI state) → `LiveCodexMonitorService` (orchestration) → `HookEventRepository` / `CodexAppServerClient` / the read-only Desktop adapters (boundaries) → `MonitorDomain` (the one data contract). Presentation is `OverlayPanelController` (panel geometry and lifetime), `NotchOverlayView` (SwiftUI, passive), `NotchStatusMatrix` (Core Animation) and `SettingsWindow`.

---

## Contributing

This is a solo side project and is not currently accepting pull requests. Bug reports and observations are welcome on the [issue tracker](https://github.com/soondubu137/notchline/issues) — especially reports of a host update breaking one of the registered integrations, since those are the failures most likely to be silent.

## License

No licence has been chosen for this repository yet, so default copyright applies and no permissions are granted. If you want to do something with the code, please open an issue and ask.
