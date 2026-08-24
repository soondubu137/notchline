# Notchline

A macOS overlay in the notch (menu bar on notch-less displays) that watches **Codex Desktop** and **Claude Code (Desktop & TUI)** and shows which conversations need attention — waiting on input, waiting on an approval, still running, or finished and unread. Clicking a row returns to that conversation. It does not send input, approve anything, or manage sessions.

## What it looks like

Collapsed, it draws one 3×3 status matrix per connected product (Codex blue, Claude Code orange), animated per state:

<table>
<tr>
<td><img src="docs/assets/matrix-running.svg" width="260" alt="Running: a diagonal checkerboard sweep across the 3x3 grid"></td>
<td><img src="docs/assets/matrix-attention.svg" width="260" alt="Input needed or Approval needed: the centre cell flashes, then the ring flashes with it"></td>
</tr>
<tr>
<td><img src="docs/assets/matrix-completed.svg" width="260" alt="Completed: the whole grid breathes together, slowly"></td>
<td><img src="docs/assets/matrix-idle.svg" width="260" alt="Connected with no active turn: dim and static"></td>
</tr>
</table>

*(Animated SVG, sampled from the app's own keyframes. Hovering the notch drops down a list of watched conversations with project, title, a one-line preview, and elapsed time.)*

## Features

| Area | Behaviour |
| --- | --- |
| Live updates | Driven by Codex's and Claude Code's official Hooks — no polling, no screen scraping |
| State model | `Running`, `Input needed`, `Approval needed`, `Completed` — same four words for both products |
| Navigation | Click reopens the identical Codex thread; for Claude Code, activates its host app or terminal tab |
| Subagents | A finished parent turn with a subagent still working stays `Running`; a subagent stuck on approval surfaces as `Approval needed` |
| Read state | A finished row stays until the host shows it's been seen (unread marker, focus history, or terminal access time) — not a timer |
| Preview | One-line preview of the current question, progress, or answer start — no raw reasoning, commands, or diffs |
| Quota | A ring for the account's primary rate-limit window; greys out rather than showing stale data |
| Product distinction | Coloured name, plain name, badge, or colour bar — user's choice |
| Hide the wings | On displays with a measurable physical notch, collapses to just the notch silhouette |
| No history | Every restart starts empty; nothing is cached to disk |
| Permissions | No Accessibility, no Screen Recording; `LSUIElement` — no Dock icon, no ⌘-Tab, no menu bar |

## Limitations

| Limitation | Detail |
| --- | --- |
| macOS version | Requires macOS 26.5+ |
| No cold-start sync | Anything already running, finished, or waiting before launch stays invisible until its next event |
| Non-public Codex internals | Project names, unread state, and approval routing read from undocumented Desktop files; read-only, fails closed, can break on a Codex Desktop update |
| Exact navigation | Guaranteed for Codex only; Claude Code navigation activates the host, not a specific session |
| Claude Code read state | Inferred, not reported — a session with no host record and no controlling terminal only clears on its next submission or manual dismissal |
| Scope | One account, one machine — no sync, no history, no search |
| Hide the wings | Only available where the physical notch can be measured; greyed out elsewhere |
| No accessibility/screen-recording | By design — a few Claude Code edge cases are answered "unknown" rather than guessed |

## Project status

Solo project, feature-complete for an initial release. Not currently accepting pull requests.
