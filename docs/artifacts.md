# Files this app creates, edits and leaves behind

The 2026-09-12 [evidence-boundary refactor](product-generalisation-plan.md) creates no new production artifact and changes no managed path or registration bytes. `HookEvidenceBoundary` now owns the existing hook observation/trust writes; `MonitoringRepository` and a source using its typed entry alone create no configuration, helper, socket or persisted Turn state.

## 1. Files Notchline creates

All under `~/Library/Application Support/Notchline/`, namespaced per product (`agents/codex/`, `agents/claudeCode/`), so uninstalling one product's integration cannot delete the other's socket:

| File | Purpose | Written by |
| --- | --- | --- |
| `agents/<agent>/hook.sh` | The helper the product runs once per event, writing to the socket via `nc -U`. Mode `0700`; rewritten whenever its bytes differ from this build's version. It takes **one literal argument**: bare on a lifecycle event (`nc -w 1`, stdout thrown away), `wait` on the one event that asks a person (`nc -w` the product's own window, stdout carrying the app's answer back) — or, for a product whose payloads do not name their event (Antigravity CLI), the event's name, which the helper writes ahead of the payload on a line of its own. `NOTCHLINE_HOOKS_OFF` in the agent's environment exits before any of them | `ManagedHooksSetup`, `CodexHookRegistrar` |
| `agents/<agent>/hook.sock` | The Unix domain socket the listener binds. The path is kept deliberately short — `sun_path` caps at 104 bytes | `AgentHookListener.start()` |
| `agents/<agent>/install.json` | Two dates (`installedAt`, `lastEventAt`) and a list (`eventsAwaitingTrust`), mode `0600`. `lastEventAt` is written once per launch; `eventsAwaitingTrust` names the definitions this app rewrote and has not seen fire since, and shrinks by one as each of them arrives. `installedAt` is still written and still never read | `HookIntegration` |
| `agents/claudeCode/usage/` | An empty directory. It is only the fixed working directory for the app's own `claude -p /usage` runs, so the session registry and the hook store can tell those sessions from the user's | `ClaudeCodeUsageReader` |

Two more kinds of file are written **outside** the app's own directory — the user's product configuration:

| File | Notes |
| --- | --- |
| `~/.codex/hooks.json`, `~/.claude/settings.json`, `~/.gemini/config/hooks.json` | Edited in place, touching only this app's own keys — in the Antigravity file, one named hook of its own, `notchline`, beside the user's. Written atomically at mode `0600`, with a byte comparison before and a read-back after |
| `~/.codex/hooks.json.notchline-backup`, `~/.claude/settings.json.notchline-backup`, `~/.gemini/config/hooks.json.notchline-backup` | The user's file as it was immediately before this app last changed it — **refreshed on every write**, not kept from the first ([ADR 0016](adr/0016-write-the-users-claude-code-settings-and-keep-a-copy.md), `ManagedHooksFileEditor.preserveRecoveryCopy(of:)`) |

Preferences live in `~/Library/Preferences/com.yinfenglu.Notchline.plist`, with ten keys: `selectedDisplayID`, `privacyMode`, `hidesCompactWings` (`Hide Notchline`; the key kept its name through the rename), `namesWorkOnPill`, `drawsSurfaceOutline`, `groupsSessionsByProduct`, `quotaExpanded`, `quotaHiddenProducts`, `recentExpanded` and `hasCompletedOnboarding`. `quotaHiddenProducts` is the products switched off under Settings' `Quota table`, as an array of product identifiers, and is absent until one is switched off ([`quota-footer-v2.md`](quota-footer-v2.md) §13). `recentExpanded` remembers whether the Recent queue is open; like `quotaExpanded` it is absent until somebody opens that block, and the queue it governs is never itself persisted.

Sparkle keeps its own `SU…` keys in the same file; see [§ Updates](#updates).

**Further keys may be there and are never read.** `productAttribution` retired with the `Distinguish products` picker ([`colour-v2.md`](colour-v2.md) §6), `quotaFolded` with the footer's inverted default ([`quota-footer-v2.md`](quota-footer-v2.md) §8.1), and `aggregateInk` with the `Theme colour` picker itself — the app now draws one fixed ink (`NotchStatusMatrix.swift`'s `NotchPalette.themeInk`) rather than a stored choice. None is deleted from an install that has one. That is what "ignored rather than migrated" means on disk: reading a stale key back would be the migration the decision says there is not, and a plist key nothing reads costs nothing.

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


Generalisation package 5 adds no production artifact, preference or native configuration path. The explicit no-setup case creates no hook registration or helper. Disconnect/removal releases owned watcher descriptors and cancels source reads; it does not delete product records, transcripts or user files. Existing managed-file backup and narrow-edit rules are unchanged.


## Generalisation conformance follow-up (2026-09-12)

Request occurrence identities, selection, saved per-request drafts and question positions are process memory only. They are pruned with the live requests and rows and are never persisted. The generalisation follow-up adds no native configuration, helper, socket, file path or on-disk artefact.

## Trae companion artefacts

| Path | Purpose and owner | Removal |
| --- | --- | --- |
| `~/Library/Application Support/Notchline/agents/trae/<extensionHostPID>.sock` | Same-user socket, mode 0600, in a mode-0700 directory; created by each local companion, at most one observer | Clean extension deactivation removes its own endpoint; a crash may leave a stale socket, which is never treated as live |
| Trae’s managed extension storage: `notchline.trae-companion-1.2.3` | The VSIX installed by Trae’s extension CLI in its configured Extensions directory; JavaScript, manifest and the Notchline icon only | Trae’s CLI uninstalls this exact extension; if that CLI call fails, Notchline deletes this exact folder itself |
| System temporary directory: `notchline-trae-install-<UUID>/` | Notchline’s packaging staging and generated VSIX | Removed at the end of setup, including errors |

Notchline no longer keeps its own installation marker. Whether the companion is installed is read, every time, from `~/.trae/extensions/extensions.json` — Trae’s own record of what it has installed, not a path Notchline creates or owns. This file is read-only for every check; the one exception is removal. Trae 3.5.91’s own `--uninstall-extension` crashes on any installed extension (`Cannot read properties of undefined (reading 'isProtectedExtension')`, reproduced against a control extension unrelated to this companion), so when that CLI call fails, Notchline drops this extension’s one entry from `extensions.json` directly and deletes its folder above, leaving every other installed extension’s entry untouched. A companion removed by any means outside Notchline (its Extensions view, deleting the extension folder, this fallback) is reflected the next time Settings asks, rather than remembered as installed until this app’s own removal path runs.

The companion emits bounded local frames; production stores no transcript, native response capture, Thread list or progress log. It reads the four fingerprinted files listed in [trae-integration.md](trae-integration.md) and the product-owned renderer client. It edits no application resource, authentication file, workspace setting or Trae Hook definition.

## Product monitoring intent preferences

The existing preferences store now holds `productMonitoringIntent.codex`, `.claudeCode`, `.antigravity` and `.trae`, each `enabled` or `disabled`. These are user choices, never installation or connection evidence. No new marker file is created. Actual setup reads remain product-owned; Trae also reads its companion `package.json` beneath the extension manifest location. See [Product connection checks](product-connections.md).

## Updates

Sparkle ([ADR 0022](adr/0022-update-through-sparkle-signed-with-our-own-certificate.md)) writes these. Only a build with a public key starts it, and nothing is written while hosting tests.

| Location | Contents | Removed |
| --- | --- | --- |
| `~/Library/Preferences/com.yinfenglu.Notchline.plist` | `SUHasLaunchedBefore` and `SULastCheckTime`, written at the first launch, which checks at once. `SUUpdateGroupIdentifier` is written by a check that finds an update. `SUSkippedVersion` (and its major-version siblings) appears on Skip This Version. `SUEnableAutomaticChecks` and `SUAutomaticallyUpdate` appear once Settings → Updates' two switches are moved. Notchline's own two: `updateCheckAnsweredAt`, when a check last got an answer from the feed, and `updateReceiptBuild`, the build a relaunch is about to install, removed once that build's About has been closed (`updates-on-the-notch.md` §9) | Never |
| `~/Library/Caches/com.yinfenglu.Notchline/` | `org.sparkle-project.Sparkle/`, holding the downloaded archive and its extraction while an update is prepared, plus `URLSession`'s `Cache.db`. After an install, the rehearsal left the empty `Installation/` and `PersistentDownloads/` directories and 124 KB in total | Sparkle empties its own directories; the system may purge caches at any time |
| `~/Library/HTTPStorages/com.yinfenglu.Notchline/` | `URLSession`'s cookie store for the feed request | Never |

Replacing the bundle keeps its path, so nothing else in this inventory moves: hook helpers are rewritten when their bytes differ from the new build's, and the sockets and records under `Application Support` are the new build's to reuse.

The repository carries two related files the app never writes: `appcast.xml`, the feed every copy reads from `master`, and `scripts/release/designated-requirement.txt`, the requirement every release must satisfy.

## Codex CLI extension (2026-09-15)

No additional persistent artefact is created. Desktop and local CLI share the existing Codex helper, socket, registration and `~/.codex/hooks.json`; three lifecycle definitions are appended. Process identities and Thread owners are memory-only and cleared on disconnect. The adapter reads open-file paths to identify `.codex/state_5.sqlite` but never opens, parses or writes that database. No launcher, wrapper, daemon or terminal profile is installed.
