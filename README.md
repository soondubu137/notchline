<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="design/assets/03-stacked/notchline-stacked-black-1024.png">
    <img src="design/assets/03-stacked/notchline-stacked-white-1024.png" width="180" alt="Notchline">
  </picture>
</p>
<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2026.5%2B-lightgrey" alt="macOS 26.5 or later">
  <img src="https://img.shields.io/badge/built%20with-SwiftUI%20%2B%20AppKit-orange" alt="SwiftUI and AppKit">
  <img src="https://img.shields.io/badge/status-in%20development-yellow" alt="In development">
  <img src="https://img.shields.io/badge/version-0.2.7-blue" alt="Version 0.2.7">
  <img src="https://img.shields.io/badge/licence-GPL--3.0--or--later-green" alt="Licensed under GPL 3.0 or later">
</p>

**Notchline keeps coding agent activity reachable at your Mac’s notch.**

<p align="center">
  <img src="design/assets/07-readme/notchline-hero.webp" width="100%" alt="A recording of the notch: the compact bar sits above a code editor, a Claude Code question opens the panel, two questions are answered by picking an option and pressing Next then Submit, and the panel collapses back to the compact bar.">
</p>

## Overview

Notchline shows which sessions are working, waiting for you or completed. Hover to see monitored sessions, read previews, answer supported requests or return to the originating conversation. Displays without a notch use a compact pill. Currently supports Codex Desktop, Claude Code (Desktop + CLI) and Antigravity CLI, each at the tier it earns.

<p align="center">
  <img src="design/assets/07-readme/notchline-anatomy.png" width="880" alt="Notchline anatomy: the compact view with the status mark, session and subagent counts, project name, unread dot and elapsed timer; and the expanded view with the live session list grouped into one block per product, recent sessions and usage.">
</p>

<p align="center">
  <img src="design/assets/07-readme/notchline-answering.png" width="880" alt="Answering in the notch: a permission request with its labelled arguments and Deny and Approve, beside a question from a set of three, answered with a radio option and walked with Back and Next.">
</p>

## Motivation

My screens are already full of code editors, browser windows, and communication tools. I built Notchline to keep track of the coding agents buried behind them without repeatedly switching windows.

## Features

- **Live overview** — See monitored sessions in one list, ordered by urgency.
- **Content previews** — Read brief progress updates and answers alongside elapsed time and subagent activity.
- **Answers in the notch** — Respond to supported approval requests and questions directly in the panel.
- **Navigation** — Return to the originating conversation or terminal.
- **Recent sessions** — Revisit completed sessions cleared from the live list during the current app run.
- **Usage** — Check quota windows and today’s token usage for connected products.
- **Display settings** — Choose a display and adjust the compact overlay’s appearance.

## Supported products

Support is tiered, and each tier is a promise about what the notch does. Tiers are cumulative: a product sits at the highest tier whose every requirement it meets, and anything it cannot observe is declared rather than guessed.

| Tier | What the notch does | Products |
| --- | --- | --- |
| **0 — Listed** | A row appears when a turn starts, changes when the work ends, shows elapsed time, and takes you back to where it runs. Waits and request content are not detected. | Antigravity CLI |
| **1 — Attended** | Adds waits: the row shows when a session needs you and what it is waiting for, and stops asking once you deal with it in the product. | — |
| **2 — Answerable** | Adds answering: respond to supported approvals and questions from the notch, with a stale click unable to answer the wrong request. | Codex Desktop, Claude Code (Desktop + CLI) |

Capabilities are declared per product, independently of tier. Codex navigates to the exact Thread, names its actual Desktop Project and reports final answer text; Claude Code raises the host window or terminal tab, names the working directory, and reads quota from up to three windows. Antigravity CLI sits at Tier 0 and still titles its rows with what you asked and retires a finished row once you type in its terminal — read state is a capability, not a tier. Settings states each product's boundaries.

See the [tiered support plan](docs/technical-explorations/multi-product-provider-architecture/tiered-support.md) for the full requirements and capability list.

## Limitations

- **Existing activity** — Existing sessions appear only after a new lifecycle event establishes their state.
- **Side chats** — Temporary side chats do not appear as rows.
- **Claude Code navigation** — Exact session or terminal-tab selection is not always available, and full-screen hosts cannot be reached.
- **Antigravity CLI** — Tier 0: a row shows Running from a turn's first model call until it ends, titled with what you asked, with no approval or question detection. A finished row clears once you type in the terminal that conversation runs in, when the CLI process exits, or on a right-click; coming back to look without typing does not clear it, because the CLI does not ask its terminal to report focus.
- **Persistent history** — Recent sessions are temporary; there is no searchable archive or cross-device sync.
- **Compatibility** — Some features depend on undocumented product behaviour and may break after updates.

## Requirements & installation

Requires macOS 26.5 or later.

Place `Notchline.app` in Applications and open it.

> [!NOTE]
> **Notchline is not currently notarised**: if macOS blocks it, go to **System Settings → Privacy & Security → Open Anyway**, then confirm opening it ([Apple’s instructions](https://support.apple.com/en-ie/102445)).

To build from source, open `Notchline/Notchline.xcodeproj` in Xcode 26.6 or later and run the `Notchline` scheme. Optionally enable integrations during onboarding.

> [!NOTE]
> **Codex hooks require manual trust.** After enabling the Codex integration, use `/hooks` in Codex to trust Notchline’s hooks.

## Files and data

- **Product configuration** — Edits `~/.codex/hooks.json`, `~/.claude/settings.json` and `~/.gemini/config/hooks.json` when managing integrations, preserving unrelated settings and saving a `.notchline-backup` beside each existing file before changes.
- **Support files** — Creates hook helpers, local sockets and installation records under `~/Library/Application Support/Notchline/`.
- **Preferences** — Saves settings in `~/Library/Preferences/com.yinfenglu.Notchline.plist`.
- **Quota transcripts** — Claude Code quota checks create transcripts under `~/.claude/projects/`; Notchline shows their size in Settings and does not delete them.

See the [file inventory](docs/artifacts.md) for exact paths.

## How it works

```text
Coding agents → Product adapters → session state → Overlay
      ↑                                              │
      └────────── Navigation and answers ────────────┘
```

Product adapters collect local hook events and metadata, reduce them into session state and combine them into one snapshot for the overlay. User actions return to the originating product through navigation or a supported answer connection. Processing stays on your Mac.

## Next steps

The tier ladder is in place: a shared monitoring core handles turn starts and endings, and each product opts into wait detection, previews, navigation, read state, subagents, quota and answers. Next is adding further coding agents at the tier they earn, and raising Antigravity CLI if its hooks ever observe a wait. See the [architecture plan](docs/technical-explorations/multi-product-provider-architecture/README.md).

## Comparison with Open Island

[Open Island](https://github.com/Octane0411/open-vibe-island) is another native macOS notch companion. This summary is based on the [source comparison from 7 September 2026](docs/comparisons/notchline-and-open-island.md), which documents support boundaries and implementation details.

| Capability | Notchline | Open Island |
| --- | --- | --- |
| Shared features | Notch overlay, previews, supported request answers, Codex deep links and Recent | Same core features |
| Supported products | Codex Desktop, Claude Code (Desktop + CLI) and Antigravity CLI (Tier 0) | Also standalone Codex CLI, Cursor, Gemini CLI, OpenCode and more |
| Completed rows | Cleared using per-Thread read evidence | Visibility follows activity and process state |
| Codex Projects | Actual Desktop Project assignments and Chats | Working-directory names |
| Codex automatic approvals | Distinguishes automatic review from requests needing a person | No equivalent filter found |
| Subagent activity | Both products; tracks work continuing after the parent Turn ends | Claude detail list; cleared on parent completion |
| Usage | Quota windows and today's token totals | Quota windows; Claude readings depend on a terminal status-line cache |
| Turn timing | Elapsed time and finished duration | Activity age and Claude subagent timers |
| Navigation | Exact Codex Thread; Claude host, with Terminal.app/iTerm2 tab targeting | Additional terminal-pane and IDE workspace targets |
| Startup and history | New lifecycle events; Recent covers the current app run | Restores cached records and discovers existing conversations |
| Expanded list | Urgency ordering and brief content previews | Configurable grouping/sorting and more tool and work-item detail |
| Notifications | Compact status and a panel opened on hover | Automatic notification cards, sounds and haptics |
| Remote monitoring | Local observation | SSH setup for remote Claude Code |

## Project status

A solo side project in active development.

## Licence

Copyright © 2026 Yinfeng Lu. Licensed under [GPL-3.0-or-later](LICENSE), without warranty. See [LICENSE](LICENSE) for the full terms.
