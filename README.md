<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="design/assets/07-readme/notchline-readme-header-dark.png">
    <img src="design/assets/07-readme/notchline-readme-header.png" width="340" alt="Notchline">
  </picture>
</p>
<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2026.5%2B-lightgrey" alt="macOS 26.5 or later">
  <img src="https://img.shields.io/badge/built%20with-SwiftUI%20%2B%20AppKit-orange" alt="SwiftUI and AppKit">
  <img src="https://img.shields.io/badge/dependencies-none-blue" alt="No third-party dependencies">
</p>

**Notchline keeps Codex Desktop and Claude Code activity visible at your Mac’s notch.**

## Overview

Notchline shows which Turns are working, waiting for you or completed. Hover to see Threads from both products, read previews, answer supported requests or return to the originating conversation. Displays without a notch use a compact pill.

## Motivation

My screen is already full of editors, documentation, product pages and communication tools. I built Notchline to keep track of the conversations buried behind them without repeatedly switching windows.

## Features

- **Live overview** — See Threads from both products in one list, ordered by urgency.
- **Content previews** — Read brief progress updates and answers alongside elapsed time and subagent activity.
- **Answers in the notch** — Respond to supported approval requests and questions directly in the panel.
- **Thread navigation** — Return to the originating Codex Thread, Claude Desktop or terminal.
- **Recent Threads** — Revisit completed Threads cleared from the live list during the current app run.
- **Usage** — Check quota windows and today’s token usage for both products.
- **Display settings** — Choose a display and adjust the compact overlay’s appearance.

## Limitations

- **Existing activity** — Turns predating launch appear only after a new lifecycle event establishes their state.
- **Side chats** — Temporary side chats in either product do not appear as rows.
- **Claude Code navigation** — Exact Thread or terminal-tab selection is not always available, and full-screen hosts cannot be reached.
- **Persistent history** — Recent Threads are temporary; there is no searchable archive or cross-device sync.
- **Compatibility** — Some features depend on undocumented product behaviour and may break after updates.

## Requirements & installation

Requires macOS 26.5 or later and Codex Desktop with the `codex` CLI, or Claude Code with the `claude` CLI.

Place `Notchline.app` in Applications and open it. **Notchline is not currently notarised**: if macOS blocks it, go to **System Settings → Privacy & Security → Open Anyway**, then confirm opening it ([Apple’s instructions](https://support.apple.com/en-ie/102445)).

To build from source, open `Notchline/Notchline.xcodeproj` in Xcode 26.6 or later and run the `Notchline` scheme. Enable the products you use during onboarding; Codex also requires trusting the hooks through `/hooks`.

## Files and data

- **Product configuration** — Edits `~/.codex/hooks.json` and `~/.claude/settings.json` when managing integrations, preserving unrelated settings and saving a `.notchline-backup` beside each existing file before changes.
- **Support files** — Creates hook helpers, local sockets and installation records under `~/Library/Application Support/Notchline/`.
- **Preferences** — Saves settings in `~/Library/Preferences/com.yinfenglu.Notchline.plist`.
- **Quota transcripts** — Claude Code quota checks create transcripts under `~/.claude/projects/`; Notchline shows their size in Settings and does not delete them.

See the [file inventory](docs/artifacts.md) for exact paths.

## How it works

Product adapters collect local hook events and metadata, reduce them into Thread state and combine them into one snapshot for the overlay. User actions return to the originating product through navigation or a supported answer connection. Processing stays on your Mac.

## Project status

A solo side project in active development.

## Licence

No open-source licence. All rights reserved; no permission is granted to use, copy, modify or distribute the source.
