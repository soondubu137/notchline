# Antigravity CLI at Tier 0 — the third product, measured and built

| Field | Value |
| --- | --- |
| Status | **Built and run 2026-09-11** as `AgentKind.antigravity`: `Products/Antigravity/`, one registry entry, and `AntigravityConformanceTests`. Tier 0, no capability above it. This is P5's first half in [`tiered-support.md`](tiered-support.md) §8; the T1 terminal is not started. **Taken end to end through a Release build the same evening** (§6): the switch's own registration is one `agy` loads, a turn is a row, and the click focuses the Terminal window the conversation runs in. One defect fell out of it — a footer line of dashes under a product that has no quota — fixed, and priced against P4's baseline in §7. **Extended 2026-09-12** (§2.1): the row is titled with the prompt, read out of the transcript the payload names, which is what `tiered-support.md` §4's Tier 0 row content asked for all along |
| Investigated | 2026-09-11; the transcript re-measured 2026-09-12 |
| Product | Antigravity CLI `agy` 1.2.2, an arm64 Go binary at `~/.local/bin/agy`; state under `~/.gemini/antigravity-cli/`, shared configuration under `~/.gemini/config/` |
| Source baseline | Local `master`, `ee19188` |
| Method | The product's own hooks guide, read out of the binary's embedded documentation; then a hooks file of this app's own forwarding every event to a probe that records stdin, environment, ancestry, the parent's working directory and the parent's open files; three print-mode turns, one two-turn conversation, and one interactive TUI session driven through a pty. No file of the user's was edited: the global hooks file did not exist before the probe and was removed after it, and the one workspace trusted for it was this session's scratch folder, with the settings file's original bytes restored |
| Question | Is the ladder real — can a product nobody wrote a line for become a row by declaring what it does, and what does it cost? |
| Answer | Yes, at Tier 0, for the cost §5 lists. Two things the ladder had not met were found on the way and are now seams: a product whose file is not `hooks` at the root and whose lifecycle events take bare handler lists, and a product whose payloads name neither their event nor their Turn |

Terminology follows [`CONTEXT.md`](../../../CONTEXT.md). Every id and path below is the fixture's, not a conversation's.

## 1. What the product exposes

**Five hook events**, configured in a `hooks.json` whose root is a set of *named* hooks, each an object of events. `PreToolUse` and `PostToolUse` take matcher groups, exactly Claude Code's shape; `PreInvocation`, `PostInvocation` and `Stop` take the handlers directly. Handlers are `{"type": "command", "command": "...", "timeout": N}`, run through `sh -c` with the working directory set to the hooks file's folder, and there is no `args` key. The guide says a hook must print a JSON object on stdout; `{}` was accepted on every event.

**Where the file is.** The guide's example is `.agents/hooks.json` in the workspace, and that file is read **only after the workspace is trusted** (`trustedWorkspaces` in `~/.gemini/antigravity-cli/settings.json`; the CLI's own changelog records the reload on trust). The file both the TUI's `/hooks` and the backend read is `~/.gemini/config/hooks.json`, again per the changelog, and that is the one this app writes. The log line `hooks_manager.go:53] loaded N named hooks from M hooks.json file(s)` at launch is the only confirmation the product gives.

**The shape mistake is fatal and silent.** A group (`{"hooks": [...]}`) written under `Stop` made the product log `Failed to parse hooks file …: invalid hook "notchline-probe": command hook must specify 'command'` and run **none** of that named hook's handlers, for any event. Two probes produced nothing before that line was found. `ManagedHookDefinition.Shape` exists because of it.

**One payload shape for every event.** Common fields on all five: `conversationId`, `workspacePaths`, `transcriptPath`, `artifactDirectoryPath`, `modelName`, camelCase throughout. **No field names the event.** Per event:

| Event | Extra fields, measured | Fired |
| --- | --- | --- |
| `PreInvocation` | `invocationNum` from 0, `initialNumSteps` | Before every model call: once for a one-call turn, eight times for a seven-tool turn |
| `PostInvocation` | Same as `PreInvocation` | After every model call |
| `PreToolUse` | `stepIdx`, `toolCall: {name, args}` — `view_file`, `find_by_name`, `run_command`, `manage_task`, `invoke_subagent` seen | Before each tool, including one headless mode then auto-denied |
| `PostToolUse` | — | **Never**, across seven tool calls with matcher `""` and again with `"*"`. Not investigated further; nothing at Tier 0 wants it |
| `Stop` | `executionNum`, `fullyIdle`, `terminationReason` (`NO_TOOL_CALL`), `error` | Once at the turn's end |

The hook process's parent is the `agy` process itself (ancestry `sh ← agy ← <terminal>`), its environment carries `ANTIGRAVITY_CONVERSATION_ID`, and `workspacePaths` is the workspace in the TUI and `[]` under `-p`, trusted or not.

## 2. The Turn boundary, and the identity the product does not send

Two turns of one conversation (`agy -p`, then `agy -c -p`) and two turns in the TUI agree:

- `PreInvocation` with `invocationNum` **0** opens every turn and reads 0 again on the next turn of the same conversation; later invocations of a turn count up from 1.
- `Stop` closes every turn. `executionNum` read **0 on every turn measured**, in both modes, so it is not a turn ordinal and nothing in any payload is.

So the first invocation of a turn is the unambiguous submission boundary [`README.md`](README.md) §6.1 requires before a Provider may propose a local identity, and `AntigravityPayloadTranslator` proposes one there: association is the conversation's one open Turn — a conversation runs one execution at a time — and every later event of the conversation belongs to that Turn until its `Stop`. The duplicate and retry cases are answered without state the reducer does not already have: a later invocation of an open Turn is not a boundary and is not delivered; a `Stop` for a conversation with no open Turn reuses the id its last `Stop` retired, so the reducer sees a late duplicate; and a first invocation while a Turn is still open — a `Stop` this app never received — mints anew, which the reducer holds and redeems on the new Turn's own `Stop`, the path Claude Code's refusal-without-a-hook already takes. The identity is marked local (`local:<uuid>`) and lives only in the process that minted it.

The prompt is in no payload. It was drawn as `Untitled` on that basis until **2026-09-12**, when the transcript the payload names (`brain/<conversationId>/.system_generated/logs/transcript_full.jsonl`) turned out to answer it at no cost worth the row — see §2.1. What is written above stands as a statement about the *hooks*, and no longer as a statement about the row.

### 2.1 The prompt, read out of the transcript the payload names

Measured 2026-09-12 on the same 1.2.2 build, against the twelve conversations this machine had accumulated and one turn run for the purpose.

**The file answers, and answers in time.** Each turn appends one step of its own before any model call:

```json
{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE",
 "created_at":"2026-09-12T07:24:42Z",
 "content":"<USER_REQUEST>\nList the files in the current directory, then say done.\n</USER_REQUEST>\n<ADDITIONAL_METADATA>…"}
```

Only what is inside `<USER_REQUEST>` is the user's; the metadata after it is the product briefing its own model, and a row drawn from the whole content would carry a timestamp where the words belong. A `SYSTEM_MESSAGE` step is not a request however much its own first sentence reads like one — it opens *"The following is a `<SYSTEM_MESSAGE>` not actually sent by the user"* — so the two fields are both checked. Later turns of a conversation append their own step, so the last request in the file is the open turn's.

**It is written live, not flushed at the end**, watched growing 0 → 1 → 2 lines across one turn at 150 ms. The user's step landed 2.7 s after launch and about two seconds before the first model response.

**Whether it beats `PreInvocation` 0 is the product's race, not this app's**, and it could not be timed through the product's own hooks without writing into a hooks file of the user's. So the translator reads at the boundary and, **only if that read came back empty**, once more at the turn's `Stop`, where the step is on disk beyond any doubt; the reducer fills a blank title from a late prompt and never overwrites one. Staged against a Debug build of this tree the same day, a running row drew the whole prompt at `0:11`, so the first read wins in practice and the second is insurance. A turn's later model calls read nothing at all — the read sits inside the boundary branch, so a seven-tool turn costs one bounded read and not eight.

**Ceilings.** Only the last 256 KB of the file is read, because this runs on the hook delivery path and a conversation's transcript grows without bound; a turn that wrote more than that keeps `Untitled`. And the reading answers for the *conversation*, not for the Turn: a turn the product started for itself — none observed — would draw the last thing the user asked. All twelve of this machine's conversations returned the right request, the multi-turn ones included.

## 3. Presence, admission and the click, from one kernel read

`~/.gemini/antigravity-cli/presence/<conversationId>.lock` exists per conversation and is held open under an **exclusive `flock`** for exactly the life of the process running that conversation — polled every 250 ms across a print-mode turn: free before the process, locked from its first event to its exit, free the instant after, file left behind. The interactive session held its lock the same way, and `lsof` from inside the hook showed the `agy` parent holding it.

Which files a process holds open is a kernel fact (`proc_pidinfo(PROC_PIDLISTFDS)` and `proc_pidfdinfo(PROC_PIDFDVNODEPATHINFO)`), so `AntigravityConversationScanner` reads the live set without taking a lock — probing with even a shared lock would race the product's own acquisition. One reading answers all three questions the Provider and the navigator ask: **presence** (an `agy` process holding a lock), **admission** (`.exactly(set, readAt:)`, ADR 0017's "the product's own live session list" for a CLI), and **which process** a row's conversation runs in, from which the existing terminal route reads the host to raise. Ceiling, stated: an executable not named `agy` is invisible; the CLI's `remote-control` daemon and `mic-serve` are `agy` and hold no lock, so they are not "open". A `-p` row therefore leaves the list seconds after it completes, when its process exits — the same lifecycle as Claude Code's `-p`.

## 4. Why Tier 0 and not Tier 1

Nothing observes a wait. `PreToolUse` fires before every tool whether or not a person is then asked; the product's permission decision is the hook's *output* (`allow`/`deny`/`ask`), a write path this app does not take; and a headless auto-denial fired nothing at all — the turn went on to `Stop` 1.5 s after the `PreToolUse` it denied. Drawing `Approval needed` off `PreToolUse` would be exactly the false call to action §2 forbids. So the row is `Running` from the first invocation to `Stop`, and Settings says so under the switch: *Approvals and questions are not detected for Antigravity CLI; a row shows Running until its turn ends.*

Interruption was not measured cleanly — the TUI's `Ctrl-C` landed after the turn's own `Stop` — and is not required at Tier 0: silence never counts as ended, so an interrupted turn with no `Stop` stays `Running` until the conversation's next turn, its process's exit, or a right-click. Whether `Stop` fires on `Ctrl-C` with a different `terminationReason` is the first thing to measure for Tier 1.

## 5. What it cost

| File | Content | Size |
| --- | --- | --- |
| `Products/Antigravity/AntigravityHookVocabulary.swift` | The vocabulary (two definitions, the dialect, no answering) and the translator that reads the announced event, renames the fields and proposes the local Turn identity | ~230 lines, half of them the measurements above |
| `Products/Antigravity/AntigravityConversationScanner.swift` | A `ProcessTableReading` seam, its `libproc` implementation, and the scanner that is presence, admission and the click's locator at once | ~200 lines |
| `Products/Antigravity/AntigravityTranscriptReader.swift` | Added 2026-09-12 (§2.1): the reading seam and the bounded tail read that lifts the prompt out of its envelope | ~110 lines, half of them the measurement |
| `ProductRegistry.swift` | One descriptor, with the declared boundary | 25 lines |
| `MonitorDomain.swift` | One enum case | 5 lines |
| `AntigravityConformanceTests.swift` | Registration in the product's shape beside the user's hooks; the Tier 0 fixtures with the product's payloads; the lost-`Stop`, mid-turn-launch, print-mode and sibling-product cases; presence, admission and the click from one reading | ~330 lines |

Two seams had to be cut in the shared code first, each its own commit: the container key and list shape in `ManagedHooksConfiguration`, and the registration dialect, announcing helper and payload translator in the hook transport. The store, the overlay, the footer, the grouped list, the setup actor, the reducer, the listener and the Settings rows changed by one line (the caption under a row now shows a declared boundary). The navigator was renamed `ProcessHostNavigator`, since Antigravity's rows go back to a terminal the same way Claude Code's do.

## 6. The live run, and the one defect it found

Staged 2026-09-11 against a Release build of this tree: the app's own Settings switch, the product's own binary, and no probe anywhere in the path.

**The registration the app writes is one the product accepts.** Driven first against a throwaway home (`CFFIXED_USER_HOME` moves every path the app reads; `HOME` moves every path `agy` reads), so the switch's write landed in a copy rather than in the user's file. Flipping it wrote the two definitions under `notchline` in that home's `~/.gemini/config/hooks.json`, and the next `agy` launch logged `hooks_manager.go:53] loaded 1 named hooks from 1 hooks.json file(s)` — the only confirmation the product gives, and the one thing §1's silent shape mistake would have taken away. That home could not authenticate (the copied credentials are refused and the CLI asks to log in again, which is not worth chasing), so the rest ran against the real one.

**A turn is a row, and the row goes back to where the work is.** `agy -p` in a Terminal window: the row appeared as `Working...`, turned `Completed` a second later, and left the list fifteen seconds after that, when the process exited and the admission list emptied — the `-p` lifecycle §3 describes, watched rather than argued. A TUI turn in a second window drew `Antigravity · notchline · Untitled · Completed · took 1 second`: the workspace's last component for a project, `Untitled` for a prompt no payload carries, exactly what §2 predicted. ~~That second half is now the transcript's answer instead~~ — §2.1, 2026-09-12; the row of the same shape run that day drew the prompt itself. Pressing the row raised Terminal **and focused the window running that conversation**, not merely the application — the tty route reads the host off the process the lock names, and Antigravity's rows get the same pane-by-tty focus Claude Code's do.

**The defect.** The footer drew Antigravity as an outer row *and* one window line reading `-- left`, `--`. [`quota-footer-v2.md`](../../quota-footer-v2.md) §5 says the opposite in as many words — *a product with no limits still gets its row, an outer row and no inner ones*, because the absence of lines is what says there is nothing to report — and the store had held that rule, tested, since the footer was built. What produced the extra line was `HookProductProvider` answering `QuotaSnapshot.unavailable`, which is the **single-window** form: one window with nothing known about it. That is right for a product whose limits exist and could not be read this minute, and wrong for ever for a product that has none. `QuotaSnapshot.noneReported` is the empty-window value, the Provider answers it, and the two conformance suites pin it. No test could have found this: both shipping products always have windows, so the third product is the first to reach the case, and it is visible only in a footer drawn from a live snapshot.

Two smaller things, neither a defect: the settings card reads `Integration not installed` after the switch goes on until something forces a refresh (`Recheck`, or any event) — **Claude Code's row does the same at HEAD**, so it is the store's, not this product's; and `SetupDescription.installedMessage` promises a backup beside a file the app has just created, where there is nothing to back up.

## 7. What it costs, measured under Release

Release build of this tree, `ps -o time` deltas, one display, all three products registered, nothing else running. P4's baseline in [`tiered-support.md`](tiered-support.md) is the column on the right.

| Window | Measured | P4 baseline, two products |
| --- | --- | --- |
| Launch | 0.50 s CPU, 85 MB RSS | 0.24 s, 80 MB |
| Idle, no rows | 0.26 and 0.27 s per 60 s | 0.34–0.38 s per 60 s |
| Idle, no rows, this product's switch **off** | 0.42 s per 60 s | — |
| 200 hook events, transport only | 0.03 s CPU in 1.55 s wall | 0.04–0.05 s in 0.65 s |
| One running row | 0.38 s per 60 s | 0.40–0.51 s per 60 s |

No regression, and the switch-off window reading *higher* than the two switch-on windows is the measure of how much of that figure is this product's: none of it, within the noise the two shipping products make on their own.

**The one number that looks like a regression, and is not.** 200 events that each open and close a row — 100 whole turns in 1.9 seconds — cost **1.70 s** CPU, 35× the baseline's burst. Sampling the app through it puts every heavy frame in `SwiftUI` layout, so the suspicion is that this is the overlay redrawing rather than anything the product does, and the control settles it: the same 200 events carrying a sibling surface's transcript path, so the translator declines each one and no row is drawn, cost **0.03 s** — the same as 200 fabricated Claude Code events measured back to back on the same build, and the same as the baseline. The transport, the translator and the reducer cost what they have always cost; 100 rows arriving and leaving inside two seconds costs the overlay 17 ms each, against the 200 ms an expand already costs it (`AGENTS.md` §7), and no conversation produces turns at that rate.

Ten expand/collapse cycles read 3.39 s with a row and 3.44 s with none, so that figure is the method's one-second dwell and not comparable to the baseline's; it is recorded here only because the two runs agreeing is what says the product is not in it.

## 8. Not done, and not claimed

- **The T1 terminal** of P5 (WezTerm's pane-by-tty) is untouched.
- **Antigravity IDE and 2.0** share the hooks file. Their payloads name transcripts under `antigravity/` and `antigravity-ide/`, and the translator declines them, so they are neither rows nor diagnostics; observing them is a separate product.
- **Interruption is still unmeasured.** §4 stands: whether `Ctrl-C` fires `Stop` with a different `terminationReason` is the first thing to measure for Tier 1, and the live run did not reach it.
- **The throwaway home cannot authenticate**, so a future run that must not touch `~/.gemini` at all has to solve that first. Everything above except the loaded-hooks line was measured against the real one.

## 9. NO-GO check

No Turn state is inferred from silence; no historical hook is replayed; another surface's runtime is declined by its transcript path rather than mistaken for the CLI's; no permission prompt is created to observe one. The product enters Tier 0 and no higher, and the registry ([`non-public-codex-integration-features.md`](../../non-public-codex-integration-features.md)) records what it depends on that no documentation promises.
