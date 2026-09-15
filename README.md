<p align="center">
  <img src="design/assets/03-stacked/notchline-stacked-white-1024.png" width="180" alt="Notchline">
</p>
<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2026.5%2B-lightgrey" alt="macOS 26.5 or later">
  <img src="https://img.shields.io/badge/built%20with-SwiftUI%20%2B%20AppKit-orange" alt="SwiftUI and AppKit">
  <img src="https://img.shields.io/badge/status-in%20development-yellow" alt="In development">
  <img src="https://img.shields.io/badge/version-0.5.3-blue" alt="Version 0.5.3">
  <img src="https://img.shields.io/badge/licence-GPL--3.0--or--later-green" alt="Licensed under GPL 3.0 or later">
</p>

[简体中文](README.zh-CN.md)

**Notchline keeps coding agent activity reachable at your Mac’s notch.**

<p align="center">
  <img src="design/assets/07-readme/notchline-hero.webp" width="100%" alt="Notchline showing coding agent activity and answering questions from the notch.">
</p>

## Overview and Motivation

My screens are already full of editors, browsers and communication tools. Notchline keeps coding agent activity visible without repeatedly switching windows: hover to inspect conversations, answer supported requests or jump back. Displays without a notch use a compact pill.

## Key Features

- **Live overview** — Urgency ordering, progress previews, elapsed time and subagent activity.
- **Answers and navigation** — Handle supported requests or return to their conversation.
- **Read removal and Recent** — Clear completed rows on read evidence and revisit them during the current app run.
- **Usage and privacy** — Product quota and daily tokens where supported; Privacy Mode covers text.

## Supported Products

| [Cumulative level](docs/product-support.md) | Adds within the declared modes and request forms |
| --- | --- |
| **L1 — Lifecycle monitoring** | Turn start/end, elapsed time and manual dismissal |
| **L2 — Context identification** | Project names and Thread titles |
| **L3 — Progress monitoring** | Current-Turn progress |
| **L4 — Wait detection** | Approval/input waits and their resolution |
| **L5 — Request reading** | Commands, questions, options and documents |
| **L6 — Request answering** | Answers through valid connections, with stale-answer protection |

| Product | Level | Extra capabilities (independent of level) | Boundaries |
| --- | --- | --- | --- |
| **Codex Desktop** | **L6**: ordinary approvals | Exact Thread navigation, Desktop Projects/read removal, final-answer previews, subagents, quota and daily tokens | Standalone CLI excluded; synchronous questions and `request_permissions` reading-only; asynchronous questions preview-only |
| **Claude Code (Desktop + CLI)** | **L6**: tool/plan approvals and question sets | Folder-based Projects, conditional Desktop/terminal read removal, host/tab navigation, subagents, quota and daily tokens | No final-answer preview; exact navigation depends on host, full-screen hosts unreachable |
| **Antigravity (Desktop + CLI)** | **L3** | Desktop Projects, conditional Desktop/terminal read removal, host navigation and final-answer previews | No waits, requests, quota, tokens or subagents; progress can wait for tools; Desktop Stop may leave a working row; CLI read removal needs typing/pasting, not tab focus |
| **Trae Desktop (local IDE/V2)** | **L5**: ordinary commands and structured questions | Exact observed Thread navigation, conditional visible-completion read removal, retained root text | Verified 3.5.91 build only; answer in Trae; no quota, tokens or subagents; IDE-hosted SOLO outside L5, standalone SoloLite, remote, Plan/Spec and rich permissions excluded ([scope](docs/trae-integration.md)) |

| [Terminal host](docs/tech-design.md#142-raising-the-host-claude-code) for Claude Code / Antigravity CLI | Return navigation | Read removal after completion (foreground host, unlocked screen) |
| --- | --- | --- |
| **Terminal.app** | Select matching tab; requires Automation permission | Conditional on terminal input evidence; focus/pointer gestures depend on what the product and terminal report |
| **iTerm2** | Select matching window, tab and pane; requires Automation permission | Same terminal-input conditions as Terminal.app |
| **Ghostty 1.3.1** | Raise app; no exact tab/pane selection | Claude Code: typing/paste, focus or pointer gestures; Antigravity: typing/paste only |
| **kitty, WezTerm, Alacritty, VS Code terminal** | Raise host if identifiable; no exact tab/pane selection | Shared terminal-evidence path; individual host combinations unverified |
| **tmux, screen, SSH, pipes** | No dedicated return target | Unsupported |

## General Limitations

- Remote agent monitoring, including agents running on SSH hosts, is not supported.
- No pre-launch Turn recovery or temporary side-chat rows; start a new Turn after connecting.
- Recent lasts only until the app quits; no persistent archive or cross-device sync.
- Read removal depends on trustworthy evidence; dismissal removes only the row, never the conversation.
- Undocumented product behaviour can change after updates; answers require a valid request connection.

## Requirements, Installation, and Development

Requires **macOS 26.5+**. Move `Notchline.app` to Applications and open it. It is not notarised; if blocked, use **System Settings → Privacy & Security → Open Anyway** ([instructions](https://support.apple.com/en-ie/102445)). That is needed once: Notchline checks for updates daily, or from **About → Check for Updates**, and installs them in place without asking again.

Enable products in onboarding or Settings. Trust Codex hooks using `/hooks`. Enabling Trae installs its companion; reopen Trae’s windows afterwards.

With **Xcode 26.6+**, open `Notchline/Notchline.xcodeproj` and select the **Notchline** scheme:

- **Debug:** in **Product → Scheme → Edit Scheme → Run**, select **Debug**, then **Product → Run** (⌘R).
- **Release:** set **Run → Build Configuration** to **Release**, then **Product → Build** (⌘B). Find `Notchline.app` under **Products → Show in Finder**. Use **Product → Archive** for an archive, with its configuration set to **Release**.

## Files and Data

| Location | Use |
| --- | --- |
| `~/.codex/hooks.json`, `~/.claude/settings.json`, `~/.gemini/config/hooks.json` | Managed hook entries; unrelated settings preserved, existing files backed up beside them as `.notchline-backup` |
| Trae’s extension storage | Installs/removes `notchline.trae-companion`; removal may also edit its entry in `~/.trae/extensions/extensions.json` |
| `~/Library/Application Support/Notchline/` | Helpers, local sockets and installation records |
| `~/Library/Preferences/com.yinfenglu.Notchline.plist` | Preferences, including the updater's |
| `~/Library/Caches/com.yinfenglu.Notchline/` | Update downloads while one is prepared |
| `~/.claude/projects/` | Quota-check transcripts; size shown in Settings, never deleted by Notchline |
| Memory only | Monitored state, previews and Recent; [full file inventory](docs/artifacts.md) |

## How it works

Each product’s Provider coordinates its local evidence sources, which feed typed events into one shared Turn reducer. The refactored runtime composes lifecycle, content, read evidence and usage; Codex retains its own orchestration for App Server alongside hooks. The overlay renders one `MonitorSnapshot`, with navigation and supported answers routed back to the originating product ([architecture](docs/system-architecture.md)).

## Project status

A solo side project in active development.

## Licence

Copyright © 2026 Yinfeng Lu. Licensed under [GPL-3.0-or-later](LICENSE), without warranty. See [LICENSE](LICENSE) for the full terms.
