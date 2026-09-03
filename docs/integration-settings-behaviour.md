# What the integration switches actually do

## 1. Turning the Codex switch on

`ProductConnectionRows` binds to `MonitorStore.setIntegrationEnabled(true, for: .codex)`. That call only records intent; each product's own convergence task applies it, re-reading the target state after every step, so rapid toggling coalesces and the last flip wins. Convergence calls `LiveCodexMonitorService.installHooks()` → `CodexHookRegistrar.install()`:

1. **No-op guard** — with registration already `.complete`, nothing is written. A rewrite would not only reformat a file that is not ours, it would *renumber the hook groups*: Codex keys trust on `<path>:<event>:<group index>:<handler index>`, so a rewrite silently invalidates definitions the user had already trusted ([ADR 0014](adr/0014-the-codex-hook-definition-is-never-rewritten.md)).
2. **Helper script** — creates `~/Library/Application Support/…/agents/codex/` at `0700` and writes `hook.sh`, also `0700`. The four-line script hands the payload to `hook.sock` in the same directory.
3. **Edit the file** — `ManagedHooksFileEditor` does a read-modify-write on `~/.codex/hooks.json`: *before every write*, copy the bytes just read to `hooks.json.notchline-backup` (`0600`); remove every current or legacy handler of ours; append one group per managed event at the tail; write atomically at `0600`; re-read and verify. It refuses rather than coerces when the root is not an object, an event's value is not an array, or the bytes changed during the edit.
4. **Seven definitions**, all without a matcher: `UserPromptSubmit`, `PermissionRequest`, `SubagentStart`, `SubagentStop`, `PreToolUse`, `PostToolUse`, `Stop`. The handler is `{"type":"command","command":"/bin/sh '<helper>'","timeout":3}`.
5. Writes `installedAt` into `install.json`, deletes retired artefacts, then has `prepareTransport()` bind the socket listener immediately, so the first Turn after setup does not wait for the next refresh.

Codex still *runs* nothing until the user trusts the definitions via `/hooks` — which is what `lastIntegrationMessage` says on a successful install.

## 2. Turning the Claude Code switch on

Same store path and convergence, different service: `ClaudeCodeHookSetup.install()`.

- The helper script is written first; if that fails, **the whole install aborts** (`verificationFailed`) — a registration pointing at a script that does not exist prints `ENOENT … posix_spawn` once per event.
- Then *the same* strict editor handles `~/.claude/settings.json`, with the same backup rule (`settings.json.notchline-backup`), byte-equality guard and read-back verification as Codex.
- **Thirteen definitions**: `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`, `Elicitation`, `ElicitationResult`, `SubagentStart`, `SubagentStop`, `MessageDisplay`, `Stop`, `StopFailure`. Handlers carry `args: []` to select Claude Code's exec form (one process launched; measured 6.3 ms against 10.9 ms for the other form). No `description` key is written even in a file this app created, because Claude Code validates these keys.
- A pre-ADR-0013 `http` handler is recognised by its `/codex-in-notch/hook` marker and **removed** while the current handler is written.
- There is no trust step. The socket binds at the next refresh's `prepareTransport()`.

> Count these in `HookIntegration.swift`'s two `managedDefinitions`, never from prose: this line has read six, five, eleven and twelve at various times, and each was a document lagging an event being added.

## 3. Turning either switch off

Convergence calls `removeIntegrationAndWait` → `service.removeHooks()`.

- **Both products**: the editor removes every handler of that product from every parsable event (removal is never strict about events, so an odd event elsewhere cannot block an uninstall); the backup is refreshed first; all handlers are verified gone; and `unremovableManagedCommand` is thrown if a marker survives anywhere in the document.
- **Codex additionally**: resets hook observations and clears Turns; stops the listener; deletes the helper, `install.json`, the socket and retired artefacts; removes directories that are now empty; and clears the observed Desktop pid, tracked threads, refresh tasks and gates, and `lastTrustedSnapshot`.
- **Claude Code deliberately keeps** its helper and socket — with the registration gone nothing will run them, and the refresh loop rewrites both within a second.
- The store then records a synthetic snapshot **for that product only**: `.setupRequired`, no threads, quota unavailable, `setupStatus: .notInstalled`, presence preserved. Replacing the key rather than removing it is what stops one product's uninstall taking the other product's rows off the notch too.
- If removal throws, the switch springs back (`setSwitch(!desired)`) and the error goes to `lastIntegrationMessage`. The switch is disabled while the operation runs.

## 4. How `Connected` is decided

From two independent facts, projected by `HookSetupStatus.card(registration:hasObservedEvent:)` and then crossed with integration availability in `ProductSettingsCopy`.

- **Registration status** comes from a pure file read: `complete` / `mismatched` / `absent`.
- **Event delivery**: for Codex, whether a hook event has *ever* reached the reducer (`hasObservedEvent`), seeded at launch from `lastEventAt` in `install.json` and set true once a payload lands. Claude Code always passes `hasObservedEvent: true`, since it has no trust step and therefore cannot be "registered but never trusted".
- **The Codex row** shows `Connected · compatible version` when setup is `.active` (or `.reviewRequired`) **and** integration availability is `.ready`. `.ready` requires the setup gate to pass, the `codex app-server --listen stdio://` subprocess to start, and the `initialize` handshake to answer; a branch carrying thread rows additionally requires observed live hooks whose Desktop pid matches a running process.
- **The Claude Code row** shows `Connected · hooks installed` when setup is `.active` **and** integration availability is not `.disconnected`. It used to read `setup.status()` alone, which is a statement about the registration and not about being able to watch anything: on a machine where the session list cannot be read the notch drew no Claude Code mark and no row ever appeared, while this row said `Connected · hooks installed` throughout. The two now agree, because `ClaudeCodeMonitorService` reports `.disconnected` whenever presence is `unknown` — see §6.

Two things about this row logic are worth flagging:

- The Codex row reads `store.availability`, the **merged** integration availability, while the Claude Code row reads `store.agentAvailability(for:)`. The merge is "ready if *any* product is ready", so when Claude Code is ready the Codex row can show `Connected · compatible version` on Claude Code's evidence.
- `.reviewRequired` (Codex hooks written but never trusted in `/hooks`) does not surface in this row: it passes the `notInstalled` / `repairRequired` checks and falls through to the availability branch, so it also reads `Connected · compatible version`. Its own wording, `Installed; trust it under /hooks in Codex`, exists only in `HookSetupStatus.displayName` for other callers.

## 5. How `compatible version` is decided

It is simply `.ready`'s label — there is no separate version probe. The meaning is carried by its opposite: an App Server request answering JSON-RPC **-32601, method not found** sets `.unsupportedVersion` (`Version unsupported`). So `compatible version` means the App Server started, answered `initialize`, and has not yet refused a method this app needs.

`Update Codex Desktop` (`.updateAgent`) is unreachable copy — no live service produces that case; only consumers reference it.

## 6. Every other state

| Shown | Set when |
| --- | --- |
| `Integration is off` (both products) | Registration `.absent` → `.notInstalled`: no marker of ours anywhere in the document. Also covers a file that is missing, empty, unreadable, or whose root is not an object |
| `Integration needs repair` (Codex) / `Registration is out of date · turn the switch on to rewrite it` (Claude Code) | Registration `.mismatched`: a current or legacy marker exists, but not every managed event has exactly one **current-version** handler. "Current version" means the whole dictionary equals what this build writes, so a stale `timeout`, an extra or missing key, an old helper path, a duplicated group, or a legacy `http` handler all land here |
| `Connecting…` (Codex) | `.connecting`: a transient App Server failure with no last-trustworthy snapshot to hold; also the merged default before any product has answered |
| `Disconnected` (Codex) | A non-transient failure — executable not found, launch failed, protocol violation, connection dropped — or a transient failure before the server has ever answered |
| Presence `unknown` (Claude Code) | `ClaudeCodeSessionRegistry` has no reading to offer: three consecutive failed `claude agents --json` attempts a `freshness` apart, or none ever answered. `closed` is not this and must never be caught by it — that is the command answering that nothing is open, which is a healthy machine with no session running |
| `Registered · not watching Claude Code` (Claude Code) | `.active` + `.disconnected`, which for this product is **three** different failures, all of them meaning the hooks are registered and nothing is being watched. (1) `prepareTransport()` returned `false`: the helper could not be written or the socket could not be bound, whether the folder is unwritable or another instance of the app already holds it. (2) Presence is `unknown` and **no `claude` executable exists** to run `claude agents --json`. (3) Presence is `unknown` with an executable that is there and will not answer. The headline names none of the three on purpose — each writes its own diagnostic, and that sentence is drawn directly underneath it |
| Extra grey text beneath the status | `latestByAgent[agent]?.diagnostic` — what that product reported this refresh; absent when nothing is wrong |
| The switch's own position | After every refresh `applyIntegrationHealth` re-derives it from `setupStatus.isIntegrationEnabled` — on for `active` / `reviewRequired`, off for `notInstalled` / `repairRequired` — except while a change is in flight. This is what makes "turn the switch on to rewrite it" coherent: with a stale registration the switch genuinely reads as off |
| `Recheck` | Calls `store.refreshNow()`; the Codex path first discards the cached registration read, because a deliberate re-check is one of the two moments registration health may have changed without this app doing it |
