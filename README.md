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

**Notchline is a macOS overlay that keeps the Codex Desktop and Claude Code Turns which still need attention visible without taking up usable desktop space.**

<!--
HERO DEMO PLACEHOLDER

Recommended visual:
A 6–10 second screen recording or GIF of the top portion of a real MacBook display.

Composition:
- Crop to a wide horizontal strip covering roughly the top 20–30% of the display.
- Keep the physical notch centred and leave enough desktop and menu-bar context to make the placement unambiguous.
- Begin with Notchline collapsed around the notch with both product matrices visible.
- Let a live Turn change state, then move the pointer onto the surface so the session list and quota footer expand below it.
- Move the pointer away and show the panel returning to its collapsed form.
- Use neutral Project and Thread names, hide notifications and personal menu-bar items, and remove unrelated desktop files.
- Prefer a direct screen recording over a device mock-up; avoid perspective, gradients and promotional framing.
- Suggested final width for GitHub: 1600–2000 px.

What it should communicate:
Notchline is a persistent surface attached to the top edge of the display, not a conventional app window or another menu-bar icon.
-->

## Overview

Daily work can already fill the screen with a code editor, a browser, documents, and communication tools. Codex Desktop, Claude Desktop and terminal sessions then end up buried under those windows, even while several Turns continue working in the background.

Once the agent windows are out of sight, it becomes difficult to see which work is still running, which Turn needs an approval or answer, and which conversation has completed. Repeatedly bringing every window to the front just to check its state interrupts the work that already occupies the desktop.

Notchline moves that overview into the otherwise unused area around the display notch. Its collapsed surface quietly shows the current state of both products without covering any working window; hovering reveals the monitored Threads, and clicking a row returns to the originating conversation. It observes and navigates, but does not approve commands, answer questions, send input, cancel work, archive Threads or mark them as read.

## Features

### Live status without another window

The collapsed surface sits around a physical notch, or appears as a compact pill on a display without one. A 4×4 matrix for each connected product distinguishes `Running`, `Input needed`, `Approval needed` and `Completed`, while the trailing side can show elapsed time and subagent activity; hovering expands the same surface into the Thread list.

<!--
SCREENSHOT PLACEHOLDER — Collapsed states

Recommended visual:
Two real screenshots at the same scale: one from a notched MacBook display and one from a display without a notch.

Composition:
- Keep the full top edge of each display visible, with restrained desktop context below it.
- On the notched display, show two connected products and an active elapsed-time reading in the wings.
- On the notch-less display, show the compact pill in the menu-bar band without obscuring unrelated menu items.
- Use the same state and demo data in both captures so the layout difference is the subject.
- Hide notifications, account names and private menu-bar items.

What it should communicate:
The physical notch is part of the notched layout, while the notch-less form preserves the same interaction model without pretending a cut-out exists.
-->

### One list for both products

Codex Desktop and Claude Code Threads share one urgency-sorted list and the same four statuses. Each row can show its Project, title, current-content preview, elapsed time and subagent count; completed rows remain until trustworthy read or navigation evidence removes them, or until the user dismisses the row with a secondary click.

### Navigation back to the originating work

Clicking a Codex row confirms that the Thread is still navigable before using its official deep link. Claude Code rows return to Claude Desktop or the originating terminal; Terminal.app and iTerm2 can select the exact tab when its tty is available, while other terminals fall back to application activation.

### Quota and daily usage

The expanded footer shows Codex's primary rate-limit window, Claude Code's 5-hour and 7-day windows, and today's token count. Unavailable readings remain unavailable rather than being estimated, and the quota rows can be folded down to the daily summary.

### Display and product settings

Each product has an independent integration switch and health row. Settings also choose the display, optionally hide the collapsed wings, add an outline for dark wallpapers, and present product attribution as a coloured name, plain name, badge or colour bar.

<!--
SCREENSHOT PLACEHOLDER — Expanded panel

Recommended visual:
A real screenshot of the expanded panel attached to the top edge of a notched display.

Composition:
- Include the notch and enough of the menu-bar band to preserve the spatial relationship.
- Show three non-sensitive rows: one needing approval or input, one running with a current-content preview and elapsed time, and one completed.
- Include both products, at least one subagent count, the quota rules and the daily token line.
- Crop tightly enough for the row text to remain readable on GitHub, but not so tightly that the panel looks like a detached window.
- Use neutral Project names and text written specifically for the demo.

What it should communicate:
The expanded panel is the collapsed notch surface revealing more detail, not a separate dashboard.
-->

<!--
SCREENSHOT PLACEHOLDER — Settings

Recommended visual:
A real screenshot of the single-pane Notchline Settings window.

Composition:
- Show the Products, Display and Session list groups in one capture if the text remains readable; otherwise show the Products and Display groups.
- Keep native macOS window chrome visible.
- Show both product switches enabled with healthy, non-sensitive status text.
- Ensure no home-directory path, account detail or machine name is visible.
- Use the same appearance and scale as the other README captures.

What it should communicate:
Configuration is conventional macOS UI even though the primary interface is not a conventional window.
-->

## Motivation

In my daily work, the available screen area is often already occupied by a code editor, internal documentation, product pages, communication software and the other tools needed for the task in front of me. There is rarely space left to keep Codex Desktop, Claude Desktop or every Claude Code terminal visible as well.

The agent windows therefore spend much of their time underneath everything else. That makes it easy to miss a conversation waiting for permission, a question that needs an answer, or a Turn that has already completed. Bringing those windows to the front, checking them one by one and burying them again is a small but frequent interruption.

I wanted one quiet place that consumed no usable desktop area but still made the live state of every task easy to check at any moment. The strip around the MacBook notch was already present, always visible and otherwise unable to hold a normal window. Notchline grew from using that space as a compact status surface: small enough to stay out of the way, but detailed enough to show when my attention is needed.

## Requirements and installation

| Requirement | Current project setting |
| --- | --- |
| macOS | 26.5 or later |
| Xcode | 26.6 (the project was created and last upgraded with this tool version) |
| Swift | Swift 5 language mode with approachable concurrency and main-actor default isolation |
| Dependencies | Apple platform frameworks and system interfaces only; no Swift Package Manager or CocoaPods packages |
| Codex | Codex Desktop and a `codex` executable Notchline can locate |
| Claude Code | The `claude` CLI; Claude Desktop for sessions hosted in that application |

There is currently no packaged, signed or notarised release. Build the app from source:

```sh
git clone https://github.com/soondubu137/notchline.git
cd notchline
open Notchline/Notchline.xcodeproj
```

Run the `Notchline` scheme from Xcode, or build from the command line after Xcode has generated the local scheme:

```sh
xcodebuild build \
  -project Notchline/Notchline.xcodeproj \
  -scheme Notchline \
  -destination 'platform=macOS'
```

Code signing is configured as automatic for local development. The app target is not sandboxed because it must run local product commands, read product-owned metadata, manage Hook configuration and communicate with terminal applications.

### Permissions

Notchline does not request Accessibility or Screen Recording permission.

It may request Automation permission when opening a Claude Code row hosted in Terminal.app or iTerm2. That permission is used only to identify and select the tab whose tty belongs to the session. If permission is denied, navigation falls back to activating the terminal application.

## First run and usage

The first launch opens one onboarding window. It contains the two product connection switches, an explanation of the Hook configuration they manage, and a live legend for reading the notch. Selecting `Start` completes onboarding; later launches show only the overlay.

Enabling an integration adds Notchline's lifecycle definitions to the product's own configuration:

- Codex: `~/.codex/hooks.json`
- Claude Code: `~/.claude/settings.json`

Before each change, the existing file is copied beside itself as `hooks.json.notchline-backup` or `settings.json.notchline-backup`. The editor changes only Notchline's managed definitions and preserves unrelated settings. Codex also requires the new definitions to be trusted through `/hooks`; Claude Code has no equivalent trust step.

Once running:

- Hover over the collapsed surface to expand it; move the pointer away to collapse it.
- Left-click a row to return to its originating Thread or host.
- Right-click a completed row to dismiss that Turn's row without deleting or marking anything read.
- Use the gear in the expanded header to open Settings.
- Use `Quit` in Settings to stop the app.

There is no keyboard shortcut for opening or closing the overlay. Because Notchline runs as `LSUIElement`, it has no Dock tile, app-switcher entry or application menu; consequently there is no application-level `⌘,` or `⌘Q` route either.

## How it works

Notchline is one `LSUIElement` process that observes two products it does not control. Each product is understood through its own boundary — hooks, a subprocess, a few read-only file adapters — and everything past that boundary follows a single path: one reducer per product, one merged snapshot, one main-actor store, one overlay.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="design/assets/07-readme/notchline-architecture-dark.svg">
  <img src="design/assets/07-readme/notchline-architecture.svg" alt="Notchline architecture: the Codex and Claude Code boundaries converge on one merged snapshot and one overlay" width="1120">
</picture>

### Live Turn state comes only from Hooks

Both products run a small `sh` helper for lifecycle events. The helper forwards one payload to a per-product, permission-restricted Unix domain socket and always exits successfully, so Notchline being closed does not add errors to the originating session. Payloads go straight into an in-memory reducer that holds each Turn's exact state; there is no on-disk event queue and no persisted Thread list. The socket transport and the reducer are one implementation shared by both products, instantiated once each.

### Codex is read through a second App Server

Codex Desktop drives its own App Server in-process. Notchline never attaches to it. It launches a **separate** `codex app-server` subprocess of its own and speaks JSON-RPC over stdio to that one, using six public read-only methods plus one registered experimental method.

The two servers never exchange live state, and that is a measured capability boundary rather than a design preference: on a standalone App Server, `thread/loaded/list` comes back empty, threads read as `notLoaded`, and `thread/read` never reports `inProgress`. What they do share is the records on disk — the same thread rollout files under `~/.codex`. So the split falls out naturally: the App Server answers what is already persisted (Thread identity, titles, Projects, quota, and the pre-flight that a row is still navigable), while whether a Turn is running, waiting or finished arrives only through the hook socket. This is also why there is no cold-start reconstruction.

A small number of features that public interfaces do not expose — Desktop Project identity, unread state and approval routing — are handled by read-only adapters over Desktop's own state file, and documented in the [non-public integration registry](docs/non-public-codex-integration-features.md).

### Claude Code divides the same way

Notchline runs its own `claude` subprocesses too — `claude agents --json` for the session list and `claude -p "/usage"` for quota — and they are separate invocations, not attachments to the user's sessions. Narrowly scoped local readers supply titles, read evidence and host discovery from transcripts, Claude Desktop's session records and each session's controlling tty. As on the Codex side, files can say what a session is, but only a hook can say what its Turn is doing right now.

### One contract, one store, one surface

Each service reduces its own product's evidence into an `AgentSnapshot`. The two merge into a single `MonitorSnapshot` — availability, sessions, quota and diagnostics — which `MonitorStore` publishes on the main actor. The views render that store and nothing else: they parse no protocol and read no product file. Clicking a row runs the same loop in reverse, back to the originating Thread through the official deep link, or to the terminal or Claude Desktop host that owns the session.

The app has no network client. Every socket, subprocess and file read in the diagram above is local.

## Known limitations

- **No cold-start reconstruction.** Turns that were already running, waiting or completed before Notchline launched are not shown until a later lifecycle event establishes current state. Neither product offers a reliable common way to reconstruct the distinction between work and a wait.
- **Only navigable root Threads become rows.** Codex side chats cannot be vouched for or reopened through the available interfaces. Claude Code side chats do not reach the observation boundary.
- **Claude Code navigation can degrade.** Claude Desktop can only be activated, not focused to a specific existing session. A terminal tab is selected only when the terminal exposes its tty through a scripting dictionary; otherwise only the host application is activated.
- **Some completed Claude Code rows have no automatic read signal.** A session with neither a Claude Desktop record nor a controlling terminal cannot prove it has been read. Its row remains until the next submission, the session disappears, or the user dismisses it.
- **Several integrations depend on observed or undocumented local behaviour.** Host updates can affect Project names, unread membership, Claude Code titles, quota parsing, approval correction, subagent attribution or navigation. These dependencies and their conservative degradation paths are maintained in the [integration registry](docs/non-public-codex-integration-features.md).
- **Claude Code quota reads leave transcripts.** The `claude -p "/usage"` command creates a Claude Code project transcript. Notchline reports the accumulated footprint in Settings but does not delete files from a directory that can also contain the user's own sessions.
- **A lost subagent stop can leave a stale running count.** There is no safe timeout from which to infer that a subagent ended. The row can be dismissed once its Turn is completed or will leave when the Thread leaves the monitored list; the trade-off is tracked in [issue #102](https://github.com/soondubu137/notchline/issues/102).
- **The scope is local and current.** There is no history browser, search, cross-device sync or remote service.

## Project status

Notchline is an actively developed, pre-release solo side project. There are no published tags or GitHub releases; current work is tracked on the [project board](https://github.com/users/soondubu137/projects/2) and in [GitHub Issues](https://github.com/soondubu137/notchline/issues).

## Licence

No open-source licence has been selected for this repository. All rights are reserved, and no permission is granted to use, copy, modify or distribute the source.
