# Read the quota from the record the command leaves, not from the sentence it prints

Claude Code's rolling quota windows are read from `cachedUsageUtilization` in `~/.claude.json` — the answer the product's own usage endpoint last gave, as JSON, stamped with `fetchedAtMs`. The app still runs `claude -p "/usage" --output-format json` on the same cadence, but for what the run *does* rather than for what it prints: the run performs the usage fetch, and the fetch writes that record.

This **amends [ADR 0007](0007-read-claude-code-quota-from-the-cli.md)**, which is otherwise unchanged and still governs: the quota comes from the CLI, not from a Claude Desktop private file, and reading OAuth credentials to call `/api/oauth/usage` directly stays a NO-GO. What moves is only where in the CLI's own output the numbers are taken from.

## What went wrong

The footer drew `-- left` and `--` for both Claude Code windows, indefinitely, on a machine using Claude Code all day.

The cause is not a format change. `claude -p "/usage"` prints the windows **only when the CLI itself is signed in to a Claude subscription**; when it is not, the same run answers with its session-cost summary —

```
Total cost:            $0.0000
Total duration (API):  0s
Total duration (wall): 0s
Total code changes:    0 lines added, 0 lines removed
Usage:                 0 input, 0 output, 0 cache read, 0 cache write
```

— which has no window lines in it at all. Every anchor came back empty, and ADR 0007's degradation rule did exactly what it says: unavailable, never a stale value. The app was behaving correctly and the user was left with two blanks.

**And the CLI being signed out is an ordinary state, not a broken machine.** Measured 2026-09-09: `claude auth status` reports `{"loggedIn": false, "authMethod": "none", "apiProvider": "firstParty"}` for the `PATH` binary *and* for both of Claude Desktop's bundled copies, while Claude Code is in constant use — Desktop hosts its own sessions with auth injected per session, so the CLI's own credential is never needed and can lapse without anything noticing. `notchline-desktop-only-machine` recorded "whether `-p /usage` needs a credential" as the one link never tested on such a machine. It does.

## What replaces it

The same run leaves the same numbers behind as JSON:

```json
"cachedUsageUtilization": {
  "fetchedAtMs": 1788842193281,
  "utilization": {
    "limits": [
      {"kind": "session",       "percent": 23, "resets_at": "2026-09-08T07:10:00.303358+00:00"},
      {"kind": "weekly_all",    "percent": 41, "resets_at": "2026-09-12T07:00:00.303376+00:00"},
      {"kind": "weekly_scoped", "percent": 0,  "resets_at": null,
       "scope": {"model": {"display_name": "Fable"}}}
    ]
  }
}
```

Three windows, in the order the footer draws them (`quota-footer-v2.md` §5), each reported as **used** so a rule still draws `100 − used`. It is written by the CLI on every usage fetch, throttled to one write per five minutes, and Claude Code's own reader of it stops trusting it at one hour.

Four things get better, and none of them is "it is nicer JSON":

1. **A shape change fails as a decode**, not as a percentage quietly gone missing. That is the whole argument. ADR 0007 accepted regex-against-prose and required a parse failure to degrade to unavailable; this failure mode is now loud where it was silent.
2. **The per-model window's model is a field.** `scope.model.display_name` replaces pulling a label out from between a `(` and a `)` on a line that also had to be told apart from `94% of your usage was at >150k context`.
3. **The answer says how old it is.** The paragraph never did, so the reader could only date an answer by when it ran the command — which meant a command answering out of a cache it had failed to refresh was redrawn as new. The trust ceiling now counts from `fetchedAtMs`. The number is unchanged at `3600`; what it is measured from is not, and the hour is the product's own.
4. **A failed launch no longer blanks anything on its own.** The record is independent of this app's run, so another Claude Code on the machine refreshing it a minute ago is worth exactly as much as our own launch.

## What is still read out of the prose, and why that is not a relapse

One line prefix: an answer whose first line is `Total cost:` is the no-subscription fallback. It produces a **sentence**, never a figure —

> Claude Code reported no usage limits: its CLI is not signed in. Run `claude auth login` in a terminal — signing in to Claude Desktop does not sign in the CLI.

— and it is said only while there is in fact nothing to draw, so an account whose figures are on screen is never told it has a problem. A rewording upstream costs the explanation and nothing else. This is the part ADR 0007 had no answer for: the app could see the blank and could not say why.

## Considered and rejected

**The statusline `rate_limits` field.** Claude Code hands `statusLine` commands a JSON object carrying `five_hour` and `seven_day` with `used_percentage` and `resets_at`, derived from response headers, so it is live and needs no fetch at all. It is rejected because **`statusLine` is a single slot the user owns**: writing ours into `~/.claude/settings.json` would either replace whatever they had — violating the first of [ADR 0016](0016-write-the-users-claude-code-settings-and-keep-a-copy.md)'s four safeguards, *touch only our own keys* — or require wrapping their command in ours, which breaks the moment they edit it. It also only exists while a session is running and has had one API response, and (measured 2026-09-09) it is absent from the payload until then.

**A `--output-format stream-json` run, reading a rate-limit event.** Measured 2026-09-09 on 2.1.263: no such event appears on the stream, for a local command or for a real model turn. The `SDKRateLimitEvent` the changelog describes is not reachable from a subprocess.

**`~/Library/Application Support/Claude/plan-usage-history.json`.** Already rejected by ADR 0007 as Desktop-private, and now also dead: last written 2026-08-15 on a machine in daily use.

**Reading the record alone, without running the command.** The record only moves when something fetches, and nothing else on a Desktop-only machine does. The run is what keeps it fresh, which is why the cadence and its cost are unchanged.

## Costs, recorded plainly

- **A signed-out CLI still draws `--`.** Nothing here fixes that, and nothing can: the numbers do not exist locally until somebody signs in. What changed is that the user is told, in the one place they can act on it. **And the record does not merely go stale there — it is deleted.** Measured 2026-09-09, in the course of writing this: Claude Code drops `cachedUsageUtilization` when the record's `accountUuid` does not match the account in hand, and on a signed-out machine there is no account to match, so the next run removes the key. The reading answers nil either way, which is why the source treats "absent", "unreadable" and "past the ceiling" as one answer.
- **The freshness of the figures now depends on a fetch succeeding**, not merely on the command answering. Offline, the run answers from headers or from its own cache without writing, `fetchedAtMs` stands still, and the windows blank at the hour instead of being redrawn. That is the correct behaviour and it is more visible than the old one.
- **One more private read.** `~/.claude.json` is the product's file and this app only ever reads it. It joins `~/.claude/sessions`, `~/.claude/projects` and the rest in [`non-public-codex-integration-features.md`](../non-public-codex-integration-features.md), where the registry row for this dependency is rewritten with it.
- **The prose parser and its tests are deleted, not kept as a fallback.** Keeping both would mean two sources for one number and a rule for which wins; the record is strictly better data, and the failure it cannot cover — nobody has fetched in an hour — is one the fallback could not cover either.

## Where it lands

`ClaudeCodeUsageUtilization` (new), `ClaudeCodeUsageReader.performRead(readingWindows:)` / `quotaDiagnostic()` / `isCostSummary(_:)`, and `ClaudeCodeMonitorService`'s snapshot, which carries the sentence on the diagnostic channel it already had.

Tests: `theWindowsComeFromTheProductsOwnRecordRatherThanItsParagraph`, `aPerModelWindowIsDrawnOnlyWhereTheRecordNamesOne`, `aReadingTheProductHasAlreadyExpiredIsNotDrawn`, `aRecordWithoutTheLimitsListFallsBackToTheTwoNamedWindows`, `aRecordThisAppCannotReadIsUnavailableRatherThanZero`, `aRecordWhoseShapeMovedGoesUnavailableAtOnce`, `aResetIsReadFromTheRecordsOwnStampFractionAndAll`, `aSignedOutClaudeCodeIsSaidOutLoudRatherThanDrawnAsABlank`.
