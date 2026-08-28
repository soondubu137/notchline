# The Codex hook definition is never rewritten once written

The definitions this app registers in `~/.codex/hooks.json` — seven of them today — **never change their content after first installation**. Changing behaviour means changing the script a definition points at, not the definition.

## Why

Codex records trust by hashing definition content, under `[hooks.state."<hooks.json path>:<event>:<group>:<handler>"]` in `config.toml`. Change the content and Codex **silently stops executing that definition** until the user trusts it again via `/hooks`; every untouched definition keeps its hash and keeps firing.

**This app cannot see that failure.** The evidence "have we ever received an event" is satisfied by the definitions still working, the UI keeps showing Connected, and the user is told nothing. Measured 2026-08-15: `PreToolUse` did not fire at all for two consecutive Turns, with nothing wrong on screen.

So versioning moves entirely into the **script**, which is not hashed. The definition carries a stable path and nothing else — no version number, no port, no token, no parameter that could ever need to change.

```json
{"type": "command", "command": "/bin/sh '<support>/agents/codex/hook.sh'", "timeout": 3}
```

The upgrade path is therefore "overwrite `hook.sh` with this version's contents", `hooks.json` untouched to the byte, and no re-trusting.

## Measured: the trust key's third segment is an array index

Read from this machine's `config.toml`, 2026-08-20:

```toml
[hooks.state."/Users/…/.codex/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:e304ee0f…"
```

The event name is snake case, the third segment is the **group's index within that event's array**, and the fourth is the handler's index within the group. **This turns two merge rules from tidiness into something that carries the user's own definitions:**

1. **Append at the tail only, remove from the tail only.** This app's group always sits last in each event. Removing a group from the middle renumbers every group after it, so **the user's own** definitions silently lose trust.
2. **An already correct installation writes nothing.** With `isFullyInstalled` true, `install()` returns immediately. Previously, flipping the master switch rewrote — and reordered — a file that was already correct.

Both are pinned by `registrationMergesAtTheTailAndAnAlreadyCorrectInstallWritesNothing`.

## Considered and rejected

**Inline the helper into the definition.** Codex parses `command` with a shell, so the whole helper fits on one line:

```
/usr/bin/nc -U '<path>/hook.sock' >/dev/null 2>&1; echo '{}'
```

No script file to write, upgrade or validate; installation health collapses to "is this exact string present"; and what the user reviews in `/hooks` is what will actually run, rather than the path to an opaque file.

**Rejected, narrowly.** The script file is the one layer of indirection that lets behaviour change while the definition does not. Inlining trades away this app's only upgrade path that avoids re-trusting, for one fewer file. Worth reconsidering only once the helper's behaviour is declared final.

**Read `[hooks.state]` from `config.toml` and report each definition's trust directly.** This replaces inference-from-silence with an exact answer. Rejected: it is a private schema dependency requiring an entry in [`non-public-codex-integration-features.md`](../non-public-codex-integration-features.md), it breaks on Codex updates, and it buys only a better diagnostic for a state this decision has largely eliminated. If the silence probe below proves insufficient this is the next step, and it is an ADR-level decision in its own right.

## Costs

**One re-trust at migration.** The definition changes from a Python command line to `/bin/sh '…/hook.sh'`; that once is unavoidable and is precisely the once that buys "never again". The old Python command line is kept as the single legacy identity marker (matching the filename `codex_in_notch_hook.py`, so both the pre- and post-namespacing paths are recognised), which makes an existing installation read as `mismatched` rather than `absent` — the user is asked to repair rather than told "you have not installed it", which would make them paste a second copy beside the first.

**The silence probe stays.** "Since launch, ≥3 `PostToolUse` and 0 `PreToolUse` ⇒ `PreToolUse` is registered but not firing" is still the only run-time evidence of lost trust that is visible at all. This decision closes the path by which the app itself caused that state; a user editing `config.toml` by hand, or a Codex update re-hashing, can still reach it. Only implications where **absence really is evidence** may join that table: `PermissionRequest` fires only when someone is asked, so its silence proves nothing and it must never be probed.

**That probe computed correctly and propagated correctly, but no view read it** — so its claim to be the only visible evidence held for a while only in the code (CR-029). It now appears in Settings beneath that product's row. The sentence itself also changed: it used to name Codex and `/hooks` from inside a reducer shared by both products, which is wrong advice for Claude Code, where there is no trust step and no hash to lose. Each product now supplies its own vocabulary. Claude Code's used to read "check whether PreToolUse is still in `~/.claude/settings.json`"; after [ADR 0016](0016-write-the-users-claude-code-settings-and-keep-a-copy.md) it reads "flip that switch" — the repair moved from the user's edit to this app's write, and the sentence followed.

## Status

Implemented. `CodexHookRegistrar` writes the definitions and the script; `ManagedHooksFileEditor.install()` carries the no-op guard. Tests: `theRegisteredDefinitionCarriesNothingThatCouldEverNeedToChange`, `registrationMergesAtTheTailAndAnAlreadyCorrectInstallWritesNothing`, `installingOverAnEarlierVersionsRegistrationReplacesIt`, `closesWithoutOpensReportTheUntrustedPreToolUseHook`.
