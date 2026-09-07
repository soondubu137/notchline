# Notchline — The panel, whole: three decisions composed

| Field | Value |
| --- | --- |
| Status | **A composition, not a new decision — and two of the three are built.** The badge and the band ([`colour-v2.md`](colour-v2.md)) and the footer ([`quota-footer-v2.md`](quota-footer-v2.md)) were implemented on 2026-09-05, in the order §5 says they can be built in. The answer row ([`answer-in-notch.md`](answer-in-notch.md)) is the one that still waits on the two investigations §5 marks ★. Every rule here is already taken in those three files; what this file adds is the arithmetic of the three together and the five places where their drafts contradict one another — four of which are figures taken before a neighbouring decision landed, and one of which is a genuine disagreement neither document could settle alone. |
| Version | 1.1 |
| Date | 2026-09-05 |
| File | [Notchline V2](https://www.figma.com/design/c3CQBBk3Boiu0oM00Vvs9Y/Notchline-V2?node-id=272-2) — `11 — The panel, whole` |
| Scope | The expanded panel in every state it can reach, and nothing else. Neither collapsed form is touched: none of the three decisions reaches the bar or the pill, and [`compact-view-v2.md`](compact-view-v2.md) stands whole. |
| Answered since | All six of §5, by the board's owner on 2026-09-05 from Figma page `11` §07. One of them changes what is drawn: **there is no critical threshold**, so the footer has no speaking form and the panel's `333` row is void ([`quota-footer-v2.md`](quota-footer-v2.md) §4). The other five settle without moving a figure — §5 carries each. |
| Supersedes | Nothing outright. It **corrects** [`quota-footer-v2.md`](quota-footer-v2.md) §6's two height tables, [`answer-in-notch.md`](answer-in-notch.md) §12's panel column, and [`figma-design.md`](figma-design.md) §4.7's treatment of the waiting reading; and it settles the separator that Figma pages 09 and 10 draw differently. All five are §3. |

## 1. The three decisions are one decision

| The page | What it took off the panel | What was already saying it |
| --- | --- | --- |
| `08 — The footer without a gauge` | A `496 × 3` rule for every quota window, drawn whether or not anything was close | The percentage its own caption printed exactly, two points to its right |
| `09 — Identity without a palette` | A hue per product, and the band's column of sessions and subagents per agent | The product's own name on the caption line the hue was tinting — and, `46` below the band, one row per session naming its agent in words |
| `10 — The answer` | The eleven-step journey from a request arriving to a person answering it | Nothing. This is the one that adds a job rather than removing a duplicate — and it adds it to an object the panel already draws on exactly the two states with something to answer |

Three rules follow, and they are the whole of what the composed surface is:

1. **Brightness is the only channel left, and it means one thing.** Hue said which product; a bar's length said how much of a window was left; a white ground said a person was wanted. Two of those are gone and the third has been given the extra job of being the control that answers. Every value on this surface brighter than the values around it is brighter for the same reason. *That ground is `#DEE8E0` rather than `#FFFFFF` since 2026-09-06 (§3.5) — still one channel, still one meaning, and white freed for the pointer.*
2. **Nothing is drawn while it has nothing to say.** The band and the footer were the two surfaces exempt from a rule the rest of the panel already kept — one drew a column per agent whatever it held, the other drew four numbers every time the panel opened. Both now keep it, and so does the open row: where there is no write path the affirmative is **absent rather than greyed out**, because a disabled control is a promise made quietly ([`answer-in-notch.md`](answer-in-notch.md) §11 rule 03).
3. **Every one of the three re-uses an object already on the panel.** The badge is the finished reading's chip, at its corner, in the mark's ink. The footer's table is `FooterRule` drawn as the two-level thing it already was. The answer row is the waiting ground grown `16 → 28`, with the quota block's own chevron standing where it sat. **No new constant is introduced by any of the three**, which is why they compose rather than merely coexist.

## 2. The panel, region by region

```
46   band       the aggregate mark, the two totals, the gear.  Leading side 53.8 at every agent count
240  viewport   at most three live rows at 80; an open question may grow it to 400
22   footer     today's spend, and the control
```

- **A row's caption is the badge and then the Project** — no separator (§3.4). The caption line is `16` whether or not a badge is in it, so nothing on a row moves at the moment a second product connects. The badge itself is drawn on `showsProductAttribution`: presence, not "who has threads right now".
- **The reading is one slot in three outlines**: bright ground on a waiting row, bare on a running one, the dark chip on a finished one holding how long the Turn took. The badge is that same chip in the theme ink. *Since §3.5's redraw the waiting outline is not a reading at all but a `32` pt control carrying a verb; the slot is still one slot, and it is the one that is twice as tall.*
- **The theme ink has three readers**: the mark, the badge, and — since [`answer-in-notch.md`](answer-in-notch.md) §5.5 — the `12 × 12` tick box on a question that accepts more than one answer. That box is the only coloured object anywhere inside an open row; everything else in there is white, `#C7C7CC`, `#7C7C80` or `#242424`.
- **The footer draws one number, and then only what somebody opened.** ~~grows one line when a window crosses `15%` with more than `15%` of its time left~~ is void ([`quota-footer-v2.md`](quota-footer-v2.md) §4): there is no threshold, nothing is drawn differently for being low, and the two-level table is reached by the control alone. A field this app cannot read draws `--` in its own place and is marked in no other way.

## 3. The five corrections

### 3.1 Page 10's panel heights were taken with the pre-V2 footer

[`answer-in-notch.md`](answer-in-notch.md) §12 computes `279` / `332` / `370` from a footer of `84` — [`dual-agent-design.md`](dual-agent-design.md)'s two-product figure. [`quota-footer-v2.md`](quota-footer-v2.md) had already replaced that footer with `22` at every product count.

**Recomputed on the V2 footer the three are `217` / `270` / `308`**, and every open-row panel figure in that table falls by exactly `62`. The viewport cap does not move — an open row at its maximum is still the viewport — so what changed is the floor under it. §4 carries the corrected series.

### 3.2 The quota table's own heights were taken before the badge

[`quota-footer-v2.md`](quota-footer-v2.md) §2 says a caption line carrying a badge is the badge's own `16` rather than `footerCaptionHeight`'s `14`, and gives `19W + 30P + 17` with a spoken line of `47`. Its §6 tables, and Figma page 08's §05, still carry `19W + 28P + 17` and `45`.

**The note is right and the tables are stale.** ~~`45 → 47`~~, `64 → 66`, `83 → 85`, `130 → 134`, `177 → 183`, `215 → 221`, with the panel figures following. No constant is introduced: the `16` is the badge height the `Badge` option already defined.

**The first of those corrections was overtaken before it was applied.** The spoken line was removed entirely on 2026-09-05 ([`quota-footer-v2.md`](quota-footer-v2.md) §4), so `45` and `47` are both void and this correction now covers the table's five figures alone. It is recorded rather than dropped because it is what settled the disagreement, and because the same `16` is what makes the table's `30P` right.

> **And the whole of it is reversed on 2026-09-06** ([`quota-footer-v2.md`](quota-footer-v2.md) §12.1). The badge came off the footer's outer row, so a product line is `footerCaptionHeight`'s `14` again and the table is `19W + 28P + 33` — the arithmetic §6's tables carried all along. The correction stands as the record of a disagreement that was real while the badge was there; the tables it corrected were right for a reason nobody had yet, which is worth leaving visible.

### 3.3 Figma page 09 draws a grey chip and keeps `Name and colour` as the default

The page argues that the badge is the one presentation of four that still answers when the hue is taken away, and proposes it as an option among four, in `#242424` / `#C7C7CC`. [`colour-v2.md`](colour-v2.md) §4 makes it the **only** presentation, in the theme ink's own pair.

The decision is later and went further on both counts, and says so itself. **Page 09 stays as the argument that produced it; page 11 §02 is the drawing.** This answers [`colour-v2.md`](colour-v2.md) §10 question 05.

### 3.4 The separator between the chip and the Project

Figma page 09 draws `[Codex] notchline`; page 10 draws `[Codex] · notchline`, carrying the dot over from the `Codex ·` prefix the badge replaced.

**No dot.** [`colour-v2.md`](colour-v2.md) §5 says *the badge, then the Project* — the whole prefix is what the chip replaces. The dot divided two words inside one grey run and there is no longer a run to divide; a boundary after a boundary is a mark doing nothing. The `6` between chip and Project is the badge's own padding, so nothing is measured that was not measured before.

### 3.5 What the bright ground on a waiting row says

[`figma-design.md`](figma-design.md) §4.7 puts the reading — a duration — on the white ground, and Figma page 06 draws `0:42` there. [`answer-in-notch.md`](answer-in-notch.md) §3.3 says the mark says `Approval needed` or `Input needed`, and page 10 draws that.

~~**The name, and it is the composition that decides it rather than either document.**~~ **The act, since 2026-09-06** — `Approve`, `Answer`, or `Read` where neither is available — and the composition still decides it, by the same argument turned round. §3.3 held that the ground **does not resize** when the word inside it becomes `Answer` under the pointer, so the ground was sized for the longest name it could say; with the word settled at rest there is nothing to reserve against and the chip hugs one verb, `77` at its widest against the reservation's `113`. **What is unchanged is the conclusion this section exists for**: neither the name nor the act is a duration, so the duration keeps the place it already had — the finished row's dark ground, the one object on this panel that reports how long a Turn took. It is safer than it was, because the mark is now `32` tall against that reading's `16` and the two could not be confused for one slot even if something tried.

**And the ground is the app's ink rather than white.** `NotchPalette.brightGround` — `themeInk`'s lit `#DEE8E0` — wherever this panel fills a bright ground: the mark, the subagent badge, and the ground `⏎` sits on inside an open row. §1's *a white ground said a person was wanted* is now *the app's own ink says it*, which costs the argument nothing and gains it the thing the rule was really after: the brightest value on the surface is spent on one state rather than on two, and request controls deepen that same hue under the pointer instead of filling white ([`answer-in-notch.md`](answer-in-notch.md) §3.3).

## 4. How big it is

```
panel  =  46  +  viewport (normally at most 240; 400 for an open question)  +  footer            width  =  520
```

Two of the three terms cannot move at all, and the third moves only between `0` and its cap.

| The state | Band | Viewport | Footer | Panel | What it was, and where |
| --- | --- | --- | --- | --- | --- |
| At rest — Codex alone, one working agent | 46 | 240 | 22 | **308** | `316` — [`figma-design.md`](figma-design.md) §4.5 |
| At rest — Claude Code alone, two windows | 46 | 240 | 22 | **308** | `339` — the footer grew with the windows |
| At rest — both products, four working agents | 46 | 240 | 22 | **308** | `370`, and `536` wide |
| At rest — three products, eight working agents | 46 | 240 | 22 | **308** | `401`, and `649` wide |
| ~~A window past the threshold speaks~~ | ~~46~~ | ~~240~~ | ~~47~~ | ~~**333**~~ | void — [`quota-footer-v2.md`](quota-footer-v2.md) §4 |
| One waiting row, opened at one prose line | 46 | 149 | 22 | **217** | `279` — §3.1 |
| One waiting row, opened at three lines | 46 | 202 | 22 | **270** | `332` — §3.1 |
| One approval or plan, opened at the body's cap | 46 | 240 | 22 | **308** | `370` — §3.1 |
| The quota table opened, two products, three windows | 46 | 240 | 134 | **420** | `416` — §3.2 |
| The quota table opened, three products, six windows | 46 | 240 | 221 | **507** | `501` — §3.2 |

**The width series is one number.** At a `220 × 38` cut-out the panel was `520` up to four working agents and then `532` / `571` / `610` / `649`; the band's leading side ran `53.8 → 213.4` across the same range. The band was the only term that read an agent count, and holding it at `53.8` removes the count from the width entirely.

Three consequences:

- **Two of those nine figures are the user's own doing and the other seven are not.** Opening the quota table takes the panel to `420` or `507`, on a control that is always drawn. Everything else is `308` or below, whatever is connected, whatever is running, and whatever the machine's cut-out measures.
- **The cap has not moved; the floor under it has.** `308` is still reached by three live rows or by one request opened at the body's cap — not by owning a second product.
- ~~**A limit speaking is the one state neither the user nor the machine chose.** It costs `25`, once, at any product and window count, and it arrives as a line that was not there a moment ago.~~ **Void, and it makes the bullet above absolute.** With the threshold removed, the *only* thing that takes this panel past `308` is the user opening the quota table. Nothing the machine observes — no share, no reset, no unreadable reading — changes its height at all.

Approval detail refinement (2026-09-07): the body retains labelled argument fields with separate prose and code treatments ([`answer-in-notch.md`](answer-in-notch.md) §4.2). Its measured content includes labels and spacing but is still capped at `140` pt; the open row remains capped at `240` pt. The header, queue and footer dimensions are unchanged.

Question refinement (2026-09-07): the body may reach `300` pt and the row `400` pt, with the same fixed `100` pt heading/footer composition. The live viewport is capped at `max(240, openRowHeight)`, so the Send row remains visible. The height table above describes closed rows and approval/plan bodies; at its question cap the reference panel is `46 + 400 + 22 = 468` pt before any Recent section. Option cards wrap titles and independently expand long descriptions; both selection modes use the same permanent answer field and Send ([`answer-in-notch.md`](answer-in-notch.md) §5).


## 5. What still gates this

Nothing new, and as of 2026-09-05 nothing undecided either. All six were put to the board's owner from Figma page `11` §07 and came back settled; the two marked **★** are settled *as investigations*, which is what they always were — neither is a drawing question, and both are answered by measuring something rather than by choosing something.

| | Question | Recorded in | Where it stands |
| --- | --- | --- | --- |
| 01 | Is the badge's lit text too loud on a real list? | [`colour-v2.md`](colour-v2.md) §10 q01 | **Build it as designed.** The lit value ships and is judged on the running app; the caption-lightness fallback stays recorded and untaken |
| 02 | Is `15%` right on both sides of the speaking rule? | [`quota-footer-v2.md`](quota-footer-v2.md) §8.5 q03 | **Void with its subject — there is no critical threshold.** The concept is removed rather than re-tuned, and this is the one answer that changes what is drawn: §2, §4 and §6 all move |
| 03 | How does a user learn that quota is unreadable? | [`quota-footer-v2.md`](quota-footer-v2.md) §8.5 q01 | **The field says so itself.** `-- today`, `-- left`, `--` — the unreadable field is replaced in its own place, with its unit if it has one, and marked in no other way |
| 04 ★ | Will this app keep the `tool_input` it is already sent? | [`answer-in-notch.md`](answer-in-notch.md) §15 q02 | **Answered — yes, and built 2026-09-05.** Carrying it costs 0.18% of tool calls rather than all of them, because the gate is the events that open a wait rather than `PreToolUse`. Two of §14.1's own clauses were wrong and are struck there |
| 05 ★ | Will either product accept an answer from outside it? | [`answer-in-notch.md`](answer-in-notch.md) §15 q01 | **Answered — yes**, measured 2026-09-05 from both products' shipped binaries. Both take an approval decision on the hook's own stdout; Claude Code also takes a question's answers through `updatedInput`, which Codex reserves. The answering half is unblocked, with §5 built on one product and read on the other ([`answer-in-notch.md`](answer-in-notch.md) §14.2) |
| 06 | Which chord, and what happens when it is taken? | [`answer-in-notch.md`](answer-in-notch.md) §15 q03 | ~~**`⌥Space`, as recommended** — user-settable, registered so a clash fails at registration, with the settings row showing the chord actually held. **Since answered, and deferred**: the answering experience ships pointer-first, and the chord with the rest of the keyboard.~~ **Closed on 2026-09-06 by the same owner: there is no chord**, and the question is neither open nor deferred — this app registers no global hotkey and offers no setting for one, so there is no clash to report and no settings row to draw it in ([`answer-in-notch.md`](answer-in-notch.md) §9.3, §15 q03). The recommendation is kept struck in case it is ever reopened, and nothing on this page moves either way |

**Five of the six close without moving a figure on this page.** Question 02 is the exception, and it takes something off rather than adding it: the footer loses its second closed height, so the composed panel is `308` in every state the user did not open.

So the three were built in the order they were argued: the badge and the band, then the footer, then the field this app already receives and throws away — and **all three closed free of open questions**. The third landed whole on 2026-09-05: the app keeps the request, the reducer holds it on the wait that asked, it reaches `MonitorSnapshot`, and the open row draws it and answers it where the product allows ([`answer-in-notch.md`](answer-in-notch.md) §17). ~~Nothing draws it yet, which is why §6's two boxes below are still unticked.~~ Both boxes are ticked below, and the second of them is what the `multiSelect` tick box closed.

## 6. Verification

These are the checks that span more than one of the three; each document keeps its own. All of them were checked on 2026-09-05, on the running app and in `NotchlineTests.swift` — the last two with the open row, which is now built ([`answer-in-notch.md`](answer-in-notch.md) §17).

- [x] The panel is `520 × 308` with three live rows, at every cut-out, every working-agent count and every connected-product count, and no width or height term reads either count.
- [x] **Opening the quota table is the only thing that takes the panel past `308`**, full stop: sweep every window's share across its whole range, make every reading unavailable, and the panel does not move. ~~other than a window crossing the threshold, which takes it to `333`~~ is void (§5 q02).
- [x] A row's caption draws the badge and then the Project, with no separator between them, and the caption line measures `16` with a badge and without one.
- [x] The theme ink reaches the mark, the badge and the `multiSelect` tick box, and those three change together when the `Theme colour` selection changes. Built 2026-09-05: the box is `NotchPalette.badgeInk(store.aggregateInk).on`, which is the accessor the badge already reads and the same pair the mark reads, so the three cannot drift; a ticked box was seen in the theme ink on the running app.
- [x] ~~A waiting row's white ground is sized for `Approval needed` / `Input needed` and does not resize when the word inside it becomes `Answer` or `Read`. Built 2026-09-05: `PanelMetrics.waitingMarkWidth` is measured once against all four words, and the word says `Read` on every row until §14.2's write path exists.~~ **Redrawn 2026-09-06** (§3.5): the ground hugs one verb decided at rest, so it cannot resize under a pointer that changes nothing. `PanelMetrics.waitingMarkWord(for:canBeAnswered:)` is what the two new assertions pin, and the reservation is gone.
- [x] A finished row's dark ground is the only place on the panel that reports how long a Turn took.
- [x] With every colour rendered as flat grey, no figure, name or state on the expanded panel becomes ambiguous.
- [x] An unreadable quota field draws `--` and nothing anywhere else on the panel — band, mark, rows or footer control — reports it.
