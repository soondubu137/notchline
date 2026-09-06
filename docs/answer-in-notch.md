# Notchline — Answering in the notch

| Field | Value |
| --- | --- |
| Status | **Stage 01's dependency is built; the drawing is not.** §14.1 landed on 2026-09-05 — the app keeps the request it was already being sent, the reducer holds it on the wait that asked, and it reaches `MonitorSnapshot`. Nothing draws it yet. §15 q01 and q02 are both **answered** below, and q01 came back further than expected: a write path exists on both products, and on Claude Code it reaches questions too. The rest ships in three stages. §11 reads a request and needs only §14.1, one field this app already receives and discards. §3 to §8 answer one with the pointer and need §14.2, a capability neither product offers. §9.3 — the chord, and everything that navigates without a pointer — is designed, deferred behind both, and kept here whole. |
| Version | 1.3 |
| Date | 2026-09-05 |
| File | [Notchline V2](https://www.figma.com/design/c3CQBBk3Boiu0oM00Vvs9Y/Notchline-V2) — `10 — The answer`. `11 — The panel, whole` redraws the open row on the composed surface and corrects §12's panel column — see [`panel-v2.md`](panel-v2.md). |
| Scope | What happens between a request arriving and a person answering it: how the request reaches somebody who is not looking at the notch, every shape the two products ask in, what an opened row draws for each of them, what a click takes, which keys the panel answers to and which wait for the keyboard half, and what the row becomes once the answer has gone. The band, the quota footer and both collapsed forms are untouched, and nothing here reaches the collapsed surface. |
| Supersedes | [`expanded-panel-v2.md`](expanded-panel-v2.md) §3 entire. Three of its clauses are corrected rather than extended, each marked below: §3.1's opening gesture (§3), §3.2's fade and its three-line cap (§4), §3.5's close-on-send (§8). A fourth — §3.4's forces on the affirmative — **is not corrected in the initial version**: it is right for a surface answered with the pointer, and the correction arrives with the keys that make it necessary (§6, §9.3). §2 — the Recent queue — is untouched and independent. |

## 1. What this designs, what it waits on, and what it ships first

[`expanded-panel-v2.md`](expanded-panel-v2.md) §3 established the idea: a row already draws a bright ground on exactly the two states with something to answer, so make that ground the control. It then drew one open approval row and stopped. Three things were left undone, and each of them turns out to decide the shape of the whole.

**The journey was never designed, only the destination.** A request arrives while a person is inside an editor or a terminal with both hands on the keyboard. Answering it today costs eleven steps — the bar knocks, look up, find the pointer, travel to the notch, hover and hold still, read one truncated line, click the row, the product takes the screen, find the dialogue, answer, come back — of which six cannot be taken without the pointer and only five happen on a surface this app draws. What disturbs the work is not the answering. It is the journey to the place where answering is possible — and that journey has two halves, **the travel to the notch and the departure to the product**, which are removed by different things. §1.1 is why they are removed in a different order.

**One shape was designed for; there are seven.** Both products ask in more than one way, and the ways are not interchangeable: one carries a command, one carries a document, one carries a list of answers somebody else wrote, and one carries a form built at run time by code this app has never seen. §2 enumerates them from the event set this app already registers.

**The request itself has never reached this app.** `HookPayload` decodes `tool_name` and `tool_use_id` and not `tool_input`; `HookPayloadDistiller` steps over every top-level key `CodingKeys` does not name. That is deliberate and correct — an oversized `PostToolUse` tool result once took a lifecycle event down with it (CR-030) — but its effect is that the bytes for every request below already arrive on the socket and are discarded one step before the decode. §14.1.

**What follows adds no region, no ink, no corner and no curve.** Every state in it is an object the panel already draws, given one more dimension.

### 1.1 Three stages, and the initial version is the second

| | Stage | What it waits on | The journey it leaves |
| --- | --- | --- | --- |
| 01 | **Read it here** — §11 | §14.1, one field this app already throws away | Eleven steps still, and not one of them a guess: the reader decides whether to leave at all knowing the whole request, instead of leaving in order to find out what it says |
| 02 | **Answer it here, with the pointer** — §3 to §8 | §14.2, a write path per product | **Eight steps on one surface**: the bar knocks, look up, find the pointer, travel to the notch, click the mark, read it in full, type or don't, click the answer |
| 03 | **Answer it here, without the pointer** — §9.3 | Nothing outside this app: a chord, and the navigation under it | **Five steps and no pointer**: the bar knocks, `⌥Space`, read it in full, type or don't, `⏎` |

**Stage 02 is the initial version of this experience, and stage 03 is deferred.** This document keeps stage 03 whole rather than deleting it: the argument is the expensive part, and half a keyboard model is worse than none.

Eleven to eight removes four steps, **three of which belonged to another application** — the screen surrendered, the dialogue found, the journey back — and turns the single act of answering into two, which is what doing it here costs. Eight to five removes four more, **three of which are the pointer's**. Both are worth having, and the first is at once the larger removal and the cheaper one to build: it needs a write path and no new mechanic, where the chord is the only genuinely new mechanic on this page — a global hotkey that can fail at registration, a settings row to report what it actually holds, and a keyboard model that has to be complete before it is honest. **Shipping them together would hold the larger saving behind the smaller one.**

Nothing is thrown away by taking them in this order. Every object stage 03 touches is one stage 02 already draws; it adds keys, and the only thing it draws is a word this surface already draws under the pointer (§3.3). What waiting for it costs is stated where it is felt — §13.3, and it is not merely a delay: **the initial version cannot be operated from the keyboard alone.**

## 2. The forms a request arrives in

Measured 2026-09-04 from the events [`tech-design.md`](tech-design.md) §9 registers, the schemas recorded in [`technical-explorations/claude-code-support/`](technical-explorations/claude-code-support/README.md), and the `AskUserQuestion` payloads in this machine's own transcripts.

| Product | What arrives | What the payload carries | What can be answered |
| --- | --- | --- | --- |
| Claude Code | `PermissionRequest` | `tool_name`, `tool_input`, optional `permission_suggestions` — the tool's own arguments: a command, a path, a patch, a URL | Grant it, or refuse with a reason |
| Claude Code | `PermissionRequest` — `ExitPlanMode` | `tool_input.plan`: a document, in prose and markdown, routinely longer than the whole panel | Accept it, or send it back with a note |
| Claude Code | `PreToolUse` — `AskUserQuestion`, **and a `PermissionRequest` for the same call** | `questions`: one to four of them, each with a `header` of at most sixteen characters, the question, two to four labelled `options` carrying a `description` each, and `multiSelect` | One option, several options, or your own words — once per question |
| Claude Code | `Elicitation` / `ElicitationResult` | An MCP server's own form, described by a JSON schema it chose | **Not from here** — §11 |
| Codex | `PermissionRequest` | The command, under the shipped `permission-request.command.input` schema. No `tool_use_id`, which is why the wait borrows the open call | Grant it, or refuse with a reason |
| Codex | `PreToolUse` — `request_permissions` | A dedicated approval that stays open for exactly as long as a person is being asked — a network access, say | Grant it, or refuse |
| Codex | `PreToolUse` — `request_user_input` | A question, with no options attached to it | Your own words |

**A question is a set, not a question.** Across every transcript under `~/.claude/projects`, 86 questions arrived in 55 calls: 32 calls carried one, 17 carried two, 4 carried three and 2 carried four. **63% of questions therefore arrive in a call carrying more than one**, options run two to four with three the mode, and `multiSelect` is rare but real. That measurement is what makes the position in the set (§5.2) a drawn element rather than an edge case.

### 2.1 Seven shapes, four drawn forms

| | Form | Where it comes from | What the row draws |
| --- | --- | --- | --- |
| 01 | **A command to grant** | `PermissionRequest` on either product, and `request_permissions` | Machine text on the recessed ground, verbatim, scrolling past the fold. Two answers, and a field that belongs to the refusal |
| 02 | **A document to accept** | `ExitPlanMode`, and anything else that hands over prose | The same body set as prose rather than machine text, and taller: a plan is read, not scanned. Two answers — §4.3 |
| 03 | **A question with options** | `AskUserQuestion` | The header and the position in the set on the caption line, the question and the options as the body, and the field beneath them |
| 04 | **A question with none** | `request_user_input`, and any option list once a person decides none of them is right | No body at all. The question sits where the preview does, and the field is the whole answer. The shortest row that can be opened |

### 2.2 The form this declines, and why it is a boundary

An `Elicitation` is a form whose fields a third-party MCP server chose at run time, of arbitrary shape, count and validation. Drawing it would make this panel a general form renderer for code it has never seen, inside 240 points, and **a half-rendered form is a wrong answer submitted confidently**. That row keeps §11's reading treatment and sends the person to Claude Code, which is where a form belongs.

This is a capability boundary rather than a deferral, on the same footing as the Codex side chat ([ADR 0017](adr/0017-a-row-requires-a-thread-the-app-server-vouches-for.md)). It is worth reopening only if the shapes servers actually send turn out in practice to be a small closed set, which is a measurement nobody has taken.

### 2.3 The row draws the product's own words

A question's options are labelled text in the payload, so those words are drawn and never a paraphrase of them. Where no labels arrive — an ordinary approval — the row uses the fixed pair `Approve` / `Deny`, which is both products' own three-part question minus the one this design declines to offer (§6.5). **Nothing on this surface invents a word that a person's answer will be recorded under.**

## 3. Two targets on one row

**A correction to §3.1**, which made the reading's ground open the row on a click and drew the word `Answer` in it. The gesture is kept and its consequence is made explicit: the mark is now a second target, and the two targets are the two answers to *what do I want with this row*.

- **The text is the Thread.** A click anywhere on the badge, the Project, the title or the preview opens that Thread in its product, exactly as it always did ([`figma-design.md`](figma-design.md) §9.2).
- **The mark is the request.** A click on the bright ground opens the row here.

No other row gains a click, and no row gains a second destination — a `Running` or `Completed` row has no mark, so it stays a single target.

### 3.1 The ground travels; it is not duplicated

Opening does not create a second bright object. The ground the pointer pressed **grows from `16` to `28` and travels from the caption line down to the answer row**, where it becomes the affirmative. So the surface never draws two white grounds at once, and what the ground means never changes: it is the thing that wants you, and then it is the thing `⏎` will do.

### 3.2 The chevron takes the place it left, and it is the exit

Where the mark was, an open row draws **the quota block's own control unchanged** — `16 × 16`, a `9 × 4.5` glyph at `1.4` stroke with round caps in `#7C7C80`, pointing up because the thing it folds is open ([`expanded-panel-v2.md`](expanded-panel-v2.md) §2.2). A click collapses the row, sends nothing, keeps whatever was typed and whatever part of a set was answered, and leaves the request exactly where it was. `⎋` does the same from the keyboard.

### 3.3 The word in the mark

At rest the mark says `Approval needed` or `Input needed`. Under the pointer it says `Answer` where the request can be answered here and `Read` where it cannot (§11). **The ground does not resize** — only the word inside it changes, so nothing on the row moves under a passing pointer. Which settles what the ground says at rest: it is sized for the longest name it can hold, so [`figma-design.md`](figma-design.md) §4.7's *reading* — a duration — cannot be what is in it, or `Answer` would not fit without moving it. The duration keeps the place it already had, on the finished row's dark ground ([`panel-v2.md`](panel-v2.md) §3.5).

Drawing the word under keyboard focus as well as under the pointer would be **a correction to §6** of the superseded document, and it is **not made in the initial version**: with no keyboard path there is no focus to draw it under. It arrives with the keys that create one, because a keyboard user would otherwise never see the affordance they are about to use — §9.3.

## 4. The body

Everything between the title line and the answer row is **one scrolling body**, and it holds whatever this request turned out to be.

### 4.1 It is bounded by the panel, not by a line count

**A correction to §3.2**, which capped the request at three lines and faded the rest.

```text
body ≤ 140 = viewport 240 − (12.5 + caption 16 + 2 + title 17 + 2) − (10 + answer row 28 + 12.5)
```

So **the tallest an open row can be is the viewport itself**, there is one number to remember rather than one per form, and below it the body hugs its content — a one-line question makes a `117` pt row and the rows under it stay on the list. Every height in §12 is this one arithmetic.

### 4.2 Two settings, decided by the payload and never by length

| Setting | For | Treatment |
| --- | --- | --- |
| Prose | A question, a restatement, a plan — sentences a person is meant to read | `13` pt Regular at `#C7C7CC`, no ground, the content width |
| Machine text | A command, a patch — strings a machine will execute | SF Mono `12/18` at `#C7C7CC` on `#242424` at corner `4`, inset `10` horizontally and `8` vertically |

The recessed ground exists to mark the second kind. Putting the first kind on it would make the mark mean nothing, so **which setting a request gets is decided by which payload it came from** — never by how long it is.

### 4.3 A document is accepted, but its mode is not chosen here

A plan's product offers three answers: accept and auto-approve the edits that follow, accept and approve them one by one, or keep planning. The middle of those is **a policy about every edit that follows, taken from a panel showing part of a plan**, and §6.5 already forbids a policy from being what `⏎` does. So the row offers two — `Accept`, and `Send it back` with a note — and accepting from here accepts into whatever mode the session already has. The row says nothing about a mode it did not set.

### 4.4 It scrolls, and it says how much is under the fold

A fade is right for a title, where what is lost is more of the same sentence. It is wrong for a command, where what is lost may be a second command after `&&`, a `--force`, or a path outside the project. So the body ends in **a count of the lines not on screen** — `+2 lines`, `11` pt at `#7C7C80`, at the body's trailing foot over the fade its last line already has — and the count **clears when the last line is on screen**.

A count that names something unreachable is an apology, which is why the two arrived together: the body scrolls on the pointer's wheel — the only thing that scrolls it until §9.3's arrows land — with a `1.5` pt rail at the body's trailing edge in the panel's own hairline value (white at `15%`) and a thumb at white `50%`. The rail reports where the reader is; at `1.5` points it is not a grip, and it is never the only way to move. **Nothing else on this surface scrolls, and nothing else needs to.**

### 4.5 Wrapping preserves what indentation meant

Line breaks are the ones the product sent. A line wider than the body wraps at its edge and the continuation carries **that line's own indent plus two spaces**, so a wrap is never read as a new argument. Whitespace is never collapsed, order is never changed, and a token with nowhere to break is broken at the edge rather than dropped.

### 4.6 The app never marks a command as dangerous

No verb list, no warning glyph, no colour, ever. A heuristic that knows `rm` does not know `find -delete`, a `tee` into a path, or a pipe into a shell — **every miss is silent, and every hit teaches the reader that an unmarked command has been checked by something**. Nothing on this surface has been checked. The app shows what it was handed, says how much of it is on screen, and leaves the judgement where it already was.

## 5. A question with options

### 5.1 Composition

| Object | Height | Treatment |
| --- | --- | --- |
| The question | `17` per line, prose | §4.2's prose setting |
| An option | `24` | Numeral, label, description, on one line |
| The answer row | `28` | The field and `Send` |

An option's numeral is `11` pt SF Mono at `#6E6E73` at `+9` from the option's leading edge; the label is `13` pt Medium at `#F5F5F7` at `+28`; the description follows it after `12`, `13` pt Regular at `#7C7C80`, ending in the row's own fade. **The option the ground is on carries the white ground** across the full content width at corner `4`, with its label at `#0D0D0F` and its numeral and description at `#5A5A5E`. An option under the pointer takes the list's own hover fill instead, and the ground does not move to meet it (§6.6).

### 5.2 The position in the set

The caption line carries the badge and the Project on the left and **nothing at all on the right**, so the header and the count sit there — `Scope · 2/3` — in the caption's own ink at `11` pt, tabular, `8` before the chevron. Both come from the payload.

- **Every question draws it, `1/1` included.** A count that appears only sometimes is a count nobody learns to read.
- **Codex sends no header**, so that side carries only the chevron there. Claude Code's header is at most sixteen characters by its own schema, so header and count together never threaten the badge.

### 5.3 Answering one question of a set sends nothing

The set goes back as one answer, so `⏎` on question two draws question three — the body alone changes, the head and the answer row stand still — and sends nothing. **The count is what makes that legible**: without it, an answer that appears to do nothing looks like a failure. Closing part-way keeps what has been answered with the row for as long as the row lives, exactly as typed text is kept, and reopening resumes where it stopped.

### 5.4 The field is on every question form

Both products accept an answer that is not on the list, and it is often the real answer. So a field sits beneath the options in every question form with its own placeholder, and **typing into it moves the white ground onto `Send`** and off whatever option was selected — the same one rule as everywhere else (§6).

### 5.5 Several answers means no option can be the return key

With `multiSelect` the ground **starts on `Send` and never leaves it**, the numerals become `12 × 12` boxes at corner `4` — `#242424` empty, the theme ink's lit value filled — and a click on a box or its label ticks it. (`Space` ticks the option the ground is on when §9.3 lands. Until it does, no option ever holds the ground — it never leaves `Send` — so a click is the only thing that could tick one.) The alternative, `⏎` toggling and something else sending, would make the brightest object on the row stop being what `⏎` does, on the one form where a person is most likely to press it twice.

### 5.6 A restatement is a question whose question is long

Claude Code will sometimes put back what it understood and ask whether that is right. It is the same machinery — the summary is the question, and two options stand under it — so nothing special is needed to support it, and that is the point. What it does need is §4.2's prose setting and §4.4's scrolling, both of which it shares with a plan.

## 6. One selection rule

**The brightest object on the row is always the thing the return key will do.**

It begins on the affirmative, or on the first option a question offers. **One force moves it in the initial version, and it is the person's own act: typing**, which moves it to the answer that carries text — `Deny` on an approval, `Send` on a question — because a note cannot travel with a yes. The answer it left is still clickable and still discards what was typed; it is simply no longer the key.

**§3.4 therefore stands as written**, and the second force it needs is deferred with the keys that need it. Once the arrow keys exist they move the ground along whatever answers this row has — two on an approval, up to four options and a field on a question, one on a question with nothing to pick — and the rule becomes *only two forces, and both are the person's own act*. That is a correction to §3.4 the moment there is a keyboard user, because a rule where only typing moves the ground would leave the non-default answer reachable by pointer alone. Until there is one, nothing on the row is out of reach: every answer is one click away (§6.6). §9.3.

### 6.1 One rule, every form

An approval has two answers, a question up to five, a plan two, and a question with nothing to pick one. On all of them the ground is the current answer, a click takes whichever answer it lands on, `⏎` takes the one the ground is on, and typing moves the ground to the answer that carries text. **There is no second selection model for lists and no separate default-button concept underneath — the ground is the state.**

### 6.2 The wheel is the only thing that scrolls, and the list does not walk

The pointer's wheel scrolls a body taller than the space it has, and nothing else does. With no row open there is nothing to move at all: opening is a click on a mark, and the list is browsed by hover exactly as it always was.

The arrows arrive with §9.3, and so does the one thing they need decided — that on a row whose body holds **options** all four move the ground and the body scrolls to keep it in view, while on a row whose body holds **no answers** the axes divide the way the drawing already does: `←` and `→` between the two controls, `↑` and `↓` down the body. That argument is kept there rather than deleted, because it is the part that took the thinking.

### 6.3 A ground that has not finished arriving is not a key, and not a target

Answering one question draws the next, and answering one request opens the next row (§8.2). Both put something the reader has never seen under a control the pointer is already on — and, later, under a return key a finger is already on. So the affirmative is **armed by the arrival it already animates**: the ground grows on the panel's own slot curve, and it takes a click, or a return, when the growth ends. Nothing new is drawn and nothing is delayed that the eye was not already waiting for.

**This is worth more with a pointer than it was with a keyboard**, and the drawing is why: an answered row is replaced in place by the next thing to answer, so the affirmative that arrives lands where the affirmative just clicked was. A hand has to travel to press `⏎` a second time. A pointer has to do nothing at all.

The rejected alternative was a fixed delay before the control becomes live, which would have been a new timing to tune and would have felt slow on the row a person opened deliberately.

### 6.4 Denial is the cheap direction

An empty `Deny` sends a plain no. A `Deny` carrying text sends the text, which is the third answer both products actually offer — *no, and here is what to do instead*. The caret is in the field from the moment the row opens, so refusing with a reason is a sentence and a return and no travel at all; granting needs either an untouched field or a deliberate move back to the affirmative.

### 6.5 `Always` is not offered, and neither is a plan's mode

Both products' second answer is *yes, and do not ask again*. It is a policy about every future request, taken from a panel showing part of the current one. Notchline answers this request and hands policy back to the product. If it is ever added it belongs beside the affirmative in the recessed ink and **never on the white ground, because the white ground is the return key**.

### 6.6 What a click takes, and what hover never does

The initial version is answered with the pointer, so the pointer's rules are the ones that have to be exact.

- **A click takes the answer it lands on**, whether or not the ground is on it: `Approve`, `Deny`, `Send`, `Accept`, an option, or — where several answers are allowed — the tick beside one (§5.5). An option is a button. There is no select-then-confirm on this surface, because the confirm would be a second control saying what the first already said.
- **Hover moves nothing.** An answer under the pointer takes the list's own hover fill and the white ground stays where the person's own typing left it. The ground is a statement about `⏎`, and a pointer crossing an answer is not an act.
- **The field takes the caret when the row opens**, so a note costs no click of its own and §6.4's cheap refusal stays cheap.
- **A click that is not on an answer is not an answer.** The body and the rail take clicks and do nothing with them. The only two regions on an open row that lead anywhere else are the chevron, which collapses it, and the row's own text, which opens the Thread (§3).

## 7. The answer row

```text
Approval      [ what to do instead…        ]   Deny   [ Approve ]
Input         [ your answer…                        ]  [ Send ]
Plan          [ or say what to change…     ]  Send it back  [ Accept ]
```

At the content width of `496`, relative to the content's leading edge:

| Object | Extent |
| --- | --- |
| The affirmative | Right-aligned; width is its own text plus `12` each side |
| The refusal | `8` before the affirmative; the same padding when it holds the ground, bare `13` pt Medium `#C7C7CC` when it does not |
| The field | From `0` to `8` before the refusal |

Both grounds are corner `4` and `28` tall — the mark's own `16` grown by §3.1 — and **neither control moves when the ground crosses between them**. A form with one answer (`Send`) omits the refusal and the field takes the space.

## 8. Sending, and what the row becomes

Every state below is one the panel already draws for another reason, so an answer sent from here has no aftermath of its own. It has an outcome, and the outcome is a row.

| | State | Drawn as |
| --- | --- | --- |
| 01 | **In flight** | The field and both controls drop to `45%` and stop taking keys. Nothing resizes. No spinner, no progress, no new mark: the wait is a few hundred milliseconds and anything drawn to fill it would outlive the thing it described |
| 02 | **Landed** | The body and the answer row leave, the row returns to `80`, the preview line says what was sent, and the status is whatever the Thread now is — after a grant, `Working...`. There is no confirmation to dismiss, because the row is the confirmation |
| 03 | **Not delivered** | The row goes back to waiting with the text still in the field and the reason on the preview line, **in the preview's own ink**. The app has no failure ink, and inventing one for a transport error would make it louder than a Turn that genuinely failed, which is drawn as ordinary preview text under an unchanged marker |
| 04 | **Settled elsewhere** | Granted in the product, cancelled, or the Thread gone: the row closes within one publish and becomes what it now is. What was typed is dropped, because there is nothing left to send it to. This is the one close the user did not ask for, which is why it is the row changing state rather than a message about a row |

### 8.1 Answering does not retire a row

It is tempting to file an answered request beside the read and the dismissed and let it halve under [`expanded-panel-v2.md`](expanded-panel-v2.md) §2's seam. That would be a lie about what happened: **a granted command is a Turn that is now running**, which is the least finished thing on the panel. Retirement stays what §2 defined it as — read, dismissed, or gone — and answering is not one of them.

### 8.2 More than one request waiting

Two at once is the ordinary case, not the edge one: a Turn asks while a subagent it forked is already asking ([`PRD.md`](PRD.md) §6.2 band 2). The panel gains no counter for it.

- **The answered row falls exactly one place.** `Approval needed` sits directly above `Input needed` in the sort the list has always had, so with one other request waiting the two exchange places on the panel's own slot curve and nothing else moves.
- **The next request opens itself**, with its affirmative unarmed by §6.3 — which is what stops the click that answered the first from answering the second. The advance is the whole notification: there is another one, and here it is, already open and already legible.
- **One row is open at a time**, and it is the subject: opening scrolls it to the top of the viewport and holds it there against re-sorting, lays the hover fill under it permanently, and drops every other row to `45%`.

### 8.3 The panel does not close on send

**A correction to §3.5.** Closing on send would shut the panel in front of a second request nobody had seen. With nothing left waiting the panel **unlatches** — it hands the keyboard back and starts answering the pointer again — and that release is how it says you are finished. It still closes on `⎋`, on a click outside, and on the pointer leaving, as it always did.

## 9. Arrival, the pointer, and the keys the field keeps

### 9.1 Two doors, and a third that is drawn and not built

- **The knock is unchanged**, and it is still the notification. The collapsed bar draws the double-knock curve the moment a request arrives ([`compact-view-v2.md`](compact-view-v2.md)). Nothing on this page reaches the collapsed surface: it says a person is wanted, and it never says what for.
- **The pointer keeps every door it had, and in the initial version it is the only one.** Hover browses, a click on the mark engages, a click answers (§6.6). None of that is new machinery and none of it can fail at registration, which is most of the argument in §1.1.
- **The chord is the third door**, and it is §9.3.

### 9.2 The bindings, and they are the field's

The panel takes the keyboard so that a row can be read without being lost and a note can be typed into it (§10), and that is the whole of why it takes it. So the keys it answers to are the field's own, plus the one that hands the keyboard back.

| Key | Does | Notes |
| --- | --- | --- |
| anything printable | Goes into the field, and moves the ground to the answer that carries text | The caret is in the field from the moment the row opens. No type-ahead, no first-letter jump, no single-letter shortcut: each would put a keystroke somewhere the caret is not |
| `⇧⏎` | A new line in the field | A refusal that explains itself is often two sentences, and an alternative command is often two lines. It is the only way to get one, which is why `⏎` can be unambiguous |
| `⏎` | Takes the answer the white ground is on | Which is what the ground has said all along. On a question that is one of a set, draws the next and sends nothing; on the last, sends the set |
| `⎋` | Collapses the row; again, closes the panel | The chevron's own action. A surface that takes key status has to hand it back, and this is the key that does it: the row stays on the list holding its text and its part-answered set |
| `⌘⏎` | **Unbound, and it stays that way** | A second way to approve would make the white ground advisory rather than definitive, and the whole safety of this surface rests on the ground being the literal truth about `⏎` |
| everything else | **Unbound** | §9.3 holds the keys with a reason to exist later. Binding one of them early would be a keyboard model with a hole in it, which is worse than a panel that plainly does not navigate |

### 9.3 The keyboard half, deferred and kept whole

Stage 03 of §1.1. It adds no region, no ink, no control and no height; it adds keys, and one word this surface already draws under the pointer. It is recorded here so that landing it is a build rather than a second design.

| Key | Would do | Argued in |
| --- | --- | --- |
| `⌥Space` | Bring the panel down already latched, with the first row by the existing sort already open and the caret in its field. With nothing waiting it opens the panel latched at the top of the list instead, so **the chord is never a key that sometimes does nothing** — the only variable is whether a row is already open when it lands. User-settable, defaulting to `⌥Space`, and registered through the ordinary system path so that a clash **fails loudly at registration** rather than quietly at use; the settings row shows the chord it actually holds, not the one it asked for | §15 q03 |
| `↑ ↓ ← →` | Move the white ground, and walk the list where no row is open. The body scrolls to keep the ground in view; on a row whose body has no answers to move between, `↑ ↓` scroll that body directly | §6, §6.2 |
| `1`–`4` | Take a numbered option directly — **only while the ground is still on an option**, which is to say before anything has been typed. After that a digit is a character like any other | §15 q08 |
| `Space` | Tick the option the ground is on, `multiSelect` only | §5.5 |
| `⇥` | **Still unbound.** Once the arrows exist, every journey `⇥` would serve already has a key | §15 q10 |

Three clauses of this document arrive with those keys, and each is a correction only a keyboard user makes necessary: the word drawn under focus as well as under the pointer (§3.3), the arrows as a second force on the ground (§6), and the axis split on a body with no answers in it (§6.2). Two of the three are corrections to [`expanded-panel-v2.md`](expanded-panel-v2.md) that this document deliberately does not make yet.

**What waiting for this costs is in §13.3.** It is the one consequence of the ordering in §1.1 that is not merely a delay.

### 9.4 The panel never takes the keyboard unasked

Hover browses and cannot latch, however long it lasts. **Only a click on the mark makes the panel key** — an unambiguous act, and the chord will be the second one. This matters more than it looks: the panel sits over whatever the person is typing into, and a surface that took focus on proximity would eat a line of their code. Latching takes key status from the application underneath, so `⎋`, a send with nothing left waiting, and a click outside all give it back to the same window; if that window has gone, focus goes wherever the system would have sent it and the panel does not hold it open waiting.

## 10. Latching

**A click latches the panel; hover stops holding it.** Hover is browsing and a click is engaging. From the moment a row opens, the panel stops answering the pointer and takes the keyboard, for two reasons in this order. **The first holds even where there is nothing to type**: a body of `140` points is read rather than glanced at, and a row somebody is reading must not close because their pointer drifted off it — moving to the keyboard is not a pointer movement, and any drift is. The second is the field: a note cannot be typed into a panel that is not key. So a row that can only be read (§11) latches on the same rule as one that can be answered, and gives the keyboard back the same way.

Text typed but not sent, and any part of a set already answered, stay with their row for as long as that row lives.

## 11. Before a door exists — the half that ships anyway

Notchline observes through hooks, and a hook is a notification: neither product currently offers a way back in (§14.2). **Half of this needs no way back in.**

Reading a request in full, in the notch, without surrendering the screen, barely shortens §1's eleven steps — it removes the hold-still, and that is all — and shortening them is not what it is for. **It makes the journey optional.** Today the walk to the product is compulsory even when the answer is obvious, because one faded line is enough to notice a request and never enough to grant it; read in full, most requests are settled in the reader's head before anybody leaves, and the ones that still need the product are entered already knowing what they are for. ~~removes six of §1's eleven steps on its own~~ was version 1.1's claim, and it does not survive being counted.

| | Rule | |
| --- | --- | --- |
| 01 | **The word in the mark is `Read`, not `Answer`** | §3.3 |
| 02 | **What opens is §4 entire** — the request verbatim, both settings, the scrolling body and the count | |
| 03 | **The white ground is absent, not disabled.** The affirmative ground is the return key made visible, so drawing it where there is nothing for the return key to do is a promise the app cannot keep — and a greyed-out `Approve` is exactly that promise, made quietly | |
| 04 | **One control stands where three would**, left-aligned on the recessed ground: `Answer in Codex` / `Answer in Claude Code`, which is the click that has always worked, moved to a place a reader arrives at after reading | |
| 05 | **Every height is already the height it will be.** When a product opens a write path, the single control becomes §7's row and nothing else on this page changes | |
| 06 | **The two halves are per product.** A Codex row that can be answered beside a Claude Code row that can only be read is an ordinary mixed list, not a special case. The row says what that row can do | |

Nothing here is scaffolding to be thrown away, which is what makes shipping the reading half first a decision rather than a delay.

## 12. Heights

Every open row is `100` plus its body.

| The row | Height | The body it holds |
| --- | --- | --- |
| Closed, waiting | `80` | None. `12.5 + 16 + 2 + 17 + 2 + 18 + 12.5`, the [`colour-v2.md`](colour-v2.md) badge caption included |
| A question with nothing to pick | `117` | One prose line, `17`. The shortest row that can be opened |
| An approval at three lines | `170` | The machine-text block at `70` |
| A question at three options | `193` | A question line, `4`, and three `24` pt options — `93` |
| A restatement at three lines, two options | `203` | Prose `51`, `4`, two options `48` — `103` |
| Anything at the maximum | `240` | The body's cap, `140`. The row **is** the viewport |
| In flight | unchanged | Nothing resizes; the controls lose `55%` of their opacity |

At the `46` pt menu bar reference with both products connected and the footer at rest — `22`, [`quota-footer-v2.md`](quota-footer-v2.md) §2:

| The list | Panel | Note |
| --- | --- | --- |
| One waiting row, opened at `117` | **217** | Viewport `149` — the row and the seam beneath it |
| One waiting row, opened at three lines | **270** | Viewport `202`. [`expanded-panel-v2.md`](expanded-panel-v2.md) §4, unchanged |
| One waiting row, opened at the maximum | **308** | Viewport `240`, and the seam is below the fold |
| Two waiting rows, the first opened | **308** | Content over the cap; the second row is clipped, not hidden |
| Three live rows, one of them opened | **308** | The cap has been reached since V1 and does not move |

These read `279` / `332` / `370` in version 1.0, taken with a footer of `84` — [`dual-agent-design.md`](dual-agent-design.md)'s two-product figure, which [`quota-footer-v2.md`](quota-footer-v2.md) had already replaced with `22` at every product count. **Every one of them falls by exactly `62`** ([`panel-v2.md`](panel-v2.md) §3.1). Nothing in this document's own arithmetic moves: the viewport cap is `240` and the open row's cap is the viewport. Opening the quota table adds `112` on top, at two products and three windows.

Width is [`expanded-header-v2.md`](expanded-header-v2.md)'s `520` in every state, and [`colour-v2.md`](colour-v2.md) §3 keeps it there at every agent count.

## 13. Motion, accessibility, and the one thing that ticks

### 13.1 Motion borrows, and borrows nothing new

- **Opening** grows the row in place on `PanelMotion.slot(isOpening:)` while the bright ground travels from the caption line to the answer row — one object moving, not one fading out and another in. The body's content fades in behind its ground rather than being revealed by it.
- **Drawing the next question of a set** is that same curve run on the body alone, with the head and the answer row still.
- **The advance** (§8.2) is that curve run on two neighbours at once.
- **In flight** is opacity and nothing else.
- The affirmative arms at the end of whichever of these was playing, so §6.3 costs no timing of its own.

### 13.2 The caret is the one thing that ticks, and it must not be ours

A blinking caret is precisely the continuously running animation the overlay forbids ([`system-architecture.md`](system-architecture.md) §6): drawn from SwiftUI it would invalidate the whole panel, `PanelContour` and every text measurement, twice a second, for as long as a row is open. **The field is therefore an AppKit text view hosted in the panel**, with its caret drawn by the text system into its own layer — the same division that already sends persistent motion to Core Animation.

The scrolling body is the second thing to watch: it must scroll its own layer rather than re-laying-out the row. Measure both under Release, and measure the burst by diffing cumulative CPU time rather than reading `ps %cpu`.

### 13.3 Accessibility follows the ground, and speaks the count

- The open row's answers are one group named for the question or the request. A question's options are a radio group, or a checkbox group where several are allowed, and **the white ground is the selected state**, so a screen reader announces exactly what the ground says.
- The position in the set is spoken with the question — *question two of three*.
- **The count of lines below the fold is spoken with the body.** A reader who cannot see the count must not be the only one who does not know something is missing.
- A closed waiting row keeps the accessible action `Answer this request` (or `Read this request`, §11) regardless of hover, and every answer on an open row carries an action of the same kind. Assistive technology therefore reaches all of them by its own means, which are not key bindings and do not wait on §9.3.

**What the initial version does not give is full keyboard access.** With no chord and no arrows, somebody who works without a pointer answers in the product exactly as they do today: nothing they could do gets worse, and nothing this page adds is for them yet. That is the largest cost of shipping the pointer half first, it is why §9.3 is deferred rather than dropped, and it is stated here rather than in a footnote.

## 14. What this reaches outside the viewport

### 14.1 One field this app already receives and throws away

`HookPayload.CodingKeys` names `hook_event_name`, `session_id`, `turn_id`, `prompt_id`, `agent_id`, `tool_name`, `tool_use_id`, `permission_mode`, `cwd`, `prompt`, `last_assistant_message`, `message_id`, `delta` and `background_tasks` — **and not `tool_input`**. `HookPayloadDistiller` walks the top level once and steps over every key `CodingKeys` does not name.

That is right as it stands, and the reason is recorded: the helper forwards stdin unchanged, so an oversized `PostToolUse` tool result once took the lifecycle event down with it, leaving a wait its `tool_use_id` opened unclosed until the Turn's `Stop` (CR-030). **Nothing about the size of a tool result is evidence about the Turn.**

What §2 needs is narrower than lifting that. **Built on 2026-09-05, and two of the three clauses below were wrong when this document first wrote them.**

- ~~`tool_input` is kept **only on `PermissionRequest` and `PreToolUse`**~~ — **that gate is far wider than it sounds.** `PreToolUse` fires for *every* tool call and is one-to-one with `PostToolUse`, so it halves the volume rather than removing it. Measured 2026-09-05 over 30,909 `tool_use` blocks in 736 transcripts under `~/.claude/projects` — p50 263 B, p99 8,951 B, max 136,560 B — it would copy and decode about **28 MB** of arguments nobody reads, on the serial read queue. The gate actually wanted is **the events that open a wait**, which admits 56 of those 30,909 calls: **0.18%**. It is read off the signal table each vocabulary already declares (`AgentHookVocabulary.carriesRequest(forEvent:toolName:)`), so `PostToolUse` is refused *by construction* rather than by a rule somebody has to remember — which is the shape CR-030 turned out to be.
- ~~It is kept **bounded**, as `.text` in `CarriedValue`'s vocabulary~~ — **`.text` is wrong twice.** It means *cut short: a shorter answer is the same answer*, which is false of an object: half of one is not JSON, and cutting it would make the whole payload undecodable and lose the lifecycle event with it. And `.text`'s bound is 16 KiB, which **would have refused the only `ExitPlanMode` plan on this machine** (54,411 bytes) — the single form the reading half exists for. There is a fourth `CarriedValue` case instead, `.request`, meaning *whole or left out, and only on the events that ask*.
- The bound has to be generous enough for a plan, and a plan is the largest thing either product sends this way. `maximumRequestBytes = 128 KiB` — 2.4× that plan, and above 99.997% of the measured corpus.

One mechanical note, because it is the part that is easy to get wrong: the distiller emits fields as it scans, and `hook_event_name` and `tool_name` are not promised to precede `tool_input` — on Claude Code they never do, its keys arriving alphabetically. So the request is **held as a range into bytes the scan already has** and emitted after the loop, once both names are known. A `PostToolUse` whose request is refused therefore pays nothing at all for the refusal: no copy, no decode, and no second pass over a payload whose tail may be 16 MiB of tool result. Where two copies of the key arrive, the **first** wins, because that is what `JSONDecoder` does with a repeated key — measured, not assumed.

This is the whole dependency for §11, it is inside this app, and it was the first thing to build.

### 14.2 A write path per product, and both products have one

**Measured 2026-09-05, from each product's own shipped binary.** The channel is the hook process's stdout, on the connection it is already holding open:

| Product | Schema | What it accepts |
| --- | --- | --- |
| Codex | `permission-request.command.output` | `hookSpecificOutput.decision = { behavior: "allow" \| "deny", message? }`. `interrupt`, `updatedInput` and `updatedPermissions` are documented *reserved*, and the hook **fails closed** if any of them is present |
| Codex | `pre-tool-use.command.output` | `hookSpecificOutput.permissionDecision = "allow" \| "deny" \| "ask"`, `permissionDecisionReason` |
| Claude Code | `PermissionRequest` | `decision: { behavior: "allow", updatedInput?, updatedPermissions? }` or `{ behavior: "deny", message?, interrupt? }` |
| Claude Code | `PreToolUse` | `permissionDecision: "allow" \| "deny" \| "ask" \| "defer"`, `permissionDecisionReason`, `updatedInput` |

Two consequences change this document.

**A question can be answered, on Claude Code, and honestly.** `AskUserQuestion` raises a `PermissionRequest` as well as its `PreToolUse`, and that event's `allow` carries `updatedInput` — so the answer is delivered by handing the tool back its own input with the person's choices merged in, and the tool then runs and returns them. Nothing is blocked and nothing is paraphrased into a refusal. It is the designed path rather than a trick: `AskUserQuestion`'s own input schema carries an `answers` field described as *"User answers collected by the permission component"*, keyed by question text, beside an `annotations` field for per-question notes. **Codex has no equivalent**, its `updatedInput` being reserved — so a question is answerable on one product and readable on the other, which is §11 rule 06 exactly.

**What it costs is inside this app, not outside it.** ADR 0013 makes the helper silent — `exec >/dev/null 2>&1`, `nc -U -w 1`, `exit 0` — so nothing this app computes can reach the product; the reply channel has to be opened, and the registered `timeout: 3` has to become a window a person can answer inside. Measured on `nc` 2026-09-05: it holds the connection past stdin's EOF, takes a reply three seconds later and prints it, exiting 0 — so the transport ADR 0013 chose survives, with the wait selected per event. On Codex that timeout lives in the hashed definition, so changing it costs one silent re-trust of `PermissionRequest` alone (ADR 0014).

~~Until one does, §3 to §8 are a drawing~~ — [`expanded-panel-v2.md`](expanded-panel-v2.md) §8.4's rule still stands and is now satisfied rather than blocking: a panel offering `Approve` it cannot deliver is worse than a panel that offers nothing, and this one can deliver it. §11 is still what ships first, because reading is the larger removal and the cheaper build.

### 14.3 The panel has to be able to take the keyboard

Latching means the `NSPanel` becomes key, which takes focus from whatever the user was in and must give it back on `⎋`, on send, and on a click outside. `PanelMetrics` has nothing to say about it and `OverlayPanelController` has everything. **This one belongs to the initial version, not to §9.3**: a panel that cannot become key cannot hold a caret, whatever opened the row.

### 14.4 Two stated non-goals move, and the same two as before

[`PRD.md`](PRD.md) §3 rules out "sending input, granting permission, answering questions, cancelling, archiving or deleting threads", and separately rules out showing "tool arguments, command output, file diffs, sensitive paths or approval rationale".

- **The first reverses for exactly one payload** — the request a row is already reporting — and for nothing else. No cancelling, no archiving, no deleting, no starting a Turn.
- **The second narrows to one exception**: the payload of a request the product is already blocked on. Nobody can grant a command they have not been shown. Every other item in that sentence stands, output and diffs included — which is also why the request is set as machine text on a recessed ground rather than as prose (§4.2), and why §4.6 refuses to editorialise about it.

**Neither amendment is made in this change**, on the same footing as [`expanded-panel-v2.md`](expanded-panel-v2.md) §8.1: nothing here is implemented, and the PRD is the product contract rather than a design record. They are made in the change that builds §14.1.

## 15. Open questions

| | Question | Where it stands |
| --- | --- | --- |
| 01 | Will either product accept an answer from outside it? | **Answered — yes, and further than expected** (measured 2026-09-05 from both products' shipped binaries, §14.2). Both accept an approval decision on the hook's own stdout; Claude Code also accepts a question's *answers* through `updatedInput`, which Codex reserves and fails closed on. So §3 to §8 are unblocked, with §5 built for one product and read on the other |
| 02 | Will this app keep the request it is already sent? | **Answered — yes, and built on 2026-09-05.** §14.1, whose own first two clauses were wrong and are struck there. What carrying it costs is 0.18% of tool calls rather than all of them, because the gate is the events that open a wait; `PostToolUse` is refused by construction, so CR-030's hazard is not re-entered |
| 03 | Which chord, and what happens when it is taken? | **Answered by the board's owner on 2026-09-05, and now deferred with the chord itself.** `⌥Space`, user-settable, registered through the ordinary system path so a clash **fails at registration rather than silently at use**, and the settings row shows the chord the app actually holds rather than the one it asked for (§9.3). The initial version registers no global hotkey, so that failure path is off the critical path until stage 03 — and the answer stands, unreopened, for when it lands. Still worth testing against a machine already running a launcher on that chord |
| 04 | Does the count say lines, or bytes? | **Standing recommendation: lines.** A byte count is precise and unreadable; a line count matches what the reader is looking at and is the unit in which a hidden clause hides. Where a request arrives as one enormous unbroken line, the count is of wrapped lines |
| 05 | Should `⏎` ever take an answer the reader has not seen? | **Answered — no**, and §6.3 is how. It now answers the sharper version of the same question — should a *click* — because a pointer already resting on the answer does not have to move to press twice. The rejected alternative was a fixed delay before the control becomes live |
| 06 | Is `Always` ever offered from here? | **Answered — no.** §6.5, and [`expanded-panel-v2.md`](expanded-panel-v2.md) §8.5 question 05 |
| 07 | Does the notch choose how a plan's edits will be approved? | **Answered — no**, and for the same reason. §4.3 |
| 08 | Do the digits stay bound once a question has been typed into? | **Answered — no**, and deferred with the digits themselves (§9.3). Reserving them permanently would silently eat the first character of an answer beginning with a number |
| 09 | Does an MCP elicitation ever get drawn here? | **Answered — no.** §2.2. Reopen only on a measurement of what servers actually send |
| 10 | Is `⇥` ever bound? | **Answered — no, and moot until the arrows exist.** §9.3. Every journey it would serve has a key *in the stage that has keys*; in the initial version it would be the only key that navigates, which is a keyboard model of one binding. What would justify it later is a list long enough that the arrows are tedious, and the viewport caps at three rows |
| 11 | Does a row that cannot be answered still knock? | **Answered — yes, unchanged.** The collapsed bar reports that a person is wanted, which is true whether the answer will be given here or in the product |
| 12 | Does a click on an option answer with it, or only select it? | **Answered — it answers**, and where several answers are allowed it ticks instead and `Send` answers. §6.6, §5.5. A select-then-confirm pair would put a second control on the row saying what the first already said |
| 13 | Does a row that can only be read still take the keyboard? | **Answered — yes.** §10. It has nothing to type into, but it is the state a person reads longest, and a row closing because a pointer drifted is exactly the failure that rule exists to prevent |
| 14 | When does the keyboard half land? | **Not answered here, and deliberately.** §1.1 orders it after a write path exists and after the pointer version has been used; §9.3 is what it will be built from. The one thing that would move it earlier is §13.3 |

## 16. Verification

- [ ] A closed waiting row is `80` at every menu bar height, badge caption included, and a row with no mark gains no second target.
- [ ] A click on a row's text opens the Thread; a click on the mark opens the row; no other region does either.
- [ ] Opening moves one bright ground from the caption line to the answer row — the surface never draws two at once — and a chevron pointing up stands where it was.
- [ ] The chevron and `⎋` both collapse the row, send nothing, and preserve typed text and any part-answered set; reopening resumes at the same question.
- [ ] The body is at most `140` and the open row at most `240`, in every form; a one-line question makes a `117` pt row.
- [ ] Prose draws with no ground and machine text on `#242424`, chosen by payload and not by length, on all seven shapes in §2.
- [ ] A body longer than its cap scrolls on the wheel, draws the rail, and shows a count that clears when the last line is on screen.
- [ ] A wrapped line's continuation carries its own indent plus two spaces; no whitespace is collapsed and no token is dropped.
- [ ] No command is ever marked, coloured or flagged by the app.
- [ ] Every question draws `header · n/N`, including a one-question call; a Codex question draws the chevron alone.
- [ ] `⏎` on any question but the last draws the next and sends nothing; the last sends the whole set.
- [ ] Every question form draws the field; typing moves the white ground onto `Send`.
- [ ] With `multiSelect` the ground never leaves `Send`, the numerals are boxes, and a click on a box or its label ticks it.
- [ ] The white ground is on the affirmative with an empty field and on the refusal with a non-empty one; neither control moves as it crosses.
- [ ] Nothing but typing moves the white ground: hover moves it nowhere, and a click takes whichever answer it lands on whether the ground is there or not.
- [ ] The only keys the panel answers to are the field's — anything printable, `⇧⏎`, `⏎` — and `⎋`. `⌥Space`, `↑ ↓ ← →`, `1`–`4`, `Space`, `⌘⏎` and `⇥` are all unbound, and the app registers no global hotkey.
- [ ] A row opened by an advance, and a question drawn by answering the one before it, take neither a click nor a return until the opening animation has ended.
- [ ] While a row is open the panel does not close on pointer exit, holds the keyboard, and returns it on `⎋`, on send and on an outside click.
- [ ] A request settled elsewhere closes the open row within one publish; a send that fails keeps the text and says why in the preview's ink.
- [ ] An answered row returns to `80` and to the Thread's current status, and does not retire.
- [ ] With no write path the mark says `Read`, no white ground is drawn anywhere on the open row, and one control stands where three would.
- [ ] The panel's CPU cost while a row is open, and while its body is scrolled, is measured under Release by diffing cumulative CPU time.
- [ ] The band, both collapsed forms and the quota footer draw identically to pages 01 to 09 in every state above.

## 17. Implementation mapping

**The first row is built** (2026-09-05); the rest is not. The work lands in six places, and the first was the only one with no dependency outside this repository.

| Symbol | Change |
| --- | --- |
| `HookPayload`, `HookPayloadDistiller` | **Built.** `tool_input` as a fifteenth `CodingKey`, carried as a new `.request` kind — whole or left out, bounded at `maximumRequestBytes = 128 KiB` — and admitted only on the events that open a wait, read off each vocabulary's own signal table through `carriesRequest(forEvent:toolName:)`. ~~carried as `.text`, kept on `PermissionRequest` and `PreToolUse`~~ is struck in §14.1 with the measurements that struck it |
| `AgentRequest`, `AgentRequestReading` | **Built**, and not in the original plan. The typed request and its four drawn forms, read **in the reducer** at the moment the wait opens — the one place holding the signal, the event name, the tool name and the vocabulary at once. A form's setting (§4.2) is derived from its case rather than stored, so it cannot be set wrong; a command's body is the whole `tool_input` re-encoded with sorted keys, not a field picked out of it |
| `HookEventRepository` | **Built.** The request is a field **of** `PendingApproval` and of a new `PendingInput`, ~~a `PendingRequest` on the Turn's wait slots, per `(agent_id, tool_use_id)`~~ — a table beside the waits would have to be cleared at all seven sites that clear one, and a rule that holds until one site forgets it is exactly CR-030. `HookTurnState.requestAwaitingAnAnswer` picks the one request a row can open, in the order `PRD.md` §6.2 already reads, oldest subagent first |
| `MonitorSnapshot`, `MonitorStore` | **Half built.** `MonitoredSession.request` reaches the UI on the one data contract, and `renderedProjection()` carries the request's id and form — never its body, so a 54 KiB plan is not string-compared per event. Still owed: the store's draft text and part-answered set for the row's lifetime, and `openRowID` beside `quotaExpanded` and `recentExpanded` |
| `PanelMetrics` | New: `requestBodyMaximumHeight = 140`, `openRowHeight(bodyHeight:)`, `optionRowHeight = 24`, `answerRowHeight = 28`. `openRowHeight(requestLines:)` from [`expanded-panel-v2.md`](expanded-panel-v2.md) §10 is not introduced — it counted lines, and §4.1 does not |
| `NotchOverlayView` | `OpenRow` and its four bodies, `OptionRow`, `AnswerRow`, the chevron in the trailing head slot, the mark's second hit region, and a hit region and hover fill on every answer (§6.6). The field is an `NSViewRepresentable` over an AppKit text view (§13.2) |
| `OverlayPanelController` | Latching and key-window handover (§14.3). The chord's registration and its failure reporting are stage 03 and are not in the initial version (§9.3) |
| A `RequestAnswering` provider per product | The write path. **No implementation exists to write against** (§14.2); the protocol is what §11 draws around |
