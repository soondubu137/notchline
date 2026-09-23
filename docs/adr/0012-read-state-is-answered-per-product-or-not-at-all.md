# Read state is answered per product, or not at all

> **One word of the title changed in the second revision, 2026-08-19.** It used to read "the half that cannot be answered is not answered", meaning Claude Code sessions in a terminal. That half now has an answer — **not** because Claude Code started saying anything, but because a different thing was asked (see "Sessions in a terminal"). What genuinely remains unanswerable is sessions with no terminal to ask.

A terminal Turn leaves when the user has seen it ([ADR 0002](0002-use-desktop-unread-state-for-monitor-membership.md)). Codex answers from Desktop's blue-dot set. Claude Code previously had **no source at all**, so a Completed row could disappear only three ways: that session's next `UserPromptSubmit`, the session leaving the official session list, or the user clearing it by hand (CC-013). A user who reads the Turn in Claude Desktop and then goes off to do something else keeps the row forever — and "read it and move on" is exactly how this product expects to be used.

("Forever" holds for terminal sessions but not desktop-hosted ones: Claude Desktop tears those down after 900 seconds hidden, and the row goes with them. That was only measured during the 2026-08-19 review; see rule 3's corrections.)

## Decision

**Read state is a question sourced per product, not a mechanism that can be implemented once.** The Claude Code side splits in two, with entirely different evidence: desktop-hosted sessions ask Claude Desktop's records, terminal sessions ask the kernel about that terminal device. **Neither half asks Claude Code** — it has no concept of read at all.

### Desktop-hosted: answer from "last put on screen"

Claude Desktop keeps, per session, `~/Library/Application Support/Claude/claude-code-sessions/<org>/<account>/local_<uuid>.json` holding `cliSessionId` (the `session_id` the hook carries, so identity needs no guessing), `lastFocusedAt` and `isArchived`. A read-only inspection of package `1.32885.1` (2026-08-19) shows the timestamp's meaning is unambiguous:

```js
setSessionVisibility(id, isVisible, reason) {
  …
  isVisible && (session.lastFocusedAt = Date.now(), this.saveSession(session), …)
}
```

It **stamps the moment a session is put on screen and persists immediately**, by `rename` from a temporary file in the same directory (measured: the inode changes), so a directory-level watcher sees it — the row leaving the notch and the user reading it are one gesture.

**Rule 1: `lastFocusedAt` later than the Turn's end means read.**

The left side of that comparison deliberately comes from this app, not from `lastActivityAt` in the same file. The gap between those two timestamps is the desktop's own unread equivalent, but this app already holds the harder half — when the Turn actually ended, from the evidence that ended it (`Stop`, or the session-status reading in [ADR 0011](0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md)). Using our own half means a desktop's bookkeeping delay, throttling, or total silence cannot make a Turn read; **only a display that genuinely happened after it ended can.** It also makes stale data safe by construction: an old focus timestamp can never overtake a new Turn, so a last-known-good snapshot can only keep a row a little longer, never retire it early.

Archiving counts as read too: it is an explicit action on that session, and the Codex rule already says "remove on read, archive or delete".

### Rule 2: the app returns to the foreground, showing this session

Rule 1 **measured as insufficient**. Verified on a real machine 2026-08-19: the user opens a session in Claude Desktop, submits, switches to another window, waits for it to finish (Completed duly appears on the notch), then **switches back to Claude Desktop to read it** — and the row does not go.

Not because the implementation missed something, but because that reading **leaves no trace on disk**:

| Time | File change | Meaning |
| --- | --- | --- |
| 01:06:33.307 | `lastFocusedAt` ← now | user selects the session in the sidebar |
| 01:06:43.458 | `lastActivityAt` ← now | submit, Turn starts |
| 01:07:37.826 | `lastActivityAt` ← now, `completedTurns` 1→2 | **Turn ends** |
| after | **nothing** | user switches away, switches back, reads it |

A scan of the **entire** `~/Library/Application Support/Claude` tree for files modified in the last 6 minutes then found **0**. `lastFocusedAt` is stamped only when Claude Desktop **puts a session on screen** (switching to it, restoring it), and writes nothing when the window regains focus on the session it already shows. So **no read-only file adapter can ever see that reading**, and what rule 1 misses is this product's most common usage.

**Rule 2: Claude Desktop returns to the foreground after the Turn ended, and Desktop's own records show the last session it put on screen is this one.**

Three qualifications, all required:

1. **It is the transition "returns to the foreground", not the state "is in the foreground".** A user who leaves Claude Desktop in front and walks away is reading nothing; judging on "is in front" retires the row seconds after it appears. Only a person at the keyboard can produce the transition.

   > **Addendum 2026-08-19: this sentence was overturned by rule 3 inside this same ADR.** The description "retires the row seconds after it appears" is accurate; what changed is the last clause's judgement — after weighing it, the product decided that is not the one error it cannot make, only the one of two errors it chose. See rule 3. **Rule 2 itself is unchanged and still uses the transition.**
2. **Only for the session Desktop last displayed** — the one presented when the window comes forward. Another finished session queued behind it was not read, and its row stays.
3. **Only for sessions Desktop knows.** A terminal session cannot be displayed by Claude Desktop, so bringing that app forward says nothing about it. Without this, rule 2 quietly degrades into "touch Claude Desktop and every Claude Code row disappears".

Neither input is a guess: **which session is on screen** comes from Desktop's own records, and **the app came forward** from the public `NSWorkspace.didActivateApplicationNotification` (which names the activated app directly — no window-title matching, no Accessibility, no UI driving). Only together are they evidence of a reading.

### Rule 3: the user read it while it sat where it was

Rule 2 **also measured as insufficient**. On review 2026-08-19, what it misses is the most ordinary case of all: **the session was already on screen before the Turn ended and the user never left that window.** Rule 1 wants a fresh "put on screen" and there is none; rule 2 wants a "return to foreground" and there is none — the window never lost it.

Everywhere still unchecked was then checked, and **the file side ends here**:

| Checked | Result |
| --- | --- |
| Any read field in the records | None. `lastReadAt` / `hasUnread` / `seenAt` / `viewedAt` all zero hits in the package; every `markAsRead` / `isRead` hit belongs to the Outlook MCP connector and is unrelated to sessions |
| Whether `~/Library/Logs/Claude/main.log` says more than the files | ~~No. `[CCD] LocalSessions.setFocusedSession` appears only when switching sessions, a subset of the `lastFocusedAt` stamps~~ **This cell is wrong — see rule 5**: in the decisive direction it is a *superset*, because it also writes `sessionId=null`. The other half stands: no visibility write follows `[SkillsPlugin] Window focused` (0 in both instances, 23:11:42 and 00:17:05) |
| Claude Code itself | Still no focus / read / seen field persisted anywhere |

The same review corrected two previously recorded facts, written here rather than quietly edited:

- **`lastFocusedAt` gets stamped with nobody present.** The machine woke from sleep at 2026-08-19 09:29:00 and at 09:29:09 the on-screen session's `lastFocusedAt` was rewritten, with no `setFocusedSession` anywhere. So rule 1 has a misjudgement in the "retire early" direction: whichever session is on screen at wake is treated as read. It touches only that one session, so rule 4 is not contaminated by it.
- **Desktop-hosted rows are not "kept forever".** That opening sentence holds for terminal sessions only: a local session where `shouldKillOnIdlePause()` is true is torn down by `teardownSession` after 900 seconds hidden (measured: hidden from 22:04:26, torn down 22:19:27), the process goes, the session leaves the official list, and the row follows. So **after switching away a row disappears within 15 minutes at the latest**, and the only genuinely indefinite case is parking on that session. CC-013 is about "wait up to another fifteen minutes after reading", not "forever".

**At the moment a Turn ends, the two kinds of user are identical.** The person sitting there watching it finish and the person who submitted and walked away **differ on no observable signal**: the last thing each did was submit. Waiting grows no difference either — reading an answer produces no event.

So rule 3 stops trying to tell them apart and asks a narrower question it can answer honestly: **is that answer sitting on a screen someone might be looking at?**

**Rule 3: Claude Desktop holds the foreground, the display is awake, unlocked, with no screen saver, the login session is on console, and Desktop's records say the session on screen is this one.**

**This is the product's only rule requiring no gesture at all, and therefore the only one that can retire a row nobody read. That is the chosen error, not an oversight.** Only one of two errors is available: either the person who read it stares at a stale row for another fifteen minutes, or the person who walked away loses a notification. The product chose the latter. The case against is recorded here and is valid and explicitly overridden: a row kept too long can be right-clicked away, while a row retired early cannot be recovered — the two errors are not equally reversible.

"Holds the foreground" alone is poor evidence, since an app can hold it behind a lock screen, a dark display, a screen saver and a switched-away login session. Three public readings subtract those:

| Reading | Source | What it blocks |
| --- | --- | --- |
| Display awake | `CGDisplayIsAsleep` | the screen dimming after someone walks away — where most "away time" actually lands |
| Login session unlocked and on console | `CGSessionCopyCurrentDictionary` | the lock screen, and fast user switching where the screen is not this person's desktop at all |
| No screen saver running | public `com.apple.screensaver.didstart` / `didstop` | setups with a screen saver but no lock. The weakest of the three: the default configuration chains the saver to a lock, already blocked by the row above — and it is a **notification that may be missed**, where the other two are **states that can be read** |

**Hiding the app gets no separate rule**: hiding surrenders the foreground, already covered. **Minimising does not** — the window goes to the Dock while the app stays active, counted as uncovered below.

**No reading can cover** a window that is "in front but not in front of a person": on another display, on another Space, or minimised with the app still active. Answering those means reading window geometry, and that ban stands. A terminal Turn in one of those three states is retired unseen, and that is this rule's accepted cost.

Behaviour by scenario (macOS has exactly one foreground app, one across all displays, which is why the first two rows hold):

| Scenario | Row |
| --- | --- |
| Working in another app (on any screen) | **stays** — the foreground is that app, not Claude Desktop |
| Claude Desktop covered by another window, on another Space, or otherwise not activated | **stays** |
| The Turn finishes while the screen is off | **stays** while off; retired about 1 s after the user wakes the screen |
| Locked | **stays** while locked; retired about 1 s after unlock |
| The user sits there and watches it finish | retired about 2 s after the end (`terminalReadSettlingInterval`), with no action needed |
| The user leaves the window in front and walks away, screen not yet dark | **retired, unread** — this is the accepted cost |

Both inputs remain non-guesses: **which session is on screen** from Desktop's records, **which app holds the foreground** from the public activation notification. All three readings are public, need no entitlement, and measurably prompt for no authorisation. No window titles, no window geometry, no Accessibility, no GUI automation.

### Rule 4: the user moved off it, to another session

One case remains: the user reads it and then **switches to a different session** inside Claude Desktop. Rule 3 requires this session to be on screen, which stops holding; and Desktop records only that a session **was displayed**, never that it was hidden, so the one left behind is never stamped again.

**Rule 4: this app once saw this session sitting on Claude Desktop's screen carrying an ended Turn, and Desktop has since put another session there.**

- **"Once saw" is live observation, never inferred afterwards from timestamps.** Both approaches can answer "was it on screen when it ended", but only the first satisfies `AGENTS.md` §6.2: a timestamp older than this process proves only that some session was displayed at some point, not that it was displaying *then* — and a user deleting a record later would silently hand the answer to the next-newest one.

### Rule 5 is not a new test, but a second source for the sentence the first three share

Rules 2, 3 and 4 all rest on one sentence: **Desktop's records say the session on screen is this one.** That came from "the largest `lastFocusedAt`", and a lost row on the evening of 2026-08-19 shows what it was missing:

| Time | What the user did | What was written to disk |
| --- | --- | --- |
| 21:02:30 | switched to session A | A's `lastFocusedAt` ← now |
| 21:03:30 | opened the composer for a **new session** | **nothing** — a composer is not yet a session, so there is nothing to stamp |
| 21:03:58 | A's Turn ended | row goes Completed. This app still believes A is on screen, so it records rule 4's membership against it |
| 21:04:18 | sent the new session's first message | the new session is displayed → A is displaced → rule 4 holds → **the row disappears unread** |

The same stale sentence also makes rule 3 drop this row earlier (Claude Desktop holds the foreground while the user types in the composer), and makes rule 2 count "coming back to the window to send" as "coming back to read A". **These are not three bugs but one**: the records log a session being **put on screen** and never being taken off, and "taken off, replaced by something that is not a session" is the most common shape of starting a new session.

What rule 3's review missed when it judged the log a subset of the stamps is exactly this half. Claude Desktop writes a line on every navigation, **in both directions**:

```js
setFocusedSession(e){ log.info(`[CCD] LocalSessions.setFocusedSession: sessionId=${e ?? `null`}`), … }
```

(Package `1.32885.1`. `info` is written unconditionally, under no debug switch.) `sessionId=null` is the half the records cannot express.

**So rule 5 is a veto, not a new exit path:**

> **The "this session is on screen" that rules 2–4 require must now hold in the records and in Desktop's log at once; when the log says what is on screen is not a session, none of the three holds. Rule 4 additionally requires the thing displacing it to be a session — a composer is not.**

The direction is deliberately one-way, and is the entire reason for accepting a read of another app's log: **the log can only keep a row longer, never retire one early.** It may not nominate a session the records do not claim, and if the log is missing, rotated, or reshaped by a future version, `unknown` is exactly the behaviour from before this rule. So this dependency's failure mode is "the row stayed too long", not "the row vanished unread" — the same asymmetry-of-reversibility argument as rule 3.

Two qualifications go with it:

1. **Only lines this app watched being appended count.** `AGENTS.md` §6.2 says business state comes only from a current snapshot or events observed since this process started, and a line written last week is neither. The tail already present at launch is read once and **allowed to say only `null`** — the direction that only keeps rows — while any session it names is disregarded.
2. **The `local_<uuid>` → hook identity join still comes from the records** (their `sessionId` field), with no inference; an id that cannot be joined reads as "not this session", which again keeps the row.

The cost, plainly: while the user sits in the composer, this app **does not know** when that session left the screen — only that by some moment it was gone. So in the "read the answer, then casually start a new session" flow, the row that was read is no longer retired by rule 4 and waits for rule 3 (returning to that session) or its own next submission. Working backwards from "a new session was born" to when the composer opened is not possible, and is not guessed at.

### This overturns two written rules

Per `AGENTS.md` §5.2, the conflict is stated:

- PRD §3's non-goals list "guessing session identity, Project, **read state** or navigation target from window focus, paths, titles, temporal proximity or GUI automation".
- `tech-design.md` §1.3 says "Accessibility, AppleScript, title matching, timed removal and 'Desktop got focus means read' are all inaccurate and violate the safety constraints".

Both were written for **Codex**, and neither premise holds on the Claude Code side. Codex has a real unread set (so approximating it with focus swaps good evidence for bad), and Codex has **no source that can say which thread is on screen** (so "got focus" could only be read as "every thread is read", which really is a guess). Here both are reversed: there is no other source, and which session is on screen is a matter of record. What is overturned is therefore not those rules' reasoning but their scope — they continue to bind Codex unchanged.

**Rule 3 overturns more than rule 2, and that must be said plainly.** Rule 2 only treats focus as one of two checkable facts; rule 3 uses the very thing those documents name as forbidden — **"is in the foreground right now"** — and also overturns this ADR's own rule 2 qualification 1. What it buys is the product's only exit path requiring nothing of the user, at the cost of the walked-away user losing a notification (weighed in rule 3). It is still not "focus means read": on the Codex side that sentence could only mean "every thread is read", whereas here it means **the one session Desktop itself records as on screen**, with every other session untouched.

Every surviving ban is untouched: no window titles, no window geometry, no temporal-proximity matching, no row removed by waiting alone, no Accessibility or AppleScript, and a Notch click is never a read.

### ~~Sessions in a terminal: not answered~~ Sessions in a terminal: don't ask Claude Code, ask the terminal

> **The second revision, 2026-08-19, overturned this section's conclusion.** The original is kept below because what was overturned is the **conclusion**, not its reasoning — all of which still holds.

Original:

> **Claude Code has no concept of "read" anywhere.** The session record `~/.claude/sessions/<pid>.json` holds `status`, `waitingFor`, `updatedAt`, `statusUpdatedAt`, `entrypoint`; the 2.1.235 binary persists no focus / read / seen field at all (`isFocused` appears only as an Ink component prop, the terminal interface's own cursor position). Whether the terminal is in front, or the user is looking at that tab, is unknowable outside the process — and that is precisely what `AGENTS.md` §6.2 and PRD §3 forbid guessing.
>
> So these sessions report read state as **unknown** and their terminal rows keep the existing behaviour: next submission, session disappears, or manual removal. They are **not** reported as unread — the difference being that an unknown row **never enters the unread gate** at all: a row that can never be cleared would otherwise re-check once a second, for a question with no answer, until the session ended.

**Every sentence above about Claude Code still holds**, re-checked on 2.1.236: `~/.claude/sessions/<pid>.json` still has no focus / read / seen field, and while the process does hold a `userPresence` object with `lastInteractionTime()` and `terminalFocus()`, it lives only in memory — never persisted, never sent as a hook. "Which tab is in front of the user" is still unknowable and that ban stands.

What changed is that **this half was asking the wrong party**. The original asked whether Claude Code can say if the user read it; it cannot, and the half stopped there. Asked differently: **can that session's terminal say whether the user is in front of it** — a question the kernel has always answered, and answered per device.

**Test: the session's controlling terminal's access time is later than the Turn's end, and the application owning that terminal holds the foreground right now.**

> The second clause was added 2026-08-20. The original test was the first clause alone and was overturned by mouse reporting — see "Access time is not 'someone is there'". The passage below keeps the original order of argument, because apart from that one point it still holds.

`kp_eproc.e_tdev` (public `sysctl(KERN_PROC_PID)`) gives the process's controlling terminal, `devname_r` turns the device number into `/dev/ttysNNN`, and `stat` gives its `st_atime` — **the last time anything was read from this device**. All three are public BSD interfaces; no file contents are opened, no window titles or geometry read, no Accessibility touched.

Measured (2026-08-19, Ghostty + CLI `2.1.236`; re-measured on `2.1.238` 2026-08-20, adding the fifth row) it advances in five situations:

| Action | What reached the terminal |
| --- | --- |
| A keystroke (including the Return that opens the next Turn) | the key bytes |
| That surface **gains** the foreground | `ESC [ I` |
| That surface **loses** the foreground | `ESC [ O` |
| A query the CLI itself sent gets a reply | the reply bytes |
| **The pointer crossing that surface** (foreground not required) | mouse-report bytes |

The middle two work because Claude Code enables focus reporting itself — `ESC [ ? 1004 h` is in the shipped binary, written on every exit from the alternate screen. They happen to cover the terminal's most common usage: switch away while it runs, and **coming back is itself the gesture**.

**Equally important is when it does not advance**, which is the whole reason it is usable:

- **Nothing in another tab, window or application moves it.** Measured: putting a hidden surface through two complete foreground switches changed its access time **0 times**, while the on-screen surface was stamped both times. A surface that is not on screen receives nothing — the "which session is on screen" that the Desktop half needs records to answer is separated natively by the kernel, per device, here.
- **The CLI writing answers out does not move it.** That is the **modify** time, about twice a second during a Turn; reading that one would count every render as a user.
- **The Turn ending does not move it**, tested separately because the whole path is worthless otherwise: running a full Turn on a purpose-built pty (submit → `Contemplating` → answer → Stop hook → `Cooked for 2s`), the access time advanced only at **the startup capability-query reply** and **the moment the prompt was typed**, then not once in 67 seconds. The `OSC 777` notification at a Turn's end is pure output; terminals do not reply to it.

**It is a transition, not a state.** Same root as rule 2, and its entire safety argument: a running machine in front of an empty chair cannot produce one, and the first three actions all need a person at the keyboard.

**The fourth is not a person**, and that is not waved away: every measured query reply happened in the few hundred milliseconds of CLI startup, when no Turn had yet ended in that session, so it cannot be taken as reading any Turn. The real risk is future — a version that re-queries the terminal mid-session would advance the access time with no user present, showing up as a row disappearing early.

**The fifth is not a person either, and it is not in the future.** See below.

**So the terminal half deliberately has no rule 3 equivalent.** Rule 3 exists because Desktop can obtain no **per-session** gesture and must fall back to "is the answer on a screen someone might be watching", accepting retired-unread rows. The terminal half does get a per-session gesture, so it need not make that trade — **when better evidence is available, do not use worse**, which is this ADR's own wording against focus approximation for Codex.

The cost is that "sat and watched, then did nothing" is uncovered, the same user rule 3 rescues. It is far smaller in a terminal: **anything** the user does next retires the row — typing the next prompt (which retires it anyway), switching tab, switching app. What genuinely remains is "read it, then keep staring at that tab motionless", during which the answer is in front of them.

**What used to be called "the only path that can retire an unread row"** is that losing the foreground is not necessarily user-produced: an app raising itself sends the on-screen surface an `ESC [ O`. It is narrower than rule 3 — rule 3 retires even for a user who already walked away, while this requires the answer to have genuinely been on screen at that moment. It is no longer the only one, and **"only" is itself what this revision corrects**.

**Every degradation direction is towards keeping.** A terminal without focus reporting (or a multiplexer with `focus-events` off) is left with keystrokes only, so the row waits for the user's next keypress rather than their return to the tab. A session with **no controlling terminal at all** — `-p` with output piped away, and Claude Desktop-hosted ones — answers `nil`, keeps the behaviour the original described, and still **does not enter the gate**. So the original's reasoning about unknown is not voided by one word; it merely shrank from "every terminal session" to "sessions with no terminal to ask".

### Access time is not "someone is there" (correction, 2026-08-20)

That whole section's safety argument rests on one unverified sentence: **access time advancing = the terminal handed the session something.** It is false, on two levels, both measured directly on this machine that day.

**Level one: it records "the session read this device", not "there was something in the device".** Tested syscall by syscall on a purpose-built pty: a `read` that returned `EAGAIN` having read zero bytes advances the access time just the same, while `write`, `open`, `close`, `tcgetattr`, `ioctl` and `select` on the same device move it not at all. Anything that makes the CLI read will move this reading.

**Level two: Claude Code enables all-motion mouse reporting itself.** `ESC [ ? 1000 h`, `1002 h`, **`1003 h`**, `1006 h`, written once at startup and again mid-session (captured on `2.1.238`). So the terminal writes bytes into the pty for **every movement** of the pointer over the window — no keypress, no button, **and no foreground needed**. And macOS delivers pointer motion to whatever is under the pointer, regardless of which app is active — the very sentence written above when rejecting `CGEventSource` mouse movement ("movement is delivered to what is under the pointer, and on multiple displays can be entirely on another screen"). That hazard was kept out of the Codex half and came back round through the terminal half.

**What it looks like is the bug the user reported**: two displays, Ghostty parked on one running Claude Code and never once focused, and the row vanishing the instant the Turn ended. The pointer merely passed over that window, or even just crossed between displays; the gate re-checks a finished Turn once a second, and hiding is final for that Turn (CC-024), so one pass is enough and it is irreversible.

**Why "read it more carefully" is not available.** Access time is a scalar. By the time it is read, whether a keystroke, a focus report or a stream of mouse reports moved it no longer exists as information. Distinguishing them at that layer asks the kernel to have recorded what it did not.

**Correction: bind the gesture to "is that terminal in front of a person".** The test becomes access time ≥ the Turn's end **and** the application owning that terminal holds the foreground right now (with the display awake, unlocked and not user-switched — reusing rule 3's three readings). "Owning application" is answered by the process chain: walk up from the session pid and check whether the foreground process is one of its ancestors (`claude` → login shell → `login` → that terminal), needing no terminal allowlist, no bundle id, and no judgement about "which level counts as the app".

This folds a **state** into a **transition**, the same direction as rule 3's reversal — but here it is only an `AND`, so it can **only narrow** the path and can never retire an extra row:

- the pointer crossing an **unfocused** window: no longer counts;
- an `ESC [ O` caused by another app grabbing the foreground: no longer counts, because at sampling time the foreground belongs to the app that grabbed it;
- keystrokes and `ESC [ I`: still count, as both already require that terminal to be in front.

**It is still a transition first**, so "a running machine in front of an empty chair cannot produce one" still holds: the state alone can never retire a row.

**Two new costs, recorded in opposite directions:**

- **Sessions inside `tmux` / `screen` / `ssh` are no longer removed automatically.** Walking their chain upwards only reaches `launchd`, and the host never holds the foreground. This is a **new degradation**, still in the keeping direction: the row now waits for the next submission, the session disappearing, or manual removal.
- **An unread row can still be retired**, in two places: pointer movement over a terminal window that **does** hold the foreground counts as read (the same trade rule 3 makes for a window left in front of an empty chair, and narrower — it also requires someone to have moved the pointer); and the foreground is sampled about a second after the gesture, so a user leaving in the milliseconds between `ESC [ O` and the workspace notification reads as not having left.

**The lesson for whoever is next**, since it is worth more than the rule: this path measured "a whole Turn does not move it", "a hidden surface does not move it" and "writing does not move it", each solidly — and never measured **what this reading actually records**. Measuring every corollary of a proposition is not the same as measuring the proposition.

### The five are peers: remote control means the "two halves" are not exclusive

The split above reads like a partition — desktop-hosted sessions have records, terminal-started ones do not, and between them everything is covered. **Remote control overturns that.** With it on, one session sits in two places at once: the running process in the terminal, and the view in Claude Desktop (or on a phone). Approval and input work from either, and both show the same Turn.

The two sides are read by **different gestures**, and only one writes anywhere this app can see:

| Where the user reads | Desktop record's `lastFocusedAt` | That session's terminal access time |
| --- | --- | --- |
| In the terminal | **unmoved** | advances |
| In Claude Desktop (if it made a record for that session) | advances | unmoved |

So rule 5 is **not** a fallback behind the first four but their peer: **any one of the five means read.** As a fallback, a session present on both sides would always defer to the Desktop record, which never advances for a user who read it in the terminal — so the row would never leave, exactly the CC-013 failure recurring in a new configuration.

**The reverse direction is safe, structurally rather than by luck.** The terminal rule can only hold for a session that genuinely has a controlling terminal, and Claude Desktop-hosted sessions do not: Desktop runs the CLI as `--output-format stream-json` over pipes with no terminal interface — which is also why those sessions have no `status` at all ([#41](https://github.com/soondubu137/notchline/issues/41)). So applying it to every session changes nothing about the Desktop half.

**Remote control also cannot manufacture a false gesture**, worth stating because it is the obvious worry: remotely submitted input arrives over `/tmp/cc-socks/<pid>.sock`, not that tty. And even if it did write the tty it would be harmless — remote can only send a **submission** (which opens a new Turn, so the row goes back to Running) or **an approval during a Turn** (earlier than that Turn's end). Neither can land in the only meaningful window: after that Turn ended and before a new one starts.

**Measured 2026-08-19: a CLI session with remote control on has no record in the `claude-code-sessions` tree at all.** No file anywhere under `~/Library/Application Support/Claude` mentions its `sessionId`, nor the `bridgeSessionId` (`session_01…`) from the session record — Desktop learns about it through a server-side bridge that never touches local disk. So **today** it answers `unknown` as before and rule 5 is its only answerer, and the branch above is unreachable. It is written into the code because it is a fact about one version, not a property the product should rely on.

### One hole remains: a remote-controlled session read on the Desktop side

Stated up front: a user who reads a remote-controlled session on a phone or in Claude Desktop and then does not touch the terminal **keeps the row**. Neither side has evidence — Desktop made no record for it (measured above) and the terminal was never touched.

The user's observation that "reading it in the CLI also clears the unread marker in Claude Desktop" shows the two sides really do sync read state, but that sync **happens server-side** where this app cannot reach — not a byte is written locally. Unless it lands locally in future, or an official queryable interface appears, this hole cannot be closed.

It at least falls in the safe direction: the row stays rather than vanishing early. And it converges on its own — the next thing the user does in that terminal, or the next Turn submitted from either side, takes the row away.

### Addendum 2026-09-12: rule 5 answers for a third product, and the gesture is the product's

This ADR was written about two products and its title is what generalises: **read state is answered per product, or not at all**. Rule 5 turned out to be the part that transfers, because it asks the kernel about a process rather than a product about itself. Antigravity CLI — L3 under the [current support contract](../product-support.md), no desktop application, no concept of read anywhere in it — now retires its finished rows by exactly this test, with the process taken from the presence lock its conversation holds. The reading itself is unchanged and is now written once (`TerminalReadEvidence`), rather than copied.

**Antigravity Desktop, 2026-09-12, is the other half of the title.** The same product gained a desktop surface, and that surface keeps a record: a per-conversation view time its own sidebar draws unread from. So a Desktop conversation's row is answered by that record and never by a terminal, and a CLI conversation's by its terminal and never by the record — per product turned out to mean per surface of a product, decided by which surface the conversation's events came from ([`antigravity-desktop.md`](../technical-explorations/multi-product-provider-architecture/antigravity-desktop.md) §6).

**What does not transfer is what the terminal sends, and that is a per-product measurement rather than a property of terminals.** Claude Code enables focus reporting *and* all-motion mouse reporting, which is why the 2026-08-20 correction above had to pair the gesture with the foreground. Antigravity CLI's TUI enables neither (measured on a pty, 2026-09-12: `?1049h`, `?25l`, `?2004h`, and nothing else, at launch or later). So on that product the early-removal path this ADR lists under Costs — the pointer crossing a foreground terminal window — **cannot occur**, and the "read it, then sit motionless" hole is correspondingly wider: without focus reporting, even switching back to the tab sends nothing, so the row waits for a keystroke. Both differences fall the way this ADR prefers, and neither is a new rule.

**The pairing is kept regardless**, for a reason the ADR should be explicit about: it is not a workaround for mouse reporting but the sentence rule 5 shares with rules 1–4 — *while the answer was in front of the user, the user did something only a person does*. A product that happens not to report motion today does not get a looser test than one that does.

## Local Codex CLI amendment (documented 2026-09-22)

The local CLI implemented on 2026-09-15 uses rule 5 through `TerminalReadEvidence`. A gesture after completion must come from the owning TUI's controlling terminal, with that host in front and the screen available. Native CLI 0.154.0 enables focus reporting and bracketed paste but no mouse reporting. Ghostty was verified delivering focus reports only to its focused surface; Apple Terminal supplies no such report and requires input. TUI output and completion alone do not advance the reading.

This does not establish which Thread the TUI displays. `/new` retains the previous execution ownership until later evidence, so a gesture may retire every ended Turn that TUI owns. That accepted scope differs from precise Thread navigation, which remains unsupported. Desktop unread absence never judges CLI rows; a Thread owned on both surfaces is judged by neither and remains until dismissal, a later submission or loss of ownership. Unsupported SSH/multiplexer modes have no terminal read claim. The original current-view proposal was rejected; this narrower gesture rule supersedes the initial no-read-removal implementation. [Support and acceptance](../product-support.md#51-local-codex-cli).

## Rejected alternatives

- **~~"Claude Desktop is in the foreground right now" means read.~~** The recorded reason was "it retires the row for a user who has left their seat", and that sentence still holds. **Accepted 2026-08-19** in a qualified form — see rule 3: plus the three readings (display awake, unlocked, no saver, session on console) and "only for the one session Desktop's records place on screen". The explicitly accepted cost is that original objection. What remains rejected is the **unqualified** version, which would retire rows behind a lock screen and a dark display, and would empty every Claude Code row at a touch of Claude Desktop.
- **Infer a terminal session's visibility with `ps -o tty=`.** A terminal window has many tabs, and bringing the app forward says nothing about which tab is being looked at — the opposite of the Desktop side, where which session is on screen is a matter of record. **Still rejected.** The terminal half uses the same `tty` but does not ask it this: it asks whether anything was read from the device, a kernel-recorded per-device fact rather than an approximation derived from "the app is in front". That difference is exactly what this item objects to — spreading an app-level state across every tab beneath it.
- **A fixed retention period.** Timers do not produce business state; repeatedly confirmed in this repository.
- **Treating a Notch click as read.** That is this app's own "acknowledged" and cannot cover reading directly in the desktop app; and per CC-012 the click is spent on navigation (raising the host), and one interaction cannot be two things.

  (**Right-click removal of a terminal row is not this.** It claims no reading and enters neither half of this ADR's test — the test sources only from the products' own evidence, and a right-click is never fed to it. It is the user saying "I am done with this row", which needs no evidence, only their say-so. It also uses a different gesture: left-click still only navigates, so one interaction is still one thing.)
- **Using `lastActivityAt > lastFocusedAt` as the unread set.** As above: it hands both halves to the desktop app when this app has a better left half of its own.
- **~~Retiring the on-screen row the moment the Turn ends.~~** As above, **accepted**: rule 3 retires it about 2 seconds after the end (`terminalReadSettlingInterval`, originally headroom for the desktop's roughly 583 ms persistence delay). The judgement that the two users are identical at that moment is unchanged; the conclusion drawn from it changed — identical means indistinguishable, so the product picked one of two errors rather than keeping the row indefinitely.
- **Reading `setFocusedSession` from `main.log`.** It says no more than `lastFocusedAt` (only on session switches) in exchange for a more brittle dependency — log level, line text and rotation are not contracts. *(Superseded in one direction by rule 5, which uses the `null` half only.)*
- **Counting "another ordinary app taking the foreground from Claude Desktop" as read.** It covers "read it then switch to another app", at the cost of one focus steal by another app — which also happens while the user is away — retiring an unread answer. Rule 3 now covers an earlier moment in that same usage.
- **A keystroke or scroll as evidence (`CGEventSource.secondsSinceLastEventType`).** This version was **implemented and shipped** (`c1052bb`) and replaced by rule 3; recorded as it was: the rule was "after the Turn ended, the user typed or scrolled into Claude Desktop and the session on its screen is this one", with mouse movement excluded (delivered to whatever is under the pointer, possibly on another display entirely) and clicks excluded (this app's own overlay can absorb one without changing the foreground). It is safer than rule 3 — someone who left cannot produce a gesture — but **it does not answer the question the user asked**: for someone who sits, reads and does nothing, the row never goes. Measurement also exposed an unresolvable ambiguity: unlocking requires typing a password, and `secondsSinceLastEventType` is machine-wide and cannot tell those keystrokes from typing into Claude Desktop.

## Costs

- ~~**Only half the users are covered.** Pure terminal users get nothing.~~ **Cancelled by the second revision, 2026-08-19.** The final clause ("the other half has no observable truth") was wrong in a specific way: what has no observable truth is *which tab is in front of the user*, not *whether the user is in front of this session's terminal* — which the kernel has always recorded, per device. Terminal users now get stricter exit paths than Desktop users: entirely gesture-driven, with nothing like rule 3's state-only path. **What is genuinely uncovered** is sessions with no terminal to ask: `-p` with output piped away, and desktop-hosted ones whose Desktop record cannot be read either.
- **The terminal half has one early-removal path.** An app raising itself sends the on-screen surface an `ESC [ O`, which reads like the user switching away. It requires the answer to have genuinely been on screen at that moment, so it is narrower than rule 3 — but it can retire an unread answer.
- **The terminal half does not cover "read it, then sit motionless".** That is the same user rule 3 rescues, and the terminal half chooses not to; the reason (anything the user does next retires the row) is in that section. So the product gives one user two different answers on its two halves — a deliberate inconsistency: whichever half has a per-session gesture uses it.
- **A second private read-only schema dependency**, at the same risk level as the Codex unread adapter, plus one undocumented bundle identifier (`com.anthropic.claudefordesktop`, used only to recognise the app inside the public activation notification). Both registered in [`non-public-codex-integration-features.md`](../non-public-codex-integration-features.md).
- **A user who leaves the window in front and walks away loses that notification.** In the window before the screen dims or locks, rule 3 cannot tell them from someone watching and retires the row. This is the explicitly chosen cost (see rule 3), bought in exchange for the reader who moves on not having to wait.
- **The three "in front but not in front of a person" states are uncovered**: another display, another Space, minimised with the app still active. Answering them means reading window geometry, and that ban stands.
- **Three early-removal paths**, with every other failure falling towards keeping:
  - Rule 3 itself, above.
  - The user closed that session's window (the records still call it "last displayed") and later brings Claude Desktop forward for something else — the row is removed as read. It requires the session process to still be alive after the window closed (or the row would already be gone with the session), so it is hard to hit in practice, and what is removed is a session the user had open not long before.
  - On wake from sleep, Claude Desktop re-stamps `lastFocusedAt` for **the session on screen** (measured 2026-08-19: wake 09:29:00, stamp 09:29:09). The answer is on screen at wake, so it is not far-fetched — but it is a way rule 1 can hold with nobody present.
