# Notchline — Answering in the notch

| Field | Value |
| --- | --- |
| Status | **Built, and the third stage is withdrawn rather than pending.** §14.1 landed on 2026-09-05 and §3 to §8 with it: a request arrives, is read in the notch, and is answered there with the pointer, within the request forms now declared in [product support](product-support.md); local Codex CLI requests remain reading-only. §15 q01 and q02 both came back yes. **§9.3 — the chord, and everything that navigates without a pointer — is no longer deferred; it is declined** (board's owner, 2026-09-06), and one key came out of it: the digits take a numbered option, on §15 q08's own condition. So the keyboard this panel answers to is **the field's while the field holds the caret** — anything printable, `⇧⏎`, `⏎`, `⎋` — and **the panel's when it does not**: `1`–`4`, `←` and `→`. **The field stopped taking the caret unasked on 2026-09-07** (§6.6), which is what made that a rule about focus rather than about what the field happened to be holding. §9.3 is kept whole below as the design that was considered, and §13.3 says what declining it costs. |
| Version | 1.7 |
| Date | 2026-09-07 |
| File | [Notchline V2](https://www.figma.com/design/c3CQBBk3Boiu0oM00Vvs9Y/Notchline-V2) — `10 — The answer`. `11 — The panel, whole` redraws the open row on the composed surface and corrects §12's panel column — see [`panel-v2.md`](panel-v2.md). |
| Scope | What happens between a request arriving and a person answering it: how the request reaches somebody who is not looking at the notch, every shape the two products ask in, what an opened row draws for each of them, what a click takes, which keys the panel answers to and which wait for the keyboard half, and what the row becomes once the answer has gone. The band, the quota footer and both collapsed forms are untouched, and nothing here reaches the collapsed surface. |
| Supersedes | [`expanded-panel-v2.md`](expanded-panel-v2.md) §3 entire. Three of its clauses are corrected rather than extended, each marked below: §3.1's opening gesture (§3), §3.2's fade and its three-line cap (§4), §3.5's close-on-send (§8). A fourth — §3.4's forces on the affirmative — **is not corrected at all**: it is right for a surface answered with the pointer, the keys that would have made a correction necessary are declined (§6, §9.3), and so it stands as that document wrote it. §2 — the Recent queue — is untouched and independent. |

## Support coverage

On 2026-09-12, [generalisation package 1](product-generalisation-plan.md) moved native request projection to `HookEvidenceBoundary`, before typed evidence reaches `MonitoringRepository`. The reducer binds an already-projected body to the established wait identity and retains the same request/answer behaviour. It no longer parses tool input; raw input and held descriptors remain at the Hooks boundary. Concurrent request storage, structured answers and channel-independent delivery results are still packages 2–4.

[Product support](product-support.md) separates L4 wait detection, L5 request reading and L6 request answering, each scoped to native request forms. This document retains authority over the shapes and operations actually supported. Codex Desktop ordinary `PermissionRequest` has L6 answer coverage; its `request_permissions` and synchronous questions remain reading-only, and asynchronous questions preview-only. Local Codex CLI is L5 for ordinary approvals and synchronous questions, and every request remains reading-only. CLI asynchronous questions, extra permission forms and subagent variants have no independent native acceptance claim. Rendering a request does not establish an answer path. The individual live connection, not the product's level, determines whether an opened request offers an answer action.

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
| 03 | ~~**Answer it here, without the pointer** — §9.3~~ **Declined 2026-09-06** | ~~Nothing outside this app: a chord, and the navigation under it~~ | ~~**Five steps and no pointer**: the bar knocks, `⌥Space`, read it in full, type or don't, `⏎`~~ |

**Stage 02 is what this experience is.** ~~and stage 03 is deferred~~ — stage 03 was deferred behind it on 2026-09-05 and **withdrawn on 2026-09-06**: this product's keyboard is the field's own keys and the digits, and it claims no chord from the rest of the machine. This document still keeps stage 03 whole rather than deleting it, for the same reason it kept it while it was deferred — the argument is the expensive part, and a design that was considered and declined is worth more written down than gone.

Eleven to eight removes four steps, **three of which belonged to another application** — the screen surrendered, the dialogue found, the journey back — and turns the single act of answering into two, which is what doing it here costs. Eight to five removes four more, **three of which are the pointer's**. Both are worth having, and the first is at once the larger removal and the cheaper one to build: it needs a write path and no new mechanic, where the chord is the only genuinely new mechanic on this page — a global hotkey that can fail at registration, a settings row to report what it actually holds, and a keyboard model that has to be complete before it is honest. **Shipping them together would hold the larger saving behind the smaller one.**

Nothing was thrown away by taking them in this order. Every object stage 03 would have touched is one stage 02 already draws; it adds keys, and the only thing it would draw is a word this surface already draws under the pointer (§3.3). **What declining it costs is stated where it is felt** — §13.3, and it is not a delay any more: **this surface cannot be operated from the keyboard alone, and that is now a standing property rather than a stage.**

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
| Codex | `PreToolUse` — `request_user_input` | ~~A question, with no options attached to it~~ — **wrong, corrected 2026-09-07.** `questions`, the same shape `AskUserQuestion` sends: a `header`, an `id`, the question, and `options` carrying a `label` and a `description` each. Options are optional in Codex's schema, so both forms 03 and 04 occur | One option, or your own words |
| Codex | `PreToolUse` — `request_user_input_async` | The **second** question tool, selected by the model rather than by a setting. Asks without stopping **the Turn**: it returns `{"accepted":true}` in about 50 ms whatever the person does, and any answer arrives later as a new user message. ~~`{"questions":[{"title": …}]}`~~ — **corrected 2026-09-08**: `questions` carry `options` with a `label` and a `description` each, the same set as the blocking tool, whenever the model attaches them | ~~**Not from here** — nothing is waiting~~ **Not from here, for a narrower reason (2026-09-08).** Somebody *is* waiting: Codex Desktop draws an answerable card that outlives the Turn. But the answer travels on `item/tool/requestUserInput`, an App Server request this app holds no connection to (§14.2), and the hook still has no field for it. **Read and drawn, though not answerable**: the question's words are kept on the Turn and taken as the row's preview (`PRD.md` §7), which is the reading-only half §1 stage 01 already ships for every other shape. §3 of [`system-architecture.md`](system-architecture.md) |

**One shape is known to exist and is deliberately not in the table.** `item/tool/requestOptionPicker` — an App Server request beside `item/tool/requestUserInput`, answered `{action, selectedOptions, freeformAnswer}` — was found in Desktop's bundle on 2026-09-08. It is left out because this document lists **the forms a request arrives in here**, and nothing is known about how, or whether, that one reaches the hook channel: no tool name, no payload, no sample. It is recorded as open research in [`technical-explorations/answering-codex`](technical-explorations/answering-codex/README.md) §3.6.1 and belongs in this table only once a real payload has been caught.

**A question is a set, not a question.** Across every transcript under `~/.claude/projects`, 86 questions arrived in 55 calls: 32 calls carried one, 17 carried two, 4 carried three and 2 carried four. **63% of questions therefore arrive in a call carrying more than one**, options run two to four with three the mode, and `multiSelect` is rare but real. That measurement is what makes the position in the set (§5.2) a drawn element rather than an edge case.

### 2.1 Seven shapes, four drawn forms

| | Form | Where it comes from | What the row draws |
| --- | --- | --- | --- |
| 01 | **A command to grant** | `PermissionRequest` on either product, and `request_permissions` | Machine text on the recessed ground, verbatim, scrolling past the fold. Two answers, and a field that belongs to the refusal |
| 02 | **A document to accept** | `ExitPlanMode`, and anything else that hands over prose | The same body set as prose rather than machine text, and taller: a plan is read, not scanned. Two answers — §4.3 |
| 03 | **A question with options** | `AskUserQuestion`, and `request_user_input` where it attached any | The header and the position in the set on the caption line, the question and the options as the body, and the field beneath them |
| 04 | **A question with none** | `request_user_input` where it attached none, and any option list once a person decides none of them is right | No body at all. The question sits where the preview does, and the field is the whole answer. The shortest row that can be opened |

### 2.2 The form this declines, and why it is a boundary

An `Elicitation` is a form whose fields a third-party MCP server chose at run time, of arbitrary shape, count and validation. Drawing it would make this panel a general form renderer for code it has never seen, inside 240 points, and **a half-rendered form is a wrong answer submitted confidently**. That row keeps §11's reading treatment and sends the person to Claude Code, which is where a form belongs.

This is a capability boundary rather than a deferral, on the same footing as the Codex side chat ([ADR 0017](adr/0017-a-row-requires-a-thread-the-app-server-vouches-for.md)). It is worth reopening only if the shapes servers actually send turn out in practice to be a small closed set, which is a measurement nobody has taken.

### 2.3 The row draws the product's own words

A question's options are labelled text in the payload, so those words are drawn and never a paraphrase of them. Where no labels arrive — an ordinary approval — the row uses the fixed pair `Approve` / `Deny`, which is both products' own three-part question minus the one this design declines to offer (§6.5). **Nothing on this surface invents a word that a person's answer will be recorded under.**

**One exception is reserved, and it is not in use.** The persistent-rule answer §6.5 declines has no phrase in the payload to quote — `permission_suggestions` carries a rule, and the product composes the sentence itself. So if that answer is ever drawn, its label is composed rather than quoted, under the narrower rule that a composed label may name only what the rule it was composed from actually grants. That is the whole of the exception: every other word on this surface is still the product's.

## 3. Two targets on one row

**A correction to §3.1**, which made the reading's ground open the row on a click and drew the word `Answer` in it. The gesture is kept and its consequence is made explicit: the mark is now a second target, and the two targets are the two answers to *what do I want with this row*.

- **The text is the Thread.** A click anywhere on the badge, the Project, the title or the preview opens that Thread in its product, exactly as it always did ([`figma-design.md`](figma-design.md) §9.2).
- **The mark is the request.** A click on the bright ground opens the row here.

No other row gains a click, and no row gains a second destination — a `Running` or `Completed` row has no mark, so it stays a single target.

### 3.1 The ground travels; it is not duplicated

Opening does not create a second bright object. The ground the pointer pressed **travels from the caption line down to the answer row**, where it becomes the affirmative. So the surface never draws two bright grounds at once, and what the ground means never changes: it is the thing that wants you, and then it is the thing `⏎` will do.

> **The bright ground is no longer white, and it no longer grows** (2026-09-06, with §3.3's redraw). It is `NotchPalette.brightGround` — `themeInk`'s lit value, `#DEE8E0` — everywhere a ground is filled: the mark, the subagent badge behind it, the affirmative, the refusal and an option. Every `white ground` below should be read as that ground; the passages are left as written because what they say about *where* it is and *what it means* is unchanged, and only its value moved. **Hover now deepens the same hue** (§3.3); it introduces no white fill. ~~And the travel is `32 → 28` rather than `16 → 28`, because the mark is drawn as a control now — it shrinks by four points on the way down instead of growing by twelve.~~ **The travel changes no size at all** (2026-09-06, later the same day): the mark is `28` too, so the ground moves and stops being a mark, and nothing about it is redrawn on the way. The gesture is not animated in either direction, so what this clause has always asserted is what it still asserts: one ground, never two.

### 3.2 The chevron takes the place it left, and it is the exit

Where the mark was, an open row draws **the quota block's own control unchanged** — `16 × 16`, a `9 × 4.5` glyph at `1.4` stroke with round caps in `#7C7C80`, pointing up because the thing it folds is open ([`expanded-panel-v2.md`](expanded-panel-v2.md) §2.2). A click collapses the row, sends nothing, keeps whatever was typed and whatever part of a set was answered, and leaves the request exactly where it was. `⎋` does the same from the keyboard.

### 3.3 The word in the mark

~~At rest the mark says `Approval needed` or `Input needed`. Under the pointer it says `Answer` where the request can be answered here and `Read` where it cannot (§11).~~ **Redrawn 2026-09-06, and the swap is gone with the phrase.** The mark says **`Approve` on a consent, `Answer` on a question, and `Read` wherever the act is not available here** — and it says it at rest, under the pointer, and at every other moment. There is no second word.

**What the swap was for, and why removing it removes more than itself.** `Approval needed` does not look like something to click, so the pointer had to reveal a verb to say that it was; a verb on a filled chip says it without being asked. The rest follows from that one change:

- ~~**The ground can hug.**~~ **The reservation dies; the column does not.** It could not hug before: the word changed under the pointer, *nothing on a row may move as a pointer passes over it*, and so the ground was sized once against the longest of the four strings it might hold. That reservation drew `113 × 16` — `19%` of the row's content box, in the brightest value on the panel — even for a four-letter word, and killing it was right. Hugging was the wrong replacement: three verbs at three widths, each right-aligned to its row's trailing edge, left a ragged column down a mixed queue — and this is **one control appearing once per row**, not three controls, so it draws one silhouette. The reservation is now over the three verbs the mark can actually say rather than the four strings it once might, it is derived from them rather than written down, and §3.3's rule holds by construction anyway: nothing moves because nothing changes. The widest the mark can draw is `Approve`, and every verb is drawn at that width.
- **The distinction the two names carried is not lost; it chooses the verb.** A consent and a question are different waits, and `MonitorStatus.displayName` still spells both — for the mark's accessibility label, which is where a name rather than an act is what a reader wants (§13.3). **The drawn word gets shorter; the spoken one does not.**
- **`Read` is asked of the request and not of the status.** A request no connection is being held open for can only be read here and answered in its product, whatever it is waiting on — offering `Approve` on a row that cannot approve is exactly the quiet promise §11 rule 03 forbids.
- **The mark shares the answer controls' dimensions and font**: `28` tall, corner `4`, horizontal padding `12`, and `13 pt` Light from `PanelMetrics.requestControlFont`. This replaces the earlier Medium weight across `Approve`, `Answer`, `Read`, destination buttons, answer buttons and option labels. The mark reserves the widest of its three verbs using that same font; answer buttons hug their labels. Filled controls deepen the theme colour on hover: each RGB channel is multiplied by `0.85`, with full opacity. Quiet buttons deepen their theme wash from `0.24` to `0.18`; option rows without a selected ground retain the list's hover wash. Hover does not move the selected answer. The former `0.08` / `0.04` quiet fills blended into the open row, particularly on hover. The stronger fills draw approximately `#505451` / `#454846` against the default row's `#242524`; resting text retains `4.57:1` contrast.
- **The pointer confirms the target with a deeper fill and a hand.** The mark keeps the row's own timing — ~~`130 ms` in, `90 ms` out~~ none: a swept list's wash lights and clears on the frame the pointer crosses, and the mark does the same; its word and dimensions stay fixed throughout hover.

Two things from the built version are unchanged. The pointer that matters is the one on **the mark**, not anywhere on the row: the text is the Thread and the mark is the request, so a pointer resting on the title must not describe what the mark would do. And the word reads the row's **own** turn rather than its derived status, so a `Working...` row whose subagent is waiting keeps its timer and says so in brightness alone — which is `CONTEXT.md`'s rule that a row reports one Turn, with the ground as its single exception. The duration also keeps the place it already had, on the finished row ~~'s dark ground~~ behind its own dot ([`panel-v2.md`](panel-v2.md) §3.5, and [`compact-view-v2.md`](compact-view-v2.md) §4.3 for the mark) — that was settled by the reservation and survives it, because a `16` pt reading and a `28` pt control are no longer the same object at all.

**The hand is a tracking area, not a cursor rectangle.** `addCursorRect(_:cursor:)` is serviced for the key window only and this overlay is a non-activating panel that never becomes one, so the hand is set from an `.activeAlways` tracking area — and with `set()` rather than `push()`/`pop()`, because the cursor stack is global to the process and this view sits on a row that can retire under the pointer. A `set()` that is never balanced is corrected by the next thing to set a cursor; a `push()` whose `pop()` never runs is not.

~~And that is the whole mechanism.~~ **Superseded 2026-09-06: delivery was never the hard part, and on a closed row the hand did not appear at all.** The tracking area arrives exactly as described above — the chip lifts to `#FFFFFF` under the pointer, on time — and the pointer stays an arrow, because **`NSCursor.set()` does nothing outside the active application**. Measured on a panel built like this one: `mouseEntered` lands, `set()` returns, and the pointer in the very next screenshot is unchanged. Activate the application and the same call takes **with the panel still not key**, so what the window server gates on is activation, not key status.

That is exactly the line between the two surfaces this document describes, which is why the fault survived being verified. Opening a row latches the panel and latching activates this app, so every control in §7 was right; hover latches nothing and activates nothing, so the mark on a closed row was wrong — and §9.4 is not negotiable here. Hover browses. Taking the keyboard off the application the person is typing in, to change a pointer image, is not a trade this surface makes.

**So the process asks the window server for the right to set a cursor from the background, and that is all it asks for.** It does not activate, take key status, or take the keyboard. The property carrying that permission is not in a public header, so it is asked for through `dlsym`: if a release of macOS stops offering it the answer is simply no, and the panel returns to the arrow it drew before — the mark still lifts, still takes the click, and only the pointer stops agreeing. That is the one degradation, and a test asserts the permission is still granted so the day it stops is a failing suite rather than a silence.

**The two tracking scopes are separate (2026-09-09).** The always-active area
handles entry, exit and movement, so a background control can repair an arrow
set after its entry. A second area handles `.cursorUpdate` only in the key
window, where it outranks the scroll view's cursor. AppKit excludes that event
from `.activeAlways`; combining them was unsupported. Neither path activates
the app or runs while the pointer is idle.

Drawing the word under keyboard focus as well as under the pointer would be **a correction to §6** of the superseded document, and it is **not made**: with no keyboard path there is no focus to draw it under, and §9.3 — which would have created one — is declined. If the chord is ever wanted, this is one of the three clauses that comes back with it.

## 4. The body

Everything between the title line and the answer row is **one scrolling body**, and it holds whatever this request turned out to be.

### 4.1 It is bounded by the panel, not by a line count

**A correction to §3.2**, which capped the request at three lines and faded the rest.

```text
body ≤ 140 = viewport 240 − (12.5 + caption 16 + 2 + title 17 + 2) − (10 + answer row 28 + 12.5)
body ≤ 124 = viewport 216 − ( 8.5 + caption 16 + 2 + title 17 + 2) − (10 + answer row 28 +  8.5)
```

**The second line is the same subtraction, taken again** (amended 2026-09-08).
A live row's air came down from `12.5` to `8.5`
([`expanded-panel-v2.md`](expanded-panel-v2.md) §2.1), which takes `24` off the
viewport and gives `8` back to the row's fixed parts: the body loses the `16`
between them. It is a subtraction and never a chosen number, which is the whole
of why it moved — held at `140` a maximal approval would have stood `16` taller
than the three-row viewport it opens in, and the identity on the row's own line
below would simply have become false.

Approvals and plans retain this ~~`140`~~ `124` pt body cap and ~~`240`~~ `216` pt row cap. Questions with options use a body of at most `300` pt, making the open row at most `400` pt. The live viewport grows to fit that row; the heading and answer footer stay outside the body's scroll. Short bodies still hug their content, including the `117` pt row for a one-line question without options. This exception replaces the former single cap for every form: readable option descriptions need more room than the old one-line list.

### 4.2 Approval arguments retain their fields

**Redesigned 2026-09-07.** The earlier implementation flattened every `tool_input` argument into `name  value` and drew the whole request as machine text. That preserved much of the wording but erased the distinction between prose, resources and executable text: a `prompt` beside a `url` looked like terminal output. The body now retains field boundaries from the decoded payload, without trying to recover them from that flattened reading.

Each field has an `11` pt Medium label on a `15` pt line, a `4` pt gap, and its complete value. Fields are separated by `12` pt; the body has `8` pt vertical insets. Names keep deterministic key order. Familiar labels such as `URL` and `Working directory` aid scanning; the original key remains available as help. Unknown keys are also labelled and drawn, never discarded.

| Value | Treatment |
| --- | --- |
| Prompt, description and other strings | System `13` pt Regular, `19` pt lines, no recessed ground |
| URL or path | A separately labelled full value in the same readable type; no shortened host, hidden query or automatic navigation |
| `command`, `cmd`, `patch`, `diff`, `old_string`, `new_string`, `content`, `code` | SF Mono `12/18`, recessed ground, corner `4`, horizontal inset `10`, vertical inset `8` |
| Non-string value | Sorted, indented JSON on the code ground, preserving container boundaries, null, booleans and empty values |

Labels use the existing reading ink; values use the title ink. These roles select typography only, never a safety assessment. No field is collapsed behind a summary. The existing single `140` pt viewport and fixed answer row remain; field labels and values both count towards the lines below the fold. The counter counts actual line bottoms rather than dividing mixed field spacing by one line height.

Documents and questions retain their prose setting (`13/17`, reading ink, no ground). A sole `command` or `cmd` argument, a bare-string approval and manually constructed plain commands use the original unlabelled SF Mono code box. Commands accompanied by other arguments keep the labelled field layout, with the command itself still recessed and monospaced. Neither path changes answering semantics.

### 4.3 A document is accepted, but its mode is not chosen here

A plan's product offers three answers: accept and auto-approve the edits that follow, accept and approve them one by one, or keep planning. The middle of those is **a policy about every edit that follows, taken from a panel showing part of a plan**, and §6.5 already forbids a policy from being what `⏎` does. So the row offers two — `Accept`, and `Send it back` with a note — and accepting from here accepts into whatever mode the session already has. The row says nothing about a mode it did not set.

### 4.4 It scrolls, and it says how much is under the fold

A fade is right for a title, where what is lost is more of the same sentence. It is wrong for a command, where what is lost may be a second command after `&&`, a `--force`, or a path outside the project. So the body ends in **a count of the lines not on screen** — `+2 lines`, `11` pt at `#7C7C80`, at the body's trailing foot over the fade its last line already has — and the count **clears when the last line is on screen**.

A count that names something unreachable is an apology, which is why the two arrived together: the body scrolls on the pointer's wheel — **the only thing that scrolls it**, now that §9.3's arrows are declined — with a `1.5` pt rail at the body's trailing edge in the panel's own hairline value (white at `15%`) and a thumb at white `50%`. **Built by reading the wheel and translating the body, not by nesting a scroller.** A second `ScrollView` inside the list's own chains against it and loses — measured 2026-09-05, the wheel reached the app and the body never moved — which is the same finding that left the Recent queue without a scroller of its own (§2.4 rule 02). Driving the offset also makes the count exact, because the offset it counts from is the offset that was applied. **And the first form of that replacement did not scroll either** (2026-09-05, later the same day): the catcher was drawn *behind* the body, AppKit sends a wheel event to whatever wins the hit test, and behind hit-testable lines it never won one — so the wheel went on reaching the list exactly as before, with the same symptom and a different cause ([`system-architecture.md`](system-architecture.md) §6). It is drawn **over** the body now, claiming the wheel and giving back every other event, which is the shape `SecondaryClickCatcher` was already using one screen away; a body that fits claims nothing at all, so the list keeps the wheel where there is nothing here to move. The rail reports where the reader is; at `1.5` points it is not a grip, and it is never the only way to move. **Nothing else on this surface scrolls, and nothing else needs to.**

### 4.5 Wrapping preserves what indentation meant

Line breaks are the ones the product sent. A machine-text line wider than the body wraps at its edge and the continuation carries **that line's own indent plus two spaces**, so a wrap is never read as a new argument. Whitespace is never collapsed, order is never changed, and a token with nowhere to break is broken at the edge rather than dropped.

Prose, resource values and field labels wrap without adding command-continuation indentation. Explicit line breaks and source whitespace remain intact. **This paragraph was true of the wrapper and not of its callers until 2026-09-07**: a question, a plan and a document all took the wrapper's default, so every line of a wrapped paragraph after the first drew two spaces in from the one above it — a hanging indent invented for shell arguments, applied to a sentence.

### 4.6 The app never marks a command as dangerous

No verb list, no warning glyph, no colour, ever. A heuristic that knows `rm` does not know `find -delete`, a `tee` into a path, or a pipe into a shell — **every miss is silent, and every hit teaches the reader that an unmarked command has been checked by something**. Nothing on this surface has been checked. The app shows what it was handed, says how much of it is on screen, and leaves the judgement where it already was.

### 4.7 Only the lines near the viewport are drawn

**A body is bounded by the panel (§4.1) and a payload is not.** The hook
boundary accepts `128 KB` (§12.2), which is a plan of fifteen hundred wrapped
lines behind a viewport that shows eight — and every one of them was a drawn
`Text`, so opening such a plan cost `0.80` s of CPU and scrolling it about a
whole core, on Release. The lines nowhere near the viewport are now replaced by
their own height, which changes nothing anybody can see: the body is exactly as
tall as it was, so the wheel's travel, the rail and §4.4's count are all
measured from the same number, and none of them knows this happens.

**What is drawn is a slab that moves in steps, not a viewport that slides.** The
viewport is the obvious window and it is the wrong one: it changes every time
the body moves by a line, and each change rebuilds the body and re-rasterises
it (§13.2). Measured both ways — with the viewport as the window a four-option
question went from `0.32` s to `0.50` s over `240` wheel events and a
sixty-line command from `0.55` to `0.67`, while the long bodies this exists for
were three times better either way. Paying for the rare body out of the common
one is the wrong way round. So the slab is sixteen viewports, snapped to eight,
and two things fall out of that rather than being decided: **a body shorter
than the slab is not windowed at all**, which is every question and every
command of a hundred-odd lines; and **the viewport is always well inside the
slab**, so there is no offset at which the row can be looking at ground the body
has not drawn.

**Every argument field is still built, and only its lines are windowed.** A
field is one accessibility element carrying its whole label and value (§13.3),
and it takes those from the argument rather than from the drawn lines — so
skipping a field would take a parameter of the permission out of the tree, where
skipping its lines takes nothing off the screen. Their count is what a tool's
own signature bounds; their line count is what the payload does.

**What it costs a reader who cannot see the panel** is the one real trade, and
it is worth stating rather than burying. The row's own accessibility label
carries the complete body — verified unchanged at `123,844` characters on a
`1,529`-line plan — so the whole request is still read out. What is no longer in
the tree is a separate element per *wrapped line* for the lines outside the
slab: fifteen hundred fragments became a hundred, around wherever the body is
scrolled. Those fragments were a poor way to read a paragraph in any case, since
each is a wrap rather than a sentence, and §9.3 leaves the wheel as the only way
to move the body — so a reader who navigated by them could already only reach
what a pointer had scrolled to.

## 5. A question with options

### 5.1 Composition

The payload already supplies `label`, optional `description` and `multiSelect`. Titles and descriptions remain verbatim; the presentation does not infer a recommendation or summarise the choices.

| Object | Treatment |
| --- | --- |
| Question | Prose, `17` pt per line |
| Option title | System `13` Medium, `19` pt per line; wraps in full |
| Description | System `12` Regular, `18` pt per line; two-line preview, then independent `Show more` / `Show less` at `22` pt |
| Option card | `10` pt insets, `25` pt marker column, `8` pt corners; `6` pt between cards |
| Answer footer | Permanent input field on the left and the affirmative on the right — `Next` or `Submit` on a question (§5.8) — `28` pt high |

~~An instruction line sat between the question and the cards at `24` pt, naming the selection mode.~~ **Removed 2026-09-07:** it spent `28` pt of a `300` pt body restating the marker shape underneath it — a circle already says *one of these* and a box already says *as many as you like* — and the one act it described, that choosing is not sending, is taught in onboarding (§5.3) rather than repeated above every question forever. The gap it stood in becomes `12`, the distance this panel puts between any two objects, so the question still reads as the thing the list answers rather than as the head of the list.

**The card is the target, not the words on it** (2026-09-07, §6.6). The `10` pt inset ring, the marker column and the disclosure's own line all belong to the option, so the rectangle that fills under the pointer and the rectangle a click lands in are one rectangle. Only `Show more` / `Show less` is carved out of it.

Single choice uses a `14` pt radio circle; multiple choice uses a `14` pt checkbox. The selected card has a subtle theme fill and border. Description disclosure never changes selection or submits. Expanded text is complete and shares the body's wheel scrolling; there is no nested scroll area in an option. The same measured lines determine the drawing, card height and fold counter. Read-only requests still allow description disclosure while withholding selection and submission.

### 5.2 The position in the set

The caption line carries the badge and the Project on the left and **nothing at all on the right**, so the header and the count sit there — `Scope · 2/3` — in the caption's own ink at `11` pt, tabular, `8` before the chevron. Both come from the payload.

- **Every question draws it, `1/1` included.** A count that appears only sometimes is a count nobody learns to read.
- **Codex sends no header**, so that side carries only the chevron there. Claude Code's header is at most sixteen characters by its own schema, so header and count together never threaten the badge.

### 5.3 Answering one question of a set sends nothing

Only the affirmative or return records the current answer. Choosing an option never submits or advances. On an intermediate question it draws the next question and updates the count; on the last, it sends the complete set once. ~~The control says `Send` throughout.~~ **Corrected 2026-09-07 by §5.8:** it says `Next` on every question but the last and `Submit` on that one, so the control names the act the count was carrying alone. ~~Advancing clears the field, selection and expanded descriptions.~~ **Corrected 2026-09-07 by §5.7:** advancing draws the next question's *own* field, selection and expanded descriptions, which are empty until that question has been reached before — nothing is cleared, because a question that has been left is a question that can be returned to. Collapsing and reopening the same request preserves all of it. A replacement request in the same Thread starts fresh.

### 5.4 A selection outranks the field

Every question has one input field to the left of the affirmative (§5.8). There is no separate `Write my own answer` option. **A ticked option is the answer**, for both single and multiple choice; non-whitespace text in the field is the entire answer when nothing is ticked, and is never sent as an annotation on an option that is. Leading and trailing whitespace is trimmed. The affirmative is disabled when there is neither meaningful text nor a selection.

~~Non-whitespace text is the entire answer regardless of which options are selected, and while text is present the selected markers and card emphasis are suppressed.~~ **Reversed 2026-09-07.** Text winning made an option *unselectable in practice* on a question anybody had typed into: the click was accepted, nothing changed on screen, and the sentence went back to the product. The two failures were one — the suppression was the whole announcement that the options had stopped being the answer, so an option that could not be seen to be selected could not be seen to be selectable either.

**The priority is that way round because the two are not the same kind of act.** A tick is unambiguous, and it is on an option the product itself offered; text left in a field is as often a half-written thought as an answer, and a person who writes one, thinks better of it and ticks a box has decided. So the suppression moves to the side that now loses: **the field's text dims while an option is ticked**, and untick it — which only a multiple-choice question can do, since a single choice is replaced by a click and never cleared by one (§5.5) — and the field is the answer again. Neither side is ever cleared by the other, so changing your mind costs nothing in either direction.

This still replaces the original option-plus-note behaviour, which could send a selected label *and* a different typed answer, with no rule saying which the product should act on.

**What leaves the row is what was done, not how the product spells it** (2026-09-12, [generalisation package 3](product-generalisation-plan.md#6-work-package-3--structured-answers-and-permitted-operations)). An `AgentQuestionAnswer` carries the question as asked and the chosen options by their position in the set, or the words typed — so an option labelled `A, B` is one option, two options wearing one label are two, and a person typing a label is not a person choosing it, all the way to the product's own encoder. That encoder spells the answer in its product's format: Claude Code's `answers` field is one string per question keyed by the question's text, so there the labels are joined with `, ` in the product's order (§5.5) and two questions asked in the same words collapse to one key with the later answer — the product's own limitation, recorded rather than hidden. A tick on an option the question no longer offers, or words on a question that takes none, is refused at the row, at the store and at the encoder alike, and the whole set with it: half an answer is a different answer.

### 5.5 Single and multiple choice share submission

A single-choice click replaces the current selection; a multiple-choice click toggles that option. Both begin without a selection and keep the bright submission ground on the affirmative. It sends the selected label, or the selected labels joined with `, ` in their original order; with nothing selected it sends what was typed, which is §5.4 and applies to both modes. `1`–`4` do exactly what a click does on both, ticking on `multiSelect` — the exception that withheld the digits there existed only so the field could type them, and the field now keeps every key it wants by holding the caret (§9.2).

The former immediate submission on single-choice clicks is withdrawn. Selecting and sending are separate acts so a person can read long descriptions, revise a choice and enter an alternative without inadvertently advancing.

### 5.7 A set is walked backwards as well as forwards

**Added 2026-09-07.** A set was answerable in one direction only: `Send` drew the next question and there was no way back to one already answered. Claude Code's own terminal takes an arrow back through the questions it has asked, and this surface — which draws the same set, from the same call — could not. Answering the wrong option, or reading question three and realising what question one was actually about, left the person with two bad choices: send a set they knew was wrong, or `⎋` out and answer the whole thing in the product.

**The answer stops being a snapshot and becomes what the question is wearing.** What made this more than a control was that advancing *discarded* the state and kept a string: the tick, the typed text and the expanded descriptions were cleared on the way past, and only `"Postgres"` survived. A question returned to could then only have arrived empty, wearing the number of one that had been answered. So the three drafts are kept per question, and the answers are read out of them at the moment the set leaves. While nobody goes back the two are the same value; when somebody does, the snapshot would be the older of two answers to a question they deliberately came back to change.

| | Rule | |
| --- | --- | --- |
| 01 | **`Back` stands in the slot a question's absent refusal already leaves free** — §7's own geometry, and no new region: the field simply gives up the space it took there. It is drawn on question two and after, and not at all on question one | §7 |
| 02 | **It never holds the ground.** It sends nothing, so the brightest object on the row is still the only thing `⏎` does. Nor does it wait out §6.3's arrival, which arms a ground and not a control that spends nothing | §6, §6.3 |
| 03 | **The question arrives as it was left** — the option still ticked, the field still holding what was typed into *it*, the descriptions still open. That is the whole of what going back is worth | §5.1, §5.4 |
| 04 | **The affirmative is unchanged, and it is still the only thing that advances.** From a question returned to it draws the next one, which is the one already answered; on the last it sends the set. A person who goes back to question one of four presses it three times — `Next`, `Next`, `Submit` (§5.8) — each on an answer already filled in and visible | §5.3, §5.8 |
| 05 | **`→` returns to a question already reached and can never reach a new one**, which is what makes it incapable of sending: reaching a new question is the whole of what `Next` means, and on the last question the affirmative is `Submit` | §9.2, §5.8 |
| 06 | **A question that stops answering anything cannot be left.** Empty the field and untick the boxes on a question returned to, and the affirmative and `→` are both refused on it — the same gate, asked once. That is what stops a set walking backwards from sending a short one | §5.5 |

**Only a multiple-choice question can be emptied at all**, which is worth saying because it is what rule 06 is guarding: a single choice is *replaced* by a click and never cleared by one (§5.5), so a question answered by one option can never stop being answered.

~~Rule 05's arrow gives up on a question whose answer was typed, and `Back` is what works there.~~ **Corrected 2026-09-07 by §9.2's focus rule:** the arrow walks the set whatever the question is wearing, because it only reaches the panel at all while nothing holds the caret. `Back` is still the control that works in every state — it is a click, and a click never has to ask what the keyboard is doing — but the two no longer disagree.

### 5.6 A restatement is a question whose question is long

Claude Code will sometimes put back what it understood and ask whether that is right. It is the same machinery — the summary is the question, and two options stand under it — so nothing special is needed to support it, and that is the point. What it does need is §4.2's prose setting and §4.4's scrolling, both of which it shares with a plan.

### 5.8 The affirmative says which of the two things it does

**Added 2026-09-07.** One control both draws the next question and sends the set (§5.3), and it said `Send` for either. On question two of three that word was a promise the row did not keep: nothing was sent, the body changed and the count moved — and the person who had read the count knew that, while the person who had read the control had been told the opposite. The count was carrying the whole of the distinction, and the brightest object on the row was arguing with it.

**So the word is a statement about where the set stands.** `Next` while there is a question behind the one on screen; `Submit` on the last one. Nothing else about the row moves: the ground is still the return key made visible, the field still takes the space a refusal would have had (§7), and the two words are measured the same way every control here is — their own text plus `12` a side — so a set that walks from `Next` to `Submit` changes the width of one control and moves nothing that is not it.

| | Rule | |
| --- | --- | --- |
| 01 | **`Submit` on a set of one, `1/1` included.** A vocabulary that appears only on long sets is one nobody learns to read — §5.2's own argument for drawing the count on every question | §5.2 |
| 02 | **A lone question with nothing to pick is that same set of one**, and says `Submit` too. §5.3 already makes form 04 a set with one member rather than a case of its own, and this follows it rather than inventing a third word | §2.1, §5.3 |
| 03 | **It follows the set backwards as well as forwards.** Go back from the last question and the word is `Next` again; it is not a latch that trips once | §5.7 |
| 04 | **Approvals are untouched.** `Approve`/`Deny` and `Accept`/`Send it back` are about what is being granted, not about position in a sequence, and there is no sequence to be anywhere in | §7 |
| 05 | **The notice is unchanged.** Both words leave the same *Answered* on the preview line: what a person did was answer the set, whichever control the last press landed on | §8 |

**`Back` and `Next` are not a pair, and are not drawn as one.** `Back` sends nothing and never holds the ground (§5.7 rule 02); `Next` records the answer and is the only thing that reaches a new question. They sit side by side because §7's geometry puts them there, and the ground is what says they are different — which is the same reason the row does not gain a `Previous`/`Next` symmetry it would then have to explain.

## 6. One selection rule

**The brightest object on the row is always the thing the return key will do.**

For approvals and plans it begins on the affirmative; typing moves it to the refusal that carries the reason. A deliberate click on either approval control still submits that control's answer.

### 6.1 Questions keep the affirmative as the default

Questions use separate draft selection and submission state. The bright ground stays on the affirmative — `Next` or `Submit` by §5.8 — and is disabled until an answer is available. Option clicks change draft selection; description disclosure changes only what can be read. Return has exactly the same submission semantics as a click on it, including typed-text priority. Hover changes neither selection nor the default control.

### 6.2 The wheel is the only thing that scrolls, and the list does not walk

The pointer's wheel scrolls a body taller than the space it has, and nothing else does. With no row open there is nothing to move at all: opening is a click on a mark, and the list is browsed by hover exactly as it always was.

The arrows would have arrived with §9.3, and so would the one thing they need decided — that on a row whose body holds **options** all four move the ground and the body scrolls to keep it in view, while on a row whose body holds **no answers** the axes divide the way the drawing already does: `←` and `→` between the two controls, `↑` and `↓` down the body. That argument is kept there rather than deleted, because it is the part that took the thinking, and because a declined design is worth more written down than gone.

### 6.3 A ground that has not finished arriving is not a key, and not a target

Answering one question draws the next, and answering one request opens the next row (§8.2). Both put something the reader has never seen under a control the pointer is already on — and, later, under a return key a finger is already on. So the affirmative is **armed by the arrival it already animates**: the ground grows on the panel's own slot curve, and it takes a click, or a return, when the growth ends. Nothing new is drawn and nothing is delayed that the eye was not already waiting for.

**This is worth more with a pointer than it was with a keyboard**, and the drawing is why: an answered row is replaced in place by the next thing to answer, so the affirmative that arrives lands where the affirmative just clicked was. A hand has to travel to press `⏎` a second time. A pointer has to do nothing at all.

The rejected alternative was a fixed delay before the control becomes live, which would have been a new timing to tune and would have felt slow on the row a person opened deliberately.

### 6.4 Denial is the cheap direction

An empty `Deny` sends a plain no. A `Deny` carrying text sends the text, which is the third answer both products actually offer — *no, and here is what to do instead*. The caret is in the field from the moment the row opens, so refusing with a reason is a sentence and a return and no travel at all; granting needs either an untouched field or a deliberate move back to the affirmative.

### 6.5 `Always` is not offered, and neither is a plan's mode

Both products' second answer is *yes, and do not ask again*. It is a policy about every future request, taken from a panel showing part of the current one. Notchline answers this request and hands policy back to the product. If it is ever added it belongs beside the affirmative in the recessed ink and **never on the white ground, because the white ground is the return key**.

**Re-examined 2026-09-06, and the decision stands.** Raised as a defect — Claude Code's own dialogue draws three answers where an open row draws two — so both halves were measured against the shipped product rather than argued about. They are there, on both sides:

| Half | Where | What it is |
| --- | --- | --- |
| Read | `PermissionRequest` hook input | `permission_suggestions?: PermissionUpdate[]` — a tagged union of `addRules` / `replaceRules` / `removeRules` / `setMode` / `addDirectories` / `removeDirectories`, each with a `destination` of `userSettings` \| `projectSettings` \| `localSettings` \| `session` \| `cliArg` |
| Write | the same hook's `allow` decision | `updatedPermissions`, **the same type**. The product applies it to the session's permission context and persists it to the named destination |

Three things that measurement settled, and they change what building it would cost rather than whether it was declined:

- **Withholding needs nothing new.** An ask carries *either* `suggestions` *or* `suppressAlwaysAllowRule`, never both, so a request arriving with no `permission_suggestions` is one the product's own dialogue draws no persistent-rule row for. Absence is the whole signal — which matters, because the hook payload carries neither `suppress_always_allow_rule` nor `default_to_no`; those are on the SDK's `can_use_tool` request only.
- **This app cannot widen a grant even by accident.** Before applying a hook's `updatedPermissions` the product filters them through the tool's own `suppressesAllPermissionUpdates`.
- **The payload carries the rule and not the words.** The product composes at least three phrasings itself — *don't ask again for &lt;domain&gt;*, *for `<cmd>` commands in &lt;dir&gt;*, *always allow access to … from this project*. So the label is the real design question, not the transport.

**What landed instead: the read half, and nothing drawn.** `permission_suggestions` is carried through the distiller and parsed into `AgentRequest.offeredRules`, so a row *knows* a persistent rule was offered. Nothing draws it, `AgentAnswer` gains no case, and a grant from the notch is still a bare `allow` that writes to no settings file. That keeps this section's decision intact while removing the reason it could not have been reversed cheaply.

**And if it is ever drawn, the label is composed per rule kind** — the product's phrasing for a domain, a command family and a path, falling back to the rule verbatim for a kind not recognised. Decided 2026-09-06, and it is the one deliberate exception to §2.3: the payload holds no phrase to quote, so a surface that refuses to compose one cannot draw this answer at all. The rule that survives is the narrower one — **nothing is paraphrased that the product did send**, and a composed label may name only what the rule it was composed from actually grants. What goes back on the wire is the suggestion **verbatim**, never re-encoded from this app's own parse, so a union member added to that product and not to this type cannot round-trip into a different rule.

### 6.6 What a click takes, and what hover never does

The initial version is answered with the pointer, so the pointer's rules are the ones that have to be exact.

- **A click on an approval control submits its answer.** A question option only changes selection; the affirmative submits the effective answer. `Show more` and `Show less` only change the description's visible extent.
- **Hover moves nothing.** Buttons deepen their existing theme ground under the pointer (§3.3), and the selected ground stays where the person's own typing left it. The ground is a statement about `⏎`, and a pointer crossing an answer is not an act.
- ~~**The field takes the caret when the row opens**, so a note costs no click of its own and §6.4's cheap refusal stays cheap.~~ **Withdrawn 2026-09-07: the field is an ordinary focusable field.** It takes the caret on a click into it and loses it on a click anywhere else — an option card, a control, the body, the caption. What it cost was the whole keyboard: with the caret always in the field, every key on this surface had to be conditional on *what the field was holding* rather than on where the caret was, and the two rules that followed both broke in the case they were written for — `1` selected an option instead of typing a `1`, and `←` walked the question set instead of moving through the sentence just written (§9.2). It also put the one blinking object on this surface over a row nobody was writing in. **What it costs is one click on the two forms that carry a refusal**: §6.4's cheap direction is now a click and a sentence rather than a sentence alone, which is the price of a keyboard whose rules can be learned once.
- **What lights up is what takes the click.** An option card fills under the pointer over the whole of its `10` pt ring, and that fill is a promise about where a click lands: every point of it selects the option, apart from `Show more` / `Show less`, which is a target of its own. **Added 2026-09-07, as a defect.** The card was drawn one way and built another — the button sat *inside* the padding and the disclosure was its sibling, so the ring and the whole of the disclosure's line either side of two words answered the pointer and refused the click. At `579 × 100` that was `44%` of an expandable card lit and dead, and it fails in the way that teaches nothing: the pointer says *here*, the click says nothing at all, and there is no second thing to try. The card is now one button with the padding inside its label and the disclosure drawn over a band held open for it. Pinned by `everyPointUnderAnOptionsFillTakesItsClick`, which drives real events at a real hosting view because nothing in the view tree reports hit order.
- **A click that is not on an answer is not an answer.** Body text and the rail do not submit; option selection and description disclosure follow §5. The only two regions on an open row that lead anywhere else are the chevron, which collapses it, and the row's own text, which opens the Thread (§3).

## 7. The answer row

```text
Approval      [ what to do instead…        ]   Deny   [ Approve ]
Input         [ your answer…                      ]  [ Submit ]
Plan          [ or say what to change…     ]  Send it back  [ Accept ]
```

At the content width of `496`, relative to the content's leading edge:

| Object | Extent |
| --- | --- |
| The affirmative | Right-aligned; width is its own text plus `12` each side |
| The refusal | `8` before the affirmative; the same padding when it holds the ground, `13` pt Light `#C7C7CC` when it does not |
| The field | From `0` to `8` before the refusal |

Both grounds are corner `4` and `28` tall — the mark's own `16` grown by §3.1 — and **neither control moves when the ground crosses between them**: each is its own text plus `12` a side whether it is holding the ground or not. A form with one answer (`Next` or `Submit`, §5.8) omits the refusal and the field takes the space.

**The one thing that stands in the space the refusal left is `Back`** (§5.7), on a set past its first question:

```text
Question 2/3  [ your answer…                 ]  Back  [ Next ]
Question 3/3  [ your answer…               ]  Back  [ Submit ]
```

It is that slot's own geometry unchanged — `8` before the affirmative, its own text plus `12` a side, quiet at rest and never holding the ground — and the field gives up exactly the width it takes, which is the same trade the refusal already makes on the two forms that have one. On question one there is no `Back` and the field is the whole row again, so the two states differ by one control appearing rather than by a layout.

**The field is drawn with no ground of its own at rest**, decided while building it and worth stating because the drawing above implies one. The body directly over it is already on the recessed step where it is machine text, and a second recessed rectangle immediately below reads as more body rather than as a place to type. What says the field is a field is the placeholder, in the label's own ink, which is the only text on this row that is not something the product or the person said.

**Under the pointer and while it holds the caret it wears the row's own quiet button wash** (2026-09-07). That reasoning is untouched: this is not §4.2's recessed step but the wash `Back`, `Deny` and `Submit` already wear beside it, at the same `4` corner and the same `28` height, and it is nothing at all when neither is true. It is there because the caret used to be the other half of the answer to *is this a field* and no longer is (§6.6) — resting at the pointer's weight, deepening while focused, and edged at the weight a selected option card is edged at, because a field holding the caret and an option holding the answer are the same statement about where the next thing you do will land. **Since 2026-09-15 the box the field stands in draws that ground, and it covers the whole grown field** (§7.1): the text view is now as tall as its text and slides under a clip.

### 7.1 The field grows to four lines, then scrolls inside itself

**Added 2026-09-15, as a defect.** The field was a bare text view held to the row's `28`, and its own comment said a second line would scroll. Nothing scrolled it: a text view outside a scroller neither scrolls nor clips. A draft that wrapped, or took a `⇧⏎`, drew its second line through the bottom edge of the ground and over whatever came below the row — seen on a Claude Code question, with the second line lying across the `Recent` seam.

```text
one line      [ Software engineer.                  ]  Back  [ Submit ]
two lines     [ A software engineer who enjoys…     ]  Back  [ Submit ]
              [ (use something like this)           ]
past four     [ Line 6 of what I wrote            ┃ ]  Back  [ Submit ]
              [ Line 7 of what I wrote            ┃ ]
              [ Line 8 of what I wrote            ┃ ]
              [ Line 9 of what I wrote            ┃ ]
```

| | Rule |
| --- | --- |
| 01 | **One line is the row it always was**: `28` tall, so an answer that fits moves nothing |
| 02 | **Each further line adds `16`**, the text system's own line for `13` pt, to the field and so to the row. The field is `12 + 16 × lines` |
| 03 | **Four lines is the ceiling**, at `76`. Past it the lines scroll between the ground's `6` pt insets and never through them. The text system keeps the caret in view, the wheel reaches what went above the fold, and the body's rail (§4.4) stands at the trailing edge while there is anything to scroll |
| 04 | **The controls stay beside the first line.** The row grows downward from the notch, so a control on the last line would walk down the screen a line at a time under a pointer resting on it. A chat field works the same way: its send button stays still while the field grows away from where it is anchored |
| 05 | **The whole grown field wears the ground**: the wash under the pointer, and the edge while it holds the caret (§7). A press on the insets gives the caret too |
| 06 | **It publishes when a line comes or goes, never on a keystroke.** The store measures the draft at a fixed wrap width with the TextKit 1 stack the field draws with, so the height reserved is the height drawn. That width is the body's (§4.1) less the controls beside the field. `Back` is counted wherever the set has one, so an answer in flight keeps its lines when the send hides `Back` (§8 state 01) |

**What was rejected.** Keeping `28` and scrolling one line sideways hides what was written from the person about to send it, and those words are the answer. Growing without a ceiling lets a paste of any length push the rest of the list away. Moving the field onto its own line above the controls would redraw every row to serve the long answer, while growing in place leaves the common short answer exactly as it was.

**The typed baseline came down a point** (inset `5` → `6`). It now sits on the baseline of `Back` and `Submit`; before, it was `1` pt high (sampled from an offscreen snapshot, `2×`: all three at row `376`).

## 8. Sending, and what the row becomes

Every state below is one the panel already draws for another reason, so an answer sent from here has no aftermath of its own. It has an outcome, and the outcome is a row.

| | State | Drawn as |
| --- | --- | --- |
| 01 | **In flight** | The field and both controls drop to `45%` and stop taking keys. Nothing resizes. No spinner, no progress, no new mark: the wait is a few hundred milliseconds and anything drawn to fill it would outlive the thing it described |
| 02 | **Landed** | The body and the answer row leave, the row returns to `80`, the preview line says what was sent, and the status is whatever the Thread now is — after a grant, `Working...`. There is no confirmation to dismiss, because the row is the confirmation |
| 03 | **Not delivered** | The row goes back to waiting with the text still in the field and the reason on the preview line, **in the preview's own ink**. The app has no failure ink, and inventing one for a transport error would make it louder than a Turn that genuinely failed, which is drawn as ordinary preview text under an unchanged marker. **The reason is the one the channel proved** (2026-09-12, `AnswerOutcome`): the peer went away (`Not sent — the product stopped waiting for this answer`), the product's own window ran out (`… the time for answering here ran out`), nothing holds the handle any more (`… this request can no longer be answered here`), the product refused in its own words (`Not accepted — <reason>`, which no shipping channel can hear yet), or the operation is one the channel does not carry. **One more, and it is the only one that sends the person somewhere**: `Sent, but not confirmed — check in <product>`, for a write nobody can vouch for. It keeps what was typed like every other not-delivered row and, unlike every other, must never be sent again: the handle is spent by the attempt |
| 04 | **Settled elsewhere** | Granted in the product, cancelled, or the Thread gone: the row closes within one publish and becomes what it now is. What was typed is dropped, because there is nothing left to send it to. This is the one close the user did not ask for, which is why it is the row changing state rather than a message about a row. **All three of those endings close it, and the third used to be missed** — a row still on the list that stopped asking was reconciled, and a row that left the list altogether was not, on the reasoning that nothing draws it either way. The latch is what that reasoning forgot: it is keyed on the open row's id rather than on the row, so an unclosed departure left the panel holding the keyboard over nothing (2026-09-05, `system-architecture.md` §6) |

**Landed and not delivered are one mechanism**, decided while building: either way the row goes back to `80` and says one thing on the line it already draws — `Approved`, `Denied`, `Accepted`, `Sent back`, `Answered`, or one of state 03's sentences. **Landed means *sent*, not *accepted*** — a hook's stdout is written and closed and nothing comes back on it; measured, both products act on what arrives there (§14.2), but that is a fact about the products and not an acknowledgement, and the row's past-tense word is the app's summary of what it did, not the product's. **A handle is spent by one attempt**, at the channel and again in the store: a second press while the answer is on its way sends nothing, and a press after it landed — however it landed — sends nothing either, because an answer that may have arrived must not arrive twice. **And a result that lands after another request has taken the row annotates nothing**: a row is `agent:threadID:turnID`, the request on it can change while an answer is in flight, and a sentence about the old request under the new one's words would be a sentence about the wrong thing. *Not delivered* leaves the row closed rather than open, because the sentence goes on the preview line and an open row has no preview line; what was typed stays with the row (§10), so reopening finds it where it was left. The line stands until the product says something newer, which is the only clock this needs: the app's own sentence is the last word exactly until the Turn it answered produces one of its own.

### 8.1 Answering does not retire a row

It is tempting to file an answered request beside the read and the dismissed and let it halve under [`expanded-panel-v2.md`](expanded-panel-v2.md) §2's seam. That would be a lie about what happened: **a granted command is a Turn that is now running**, which is the least finished thing on the panel. Retirement stays what §2 defined it as — read, dismissed, or gone — and answering is not one of them.

### 8.2 More than one request waiting

Two at once is the ordinary case, not the edge one: a Turn asks while a subagent it forked is already asking ([`PRD.md`](PRD.md) §6.2 band 2). The panel gains no counter for it.

**And two on one agent is ordinary too** (2026-09-12, [generalisation package 2](product-generalisation-plan.md#5-work-package-2--requests-identified-independently-of-slots)): Claude Code runs tool calls in parallel and asks about each. Every request a producer has open is held under its own identity, the row opens one — the Turn's own questions first, then its approvals, then running subagents' approvals; answerable before merely readable; then in arrival order — and **the one a person is reading stays on screen while it is still live**, whatever the product now puts first. Only its resolution moves the row on. Answering one opens the next on the same row (below), and switching what is drawn sends nothing.

- **The answered row falls exactly one place.** `Approval needed` sits directly above `Input needed` in the sort the list has always had, so with one other request waiting the two exchange places on the panel's own slot curve and nothing else moves.
- **The next request opens itself**, with its affirmative unarmed by §6.3 — which is what stops the click that answered the first from answering the second. The advance is the whole notification: there is another one, and here it is, already open and already legible.
- **One row is open at a time**, and it is the subject: opening scrolls it to the top of the viewport and holds it there against re-sorting, lays the hover fill under it permanently, and drops every other row to `45%`.

### 8.3 The panel does not close on send

**A correction to §3.5.** Closing on send would shut the panel in front of a second request nobody had seen. With nothing left waiting the panel **unlatches** — it hands the keyboard back and starts answering the pointer again — and that release is how it says you are finished. It still closes on `⎋`, on a click outside, and on the pointer leaving, as it always did.

## 9. Arrival, the pointer, and the keys the field keeps

### 9.1 Two doors, and a third that is drawn and not built

- **The knock is unchanged**, and it is still the notification. The collapsed bar draws the double-knock curve the moment a request arrives ([`compact-view-v2.md`](compact-view-v2.md)). Nothing on this page reaches the collapsed surface: it says a person is wanted, and it never says what for.
- **The pointer keeps every door it had, and in the initial version it is the only one.** Hover browses, a click on the mark engages, a click answers (§6.6). None of that is new machinery and none of it can fail at registration, which is most of the argument in §1.1.
- ~~**The chord is the third door**~~ **There is no third door.** §9.3 is declined: the pointer opens this panel and the keyboard answers inside it.

### 9.2 The bindings, and the condition on them is focus

The panel takes the keyboard so that a row can be read without being lost and a note can be typed into it (§10), and that is the whole of why it takes it. **Which keys are the field's and which are the panel's is decided by where the caret is, and by nothing else.** Click into the field and it is an ordinary field: every key is the text system's, bar the two below that are the field's own. Click anywhere else and the caret leaves it (§6.6), and the panel's three keys are live.

| Key | Whose | Does |
| --- | --- | --- |
| anything printable | The field's, while it holds the caret | Goes into it, and moves the ground to the answer that carries text. With the caret elsewhere it does nothing: no type-ahead, no first-letter jump, no single-letter shortcut |
| `⇧⏎` | The field's | A new line in the field. A refusal that explains itself is often two sentences, and an alternative command is often two lines. It is the only way to get one, which is why `⏎` can be unambiguous |
| `⏎` | Both | Takes the answer the white ground is on, which is what the ground has said all along. On a question that is one of a set, draws the next and sends nothing; on the last, sends the set. Refused, rather than swallowed, where `Send` is greyed |
| `⎋` | Both | Collapses the row; again, closes the panel. The chevron's own action, and the key that hands the keyboard back: the row stays on the list holding its text and its part-answered set |
| `1`–`4` | The panel's, while nothing holds the caret | Selects or ticks the option at that position, exactly as a click on it would, on single and multiple choice alike. Never submits. In the focused field it is a character like any other |
| `←` `→` | The panel's, while nothing holds the caret | Walks a question set backwards, and forwards again over a question already reached. Never submits: `→` cannot reach a question the set has not drawn (§5.7). In the focused field it moves the caret |
| `⌘⏎` | **Unbound, and it stays that way** | A second way to approve would make the white ground advisory rather than definitive, and the whole safety of this surface rests on the ground being the literal truth about `⏎` |
| everything else | **Unbound** | §9.3's keys are declined rather than pending, so there is nothing here waiting for a later stage. Binding one of them anyway would be a keyboard model with a hole in it, which is worse than a panel that plainly does not navigate |

*Unbound* means the panel binds nothing to them, not that they are swallowed: in a focused field `Space` types a space, `⇥` types a tab and an arrow moves the caret, exactly as they would in any field, and with the caret elsewhere they reach AppKit untouched. What none of them does is move the ground, walk the list, or send anything: measured on Release for `⌘⏎`, `⇥`, all four arrows and `Space`.

**The panel's three are taken bare only.** `⌥1` is a character of its own and is nobody's option number; `⌘←` is `moveToBeginningOfLine:` and is nobody's step through a set. A modified key is left alone entirely.

~~The digits and the arrows are offered to the panel out of the focused field's own `keyDown` and command table, and taken only while the field is empty.~~ **Replaced 2026-09-07.** That was a rule about a *string* standing in for a rule about the *caret*, and it broke in exactly the two cases it was written for: a person who clicked into the field to answer `1. the first one` typed nothing and selected an option, and a person revising what they had written could not press `←`. Emptiness was only ever a proxy for *the caret has nothing to do here*, and focus says that directly. The keys now arrive at the window, which is where a key goes when nothing inside it wanted one.

**What that costs is that a keyboard-only answer needs the caret out of the field**, and the way to put it there is a click somewhere else on the panel — there is no key that unfocuses, because `⎋` already means *give the keyboard back* and a surface with two escapes has neither.

### 9.3 The keyboard half, declined and kept whole

**Withdrawn by the board's owner on 2026-09-06.** It was stage 03 of §1.1 and deferred behind stage 02 the day before; it is now a decision rather than an ordering. **The panel's keyboard is the field's own keys and the digits** (§9.2), and this app claims no chord from the rest of the machine.

**One key survived the decision**: `1`–`4` take the option they number, which is the only row of the table below that reaches nothing outside this panel and needs no navigation model behind it. It was built on 2026-09-06 under §15 q08's condition — *before* anything has been typed — and that condition was replaced on 2026-09-07 by the one in §9.2: the digit is the panel's while nothing holds the caret.

**A second pair joined it on 2026-09-07, and it is not this section coming back.** `←` and `→` walk a question set (§5.7) on the digits' own condition, which is now focus. The row below proposes something else entirely — arrows that *move the white ground* between options and *walk the list* where no row is open — and that is still declined: the ground is moved by typing and by nothing else, and the list is browsed by hover. What was built navigates a set inside an already-open row, which is a thing this document's own §5.2 count has drawn since the first version.

What follows is kept as the design that was considered — it adds no region, no ink, no control and no height; it adds keys, and one word this surface already draws under the pointer. It is recorded here **so that a decision taken once does not have to be argued twice**, and so that the cost of taking it is legible: §13.3.

| Key | Would do | Argued in |
| --- | --- | --- |
| `⌥Space` | Bring the panel down already latched, with the first row by the existing sort already open and the caret in its field. With nothing waiting it opens the panel latched at the top of the list instead, so **the chord is never a key that sometimes does nothing** — the only variable is whether a row is already open when it lands. User-settable, defaulting to `⌥Space`, and registered through the ordinary system path so that a clash **fails loudly at registration** rather than quietly at use; the settings row shows the chord it actually holds, not the one it asked for | §15 q03 |
| `↑ ↓ ← →` | Move the white ground, and walk the list where no row is open. The body scrolls to keep the ground in view; on a row whose body has no answers to move between, `↑ ↓` scroll that body directly | §6, §6.2 |
| `1`–`4` | Take a numbered option directly — **only while the ground is still on an option**, which is to say before anything has been typed. After that a digit is a character like any other. *Built, and then loosened: the condition is the caret's whereabouts, not the field's contents (§9.2)* | §15 q08 |
| `Space` | Tick the option the ground is on, `multiSelect` only | §5.5 |
| `⇥` | **Still unbound.** Once the arrows exist, every journey `⇥` would serve already has a key | §15 q10 |

Three clauses of this document would arrive with those keys, and each is a correction only a keyboard user makes necessary: the word drawn under focus as well as under the pointer (§3.3), the arrows as a second force on the ground (§6), and the axis split on a body with no answers in it (§6.2). **None of the three is made**, and two of them are corrections to [`expanded-panel-v2.md`](expanded-panel-v2.md) that therefore stand as that document wrote them.

**What declining this costs is in §13.3.** It is the one consequence of the decision that is not merely a shape not drawn.

### 9.4 The panel never takes the keyboard unasked

Hover browses and cannot latch, however long it lasts. **Only a click on the mark makes the panel key** — an unambiguous act, and the chord will be the second one. This matters more than it looks: the panel sits over whatever the person is typing into, and a surface that took focus on proximity would eat a line of their code. Latching takes key status from the application underneath, so `⎋`, a send with nothing left waiting, and a click outside all give it back to the same window; if that window has gone, focus goes wherever the system would have sent it and the panel does not hold it open waiting.

**What that costs was measured rather than assumed, and it is more than the panel** (2026-09-05, Release). `.nonactivatingPanel` promises a panel may hold key status without its application being brought forward, and as far as the panel is concerned it keeps that promise: with a row open the panel *is* `NSApp.keyWindow` and the field *is* its first responder. The keyboard is not the panel's to take on those terms — every keystroke went on to whichever application was in front, and the global monitor watching for a click outside counted a click on the panel's own field as one, so the row closed instead of answering. **An application that is not active does not receive keys, whatever its windows believe.** So the app activates for as long as a row is open and gives the application back on the same three exits, which is what the paragraph above always described — [ADR 0020](adr/0020-the-panel-takes-the-keyboard-by-activating.md). Two smaller things were in the way of it and are recorded there: `becomesKeyOnlyIfNeeded`, which makes AppKit refuse `makeKeyAndOrderFront` outright, and a text view built with no text container, which takes the caret and swallows everything typed into it.

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
| 06 | **The two halves are per product, and per connection.** A Codex row that can be answered beside a Claude Code row that can only be read is an ordinary mixed list, not a special case. The row says what that row can do — and what it can do is what the connection held for it was declared to accept (`AnswerOperations`, 2026-09-12): a decision on both products' `PermissionRequest`, a question's answers on Claude Code's `AskUserQuestion` alone. A question drawn over a Codex connection is read here whatever is held, where it used to be offered `Submit` and then say *not sent* | |

Nothing here is scaffolding to be thrown away, which is what makes shipping the reading half first a decision rather than a delay.

## 12. Heights

Every open row is `100` plus its body. **And plus `16` for each line of the field past the first, up to three** (§7.1, 2026-09-15): a field at its ceiling adds `48` to any row below, and the live viewport grows to fit it as it does for a question.

| The row | Height | The body it holds |
| --- | --- | --- |
| Closed, waiting | ~~`80`~~ `72` | None. `8.5 + 16 + 2 + 17 + 2 + 18 + 8.5`, the [`colour-v2.md`](colour-v2.md) badge caption included |
| A question with nothing to pick | ~~`117`~~ `109` | One prose line, `17`. The shortest row that can be opened |
| An approval at three lines | ~~`170`~~ `162` | The machine-text block at `70` |
| A question at three options | ~~`193`~~ `185` | A question line, `12`, and three `24` pt options — `93` |
| A restatement at three lines, two options | ~~`203`~~ `195` | Prose `51`, `12`, two options `48` — `103` |
| An approval or plan at the maximum | ~~`240`~~ `216` | The body's cap, ~~`140`~~ `124`. The row **is** the three-row viewport |
| A question at the maximum | ~~`400`~~ `392` | The question body's cap, `300` (§4.1), on `92` of fixed parts. Past the three-row viewport, which grows to it |
| In flight | unchanged | Nothing resizes; the controls lose `55%` of their opacity |

At the `46` pt menu bar reference with both products connected and the footer at rest — `22`, [`quota-footer-v2.md`](quota-footer-v2.md) §2:

> **The panel column below is the arithmetic of 2026-09-07 and is kept as the
> record.** Three things have moved under it: the footer at rest is `35` rather
> than `22` (`38` until its bottom inset came down to the panel's own side
> padding on 2026-09-09), the Recent seam is its own section rather than a line
> inside the live viewport, and a row's air came down (§4.1, 2026-09-08). The
> viewport figures still say the thing the table is for — which row heights push
> past the cap, and which do not.

| The list | Panel | Note |
| --- | --- | --- |
| One waiting row, opened at `117` | **217** | Viewport `149` — the row and the seam beneath it |
| One waiting row, opened at three lines | **270** | Viewport `202`. [`expanded-panel-v2.md`](expanded-panel-v2.md) §4, unchanged |
| One waiting row, opened at the maximum | **308** | Viewport `240`, and the seam is below the fold |
| One waiting row, opened at a question's maximum | **468** | Viewport `400`: §4.1's exception, the panel growing with the row rather than clipping it. Arithmetic, not a Release measurement |
| Two waiting rows, the first opened | **308** | Content over the cap; the second row is clipped, not hidden |
| Three live rows, one of them opened | **308** | The cap has been reached since V1 and does not move |

These read `279` / `332` / `370` in version 1.0, taken with a footer of `84` — [`dual-agent-design.md`](dual-agent-design.md)'s two-product figure, which [`quota-footer-v2.md`](quota-footer-v2.md) had already replaced with `22` at every product count. **Every one of them falls by exactly `62`** ([`panel-v2.md`](panel-v2.md) §3.1). Nothing in this document's own arithmetic moves: ~~the viewport cap is `240` and the open row's cap is the viewport.~~ **Corrected 2026-09-07, against the panel:** that held while every form shared one `140` pt body. A question's `300` pt body puts its row at `400`, and §4.1 has the live viewport grow to fit it — so `240` is the cap on *closed* rows, and an open question is its own floor under it. The two were read separately for a day: the window was sized from the grown viewport while the list still drew itself at the flat `240`, which left the panel standing exactly `160` taller than anything painted into it, the last option clipped under the footer, and that strip of panel empty. One height, read off the store, is what closes it. Opening the quota table adds `112` on top, at two products and three windows.

Width is [`expanded-header-v2.md`](expanded-header-v2.md)'s `520` in every state, and [`colour-v2.md`](colour-v2.md) §3 keeps it there at every agent count.

## 13. Motion, accessibility, and the one thing that ticks

### 13.1 Motion borrows, and borrows nothing new

- **Opening** grows the row in place on `PanelMotion.slot(isOpening:)` while the bright ground travels from the caption line to the answer row — one object moving, not one fading out and another in. The body's content fades in behind its ground rather than being revealed by it.
- **Drawing the next question of a set** is that same curve run on the body alone, with the head and the answer row still. **Going back is the same drawing** (§5.7) — the body changes and nothing else does — except that it does not re-arm the affirmative: §6.3 exists for a question nobody asked for and has never seen, and a question returned to is the opposite of both.
- **The advance** (§8.2) is that curve run on two neighbours at once.
- **In flight** is opacity and nothing else.
- The affirmative arms at the end of whichever of these was playing, so §6.3 costs no timing of its own.

### 13.2 The caret is the one thing that ticks, and it must not be ours

A blinking caret is precisely the continuously running animation the overlay forbids ([`system-architecture.md`](system-architecture.md) §6): drawn from SwiftUI it would invalidate the whole panel, `PanelContour` and every text measurement, twice a second, for as long as a row is open. **The field is therefore an AppKit text view hosted in the panel**, with its caret drawn by the text system into its own layer — the same division that already sends persistent motion to Core Animation.

The scrolling body is the second thing to watch: it must scroll its own layer rather than re-laying-out the row. Measure both under Release, and measure the burst by diffing cumulative CPU time rather than reading `ps %cpu`. **And check that the thing being measured is running** — this one was not, and a burst measurement of a gesture that does nothing looks exactly like a burst measurement of one that does.

**Both were measured on 2026-09-05, under Release, and they answer differently.**

| State | CPU over the window | Read as |
| --- | --- | --- |
| A row open, the caret blinking, nothing else happening | `0.12` s in `20` s | Identical to the collapsed panel at rest (`0.13` s in `20` s). **The caret costs nothing**, which is the whole of §13.2. *Since 2026-09-07 an open row has no caret in it until somebody clicks into the field (§6.6), so this is now the cost of the state a person types in rather than of every open row* |
| ~~`600` wheel events over a body of `60` lines~~ | ~~`3.3` s~~ | ~~~`4.7` ms an event over the `0.5` s the same `600` events cost with nothing to scroll~~ **Withdrawn: the body was not scrolling** |
| `600` wheel events over a body of `60` lines, the body actually moving | `1.03` s | `1.7` ms an event, over the `0.58` ms an event a body that fits costs by declining them |

**And the question form was measured on 2026-09-07, which is the shape this document actually specifies.** The rows above are a command — sixty `Text` lines and nothing else. A question is those lines plus option cards, and it turned out to cost far more than either the wheel or the caret, for a reason neither row above could see: the *whole body was being laid out again on every read of it*, and the panel reads it a few dozen times to draw one frame. Opening an approval detail was `0.66` s of CPU, one option click `0.29` s, one keystroke `0.26` s, and a hundred and twenty wheel events past an open row `0.44` s against `0.16` s with the row shut. They are now `0.16`, `0.04`, `0.007` and `0.17` s — the last being the with-the-row-shut figure, so an open request costs nothing to scroll past. The three causes and their fixes are in [`system-architecture.md`](system-architecture.md) §6; two of them are this document's business, because they are properties of how a body is drawn rather than of how the panel is refreshed:

- **The lines are still wrapped here rather than by the text system** (§4.5), and still character for character, so §4.4's count of what is below the fold stays exact. What changed is that the fitter bisects for the break instead of measuring every prefix of a line in turn: identical lines out, across `910` cases spanning five fonts, seven widths, both indent modes and a corpus of Unicode, emoji, tabs, URLs and unbreakable tokens.
- **The body is composited into an image before it is translated**, so §4.4's wheel moves a layer rather than re-drawing four option cards a frame. It is what took the sustained figure from `40%` of a core to `15%`, which is what the same sweep costs with no row open at all. Verified pixel-identical, with the same accessibility tree and the same clicks.
- **And a body far longer than the viewport draws only the lines near it** (§4.7), which took a fifteen-hundred-line plan from `2.09` s to `0.51` s over `240` wheel events and `0.80` s to `0.55` s to open, at `39` MB less resident — while leaving every question and every ordinary command drawing exactly what it drew.

The second row is the one to keep an eye on, and it is not the row that was written here first. ~~It is a whole panel's worth of work per event rather than a translation, and `.equatable()` on the body was tried and bought nothing, so what it is re-doing is not the sixty `Text` lines.~~ **That measurement was of a scroller that was never running** — the catcher sat behind the body and AppKit never handed it an event, so `600` wheel events over an open request moved nothing and what was being timed was the panel's list refusing to scroll ([`system-architecture.md`](system-architecture.md) §6). With the delivery fixed the honest figure is `1.7` ms an event, it is transient and user-driven — paid only while a finger is actually moving, and a flick is a second or two — and it does scale with the number of lines drawn (`0.51` s at `10` lines against `1.35` s at `120`, over the same `600` events). ~~which the layer-backed body §7 would prefer is what would take away.~~ **The layer-backed body §7 would prefer was then built and measured, and it is three times worse** — it draws pixel-identically and costs `5.20` ms an event against `1.74`. The scaling is real and it is a minority of the cost: an empty body scrolled the same way costs `1.19` of the `1.74`, so the sixty `Text` views are half a millisecond and the rest is the scroll itself ([`system-architecture.md`](system-architecture.md) §6). **It is `expanded-panel-v2.md`'s scroller rather than this document's**, it predates the answer row, and it is recorded here because §16 asks for the number rather than because this change caused it.

### 13.3 Accessibility follows the ground, and speaks the count

- Each option control is named by its full title, with its full description as an accessibility hint. Its value reports selection and whether typed text has replaced it. The independent disclosure announces its option and expanded/collapsed state. The affirmative reports disabled when no answer is available, under whichever of §5.8's two words it is drawing.
- The position in the set is spoken with the question — *question two of three*.
- **`Back` is spoken as the act rather than the word**: *Back to the previous question*, because `Back` on its own says a direction and not what it goes back to. It is the one control on the row whose drawn word is shorter than what it does (§5.7), and like every other it carries an accessibility action, so assistive technology reaches it without the arrow.
- **The count of lines below the fold is spoken with the body.** A reader who cannot see the count must not be the only one who does not know something is missing.
- A closed waiting row keeps the accessible action `Answer this request` (or `Read this request`, §11) regardless of hover, and every answer on an open row carries an action of the same kind. Assistive technology therefore reaches all of them by its own means, which are not key bindings and never depended on §9.3 — which is why declining that section changes nothing here.

**What this surface does not give is full keyboard access, and that is now a standing property rather than a stage.** With no chord, somebody who works without a pointer answers in the product exactly as they do today: nothing they could do gets worse, and nothing this page adds is for them — except the digits and §5.7's two arrows, both of which need a row already open and so need the pointer to open it. It is the largest cost of the decision in §9.3, and it is stated here rather than in a footnote **because it is the thing that would reopen that decision**: this is the only paragraph on the page that would change if the chord were ever wanted.

## 14. What this reaches outside the viewport

### 14.1 One field this app already receives and throws away

`HookPayload.CodingKeys` names `hook_event_name`, `session_id`, `turn_id`, `prompt_id`, `agent_id`, `tool_name`, `tool_use_id`, `permission_mode`, `cwd`, `prompt`, `last_assistant_message`, `message_id`, `delta` and `background_tasks` — **and not `tool_input`**. `HookPayloadDistiller` walks the top level once and steps over every key `CodingKeys` does not name.

**A second field went the same way, and was found the same way** (2026-09-06): `permission_suggestions`, the rules Claude Code offers to write if a request is granted. It is now a sixteenth key, `.request` like `tool_input` and inside the same gate rather than beside it — it arrives only on a `PermissionRequest`, which the gate already admits, so it can never widen what another event carries. §6.5 says what is done with it, which is: read, and drawn nowhere.

That is right as it stands, and the reason is recorded: the helper forwards stdin unchanged, so an oversized `PostToolUse` tool result once took the lifecycle event down with it, leaving a wait its `tool_use_id` opened unclosed until the Turn's `Stop` (CR-030). **Nothing about the size of a tool result is evidence about the Turn.**

What §2 needs is narrower than lifting that. **Built on 2026-09-05, and two of the three clauses below were wrong when this document first wrote them.**

- ~~`tool_input` is kept **only on `PermissionRequest` and `PreToolUse`**~~ — **that gate is far wider than it sounds.** `PreToolUse` fires for *every* tool call and is one-to-one with `PostToolUse`, so it halves the volume rather than removing it. Measured 2026-09-05 over 30,909 `tool_use` blocks in 736 transcripts under `~/.claude/projects` — p50 263 B, p99 8,951 B, max 136,560 B — it would copy and decode about **28 MB** of arguments nobody reads, on the serial read queue. The gate actually wanted is **the events that open a wait**, which admits 56 of those 30,909 calls: **0.18%**. It is read off the signal table each vocabulary already declares (`AgentHookVocabulary.carriesRequest(forEvent:toolName:)`), so `PostToolUse` is refused *by construction* rather than by a rule somebody has to remember — which is the shape CR-030 turned out to be.
- ~~It is kept **bounded**, as `.text` in `CarriedValue`'s vocabulary~~ — **`.text` is wrong twice.** It means *cut short: a shorter answer is the same answer*, which is false of an object: half of one is not JSON, and cutting it would make the whole payload undecodable and lose the lifecycle event with it. And `.text`'s bound is 16 KiB, which **would have refused the only `ExitPlanMode` plan on this machine** (54,411 bytes) — the single form the reading half exists for. There is a fourth `CarriedValue` case instead, `.request`, meaning *whole or left out, and only on the events that ask*.
- The bound has to be generous enough for a plan, and a plan is the largest thing either product sends this way. `maximumRequestBytes = 128 KiB` — 2.4× that plan, and above 99.997% of the measured corpus.

One mechanical note, because it is the part that is easy to get wrong: the distiller emits fields as it scans, and `hook_event_name` and `tool_name` are not promised to precede `tool_input` — on Claude Code they never do, its keys arriving alphabetically. So the request is **held as a range into bytes the scan already has** and emitted after the loop, once both names are known. **Held per key, and that only became load-bearing when there were two of them**: one slot re-emitted under a hard-coded `tool_input` would not merely drop `permission_suggestions` — alphabetical arrival means the suggestions win the slot every time, and are then drawn as the command a person is being asked to approve. The emit order is read off `CodingKeys` rather than off the dictionary, because a `Dictionary` iterates differently between instances holding equal values and the projection compares rendered strings. A `PostToolUse` whose request is refused therefore pays nothing at all for the refusal: no copy, no decode, and no second pass over a payload whose tail may be 16 MiB of tool result. Where two copies of the key arrive, the **first** wins, because that is what `JSONDecoder` does with a repeated key — measured, not assumed.

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

**What it costs is inside this app, not outside it — and that half is now built** (2026-09-05, [ADR 0019](adr/0019-the-helper-answers-on-the-stream-adr-0013-silenced.md)). ADR 0013 made the helper silent — `exec >/dev/null 2>&1`, `nc -U -w 1`, `exit 0` — so nothing this app computes could reach the product. Stdout is now opened **per call rather than per file**: the helper takes one literal argument, `wait`, which the registration passes on the one definition that asks a person, and every other event still discards stdout at the call. `nc` was measured holding the connection past stdin's EOF, taking a reply and printing it at status 0; `-w` turned out to be an *idle* deadline rather than a total one, so `-w 3600` costs nothing when the answer comes in three seconds. On Codex the timeout lives in the hashed definition, so it costs one silent re-trust of `PermissionRequest` alone (ADR 0014, amended for the second and final one).

**And the product acts on it, measured rather than read off a schema.** Against Claude Code 2.1.261 in a pty-driven session: an `allow` written six seconds after the product had already raised its own dialogue dismissed that dialogue and let the tool run, with nothing typed into the session; a `deny` with a `message` produced `Denied by PermissionRequest hook` and handed the reason to the model as the tool's error. The dialogue itself appeared 0.32 s after the hook fired and did not wait for it — so §8's *settled elsewhere* is a real path and not a formality, and a person who walks to the product mid-decision finds the prompt there.

**And on Codex the hook's answer is the decision, not a race with a dialogue** (measured 2026-09-06, CLI `0.153.4`, an escalation request under a read-only sandbox driven through `codex app-server` against a throwaway `CODEX_HOME`). The client this app-server was talking to **was never asked for an approval at all** — no approval request of any kind reached it — and `hook/completed` recorded the `permission-request` handler running for `28,285 ms`, the length of the person's decision, after which the command ran. So the two products differ here in a way worth writing down: Claude Code raises its own dialogue 0.32 s in and takes whichever answer arrives first, while Codex puts the question to the hook and waits for it.

**And on 2026-09-15 that difference turned out to have a cost this section did not draw, at the surface where a person is already sitting.** A hold is a second surface beside the product's own on Claude Code and *instead of* it on Codex — so a local Codex CLI Turn asking for a command spent the whole wait showing `Working` in its terminal, with the question only on the notch; quitting Notchline put it back in the terminal at once. That is not a defect in the transport, it is what "waits for it" means, and it decides the scope rather than the mechanism: **a request raised by a local Codex TUI is released as soon as its payload has been read** (`CodexSurfaceLedger.receive`, whose peer *is* the execution that raised it), so Codex asks the person in front of it and the notch draws the reading-only form. `nc` returns 22 ms after that close, so the terminal pays nothing for having been read. Codex Desktop keeps the hold: there is no prompt a person walked away from, the notch is the surface, and that half is what `product-support.md` §3 still calls answerable.

**One shape drops to read-only, and it is not the one §2 expected.** Codex's `PreToolUse(request_permissions)` — how a Codex Desktop approval arrives, and which sends no `PermissionRequest` at all — cannot be held: `PreToolUse` fires on every tool call, so a window a person could answer inside would be a window every tool call waits in. So on Codex the answerable set is `PermissionRequest`, and a Desktop approval is read here and answered there.

~~Until one does, §3 to §8 are a drawing~~ — [`expanded-panel-v2.md`](expanded-panel-v2.md) §8.4's rule still stands and is now satisfied rather than blocking: a panel offering `Approve` it cannot deliver is worse than a panel that offers nothing, and this one can deliver it. §11 is still what ships first, because reading is the larger removal and the cheaper build.

### 14.3 The panel has to be able to take the keyboard

Latching means the `NSPanel` becomes key, which takes focus from whatever the user was in and must give it back on `⎋`, on send, and on a click outside. `PanelMetrics` has nothing to say about it and `OverlayPanelController` has everything. **This one belongs to the initial version, not to §9.3**: a panel that cannot become key cannot hold a caret, whatever opened the row.

### 14.4 Two stated non-goals move, and the same two as before

[`PRD.md`](PRD.md) §3 rules out "sending input, granting permission, answering questions, cancelling, archiving or deleting threads", and separately rules out showing "tool arguments, command output, file diffs, sensitive paths or approval rationale".

- **The first reverses for exactly one payload** — the request a row is already reporting — and for nothing else. No cancelling, no archiving, no deleting, no starting a Turn.
- **The second narrows to one exception**: the payload of a request the product is already blocked on. Nobody can grant a command they have not been shown. Every other item in that sentence stands, output and diffs included — the approval body now preserves labelled fields with prose or code typography (§4.2), while §4.6 continues to forbid safety judgements.

**Neither amendment is made in this change**, on the same footing as [`expanded-panel-v2.md`](expanded-panel-v2.md) §8.1: nothing here is implemented, and the PRD is the product contract rather than a design record. They are made in the change that builds §14.1.

### 14.5 First run has to be able to teach it

The window a user meets before anything else described the surface as it was before this shipped, and the two statements it made about it were both wrong: it said the app *only reads*, and it drew a waiting row as a reading on white rather than as the control this document made of it ([`figma-design.md`](figma-design.md) §7.4, §7.1).

Both are corrected there rather than here, and one of them reaches this document's own rules. **A specimen that teaches the answer control has to carry an answerable request**, and `canBeAnswered` is `replyTicket != nil` and nothing else — so the first-run fixture holds a ticket that leads nowhere. §11 rule 03 forbids offering an affirmative the app cannot deliver, and this does not breach it: the rule protects a person who can click, the drawing declines every hit, and a click that somehow arrived would find no connection under that number and say so. The alternative — a specimen drawing `Read` — would have taught the reading-only form as though it were the ordinary one.

The two shapes are both drawn, on the same page and for §7's reason: a permission has a refusal and a question does not, so their answer rows are not the same object, and a user shown one and later handed the other would meet a row that had changed shape unannounced (`figma-design.md` §7.1.2).

## 15. Open questions

| | Question | Where it stands |
| --- | --- | --- |
| 01 | Will either product accept an answer from outside it? | **Answered — yes, and then observed doing it** (schemas read from both products' shipped binaries 2026-09-05; Claude Code 2.1.261 then measured accepting an `allow` and a `deny` with a reason from a hook's stdout, and raising its own dialogue 0.32 s after the hook fired without waiting for it, §14.2). Both accept an approval decision on the hook's own stdout; Claude Code also accepts a question's *answers* through `updatedInput`, which Codex reserves and fails closed on. So §3 to §8 are unblocked, with §5 built for one product and read on the other |
| 02 | Will this app keep the request it is already sent? | **Answered — yes, and built on 2026-09-05.** §14.1, whose own first two clauses were wrong and are struck there. What carrying it costs is 0.18% of tool calls rather than all of them, because the gate is the events that open a wait; `PostToolUse` is refused by construction, so CR-030's hazard is not re-entered |
| 03 | Which chord, and what happens when it is taken? | ~~**Answered by the board's owner on 2026-09-05**: `⌥Space`, user-settable, registered through the ordinary system path so a clash fails at registration rather than silently at use.~~ **Closed on 2026-09-06 by the same owner: there is no chord.** The question is not open and not deferred — this app registers no global hotkey and offers no setting for one, so neither the chord nor its failure path exists to be answered about (§9.3). What the answer would have been is kept above, struck, in case the question is ever reopened |
| 04 | Does the count say lines, or bytes? | **Standing recommendation: lines.** A byte count is precise and unreadable; a line count matches what the reader is looking at and is the unit in which a hidden clause hides. Where a request arrives as one enormous unbroken line, the count is of wrapped lines |
| 05 | Should `⏎` ever take an answer the reader has not seen? | **Answered — no**, and §6.3 is how. It now answers the sharper version of the same question — should a *click* — because a pointer already resting on the answer does not have to move to press twice. The rejected alternative was a fixed delay before the control becomes live |
| 06 | Is `Always` ever offered from here? | **Answered — no, and re-affirmed 2026-09-06 after both halves were measured on the shipped product.** §6.5, and [`expanded-panel-v2.md`](expanded-panel-v2.md) §8.5 question 05. What changed that day is not the answer but its cost: `permission_suggestions` is now carried and parsed, so the row knows a persistent rule was offered and reversing this would draw and write rather than re-open the transport. The label form is decided in advance (§6.5) so that a later reversal is not also a design question |
| 07 | Does the notch choose how a plan's edits will be approved? | **Answered — no**, and for the same reason. §4.3 |
| 08 | Do the digits stay bound once a question has been typed into? | **Answered — no, and built that way on 2026-09-06.** Reserving them permanently would silently eat the first character of an answer beginning with a number, so the gate is a completely empty field on a single-choice question. Since 2026-09-07 a digit selects without submitting. The digits are the one key of §9.3 that survived that section being declined, because they need no navigation model behind them (§9.2) |
| 09 | Does an MCP elicitation ever get drawn here? | **Answered — no.** §2.2. Reopen only on a measurement of what servers actually send |
| 10 | Is `⇥` ever bound? | **Answered — no, and now permanently.** With §9.3 declined there are no arrows for it to be redundant beside and no walk for it to join: it would be the only key on this surface that navigates, which is a keyboard model of one binding. It types a tab into the field like any other character, measured on Release |
| 11 | Does a row that cannot be answered still knock? | **Answered — yes, unchanged.** The collapsed bar reports that a person is wanted, which is true whether the answer will be given here or in the product |
| 12 | Does a click on an option answer with it, or only select it? | **Revised 2026-09-07 — it only selects**, in both modes. The affirmative records the effective answer, with typed text taking priority (§5). |
| 13 | Does a row that can only be read still take the keyboard? | **Answered — yes.** §10. It has nothing to type into, but it is the state a person reads longest, and a row closing because a pointer drifted is exactly the failure that rule exists to prevent |
| 14 | When does the keyboard half land? | **It does not.** Deferred on 2026-09-05, declined on 2026-09-06 (§9.3): the panel answers to the field's keys and the digits, and reaching it still needs the pointer. The one thing that would reopen it is §13.3, which is the whole of what the decision costs |

## 16. Verification

**Historical Release evidence:** the measurements below predate the 2026-09-07 question redesign. Their fixed `24` pt options, `140` pt question cap, first-option ground and immediate single-choice submission no longer describe the current question UI. Current geometry and answer semantics are pinned by `OptionPresentationTests` and the answering tests. ~~the new question layout has not had a Release performance measurement.~~ **It has now** — opening, answering, typing and scrolling past it, before and after, in §13.2 and [`system-architecture.md`](system-architecture.md) §6 (2026-09-07). Approval and transport measurements remain applicable.

- [x] A closed waiting row is `80` at every menu bar height, badge caption included, and a row with no mark gains no second target. **Measured on Release** by diffing the drawn panel rather than trusting the metric: one, two and three closed rows give `140`, `220` and `300`, so a row costs exactly `80` drawn. A `Running` row with no request draws its elapsed readout where the mark would be and no mark at all. *The menu bar height itself is not varied here* — that dimension needs a second display and is held by the geometry tests.
- [x] A click on a row's text opens the Thread; a click on the mark opens the row. ~~no other region does either.~~ **Corrected against the row, 2026-09-05:** the row *is* the Thread, minus the mark — a click on the empty space between the title and the mark opens the Thread too, because `SessionRow` is one `Button` over the whole row with the mark's own gesture carved out of it. That is what §3 says (*"a click anywhere on the badge, the Project, the title or the preview"*, and *no other **row** gains a click*); this line's "no other region" read it as a claim about pixels and was the only wrong thing here. Measured on Release: title → the Thread, empty middle → the Thread, mark → the row and never the Thread.
- [x] Opening moves one bright ground from the caption line to the answer row — the surface never draws two at once — and a chevron pointing up stands where it was. **Counted on Release** rather than eyeballed: flood-filling every near-white region of the panel finds exactly **one** before opening (the mark, `112 × 15` on the caption line) and exactly **one** after (the affirmative, `75 × 27` on the answer row) — the ground travelled and grew, and at no point are there two. *The two figures are the measurement as taken on 2026-09-05; §3.3's redraw makes the mark `76 × 28` and the ground `#DEE8E0`, so a re-run would flood-fill for the ink rather than for near-white — and the mark and the affirmative now differ in width alone. What was being counted — one, then one — is unaffected.*
- [x] The chevron and `⎋` both collapse the row, send nothing, and preserve typed text and any part-answered set; reopening resumes at the same question. **Measured on Release**: `keepme` typed into a command's field survived `⎋` and reopening, then the chevron and reopening, with zero sends on the wire across all of it.
- [x] The body is at most `140` and the open row at most `240`, in every form; a one-line question makes a `117` pt row. **Measured on Release across all four drawn forms**: a `60`-line command and a `60`-line document both cap at `drawnHeight 140` and `openRowHeight 240` from content of `1096` and `1020`; a question with options is `227`, a multi-select `210`, and a genuinely one-line question is **`117.0`** exactly.
- [x] Prose draws with no ground and machine text on `#242424`, chosen by payload and not by length, on all seven shapes in §2. **The following is the earlier whole-body measurement; the 2026-09-07 field layout is verified by `ApprovalPresentationTests` and native view snapshots.** **Sampled on Release**: a command's body is `(36, 36, 36)` — `#242424` — against the open row's own `(43, 43, 46)` around it, and a document, a question with options, a multi-select and an option-less question all draw the body on the row's own ground with no recessed step. **Length plays no part**: a four-line command is machine text and a sixty-line document is prose.
- [x] A body longer than its cap scrolls on the wheel, draws the rail, and shows a count that clears when the last line is on screen. ~~*(Ticked on the code alone, and it was false: the wheel never reached the body.)*~~ **Re-ticked 2026-09-05 against a Release build with a staged `60`-line request** — driven by synthetic wheel events and screenshotted before and after: the lines move, the rail's thumb travels, the count falls from `+54` to nothing, and the fade goes with it.
- [x] A wrapped line's continuation carries its own indent plus two spaces; no whitespace is collapsed and no token is dropped. **Read character for character off the drawn layout on Release**, which a pixel measurement cannot settle — two monospace spaces and the glyphs' own left bearings are the same distance apart. A command indented four spaces wrapped to `    indented_start --with-a-long-flag && ` / `      a_second_command_that_forces_the_wrap --force ` / `      /a/path/outside`: the original four survive on the first line, the continuations carry **six**, and the three lines concatenate back to the input with `&&`, `--force` and the path outside the project all intact.
- [x] No command is ever marked, coloured or flagged by the app. **Sampled on Release** over `sudo rm -rf /Users/…/Projects --force && curl http://…/x.sh | sh`: exactly one ink holds more than 2% of the glyph pixels — `(199, 199, 204)` — and everything else over that ground is antialiasing between it and `#242424`. Not one token is bolder, brighter or a different colour than any other.
- [x] Every question draws `header · n/N`, including a one-question call; ~~a Codex question draws the chevron alone.~~ **Drawn on Release**, and the second clause is looser than §5.2: with a header the caption line reads `Scope · 1/1`, and with none — which is what Codex sends — it reads `1/1` and the chevron. **The count is still drawn**; what a Codex question loses is the header, not the count, which is the first clause of this very line.
- [x] `⏎` on any question but the last draws the next and sends nothing; the last sends the whole set. **Measured on Release** with a three-question set: returns at positions `0` and `1` advanced the index and nothing left the app; the return at position `2` was the only one that reached the wire, and it closed the row.
- [x] Every question form draws the field; typing moves the white ground onto the affirmative. **Measured on Release**: a question's ground starts on its first option and one keystroke moves it to the affirmative, which on a question ~~is `Send`~~ **is `Next` or `Submit` since 2026-09-07 (§5.8)** — the measurement is of the ground, and the word under it is the only thing that changed.
- [x] With `multiSelect` the ground never leaves the affirmative, the numerals are boxes, and a click on a box or its label ticks it. **All three on Release**: the numerals are drawn as boxes, the white ground sits on the affirmative from the moment the row opens, a click on the first option's *box* and then on the second option's *label* left `ticked=[1, 2]` — and the ground was still there at the end of it. The control read `Send` when this was measured; §5.8 renamed it on 2026-09-07 and moved nothing.
- [x] The white ground is on the affirmative with an empty field and on the refusal with a non-empty one; neither control moves as it crosses. **Measured on Release**, including the return trip — deleting the text puts the ground back on `Approve`. *Neither control moves* is measured rather than eyeballed: `Deny`'s box occupies the same columns whichever control is lit, as does `Approve`'s, and each label sits centred in its own box to the pixel.
- [x] Nothing but typing moves the white ground: hover moves it nowhere, and a click takes whichever answer it lands on whether the ground is there or not. **Measured on Release**: hovering `Deny` drew its hover fill and left the ground on `Approve`, and clicking `Deny` from there took the refusal.
- [x] The only keys the panel answers to are the field's — anything printable, `⇧⏎`, `⏎`, `1`–`4` on an untouched question — and `⎋`. ~~`⌥Space`, `↑ ↓ ← →`, `Space`, `⌘⏎` and `⇥` are all unbound~~ **`← →` came out of that list on 2026-09-07** (§5.7): on a question set with an empty field they walk the set, and everywhere else they are still the caret's. ~~*on a question set with an empty field*~~ **— corrected the same day** (§9.2): the condition is that nothing holds the caret, and a focused field keeps both arrows whatever it contains. `⌥Space`, `↑ ↓`, `Space`, `⌘⏎` and `⇥` are unbound, and the app registers no global hotkey. Measured on Release: `⌘⏎`, `⇥`, the arrows and `Space` send nothing and move nothing; inside the field they do what a field does, which is §9.2's rule rather than an exception to it. **Re-measured 2026-09-05** on an open question set with the modifiers actually applied: across `⌘⏎`, `⇥`, all four arrows, `Space` and the digits, **zero answers were taken and nothing was sent**, and the set never advanced. `⇧⏎` put a newline in the field and sent nothing; the `⏎` after it took the answer and drew the next question. `⇥`'s only effect is the tab it types, which moves the ground exactly as any other character does.
- [x] A row opened by an advance, and a question drawn by answering the one before it, take neither a click nor a return until the opening animation has ended. **Measured on Release, both halves**: a return `50` ms after an advance and a click `40` ms after one each reached the surface and were refused by an unarmed affirmative, leaving the set where it was. The gesture has to be aimed inside the window to test it at all — at `700` ms both are taken, which is the same measurement saying nothing.
- [x] While a row is open the panel does not close on pointer exit, holds the keyboard, and returns it on `⎋`, on send and on an outside click. **All five measured on Release**, with another application frontmost before the row was opened: the pointer moved right off the panel and it stayed open at its full height; the panel became `NSApp.keyWindow` with `AnswerFieldView` first responder and took a keystroke posted the way a person's arrives, six times out of six; and `⎋`, a send, and a click on the desktop each collapsed the row and left the app inactive with no key window.
- [x] A request settled elsewhere closes the open row within one publish; a send that fails keeps the text and says why in the preview's ink. **Both drawn halves measured on Release**, over and above the two unit tests that already pinned the store: a product that stops asking mid-row closed it within one publish and took the panel from `248` to `140`, carrying the half-sentence with it; and a send that could not be delivered put `Not sent — the product stopped waiting for this answer` on the closed row's preview line in **`#7C7C80`, sampled and identical to an ordinary preview's ink**, with the text still there on reopening, five times out of five. (A click on the mark inside the in-flight window does nothing, which is §8 state 01 rather than a miss — the reopen has to wait for the send to land.)
- [x] **And a row whose Thread leaves the list closes too** — added 2026-09-05, because it did not. §8 state 04's other half went unhandled on the reasoning that `openSession` reads through the list, so a departed row draws nothing and needs no reconciling. True of the drawing, false of the latch: `isLatched` reads `openRowID` itself. Measured on Release, with the pointer well off the panel — Thread gone, the panel **stayed expanded over an empty list**; product quit, the panel collapsed to the pill and **still held the keyboard**, so every keystroke went on reaching this app with nothing on screen to say why. `closeARowWhoseRequestHasGone` now treats an absent row the same as a row that stopped asking, and `aRowWhoseThreadHasGoneClosesAndUnlatches()` fails without it.
- [x] An answered row returns to `80` and to the Thread's current status, and does not retire. **Measured on Release** with a product that actually takes the answer: the panel went `248` → `140`, the mark and the answer row went with the request, the row drew its elapsed readout as an ordinary running Turn with `Approved` on the preview line, and it stayed on the live list above the seam rather than retiring.
- [x] With no write path the mark says `Read`, no white ground is drawn anywhere on the open row, and one control stands where three would. **All three on Release**: hovering the mark on a row with no reply ticket draws `Read` where an answerable one draws `Answer`, and the open row carries `Answer in Claude Code` on the recessed ground with no field, no `Approve`, no `Deny` and no white anywhere on it. *Since §3.3's redraw the mark says `Read` without being hovered, and an answerable one says `Approve` or `Answer` by its status — the fact being checked, that an unanswerable row is offered no act, is what `aWaitingRowsMarkIsDecidedByItsRequestAndNotByThePointer` now pins for every status at once.*
- [x] The panel's CPU cost while a row is open, and while its body is scrolled, is measured under Release by diffing cumulative CPU time. §13.2 carries both numbers.
- [x] ~~**A digit takes the option it numbers while the ground is still on one, and is a character afterwards**~~ **A digit takes the option it numbers while nothing holds the caret, and is a character inside a focused field** (§9.2, §15 q08). The Release measurement behind the struck clause still stands as a measurement — `3` on a three-option question took `DuckDB` and drew `2/2`; with `x` typed first, `1` went into the field as `x1` — it is the *rule* it measured that changed on 2026-09-07, because the field only had the caret in that second case by taking it unasked. Pinned by `aDigitSelectsItsOptionWithoutSendingWhateverTheFieldHolds`, `aDigitTicksWhereSeveralAnswersAreAllowed` and `onlyABareKeyIsThePanelsAndTheRestAreLeftAlone`.
- [x] The band, both collapsed forms and the quota footer draw identically to pages 01 to 09 in every state above. **Measured rather than eyeballed, 2026-09-06**: the same staged fixture — two waiting rows and a quota — was built at `99d544c` and at this change, launched on Release, and screenshotted collapsed and hover-expanded by window id. The two collapsed captures and the two expanded captures differ **only inside the aggregate mark's own bounding box**: the same `5 × 5` grid at the same position and size, caught at two phases of the `CAAnimation` it has always run. Every other pixel is identical — both wings, the count beside the mark, the rows, the seam and the quota footer — and the panel is `334 × 38` collapsed and `530 × 220` expanded on both builds.

- [x] **A real approval, on a real session, on each product — and the product acts on it.** Added 2026-09-06, because every tick above was taken against a staged store and a stub service: none of them had ever put a product on the other end. **Claude Code 2.1.263**, a `Bash` call in a pty-driven TUI: the row drew the whole `tool_input` — `command` and `description` — the field, `Deny`, and `Approve` holding the white ground; pressing `Approve` released the held `nc`, the command ran (`probe.txt` written with its exact content), and the row went back to `80` reading `Completed, took 27 seconds` with the agent's own answer on its preview line. **Codex `0.153.4`**, an escalation request under a read-only sandbox, driven through `codex app-server` against a throwaway `CODEX_HOME`: same drawing, same result — `codexprobe.txt` written, row back to `80` and `Completed, took 34 seconds`. And on Codex the decision is the hook's rather than a race with a dialogue: **the app-server asked its client for approval not once**, and `hook/completed` records the `permission-request` handler running for `28,285 ms` — the length of the human decision — before the turn carried on.
- [x] **A set walks backwards, and the question comes back wearing its answer** (§5.7, added 2026-09-07). Pinned by four store tests — the tick and the typed text both survive the round trip, the answer that travels is the one the question was last wearing rather than the one it was passed with, `→` cannot reach a question the set has not drawn, and a question emptied after being answered cannot be left. ~~**And the key is asserted against the real objects rather than against a closure**: `aBareArrowReachesThePanelThroughTheFieldsOwnCommandTable` puts a real `AnswerFieldView`, inside a real `OpenRow`, in a real key window, and sends it a real bare `←` `keyDown`.~~ **Replaced 2026-09-07**: the arrow no longer arrives through the focused field's command table, so what is asserted against the real objects is the mechanism that replaced it — `theFieldTakesTheCaretOnlyOnAClickAndLosesItOnOneElsewhere` puts a real `AnswerFieldView` inside a real `OpenRow` in a real `OverlayPanel`, finds it *not* first responder, and watches a press elsewhere take the caret back off it. The drawing was read off a cached `NSHostingView` at both ends of that trip: `Back` stands between the field and `Send` on `2/2` and is gone on `1/2`, where the field takes the space again.

  **Not measured on Release, and not against a live product.** Every tick above this one was taken with a two-question fixture and a stub service; a real multi-question `AskUserQuestion` walked backwards in the notch has not been done, and neither has a Release performance measurement of the extra body redraw — which is the same redraw §13.1 already attributes to drawing the next question, run in the other direction.
- [x] **A long answer stays inside its field** (§7.1, 2026-09-15). Covered by four tests. `aLongAnswerGrowsTheFieldALineAtATimeAndStopsAtFour`: `28`, then `+16` a line, then the ceiling, and no publish for a keystroke within a line. `anAnswerInFlightKeepsTheFieldsLines`: `Back` hidden by a send changes neither the wrap width nor the row. `aFieldGainingALineResizesThePanelAndReachesTheWindow`: the new height reaches the window's publisher list. `aLongAnswerStaysInsideItsGround` puts a real field in a real `OverlayPanel` and checks that the box is the height reserved, lines break where the store measured them, the caret's line is inside the clip past four lines, and the wheel scrolls back up. An offscreen snapshot at one, two, four and nine lines drew nothing outside the ground. The per-edit measurement costs `0.02` ms for a 20-character draft, `0.1` ms for 200 and `3.1` ms for a 10,000-character paste, averaged over 2,000 calls of the same layout code in an optimised standalone build.

  **Not seen in the running app, and not typed into a live product.** The panel's resize when a line arrives uses the same publish-and-schedule path as drawing the next question (`answerRevision`), which is already live, but that animation has not been watched with this change.
- [x] **A real `AskUserQuestion`, answered from the notch, with the product's own transcript read back.** The item this feature exists for, and the one that found a defect (§17): before the fix the row drew the question and offered `Answer in Claude Code`. After it, the open row draws the two options with the white ground on the first, the field beneath them and `Send`; pressing the second option released the connection and the row returned reading *You picked SQLite.* The transcript is the proof and it is not a refusal — `7419d4c4-…jsonl` records the `AskUserQuestion` `tool_use` and then its `tool_result`, `is_error` absent: *"Your questions have been answered: \"Which store should the probe write to?\"=\"SQLite\". You can now continue with these answers in mind."* The tool ran and returned the answer, which is the whole of what `updatedInput` buys over a refusal.

## 17. Implementation mapping

**Built** (2026-09-05): a request is read in the notch and answered there, in every shape either product asks in. The work landed in a handful of places, and the first of them was the only one with no dependency outside this repository.

| Symbol | Change |
| --- | --- |
| `HookPayload`, `HookPayloadDistiller` | **Built.** `tool_input` as a fifteenth `CodingKey`, carried as a new `.request` kind — whole or left out, bounded at `maximumRequestBytes = 128 KiB` — and admitted only on the events that open a wait, read off each vocabulary's own signal table through `carriesRequest(forEvent:toolName:)`. ~~carried as `.text`, kept on `PermissionRequest` and `PreToolUse`~~ is struck in §14.1 with the measurements that struck it |
| `AgentRequest`, `AgentRequestReading` | **Built**, and not in the original plan. The typed request and its four drawn forms, projected **at the Hooks boundary** before typed evidence is submitted, with the reducer attaching the established wait identity afterwards. The boundary holds the signal, event name, tool name and vocabulary together. Approval arguments retain their field names, values and typography roles in `argumentFields`, projected from `tool_input` in sorted key order (§4.2); question options retain their full title and description for the measured card layout (§5) |
| `HookEventRepository` | **Built.** The request is a field **of** `PendingApproval` and of a new `PendingInput`, ~~a `PendingRequest` on the Turn's wait slots, per `(agent_id, tool_use_id)`~~ — a table beside the waits would have to be cleared at all seven sites that clear one, and a rule that holds until one site forgets it is exactly CR-030. `HookTurnState.requestAwaitingAnAnswer` picks the one request a row can open, in the order `PRD.md` §6.2 already reads, oldest subagent first. **Since 2026-09-12 each producer holds a collection** (`ProducerWaits`, package 2): every wait under its own identity, a replacement in place, resolution of one leaving the others, status derived from what is left; `requestsAwaitingAnAnswer` is the ordered list and `MonitoredSession.requests` carries it, so `MonitorStore.openRequest` pins the one being read and `answerLanded` opens the next on the same row |
| `MonitorSnapshot`, `MonitorStore` | **Built.** `MonitoredSession.request` reaches the UI on the one data contract, and `renderedProjection()` carries the request's id and form — never its body, so a 54 KiB plan is not string-compared per event. The answering half is `openRowID`, `answerGround`, `isAnswerInFlight`, `isAffirmativeArmed`, `answerNotices` and `answerRevision` — and `answerProgress`, which is **not published**: it holds the draft and the part-answered set, the field writes into it on every keystroke, and publishing it would re-render a panel that measures text on every pass (`AGENTS.md` §7). What SwiftUI is told is where the ground is, which moves at most once a row. ~~`openRowID` beside `quotaExpanded` and `recentExpanded`~~ is struck: §10 says text and part-answered sets live for the row's lifetime and `artifacts.md` says no hook payload reaches disk, so none of it is persisted |
| `PanelMetrics` | New: `requestBodyMaximumHeight = 140`, `openRowHeight(bodyHeight:)`, `questionBodyMaximumHeight = 300` and content-measured option heights, `answerRowHeight = 28`. `openRowHeight(requestLines:)` from [`expanded-panel-v2.md`](expanded-panel-v2.md) §10 is not introduced — it counted lines, and §4.1 does not |
| `NotchOverlayView` | **Built**, and the mark **redrawn 2026-09-06** (§3.3): `SessionStatusControl` draws one verb on a chip in `NotchPalette.brightGround` — ~~hugging~~ at one width for all three verbs, and cut, padded, sized and set exactly like `AnswerControl` — deepening in the same hue with a `PointingHandCursor` over it while the pointer is on the mark rather than on the row. ~~the status name on a ground sized once for every word it can hold, with its own hover so `Answer` / `Read` answers for the mark~~ — and the layer-backed readout both of them replaced took a redraw a second with it. The mark is the second target, and `OpenRow` draws the head unmoved, the chevron where the mark was, the body in both settings, `OptionRow`, and §11 rule 04's single control with no white ground anywhere. The body scrolls on the wheel, draws the rail and the count, and fades at the fold. `AnswerRow` draws §7's three objects, `AnswerControl` is one answer with its own hit region and the ground drawn on it, `OptionRow` takes a click and a tick, and `AnswerField` is the `NSViewRepresentable` over `AnswerFieldView` §13.2 requires — which owns its own text and its own placeholder, because a keystroke must not reach `@Published` |
| `PanelMetrics` | **Built.** ~~`waitingMarkWidth` retired with the reservation (§3.3)~~ — **back, and derived**: it is the widest of `waitingMarkWords`, so a fourth verb cannot outgrow it, and ~~`drawnWaitingMarkWidth(_:)`~~ is `huggedWaitingMarkWidth(_:)`, the measurement the maximum is taken over rather than what any chip draws. With it, `waitingMarkWord(for:canBeAnswered:)` and the three words it chooses between, `waitingMarkFont` (`13` pt Light, shared with `requestControlFont`), `waitingMarkHeight` ~~`= 32`~~ `= answerRowHeight`, `waitingMarkCornerRadius` ~~`= 8`~~ `= controlCornerRadius`, `waitingMarkPadding = controlHorizontalPadding = 12`; `requestBodyMaximumHeight` ~~`= 140`~~ `= sessionViewportCap − openRowFixedHeight`, `openRowFixedHeight` ~~`= 100`~~ `= 92` (§4.1, 2026-09-08), `openRowHeight(bodyHeight:)`, `questionBodyMaximumHeight = 300` and content-measured option heights, `answerRowHeight = 28`, and the two settings' fonts and insets |
| `RequestBodyLayout` | **Built**, and not in the original plan. One request's body laid out once, at the width it will be drawn at — **the panel's height and the row's drawing come from the same value**, which is what makes §4.4's count of what is below the fold true rather than approximately true. §4.5's wrapping is done here rather than by the text system for the same reason: measuring and drawing the same array of lines makes disagreement impossible rather than unlikely |
| `OverlayPanelController` | **Built, and corrected by measurement.** `OverlayPanel.latches` gates `canBecomeKey`, so the panel takes the keyboard when a row opens and gives it back on `⎋`, on a click outside and when the row closes. ~~`.nonactivatingPanel` is what lets it hold a key without bringing an `LSUIElement` app to the foreground~~ is struck: it holds key status without activating and the keyboard still goes elsewhere, so the app activates for the row's lifetime and hands the previous application back — §9.4 and [ADR 0020](adr/0020-the-panel-takes-the-keyboard-by-activating.md). `becomesKeyOnlyIfNeeded` went with it, because it makes AppKit refuse `makeKeyAndOrderFront` outright and the gate on `canBecomeKey` already does its job. Hover is suspended for the duration in the store rather than the controller, because that is where the dwell lives. ~~The chord's registration and its failure reporting are stage 03 and are not in the initial version~~ — **there is no registration**: §9.3 is declined and this app claims no global hotkey |
| `AgentHookHelper` | **Built.** One literal argument selects the wait — bare keeps `nc -w 1` with stdout discarded at the call, `wait` opens the reply channel on a window the definition registers. `exec >/dev/null 2>&1` became `exec 2>/dev/null`, and never `exec /usr/bin/nc`: that would hand the product `nc`'s status, measured **1** on both shapes of "nothing is listening". `NOTCHLINE_HOOKS_OFF` is read before the payload, so a nested agent costs one `sh` and no connection |
| `ManagedHookDefinition`, `ManagedHooksConfiguration` | **Built.** The timeout and the argument moved onto the *definition*, and `handler(for:)` builds one handler per definition — so a definition that varies nothing produces the bytes it always produced, which is the whole of ADR 0014's blast radius. `isCurrentManagedHandler` is asked per definition for the same reason |
| `HookInstallRecord.eventsAwaitingTrust` | **Built**, and not in the original plan. The app's own memory of a definition it rewrote, recorded at the install that changed the bytes and cleared one event at a time as those events arrive. It is the second trigger for `restoreDefinitionAdvice`, and it exists because the first cannot reach this definition: the silence probe may never watch `PermissionRequest` |
| `HookEventRepository`, again | **Corrected 2026-09-06, by the first real question ever answered from the notch.** An `AskUserQuestion` raises two events for one call — the `PreToolUse` that opens the *input* wait and the `PermissionRequest` ~25 ms later that carries the connection — and the ticket was filed on the approval slot alone. The status is `Input needed` (`transitioned(on:)` gives approval to input on purpose) and `requestAwaitingAnAnswer` follows the status, so the row drew the question in full, `Store · 1/1`, options, descriptions and all, and offered `Answer in Claude Code` over a request it was holding a connection for. The connection belongs to the **call**, not to the slot it opened: where the borrowed approval's id is the input wait's own id, that wait's request is re-filed on this event's connection. Keyed on the id, which is what makes it safe — an approval about some *other* call carries its connection to that call and never to this one. Every test that came before built an `AgentRequest` with a ticket already on it, which is why only a real session could find it |
| `renderedProjection()`, again | **Corrected in the same change.** Its premise — one `tool_use_id` never carries two requests, so the id and the form say everything a redraw needs — is true of the *body* and false of the answer: a request becomes answerable inside one wait, when the `PermissionRequest` lands. So answerability is a third term. Still never the body: a 54 KiB plan is not string-compared per event |
| `AgentHookListener`, `HookReplyRegistry` | **Built**, and the shape changed from the plan. The listener hands the descriptor to ``deliver`` and closes it only if nobody took it, so the decision "is this a connection an answer travels on" is made where the payload is — and the *waiting* happens nowhere near the serial read queue whose serialness preserves arrival order. The registry is **reconciled** after every drain rather than released at each of the seven sites that clear a wait: a rule that holds until one site forgets it is exactly CR-030. It also holds the request's `tool_input`, so the bytes needed to answer a question live for exactly as long as the connection and never reach the snapshot |
| `AgentRequest.canBeAnswered` | **Built**, and no longer a stored flag: it is `answerHandle != nil` (the field was `replyTicket`, a `HookReplyRegistry.Ticket`, until 2026-09-11; the handle wraps the same ticket and hides the transport from the domain). A request is answerable when a connection is being held for it and at no other time — not because its product could accept an answer in principle, and not because its status says `Approval needed` |
| `RequestAnswering`, one provider per product | **Built.** `AgentAnswer` is `grant`, `refuse(String?)` and `answers([AgentQuestionAnswer])`; Codex returns `nil` for the third, because `updatedInput` there does not fail to answer but fails the hook **closed**. `interrupt` is never written by either. `AnswerGround`, `AnswerProgress` and `AnswerNotice` live beside them: the ground is *derived from what has been typed* rather than stored beside it, so the drawing and the return key cannot disagree — which is §6.1's *the ground is the state* taken literally, and the arrows (§9.3) are what will make it a value somebody sets |
| `AnswerOutcome`, `AnswerHandle`, `AnswerDelivering` | **Built 2026-09-12** (package 4). `AnswerDelivering.answer(_:on:)` is the one answer channel contract and returns an `AnswerOutcome` — `accepted`, `sent`, `expired(peerGone | timedOut | notHeld)`, `rejected(reason)`, `unsupportedOperation`, `uncertain` — each claiming only what the channel proved; the Hooks channel's best is `sent`. `AnswerHandle` is opaque and scoped to its issuer: the registry names itself on every handle it mints, so a number another channel counted to addresses nothing here, and a spent handle answers `expired(.notHeld)`. `HookReplyRegistry` reports a write that took nothing as `peerGone` and one that took part as `uncertain`, and holds each connection's own window (`answerWindowSeconds` from arrival): past it the refresh withdraws the handle and the request stays, readable, saying `Read` — the window is booked as a refresh deadline and consumed by the refresh that withdraws it. `MonitorStore` spends each handle once (`spentAnswerHandles`), says state 03's sentence for the outcome it got, and ignores a result for a request the row no longer holds |
| `AnswerOperations`, `AgentQuestionAnswer`, `AgentQuestion` | **Built 2026-09-12** (package 3). A request carries what its held connection was declared to accept — grant, refuse, refuse with words, answer its questions — declared by the vocabulary beside the connection, carried on the evidence, filed on the request and kept on the ticket; `canBeAnswered` needs the handle **and** a form those operations answer, `answerRow` draws only the answers permitted (no refusal, no field, where none is), the store sends only what is permitted and the registry writes only what is permitted. A question carries its own constraints: `acceptsFreeText`, `acceptsNote`, `nativeID`. The answer is typed — the question as asked, the chosen positions in the product's order, or the words — and `ClaudeCodeRequestAnswering.spelling(of:)` is where the `, ` join now lives (§5.4). `AnswerProgress` keys its drafts by `AgentRequest.asked`, the request stripped of its connection, so the same id wearing another body starts empty |
| `MonitorStore.takeNumberedOption(_:)`, ~~`AnswerFieldView.onDigit`~~ | **Built 2026-09-06**, and it is the whole of what §9.3 left behind. ~~The field offers a bare `1`–`4` to the store and types it when the store declines, and the store declines unless this is a single-choice question with an empty field.~~ **Rewired 2026-09-07** (§9.2): the digit never passes through the field at all. It reaches `OverlayPanel.keyDown` because nothing inside the window took it, and both conditions went with the rewiring — the emptiness one had nothing left to protect, and the single-choice one existed only so a `multiSelect` field could type digits. A digit selects exactly as a click does, without submitting, so a numbered option and a clicked one cannot mean two things |
| `AnswerProgress`, `MonitorStore.goBackAQuestion()` | **Built 2026-09-07** (§5.7). The three drafts became `AnswerProgress.Draft`, held **per question** rather than per row, and `answers: [Int: AgentQuestionAnswer]` went away with the clearing that made it necessary: an answer is now read out of its question's draft at the moment the set leaves, by the single `answer(to:from:)` that also decides whether a question may be left at all. So the gate on leaving and the value that finally goes back cannot disagree, which is what keeps a set that walks backwards from sending a short one. `canGoBackAQuestion` / `canGoForwardAQuestion` and `drawQuestion(_:)` move the index and nothing else — no clearing, no recording, and no re-arming, because §6.3 arms a ground against an arrival nobody asked for and this is one that was asked for. `AnswerControl` gained `waitsForArrival` for the same reason and `spoken` for §13.3 |
| ~~`AnswerField.onQuestionStep`~~ `PanelKey`, `OverlayPanel.handleKey`, `MonitorStore.takeKey(_:)` | **Built 2026-09-07, and rebuilt the same day.** ~~`moveLeft:` and `moveRight:` are offered to the store from `textView(_:doCommandBy:)`, and the store declines unless the field is empty.~~ Both of the field's outlets to the panel are gone with the always-on caret that justified them (§6.6). `OverlayPanel.keyDown` sees a key only when nothing inside the window took one, which *is* the focus condition — no gate to write, and none to forget. `OverlayPanelController.panelKey(for:)` decodes the `NSEvent` and nothing else: bare only, `⏎` / `1`–`4` / `←` / `→`, and `MonitorStore.takeKey(_:)` is where each means something, which is what lets the whole keyboard be asked about without an `NSEvent`. The other half is `OverlayPanel.sendEvent(_:)`, which takes the caret out of the field on a press that lands anywhere else — the field is the one view that cannot see that, and the window is the one that sees every press |
| `AnswerFieldBox`, `PanelMetrics.answerFieldLineCount`, `MonitorStore.answerFieldHeight` | **Built 2026-09-15** (§7.1). The representable now hosts `AnswerFieldBox`: it draws the ground and the rail, and holds a scroller with no bars whose clip sits inside the vertical inset, with the `AnswerFieldView` as its document. The text view is TextKit 1 (`init(usingTextLayoutManager: false)`) and wraps at `MonitorStore.answerFieldTextWidth`, not at its own width. `answerDraftChanged` bumps `answerRevision` when `answerFieldLineCount` changes, and that publisher was already in `frameChangingPublishers`. A wheel over a field that fits goes on to the list |
| `AnswerFieldView`, again | **Corrected 2026-09-07.** `viewDidMoveToWindow` and a `didBecomeKeyNotification` observer made it first responder and put it back whenever the panel became key; both are gone, and with them the blinking caret over a row nobody was writing in. It draws its own ground now (§7) — the row's quiet button wash under the pointer, deepened and edged while it holds the caret — because the caret was the other half of the answer to *is this a field*. `isSuperseded` dims its text while an option is ticked (§5.4), which is the announcement the option markers used to make in the other direction |
| `AnswerDelivering.answer(_:on:)` | **Built**, and not in the original plan. One method, on a contract of its own since 2026-09-11 (`tiered-support.md` §5.2): a product whose requests cannot be answered from the notch does not conform, and the store reads a missing conformance as *not delivered* — so a store with no services, a drawing specimen and a test double all answer truthfully rather than needing a stub. The store names the handle and the product; which bytes that becomes is the vocabulary's business and which connection they travel down is the registry's, and neither is the surface's |


## Generalisation conformance follow-up (2026-09-12)

The reading-only ground now retains the return-to-product control and adds quiet `Back` and `Next` controls where a question exists in that direction. Arrow keys browse the same questions; Return still sends nothing. This supersedes §11's single-control restriction, which left every question after the first unreachable. Answerable sets keep §5's validation and submission behaviour.

A row holding several requests draws a 24 pt navigation strip below its Thread title, separated by the existing row spacing. Previous/next controls and `Request n of m` expose the complete collection. The selection remains pinned across arrivals until explicitly changed or resolved. Switching preserves each live request's drafts and question position and rearms any newly displayed affirmative; it is disabled during submission. Request occurrences distinguish producers, observation epochs, native revisions and reuse of an ID. Late outcomes cannot annotate a replacement or clear its draft.

## Trae reading-only forms

Trae 3.5.91 local IDE contributes ordinary manual `RunCommand` approvals and `AskUserQuestion` sets at L5. The shared opened row renders the complete command plus supplied ordinary arguments, or each ordered question with its labels and descriptions. A question’s native Others field and optional additional-information question remain visible. `AgentQuestion.readingHint` carries the boundary-projected single/multiple-choice instruction, optionality and 500/1000-character custom-text limit. The hint participates in the same text measurement as the question, so drawing and reserved height agree.

Question arrows and request browsing work without an answer handle. No approve, refuse or text-submission operation is enabled. Rich permissions and other unknown forms use the existing unsupported form and return action. Plan/Spec, remote, SOLO and child activity are outside admission. See [product coverage](product-support.md) and [native acceptance](trae-integration.md).

## Local Codex CLI request scope (2026-09-15)

The local CLI uses the existing request boundary and the reading-only form. ~~Ordinary `PermissionRequest` grants/refusals travel over the held native Hook connection~~ — **revised on this branch on 2026-09-15**: they do not, because Codex waits for the Hook rather than asking beside it, and a held connection took the question out of the terminal the person was watching (§14.2). A local TUI's connection is released as soon as its payload is read, its request is read here and answered there, and no answer travels from here at all. Synchronous `request_user_input` is waiting and reading-only. Asynchronous questions, `request_permissions`, automatic-review mode and subagent variants remain unverified as independent CLI coverage in [product support](product-support.md#51-local-codex-cli); Desktop acceptance does not cover them. Exact `Interrupt` clears the observed Turn's waits. Losing an execution withdraws only its owned rows/handles; a competing executor cannot substitute a handle for the same Turn.
