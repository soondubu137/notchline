# The click asks about one Thread, not about the whole history

The re-confirmation before opening a Codex row is one `thread/read` for **that thread**, not a forced full pagination of every unarchived Thread. The test is unchanged, still [ADR 0017](0017-a-row-requires-a-thread-the-app-server-vouches-for.md)'s: the App Server hands the Thread over and it passes the navigable-root-Thread check.

## What triggered it: perceptible navigation latency

A user reported that clicking a Codex row on another Mac took 1–2 seconds to reach the Thread; milder here but still noticeable. Almost all of it measured inside this gate.

The App Server answers `thread/list` by **scanning and parsing the rollout files under `~/.codex/sessions`** — replace `state_5.sqlite` with an empty database and leave only the sessions directory and it still lists all 47 — so the cost grows with the user's history, and it is paginated, with the page count growing too. Measured 2026-08-26 against Codex Desktop's built-in CLI `0.149.0-alpha.4.3` on an isolated `CODEX_HOME`, one full pagination:

| Unarchived Threads | Pages | One full pagination |
| --: | --: | --: |
| 50 | 1 | 51 ms |
| 100 | 1 | 108 ms |
| 199 | 2 | 335 ms |
| 400 | 4 | 754 ms |
| 799 | 8 | **2215 ms** |

(Superlinear: every extra page pays for the scan again.) This machine's real history of 47 threads with larger rollouts takes 206 ms.

On the same machine one `thread/read` (`includeTurns: false`) is a median of **1.4 ms**, at most 3 ms over 20 runs. Everything else on the click path is negligible: `urlForApplication` under 10 ms, `NSWorkspace.open`'s completion callback 94 ms, and connecting is a no-op (the app-server subprocess is always up). So **the gate was the click latency** — end-to-end A/B below.

## End-to-end A/B (2026-08-26, this machine)

Same idle machine, same thread, same fixture, only the app binary swapped — one launch before and one after, a real Codex row staged through the hook socket, a real click via `CGEvent`, timed from the click to `NSWorkspace.didActivateApplicationNotification` reporting ChatGPT activated:

| | Runs | Median |
| --- | --- | --: |
| Before | 208 / 215 / 220 / 252 / 317 ms | **220 ms** |
| After | 56 / 57 / 61 / 62 / 62 / 64 / 66 / 68 / 69 ms | **62 ms** |

A 158 ms difference, the same order as this machine's full pagination (206 ms) — the remaining 62 ms is `thread/read` plus the Launch Services leg. **This machine has only 47 unarchived threads**: what was removed grows with history per the table above, 0.75 s at 400 and 2.2 s at 799. The destination was re-verified too: after the change, clicking opens exactly the thread that row refers to.

**How it was measured.** Not one number here is obtainable with `ps`: the cost is neither this app's steady-state CPU nor one of its bursts, but the **latency of a subprocess round trip**. The pagination table was taken by speaking JSON-RPC to `codex app-server` directly, requesting page by page with the same parameters this app uses (`archived: false`, `limit: 100`, `sortKey: updated_at`, four `sourceKinds`) and timing them, warming up once per size then taking the median of 4–7 runs, with an isolated `CODEX_HOME` per size (copies of real rollout files, thread ids rewritten per copy). The A/B rows are this app's **Debug** build, because this app's own Swift on that path is a few dictionary lookups and the configuration difference falls inside measurement noise; the real cost is entirely on the subprocess side, and that is the same binary under both. The machine stayed idle between the two runs — an earlier "before" measurement on a machine also running the full test suite (217/253/347 ms) agrees with the table, just noisier.

## Why one read is enough

A row exists precisely because the App Server handed its Thread over and it passed the check (ADR 0017). Asking the **same question** of the **same source** again at click time is the smallest shape this gate can have; asking more than was asked to draw the row means drawing rows you then refuse to open — the very fault ADR 0017 exists to remove.

`thread/read` also answers this question **more accurately**: measured on the same subagent thread, `thread/list` returns null for both `threadSource` and `parentThreadId` while `thread/read` fills both in. Deletion is still caught — a non-existent id gets a remote error (`thread not loaded`), and a remote error is "no such thread" under ADR 0017.

## Archiving is not in this gate

**Archiving ends a row's monitoring lifecycle, not the Thread's reachability.** An archived thread is still in Codex Desktop and the deep link still points at it, while "archived means leaving the list" is already owned by the 30-second membership reconciliation: `removeThreads(notIn: listedThreadIDs)` retires that Turn and the row stops being drawn. So a row the user can still click is a row the last reconciliation still listed, and asking again at click time buys an answer the row already carries.

It also cannot be asked cheaply, both measured 2026-08-26:

- **`thread/read` hands over an archived thread, with no archived marker of any kind.** After really calling `thread/archive` on an isolated `CODEX_HOME`, `thread/list(archived: false)` no longer contains it, `thread/read` returns as usual, and the payload has no `archived` field.
- **The `thread/archived` notification goes only to the client that performed the archive.** With two app-servers on one `CODEX_HOME`, B archiving, only B received `{"method":"thread/archived","params":{"threadId":…}}` and A received not a frame. A user archiving in Codex Desktop goes through Desktop's own app-server, and the one this app forks independently is never told. (A's next `thread/list` reflected the archive immediately — what is shared is disk state, not an event stream.)

The cost, stated: between an archive and the next membership reconciliation (at most `threadListRefreshInterval`, 30 seconds), clicking a row that has not yet gone opens the archived Thread rather than reporting "archived, deleted, or no longer available". That is the **same evidence** that is drawing the row in that same window, no longer contradicting itself.

## Older Codex

A build without `thread/read` (`-32601`) probes once and falls back permanently to full pagination, the same degradation as the metadata path — it pays what it always paid here, and nothing extra anywhere else.

## Status

Implemented. Tests: `openingAThreadAsksForThatThreadInsteadOfPaginatingTheHistory`, `openingAThreadTheAppServerRefusesIsNotNavigable`, `openingASubagentThreadIsNotNavigable`, `aThreadReadThatFailsInTransportDoesNotClaimTheSessionIsGone`, `aCodexWithoutThreadReadAnswersTheClickFromTheList`.
