# Claude Code hooks run a helper, not a port

Claude Code lifecycle events used to be POSTed by a `type: "http"` handler to `127.0.0.1:51741`. They now run a `type: "command"` handler that executes a helper the app writes into its own support directory, which hands the payload down a 0600 Unix domain socket.

## Why it changed

A port has two faults, **neither fixable by registration** — at the time the app did not write the user's `settings.json` ([ADR 0010](0010-never-write-the-users-claude-code-settings.md), later superseded by [ADR 0016](0016-write-the-users-claude-code-settings-and-keep-a-copy.md)). Taking writing back does not fix them either: they are properties of the port itself and only disappear with the helper.

**One: while the app is not running the port belongs to nobody, so every event prints a line in the user's session.** Measured on CLI 2.1.237, a pty-driven interactive session, one prompt and two tool calls: an `http` registration pointing at an unlistened port printed **9 lines** of `<event> hook error / connect ECONNREFUSED`. The renderer returns `null` only for `Stop` and `SubagentStop` and prints everything else, and **no setting or environment variable turns it off** (`suppressHook`, `hideHook`, `HOOK_SILENT`, `DISABLE_HOOK`, `quietHooks` all checked, none exists; `suppressOutput` is a field in the hook's **reply**, unreachable when the connection is refused). This is §9's NO-GO — "an `http` hook has any visible effect on the user's session while the app is not running" — and it holds for **every** event, not only `SessionEnd`.

**Two: an unoccupied port can be taken, and the token does not stop it.** `51741` sits inside the macOS ephemeral range (`net.inet.ip.portrange.first: 49152`), so any local process binding 0 may get it. A 40-line impersonating listener received the full `prompt`, `cwd`, `transcript_path`, `session_id` and bearer token; returning an `additionalContext` block made the next session answer from the injected content, and the same shape on `PreToolUse` can return a `permissionDecision`. **The bearer token authenticates the CLI, not the listener** — exactly the wrong direction.

The helper has neither fault: it exits 0 with both streams silent whether or not the app is running, so no registered event can leave a line anywhere, and the socket lives in the app's own directory at mode 0600, where another process can neither bind nor read it.

## Considered and rejected

**A resident process holding the port, handed over when the app starts.** Proposed first; the port half works well and the handover half does not.

- launchd socket activation does hold the port **with no process running** (`state = not running`, another process binding gets `EADDRINUSE`), the job starts on demand and reuses one process at 3 connections/second (one launch served 31 connections), and after `SIGKILL` the port stays held (three binds at t+0.0/0.2/0.4 s all refused) with the next POST returning 200. That half is real.
- But **there is no safe handover.** `SO_REUSEPORT` lets two processes hold `127.0.0.1:P` at once (measured: 6/6 connections went to the later binder), yet it requires **every** participant to set it — a plain bind cannot join a port held by a plain bind, or vice versa. So today nobody can push in while the app runs, whereas opening `SO_REUSEPORT` for handover lets any local process that also sets it and binds later take over delivery, **including while the app is running**: a window that exists when it is closed is traded for one that is always open. The remaining option, passing the fd by `SCM_RIGHTS`, means rewriting `AgentHookListener` from `NWListener` into a raw-fd accept loop.
- Worse, **the failure shape is more severe than the illness**. When the job cannot start (the app deleted, the bundle moved, the binary quarantined after an OS upgrade, launchd throttling), launchd still holds the listening socket: `connect()` **succeeds in 1 ms** and `recv()` never returns (measured 10 s with no response, `last exit code = 78: EX_CONFIG`). Every event then waits out its own `timeout`, and the app **cannot change the `timeout` in the user's file**. Today a refused connection returns immediately and `timeout: 5` is never reached; this trades noisy for hung.
- And **bootstrap succeeds silently when the port is taken**: `rc 0`, the job registers, and `launchctl print` is byte-identical to the healthy case (both report `sockets = { 16 (no bytes to read) }`) while the squatter keeps receiving POSTs. Today a failed `bind()` is a clean signal, and this loses it.

**A port outside the ephemeral range** (say `31741`). Cheaply closes the hijack window, does nothing about the noise, and makes every user re-paste.

**`once: true` on each handler.** The CLI removes the hook after its first trigger, capping the noise at twelve lines per session — at the cost of ending the monitoring itself.

**Accept it and explain it on the settings card.** That is: registering these hooks means a noisy CLI whenever the app is closed.

## Costs

**One process per event.** Measured (2.1.237, pty interactive session, registrations amplified 10× and 60× then regressed on event count, baseline the same prompt with no hooks registered):

| Transport | CPU per event | Per Turn (17 events) |
| --- | --- | --- |
| `http` → live listener | 1.2 ms | 21 ms |
| `command` → compiled helper | 4.8 ms | 81 ms |
| `command` → this ADR's `sh` + `nc` | 6.3 ms | 107 ms |
| `command` → Python (as Codex has always been) | 30 ms | 510 ms |

So it costs more than the channel it replaces, by tens of milliseconds per Turn, and five times less than what the app's other half has been paying all along. No separate compiled artefact was built for it: 2.2 ms saved is not worth a new target, a signature and an upgrade path.

**Registration is synchronous.** The `command` schema has an `async` key (the `http` schema does not), but on 2.1.237 it measurably lets `PreToolUse` and `PostToolUse` for the same `tool_use_id` overtake each other, and drops `Stop` entirely under `-p` (the process exits before the background hook finishes). Ordering and terminal states are worth more than 6.3 ms.

**Depends on `/usr/bin/nc` with `-U`.** It ships with macOS, so it is not a private dependency, but it is this channel's only external part. The helper's three timeouts, innermost outwards, are `SO_RCVTIMEO` 250 ms (the app reading one payload), `nc -w 1` (a peer that accepted but does not read), and `timeout: 3` in the registration.

**Users who already installed must re-paste.** Their old `http` handler stays in their file and the app cannot delete it (ADR 0010). So `ManagedHooksConfiguration` treats the old URL path `/codex-in-notch/hook` as a legacy identity marker: recognised, so status reports `repairRequired` ("this is not the registration this version wants, please re-paste") rather than `notInstalled` ("you have not installed it"), which would make users paste a second copy beside the first.

> **That conclusion changed with [ADR 0016](0016-write-the-users-claude-code-settings-and-keep-a-copy.md); the marker did not.** The app can now delete the dead handler: on install, `installing(into:isNewFile:)` strips it using that same legacy marker and writes the current shape. The user's job becomes flipping a switch rather than going back to re-paste — and `repairRequired` still needs reporting separately, because until they flip it the notch stays empty with no error anywhere.

## Consequences

**The reason for excluding `SessionEnd` is gone, and it still is not registered — for a different reason.** It was originally excluded as the one event whose failure writes to the CLI's **own stderr** and therefore follows `claude -p` into scripts, pipes and CI. The helper cannot fail that way, so that reason is void. Re-examined on its own merits, it earns nothing:

- The case for it was "retiring a dead session's row sooner than the sessions-directory watcher". **The measurement says the opposite.** On 2.1.237, pty interactive session, sampling `~/.claude/sessions/<pid>.json` every 20 ms: the file was deleted at **+15.09 s / +15.08 s** across two runs and `SessionEnd` arrived at **+15.41 s** both times — the watcher's signal is about **330 ms earlier**. Registering it only supplies a later answer to a question already answered.
- `/clear` looks like the exception: the process lives, no file changes, the watcher stays quiet. But it **swaps the session id under the same pid** (measured `bf10d6dc…` → `cd9d3d18…`, while `SessionEnd(reason: clear)` carries the old one), so the old id leaves `claude agents --json` at once and the row disappears as usual. `resume` has the same shape.
- Noted for whoever reopens this: the payload carries `reason` and a group's `matcher` matches on it, so a registration could select by reason. The vocabulary is `clear`, `resume`, `logout`, `prompt_input_exit`, `other` — only some of which mean "the session is gone", which is the second reason it is not the simple signal its name suggests.

Rows have always disappeared through "do not draw a Turn whose session is absent from the live list" (`ClaudeCodeMonitorService`). That mechanism was previously held up by one line of code and a comment; it is now pinned by `aRowGoesWhenItsSessionLeavesTheListIncludingAfterClear`, `/clear` shape included.

**CC-014 disappears with it.** "A fixed port conflict cannot self-heal" presupposes a fixed port.

## Status

Implemented. `ClaudeCodeHookSetup` writes the helper and renders the block to paste, `AgentHookListener` binds the socket, and `ClaudeCodeMonitorService.prepareTransport()` confirms both on every refresh. Tests: `theHelperDeliversWhenTheAppIsUpAndIsSilentWhenItIsNot` (running the real script in the CLI's exec form, requiring `exit 0` and two empty streams in both states), `theSocketIsPrivateToThisUserAndDropsWhatItCannotRead`, `theHandlerThisBuildReplacedStaysRecognisableSoAnUpgradeReplacesIt`, `anHTTPEraRegistrationAsksToBeRepairedRatherThanReadingAsAbsent`, `theHelperQuotesASocketPathThatCarriesAQuote`, `aRowGoesWhenItsSessionLeavesTheListIncludingAfterClear`.
