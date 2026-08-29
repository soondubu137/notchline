# Notchline

A macOS utility that uses the area around the display notch to keep the Codex Desktop and Claude Code Turns that still need attention in view.

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

Agent work often continues outside the window currently in front of you. A Turn may be running, waiting for an approval, asking a question, or finished but not yet read. Following several conversations across Codex Desktop, Claude Desktop and terminal sessions otherwise means repeatedly returning to each host to find out what changed.

Notchline keeps that state at the top of the screen. On a MacBook with a notch, its collapsed form extends from the physical cut-out into two small wings. One status matrix is shown for each connected product, while the trailing side can show the longest unfinished Turn's elapsed time and subagent activity. On a display without a notch, the same information is drawn in a compact black pill in the menu-bar band.

Hovering expands the same surface into a list of live monitored Threads. Each row carries the Project, Thread title, current-content preview, Turn status and timing information. Clicking a row returns to its originating product. Notchline observes this work; it does not approve commands, answer questions, send input, cancel work, archive Threads or mark them as read.

## Features

### A persistent status surface

The collapsed surface represents each connected product with a 4×4 matrix. Motion and shape distinguish `Running`, `Input needed`, `Approval needed` and `Completed`; a column beside each matrix indicates how many rows belong to that product. When several Threads are present, the summary follows the same priority as the expanded list: approval, input, running, then completed.

The component is a borderless, non-activating panel at the system status-bar level. It follows the selected display's menu bar across Spaces and removes itself when that menu bar is hidden by a full-screen app or automatic menu-bar hiding.

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

### Live Threads rather than history

Rows are created from lifecycle events observed after Notchline starts. Later Turns in the same Thread replace the row's current Turn rather than creating duplicates. Codex Desktop and Claude Code use one four-status vocabulary and one urgency-sorted list, with configurable product attribution when both are connected.

A row can include the prompt or current agent output, wall-clock processing time, a terminal reason, and the number of subagents still running. A subagent waiting for approval raises the Thread's derived urgency without rewriting the parent Turn's own status.

Completed rows remain visible until the originating product provides trustworthy evidence that they have been read or are no longer navigable. A completed row can also be removed with a secondary click; this dismisses only that Turn's row and changes nothing in Codex or Claude Code.

### Navigation back to the originating work

Before opening a Codex row, Notchline confirms that the Thread is still navigable and then uses the official `codex://threads/<thread-id>` deep link.

For Claude Code, it resolves the host from the session's process ancestry. Claude Desktop is activated for desktop-hosted sessions. Terminal.app and iTerm2 can have the exact tab selected through their scripting dictionaries; terminals that do not expose a controlling terminal are activated at application level instead. If the relevant window is on another Space, activation follows it there.

### Quota and daily usage

The expanded footer shows Codex's primary rate-limit window and Claude Code's 5-hour and 7-day windows, plus today's token count. Unavailable readings remain unavailable rather than being estimated. The quota rules can be folded down to the daily summary.

### Display and product settings

Each product has an independent integration switch and health row. Display settings choose which connected screen carries Notchline, optionally hide the collapsed wings where the hardware cut-out can be measured, and add a restrained outline for dark wallpapers. Session-list settings choose whether product attribution appears as a coloured name, plain name, badge or colour bar.

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

The centre of a MacBook menu bar is unusual screen space: it is persistently visible, already associated with system state, and partly occupied by hardware. That makes it a useful place for information that should remain peripheral rather than demand another window or notification.

The interaction model follows from the problem being monitored. Agent conversations can run in parallel, but the important moment is often when one stops and needs a person. A transient notification can be missed, a menu-bar glyph cannot describe several Threads, and bringing every host to the foreground defeats the purpose. Notchline explores a surface that is persistent enough to answer “what still needs me?” while remaining small until detail is requested.

That constraint also shapes what the app refuses to do. The overlay is an observer and navigation aid, not an approval surface. It begins with an empty list rather than reconstructing uncertain pre-launch state, and it withholds a row or field when its source cannot establish the answer reliably.

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

The runtime converges product-specific evidence into one path to the overlay:

```text
Codex boundary signals               Claude Code boundary signals
        ↓                                      ↓
HookEventRepository                  HookEventRepository
LiveCodexMonitorService              ClaudeCodeMonitorService
        └──────────── AgentSnapshot ────────────┘
                           ↓
             AgentSnapshotMerge / MonitorSnapshot
                           ↓
             MonitorStore (@MainActor)
                           ↓
       NSPanel geometry + SwiftUI content + CALayer motion
```

Both products run a small `sh` helper for lifecycle events. The helper forwards one payload to a per-product, permission-restricted Unix domain socket and always exits successfully, so Notchline being closed does not add errors to the originating session. Events are reduced in memory; there is no on-disk event queue or persisted Thread list.

Codex metadata, quota, membership and navigation checks come from a local `codex app-server` subprocess. A small number of features that public interfaces do not expose—such as Desktop Project identity and unread state—are handled by read-only boundary adapters and documented in the [non-public integration registry](docs/non-public-codex-integration-features.md).

Claude Code combines official Hooks and `claude agents --json` with narrowly scoped local readers for titles, read evidence, usage and host discovery. Product-specific evidence is translated into the same `AgentSnapshot` shape before the UI sees it.

The app itself has no network client. Its sockets are local, its App Server and CLI interactions are local subprocesses, and the UI receives only the merged snapshot rather than reading product files or protocols directly.

<!--
ARCHITECTURE DIAGRAM PLACEHOLDER

Recommended diagram:
A restrained engineering diagram of the implemented runtime, suitable for an SVG exported from a simple vector or Mermaid source.

Structure:
- Left column: Codex Hooks, codex app-server, and Desktop read-only metadata.
- Second left column: Claude Code Hooks, claude agents/usage commands, transcripts and host/read-state adapters.
- Centre: two Unix sockets feeding AgentHookListener and the shared HookEventRepository implementation, with one reducer instance per product.
- Next: LiveCodexMonitorService and ClaudeCodeMonitorService producing AgentSnapshots that merge into one MonitorSnapshot.
- Right: MonitorStore on the main actor feeding OverlayPanelController, NotchOverlayView and the settings/onboarding window.
- Mark public interfaces, observed/private read-only boundaries and app-owned files with simple line styles rather than decorative colour.

Keep the diagram monochrome, flat and compact. Avoid cloud symbols, service logos, gradients and infrastructure-style decoration.

What it should communicate:
Product-specific complexity stops at the boundary; state reduction and presentation have one shared path.
-->

## Design notes

### AppKit owns placement; SwiftUI owns content

`OverlayPanelController` creates a borderless, non-activating `NSPanel` at `.statusBar` level and positions it against the selected `NSScreen`. The panel can join all Spaces, does not become key or main, and deliberately bypasses the default visible-frame constraint so it can occupy the menu-bar/notch region. SwiftUI renders the contour, header, rows, footer and settings, but it does not decide window geometry or parse integration data.

Display geometry is derived from safe-area insets and the auxiliary areas on either side of the notch. The notched compact form can anchor to the measured trailing edge of the physical cut-out; screens without a usable cut-out measurement use the centred pill form instead. Screen changes are observed and the user's preferred display is restored when it becomes available again.

### Persistent motion stays out of SwiftUI's update loop

The status matrices, sweeping text and once-per-second elapsed readings are layer-backed. Continuous animation and per-second drawing are delegated to Core Animation; the timer republishes into SwiftUI only when its reserved layout changes, such as when another digit is needed. Ordinary status and content changes still arrive through snapshots. This boundary comes from Release profiling of the whole overlay, not from treating individual animations as isolated drawing costs. The measurements and rejected approaches are recorded in [the system architecture](docs/system-architecture.md#6-the-rendering-boundary-for-persistent-motion).

### Refreshes follow evidence

Hook delivery, directory changes, completed background reads and the next meaningful deadline drive refreshes. A low-frequency heartbeat is the fallback. The one deliberate poll checks whether the selected display's menu bar is present, because macOS exposes no reliable event for another application entering full screen; unchanged samples never republish the UI, and the poll parks while the screen is unavailable.

### Unknown state fails closed

Recovery timers decide when to reconnect or retry, never whether a Turn is running, waiting or read. Unrecognised payloads and incompatible private schemas retain the last trustworthy value or withhold the affected field. User configuration is parsed and changed narrowly rather than replaced with a shape Notchline happens to understand.

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

Notchline is an actively developed, pre-release side project. The core monitoring, display, navigation and settings paths are implemented and exercised by a large Swift Testing suite, while host-version compatibility and platform-specific edge cases continue to be refined. There are no published tags or GitHub releases.

The current issue register and fix order live on the [Notchline project board](https://github.com/users/soondubu137/projects/2) and in [GitHub Issues](https://github.com/soondubu137/notchline/issues). Open technical explorations under [`docs/technical-explorations/`](docs/technical-explorations/) are research records, not promises or approved roadmap items.

## Development

Run the full unit suite with:

```sh
xcodebuild test \
  -project Notchline/Notchline.xcodeproj \
  -scheme Notchline \
  -destination 'platform=macOS' \
  -only-testing:NotchlineTests
```

The unit target uses Swift Testing. The UI-test target currently provides basic launch coverage rather than a full interaction suite. There is no CI or lint configuration, so the local unit suite is the repository's required gate. Performance work must be measured with a Release build; Debug timings are not representative of the overlay.

The scheme is stored in ignored user state rather than `xcshareddata`. Opening the project in Xcode generates it locally. If a clean checkout cannot find the scheme, open the project once; if the scheme needs to work without user state, share it from Xcode instead of committing `xcuserdata`.

### Repository structure

```text
Notchline/
├── Notchline/             App entry point, domain model, providers and UI
├── NotchlineTests/        Swift Testing unit and integration-boundary tests
└── NotchlineUITests/      Basic application launch tests
docs/
├── adr/                   Decisions and their trade-offs
├── technical-explorations/ Open research, measurements and NO-GO conditions
├── PRD.md                 Current product contract
├── system-architecture.md Implemented architecture and performance boundaries
├── tech-design.md         Interfaces, data flow and recovery behaviour
└── non-public-codex-integration-features.md
                           Registry of undocumented or observed dependencies
design/                    Product marks, app icons and design source assets
```

Start with [`CONTEXT.md`](CONTEXT.md) for the project's precise terminology, then [`docs/PRD.md`](docs/PRD.md) for product behaviour and [`docs/system-architecture.md`](docs/system-architecture.md) for the implementation as it currently exists.

## Licence

This repository does not currently declare an open-source licence.
