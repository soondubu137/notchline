# Files this app creates, edits and leaves behind

## 1. Files Notchline creates

All under `~/Library/Application Support/Notchline/`, namespaced per product (`agents/codex/`, `agents/claudeCode/`), so uninstalling one product's integration cannot delete the other's socket:

| File | Purpose | Written by |
| --- | --- | --- |
| `agents/<agent>/hook.sh` | The helper the product runs once per event, writing to the socket via `nc -U`. Mode `0700`; rewritten whenever its bytes differ from this build's version. It takes **one literal argument**: bare on a lifecycle event (`nc -w 1`, stdout thrown away), `wait` on the one event that asks a person (`nc -w` the product's own window, stdout carrying the app's answer back). `NOTCHLINE_HOOKS_OFF` in the agent's environment exits before either | `ClaudeCodeHookSetup.install()`, `CodexHookRegistrar` |
| `agents/<agent>/hook.sock` | The Unix domain socket the listener binds. The path is kept deliberately short — `sun_path` caps at 104 bytes | `AgentHookListener.start()` |
| `agents/<agent>/install.json` | Two dates (`installedAt`, `lastEventAt`) and a list (`eventsAwaitingTrust`), mode `0600`. `lastEventAt` is written once per launch; `eventsAwaitingTrust` names the definitions this app rewrote and has not seen fire since, and shrinks by one as each of them arrives. `installedAt` is still written and still never read | `HookIntegration` |
| `agents/claudeCode/usage/` | An empty directory. It is only the fixed working directory for the app's own `claude -p /usage` runs, so the session registry and the hook store can tell those sessions from the user's | `ClaudeCodeUsageReader` |

Two more kinds of file are written **outside** the app's own directory — the user's product configuration:

| File | Notes |
| --- | --- |
| `~/.codex/hooks.json`, `~/.claude/settings.json` | Edited in place, touching only this app's own keys. Written atomically at mode `0600`, with a byte comparison before and a read-back after |
| `~/.codex/hooks.json.notchline-backup`, `~/.claude/settings.json.notchline-backup` | The user's file as it was immediately before this app last changed it — **refreshed on every write**, not kept from the first ([ADR 0016](adr/0016-write-the-users-claude-code-settings-and-keep-a-copy.md), `ManagedHooksFileEditor.preserveRecoveryCopy(of:)`) |

Preferences live in `~/Library/Preferences/com.yinfenglu.Notchline.plist`, with nine keys: `selectedDisplayID`, `aggregateInk`, `hidesCompactWings`, `namesWorkOnPill`, `drawsSurfaceOutline`, `quotaExpanded`, `recentExpanded`, `hasCompletedOnboarding` and `answerChord`. `answerChord` is the panel's global chord as `keyCode:modifiers` — a **position on the keyboard** and the modifier flags held with it, never a character, so the letter it is drawn as belongs to whichever layout is in front when the settings row is read ([`answer-in-notch.md`](answer-in-notch.md) §9.3). It is absent until somebody changes the chord, and an unreadable value is treated as absent: the default is `⌥Space`, and a spelling this build cannot parse is not a chord anybody chose. `recentExpanded` remembers whether the Recent queue is open; like `quotaExpanded` it is absent until somebody opens that block, and the queue it governs is never itself persisted.

**An eighth key may be there and is never read.** `productAttribution` retired with the `Distinguish products` picker ([`colour-v2.md`](colour-v2.md) §6) and `quotaFolded` with the footer's inverted default ([`quota-footer-v2.md`](quota-footer-v2.md) §8.1); neither is deleted from an install that has one. That is what "ignored rather than migrated" means on disk: reading a stale key back would be the migration the decision says there is not, and a plist key nothing reads costs nothing.

Hook payloads are never written to disk at all — they go straight into the in-memory reducer, so there is no preview cache, event queue or session state file ([ADR 0015](adr/0015-hook-events-go-straight-into-the-reducer.md)).

## 2. The one thing that grows: quota-read transcripts

```
~/.claude/projects/-Users-<you>-Library-Application-Support-Notchline-agents-claudeCode-usage/
```

Every quota read is a real Claude Code session, so Claude Code files a roughly 3.4 KB `.jsonl` transcript per read in its own project tree. At the current `freshness` of 1800 seconds that is one read every 30 minutes, about **160 KB a day** while the app runs. Measured on this machine 2026-08-28: **72 files, 284 KB**.

Notchline measures the folder and **never deletes it** — the folder-naming rule flattens both path separators and spaces, so `…/a b` and `…/a-b` land in the same directory, and that directory may hold the user's real work. Settings shows the size and offers a `Show in Finder` folder button; what to do about it is the user's call (`ClaudeCodeUsageTranscripts`, `SettingsWindow`).

The Codex side leaves nothing equivalent: it reads quota over `codex app-server`'s read-only `account/*` RPCs and creates no conversation.

## 3. One thing worth knowing

`~/Library/Application Support/Notchline/current-activity.json` and `current-activity.lock`, both dated 14 August, are still in the support directory. **Nothing in the working tree reads or writes them**, and they are not in the `retiredArtifacts` deletion list (`HookIntegration.AgentPaths.retiredArtifacts`) — leftovers from an older build that neither install nor uninstall cleans up. They are small (258 bytes and 0 bytes), harmless, and survive uninstallation.

Separately, `default.profraw` in the repository root is a coverage artefact from running an instrumented binary, not something the shipped app produces.
