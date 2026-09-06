# The helper answers on the stream ADR 0013 silenced

[ADR 0013](0013-claude-code-hooks-run-a-helper-not-a-port.md) made the helper silent on both streams, because both products *print* a hook's stderr and *parse* its stdout, and a helper that said "the app is not running" would be the noise that decision existed to remove. Stdout is now opened — **on one registered event per product, and on no other** — because parsing it is exactly what this app now wants that product to do.

## What changed

`AgentHookHelper.script` takes one literal argument, and the registration is what passes it.

| Form | Registered on | What it does |
| --- | --- | --- |
| bare | every lifecycle definition | `nc -U -w 1 <socket> >/dev/null` — the ADR 0013 helper unchanged, with stdout discarded **at the call** |
| `wait` | `PermissionRequest`, on both products | `nc -U -w <window> <socket>` — stdout is the reply channel, and the app writes that product's own hook-output JSON onto it |

`exec >/dev/null 2>&1` becomes `exec 2>/dev/null`: stderr stays discarded for the whole script, including the shell's own "not found" if `nc` is ever absent. Stdout is silenced per branch rather than for the file, so the 99.8% of events where nobody is being asked keep the older, stricter silence **by construction** rather than because the app remembers not to write on them.

Two properties of ADR 0013 are unchanged and one is qualified:

- **It always succeeds.** `nc` was measured to exit **1** on both shapes of "nothing is listening" — no socket file, and a socket file whose owner has gone (2026-09-05) — so the unconditional `exit 0` is load-bearing, and the script must not `exec` into `nc`: that would hand the product `nc`'s status instead of its own.
- **It cannot hang.** `-w` still bounds it. The bound is now per event, and the long one is inside the timeout its definition registers, so the helper always gives up before the product kills it — a helper that gives up exits 0 and says nothing, and one the product kills is a hook error printed in the user's session.
- **It never speaks unless it has something to say**, which is the qualified one. It used to mean "never"; it now means "only where a person is being asked, and only what they answered".

## Why `nc -U` still works, measured rather than assumed

Decision 4 of the plan kept the transport rather than building a compiled helper, on the strength of `nc`'s man page. Measured against a Unix-domain server on this machine, 2026-09-05:

| Question | Answer |
| --- | --- |
| Does `nc` hold the connection after its stdin reaches EOF? | **Yes.** It shuts down only its *write* half — the server sees end-of-payload immediately — and goes on reading until the peer closes or `-w` expires |
| Is `-w` a total deadline or an idle one? | **Idle.** `-w 3600` against a server that answered after 3 s returned in **3.04 s**, so a long window costs nothing when the answer comes early |
| What does `-w 1` do now? | Unchanged: gives up at **1.04 s** with empty output and status 0 |
| Does the app closing the connection release the client? | **Yes, at once** — and so does the app's process dying |
| Does a large payload deadlock against the reply? | **No.** 128 KiB out and an answer back in **60 ms** |

The half-close is the part that makes this shape work at all: the app can read to end-of-payload *and* write an answer on the same descriptor, with no framing and no second connection.

## Why the product will act on it

Measured against Claude Code **2.1.261**, a pty-driven interactive session on a throwaway `--settings` file, `--permission-mode default`, with a hook that read the payload, slept, and then wrote one line:

- **The product does not wait for the hook.** Its own permission dialogue was on screen **0.32 s after the hook fired**, while that hook still had 6 s to sleep. So a person who walks to the product mid-decision finds the prompt there — the notch is a second place to answer, not the only one.
- **`allow` answers it.** `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`, written 6 s after the prompt appeared and with **nothing typed into the session**, dismissed the dialogue and let the `Write` run: the file was on disk 5.9 s later.
- **`deny` with a `message` answers it too, and the reason reaches the model.** The transcript recorded `Denied by PermissionRequest hook`, the tool returned the message verbatim as its error, and nothing was written.

The payload that arrived on that event carried `tool_name`, `tool_input`, `permission_mode` and `permission_suggestions` — the request itself, which is what [`answer-in-notch.md`](../answer-in-notch.md) §14.1 already keeps.

## Considered and rejected

**A compiled helper that reads the payload and chooses its own wait.** What the reference implementation does, and what decision 4 held in reserve if `nc` could not hold a connection. It can, so this buys a target, a signature and an upgrade path in exchange for nothing. Choosing the wait from the *registration* is also strictly better information: the registration knows which event it is registering, so the shell never parses anything.

**One long window for every definition.** One line shorter and catastrophic: `PreToolUse` fires on every tool call, so a window a person could answer inside would be a window every tool call waits in.

**Letting the helper write diagnostics to stderr**, as the reference implementation does. Both products print it into the user's session. This is the one thing in that implementation this design refuses, and ADR 0013 is why.

## Costs

**The window is registered, so on Codex it is a re-trust.** See [ADR 0014](0014-the-codex-hook-definition-is-never-rewritten.md), amended for this change: one definition of seven, and the value chosen to be final.

**One event per product can now be answered, and only one.** `PermissionRequest` is the definition that carries the argument on both products, which is where the answer travels even for a question — an `AskUserQuestion` raises a `PreToolUse` that opens the wait *and* a `PermissionRequest` that carries the answer. Codex's `PreToolUse(request_permissions)`, which is how a Codex Desktop approval arrives and which sends no `PermissionRequest` at all (measured 2026-08-15), is therefore **read-only**: holding it would mean holding every tool call.

**A held connection is a hook process the product is waiting on.** It is released the moment the request settles, the app closes it, or the app goes away — all three measured above — and it is bounded by `-w` in every other case.

## Status

The helper, the argument and the registration are implemented. Tests: `theHelperOpensTheReplyChannelOnlyOnTheEventThatAsks`, `theHelperGivesUpInsideTheWindowTheDefinitionRegisters`, `theHelperDeliversWhenTheAppIsUpAndIsSilentWhenItIsNot` (which runs the real script in both forms, with the app up and with it closed, and with the agent told to stay out), `onlyTheAnsweringDefinitionEverChangedAndTheRestAreByteIdentical`.
