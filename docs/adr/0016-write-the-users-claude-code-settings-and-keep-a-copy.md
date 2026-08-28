# Write the user's Claude Code settings, keeping a copy first

The app writes its own hook registration into `~/.claude/settings.json` directly, and takes it back out on request. The Claude Code row in Settings and in first-run therefore gets a switch, identical to the Codex row's.

**Before every write**, the file's current bytes are copied to `settings.json.notchline-backup` in the same directory.

This **supersedes [ADR 0010](0010-never-write-the-users-claude-code-settings.md)**, which said the app never writes this file and the user pastes it themselves. The paste card, `AgentManualSetup`, `configurationSnippet()` and `manualSetup()` are deleted with this decision.

## Why it reversed

ADR 0010's argument was never "we cannot" — it says outright that the writing version was implemented and passed its tests, and that what was missing was a product decision. It weighed the blast radius of one bad edit: `~/.codex/hooks.json` holds almost nothing but hooks, `~/.claude/settings.json` holds a user's entire Claude Code installation.

What that weighing underrated was a cost it recorded itself: **this was the only place Claude Code was harder to adopt than Codex**. It was written off as "a developer tool whose users already edit this file". The actual shape was not that:

- The user copies a dozen-event JSON block from a card and merges it by hand into a file that already has contents.
- **An incomplete paste fails silently.** ADR 0010 listed this and required `status()` to report `repairRequired` separately — but the app can only see it and say so, never fix it.
- **A stale shape is the user's job too.** After [ADR 0013](0013-claude-code-hooks-run-a-helper-not-a-port.md) moved handlers from `type: "http"` to `command`, every installed user had to go back and re-paste, and the app could not even delete the dead `http` handler — only recognise it and ask them to do it.
- Every new event in the vocabulary (`MessageDisplay` was one) means another re-paste.

So ADR 0010 converted an entire class of problems the app can fix, and knows how to fix, into manual labour — and **none of these problems raises an error**. It traded the risk of one bad edit for a permanent silent-failure channel.

## What makes writing acceptable

Not confidence: three things already in the code, plus one new one.

1. **Touch only our own keys.** `ManagedHooksConfiguration` adds and removes only handlers this app's identity marker recognises; the user's groups under the same event are preserved in place (we append at the tail only).
2. **Refuse what we cannot read; never coerce.** A root that is not an object, a `hooks` that is not an object, an event that is not an array of groups — all throw and stop before any write. The pre-ADR-0010 implementation overwrote an entire valid JSON file whose root was an array precisely because it coerced what it could not read into an empty dictionary.
3. **Compare bytes before writing and verify by reading back.** If the file changed under us during the read-modify-write, abandon the write and report `changedWhileEditing`; after writing, re-read to confirm the registration is complete, and error if not.
4. **New: keep a copy before every write.**

## Why the copy refreshes rather than being kept from the first write — **one rule for both products**

`ManagedHooksFileEditor` originally meant **write once, never refresh**, reasoning that the first copy predates all our edits and overwriting it with later state destroys the only version worth keeping.

This ADR first said that rule held for `~/.codex/hooks.json` and inverted for `~/.claude/settings.json`, treating refresh as a Claude Code special case. **That was wrong**, and the code never implemented it that way — `preserveRecoveryCopy(of:)` lives in the shared editor and both products have always taken the same path. Worked through again for both sides, refresh is right for both files, and the Codex reason is the harder one:

- **`~/.claude/settings.json`** holds the user's whole installation. Someone who enabled the switch six months ago and has since edited themes, permissions, environment variables and MCP servers will read `settings.json.notchline-backup` as "my file before this went wrong"; under write-once it is the file from six months ago, and restoring it is data loss caused by this app.
- **`~/.codex/hooks.json`**: Codex records trust by `<path>:<event>:<group index>:<handler index>` (measured 2026-08-20, and the origin of the append-at-tail rule). Restoring a copy from before this app's first edit does not merely discard definitions the user added since — **it shifts the group indices of the remaining ones, so trust on their own definitions silently lapses**, Codex stops running them, and nothing anywhere reports it. That is exactly the failure append-at-tail exists to prevent, entering by another door. **A stale `hooks.json` copy is more dangerous than a stale `settings.json` copy, not safer.**
- And write-once is incoherent for **a file this app created**: that write has no copy to keep, so it freezes at the state before this app's **second** edit — a version nobody can name.

The direction is therefore the same for both files: **what we wrote comes out cleanly when the switch goes off; the user's own edits are recoverable from nowhere else.** The copy refreshes, and its meaning is fixed as one sentence —

> your file as it was immediately before this app last changed it.

It is implemented by writing the bytes `write(_:replacing:)` just read and compared, rather than a second `copyItem`: one less read, and no window in which the copied version differs from the replaced one. It is written `.atomic`, so a crash mid-write leaves the previous copy rather than none. A failed copy fails the whole write — the copy exists before the user's file is touched.

**Files this app created get no copy.** Something that did not exist has no earlier version, and an empty copy would only mislead.

**Upgrade behaviour, recorded plainly:** the write-once copy an older version left beside `~/.codex/hooks.json` is replaced by the new semantics at the next write. That is intended — by the second point above, that older copy is exactly the one that should never be restored.

**But the rename left an orphan.** The copy's name derives from the app's name (`hooksConfiguration + ".notchline-backup"`); before the rename it was `hooks.json.codex-in-notch-backup`. This machine has one such file from 2026-08-12 in `~/.codex/`, and nothing in the code references that name any more: it is never refreshed and never read. **The app does not delete it** — it is a recovery copy inside the user's file space, and removing it is the user's call. The cost is that the directory may hold two copies with different meanings, only the newer of which is live.

## Costs, recorded plainly

- **The app now writes the central file of a user's Claude Code installation.** The four points above are the entire safeguard. The cases known to be refused rather than mangled are covered by tests (root not an object, `hooks` not an object, an unrecognised event shape), each requiring the file's bytes to be unchanged and no copy left behind.
- **One extra file each in `~/.claude/` and `~/.codex/`.** The user did not ask for them. They are this decision's price, and the footnote in Settings and first-run names **both** files — it previously named only the Claude Code one while the Codex copy was already being written, which was something that should have been said and was not. Each switch's tooltip names its own copy. Only the Claude Code completion message mentions the copy: the Codex one has to carry a mandatory next step (go and trust it via `/hooks`), and a second sentence would compete with it. What must reach the user is the notice **before** they flip the switch, and that is the footnote.
- **No `description` key.** The Codex side stamps a `description` on the root of a file it creates, as a note to whoever opens it; not here. Claude Code validates this file's keys, and the first thing this app does when creating that file for a user should not be to put a key it does not recognise in it. `descriptionForNewFiles` is therefore optional and Claude Code passes `nil`.
- **`repairRequired` stays as a state.** The app can now fix it, but an incomplete registration from an older version still means "the notch stays empty and nothing reports it" until the user flips the switch. So it is still reported separately rather than merged into "off". In that state the switch already reads as off (`isIntegrationEnabled` is false for `repairRequired`), so the wording is "turn the switch on"; whereas the "registered but not firing" diagnostic (`restoreDefinitionAdvice`) has the switch on, so its wording is "flip it" — `install()` writes nothing when the registration is already correct.
- **The Codex side needed no new safety mechanism, only the existing one stated and pinned.** This ADR first described the copy as a Claude Code addition; it actually lands in the shared `ManagedHooksFileEditor` and both products got it at once — and the Codex path had **no tests at all**. `theUsersCodexHooksAreCopiedBesideThemselvesBeforeEveryChange` and `aRefusedCodexInstallLeavesNeitherAnEditNorACopy` fill that in. Also checked: this editor is the only path by which the app writes a user's file (every other write is inside its own support directory), and Codex uninstall deleting the helper and socket looks like the opposite of ADR 0016's conclusion for Claude Code, but `AgentHookListener.start` compares inodes to decide whether it is already bound, so the next `prepareTransport()` rebinds after the socket file is deleted — a harmless redundancy, not a safety hole.
- **Uninstall still only takes back the registration.** The helper and socket stay in this app's own support directory: with the registration gone nothing will run them, and the refresh loop's `prepareTransport()` writes both back within a second. Deleting them here claims a tidiness it cannot deliver.

## Where it lands

`ClaudeCodeHookSetup.install()` / `uninstall()`, `ManagedHooksFileEditor.preserveRecoveryCopy(of:)`, `ClaudeCodeMonitorService.installHooks()` / `removeHooks()`, `MonitorStore`'s per-product switches (`integrationSwitchIsOnByAgent`, `setupStatusByAgent`, `integrationBusyAgents`, one convergence task per product), and `ProductConnectionRows`' two rows with two switches.

Tests: `bothProductsInstallTheirOwnRegistration`, `theUsersSettingsAreCopiedBesideThemselvesBeforeEveryChange`, `theUsersCodexHooksAreCopiedBesideThemselvesBeforeEveryChange`, `aRefusedCodexInstallLeavesNeitherAnEditNorACopy`, `installingTouchesOnlyThisAppsOwnKeysInTheUsersSettings`, `aSettingsShapeThisAppCannotReadIsRefusedRatherThanOverwritten`, `aPartialRegistrationReportsThatItNeedsRepair`, `eachProductsIntegrationSwitchMovesOnlyItsOwnProduct`.
