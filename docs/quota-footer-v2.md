# Notchline — Quota footer V2

| Field | Value |
| --- | --- |
| Status | **Designed, and implemented on 2026-09-05.** Nothing here needed a capability the app lacked: the data model was already a list of products each holding a list of windows (`MonitorStore.footerRules`), and only the layout was written for two. §11 records what each symbol became. |
| Version | 3.4 |
| Date | 2026-09-05 |
| File | [Notchline V2](https://www.figma.com/design/c3CQBBk3Boiu0oM00Vvs9Y/Notchline-V2) — `08 — The footer without a gauge`. `07 — The quota footer (superseded)` is kept as the record of the direction this one leaves (§9). `11 — The panel, whole` draws this footer composed with the other two V2 decisions — see [`panel-v2.md`](panel-v2.md). |
| Scope | The expanded panel's footer only: the quota rules and today's tokens. The band is [`expanded-header-v2.md`](expanded-header-v2.md), the session list is [`expanded-panel-v2.md`](expanded-panel-v2.md), both collapsed forms are [`compact-view-v2.md`](compact-view-v2.md). None is touched, and the panel's width does not move. |
| Supersedes | [`dual-agent-design.md`](dual-agent-design.md) §5.1 (structure and the four heights), §5.2 (which windows are drawn), §5.4 (the fold, its default and its trap). |
| Answered since | §8.5 questions 01 and 03, by the board's owner on 2026-09-05, from Figma page `11` §07. **There is no critical threshold and the concept is removed rather than re-tuned**, so §4 is void and no window speaks. **A field this app cannot read draws `--` in its own place** and is marked in no other way — §8.3, which is what the void threshold leaves behind. |
| Overruled since | 3.3 kept tightest-first ordering inside a product and said so in §4. **The board's owner overruled that the same day: the order is fixed, and it is the order the product reports.** §5 is the rule, and it deletes work rather than adding it — `footerRules` already preserves the reader's order, so nothing is sorted anywhere. |
| Superseded in | §2's ~~two heights~~ one height, by [`colour-v2.md`](colour-v2.md) §5 — the product name is a badge, so the table is `19W + 30P + 17`; the second of the two was the spoken line's `47`, and 3.3 removed the line under it (§4). §6's two tables were written before that and are corrected in place below; [`panel-v2.md`](panel-v2.md) §3.2 records the correction. Nothing else here moves. |

## 1. What V2 changes here, and why

### 1.1 The gauge is redundant with the number beside it

A `496 × 3` rule draws `59%` as a length, and its own caption prints `59%` two points to the right, exactly. The bar is a decoration of a figure it stands next to. Its one real advantage is **pre-attentive comparison** — seeing which of several is shortest without reading — and that is worth nothing in a footer that has already chosen the one that matters, and nothing again in a detail view somebody opened on purpose and is reading.

### 1.2 The footer is a dashboard on a surface that is an attention queue

The mark shows the most urgent thing. Rows appear when they want the user and leave when they stop. A wing with nothing to say is removed rather than left blank; a column with no sessions is not drawn; a zero is never drawn anywhere. **Only the footer draws its subject whether or not it has anything to say** — four numbers, every time the panel opens, on nearly all of which not one of them needs anything. It spends between a fifth and a third of the panel's height saying so.

### 1.3 And it does not survive a third product

Width is split per window: Codex takes the full `496` because it has one, Claude Code is halved because it has two. Thirds are `160`, against a caption of `182` — so `/usage`'s third window was **removed from the design rather than from the product**, and §5.2 wrote the cost down: *a user who exhausts the per-model weekly cap sees two healthy rules and is still refused.* Height grows per product (`30` / `53` / `84` / `115`), and the today line names products in words, running to `340` at three of them against the `496` it has.

**V2 takes the gauge out.** One figure at rest, and a table for anyone who wants to look rather than be told. ~~a sentence when something is~~ is void since 3.3: there is no threshold for anything to cross, and nothing on this surface is drawn differently for being low (§4).

## 2. Composition

> **The product names below become badges** ([`colour-v2.md`](colour-v2.md) §5). This footer is the one surface that already named products in words rather than in colour, so the decision costs it almost nothing — the name moves inside a `16` pt chip in the user's theme ink, and only two heights follow it. ~~The spoken line's `Claude Code ·` and~~ the table's outer-row `Codex` is the one place affected — the spoken line went with the threshold (§4); the window rows, the spend figures, the leader and the control are untouched.
>
> | | Written here | With the badge |
> | --- | --- | --- |
> | ~~Speaking~~ | ~~`45`~~ | ~~**`47`**~~ — void (§4) |
> | Opened table | `19W + 28P + 17` | **`19W + 30P + 17`** |
>
> One term moves and no constant is introduced: a caption line carrying a badge is the badge's own `16` rather than `footerCaptionHeight`'s `14`, so a product group is `16 + 19w`. Collapsed is unchanged at `22` — it names no product, and since 3.3 it is the only form the footer has until somebody opens it.

**Collapsed — `22`, every connected form, every product count, and every share.**

```
12 →  518.7M today                                                  ⌄  ← 508
      ─ 6 ─
```

Today's tokens and the control. Nothing else. **There is no second closed form**: no share, however low, adds a line here (§4).

~~**Speaking — `45`, one line whatever the count.**~~ Void since 3.3. It drew

```
      518.7M today                                                  ⌄
      Claude Code · 5 h · 8% left · 47m
```

and there is no threshold left to put it on the surface (§4).

**Opened — `19W + 28P + 17`**, a two-level table: the product outside, its windows inside.

```
      518.7M today                                                  ⌃
      Codex ─────────────────────────────────────────── 310.1M today
          weekly                     72% left                 3d 12h
      Claude Code ───────────────────────────────────── 208.6M today
          5 h                        59% left                     2h
          7 d                        85% left                  4d 6h
```

| Term | Value | Constant it already is |
| --- | --- | --- |
| The spend line, carrying the control | `16` | `quotaFoldControlSize` |
| Before whatever follows it | `9` | `footerRuleSpacing` |
| ~~The spoken line, and the gap before it~~ | ~~`9 + 14`~~ | void (§4) |
| The leader on an outer row | `1` at 10% white | one step below the panel’s own hairline |
| A table line, and the gap after it | `14 + 5` | `footerCaptionHeight` + `footerCaptionSpacing` |
| Between one product and the next | `14` | `footerCaptionHeight` — one line of air |
| The window column's indent | `12` | `expandedHorizontalPadding`, a second step |
| Below the last line | `6` | `footerBottomMargin` |

A product group is `14 + 19w`, so the table is `31 + Σ(14 + 19w) + 14(P − 1)` = **`19W + 28P + 17`**.

`footerRuleHeight` (`3`) and `footerWindowSpacing` (`8`) retire; the other five do the same jobs in a different shape. **No new measurement is introduced**, and `FooterRule` — one per connected product, holding its windows — survives unchanged, because it *is* the two-level table.

## 3. Collapsed

**One number, and it is the one that is always worth a glance.** Tokens spent today, as a whole, in `#C7C7CC` with `today` in `#7C7C80`. [`dual-agent-design.md`](dual-agent-design.md) §5.4 already picked this figure as the one a folded footer keeps; here it is simply what the footer *is*.

**It is not broken into products on this line.** The word that says whose a number is costs width here and costs nothing in the table, where every figure sits beside its own product's name. So the coloured parts that used to trail this line move to §5's outer rows, and the collapsed footer carries no hue at all.

**Nothing about a limit is drawn here at all.** A wing with nothing to say is removed rather than left blank; a column with no sessions is not drawn; a zero is never drawn anywhere. ~~while nothing is close~~ was the qualification version 3.1 needed and 3.3 does not: there is no *close* on this surface any more (§4).

**What this gives up, stated plainly, and it is now a decision rather than a cost.** Version 3.0 kept a `59% left` figure at the trailing end, which told *nothing is close* apart from *nothing is known*. Version 3.1 dropped it and recorded the loss; **version 3.3 accepts it outright** — the collapsed footer says nothing about any limit, low or high, readable or not (§4).

**What is left to say is only whether a figure could be read at all, and it is said in the figure's own place.** An unreadable today total draws `-- today` where `518.7M today` would have gone, and nothing else on the panel changes. That is the whole of §8.5 question 01's answer, and §8.3 is the rule it generalises to.

## 4. Nothing speaks, and there is no threshold

**Decided by the board's owner on 2026-09-05, answering §8.5 question 03: there is no critical threshold, and the concept is removed rather than re-tuned.** The question asked whether `15%` was the right number on both sides of the speaking rule. Neither side survives it. **No quota figure anywhere on this surface is drawn differently for being low**, and the collapsed footer grows no line for any window at any share.

Every rule this section held is void. They are kept below because all but the first were arguments rather than measurements, and an argument that has been overruled is worth being able to read.

| | What version 3.2 ruled | Where it stands |
| --- | --- | --- |
| 01 | ~~A window speaks when less than a sixth of it is left and more than a sixth of its time is~~ | Void. `15%` was [`figma-design.md`](figma-design.md) §4.3's own critical threshold used twice, and that threshold is now struck at its source too — with the ring's amber and red, and `Usage Indicator`'s Healthy, Warning and Critical variants |
| 02 | ~~It is the only thing the collapsed footer says about a limit~~ | Void, and replaced by something stronger: the collapsed footer says **nothing** about a limit |
| 03 | ~~The line is words, not a gauge~~ | Void with the line. The choice between a bar and a sentence does not arise when neither is drawn |
| 04 | ~~It is drawn one step brighter, and nothing changes hue~~ | Void. Brightness on this footer now separates only the table's three levels (§5), and separates nothing by value |
| 05 | ~~There is one line, never two, and the product that has spent the most today gets it~~ | Void with the line, and it takes §8.5 question 02 with it (§8.5) |
| 06 | ~~Which means the figure above chooses what goes below it~~ | Void. Nothing goes below it |
| 07 | ~~What the one-line rule costs, and where it is paid back~~ | Void, and the debt goes with the rule: no window is selected over another, so none is passed over |
| 08 | ~~Opened, the table replaces the spoken line entirely~~ | Void. The table replaces nothing; it is the only place a share is drawn |

**What this gives up.** A person about to be refused learns it from the product that refuses them, not from this surface. That is a real loss and it is the one this page had been arguing against since §1.2 — but the argument it was making was that the footer should *stop* drawing a dashboard nobody asked for, and an alarm is a dashboard that has chosen its own moment. The table is one click away in every state, on a control that is always drawn (§8.5 question 06), and the share is in it.

**What it buys, and none of it is small.**

- **The footer is one height in every state the user did not open** — `22`, at every product count, every window count and every share. Version 3.2 had two, and the second arrived unbidden.
- **The panel is `308` at rest and `308` while a window is nearly exhausted.** `333` was the only figure in [`panel-v2.md`](panel-v2.md) §4 that neither the user nor the machine chose; it is now unreachable, and that table has nine rows where it had ten.
- **The selection rule and its trade disappear.** Rule 05 put the line on the product with the most spend today, which could put an `11%` ahead of an `8%` and could hand the line to a different product mid-afternoon. Both were defended by the table being one click away, and both simply do not arise.
- **No time-remaining term is needed at all.** Rule 01's second half read `resetsAt` against each window's nominal length. Nothing else on this page wants a nominal length, so the concept leaves the design with the rule.

~~**What is deliberately kept: windows still sort tightest first inside their product (§5).** An order is not an indication — it does not draw anything differently, and it is the only order the inner rows can have that means anything. Removing it would leave the table's one repeated column arranged by nothing.~~

**Overruled the same day, and rightly: the order is fixed, and it is the product's own (§5).** The paragraph above defended a sort on the grounds that an order is not an indication. That is true and it was the wrong question — the objection to sorting by share is not that it indicates something, it is that it **moves**. A share crossing another share would have re-ordered two rows for a reason nobody asked about, which is the re-sorting reference this page has objected to since version 3.0, one level further in. The fixed order is also not arranged by nothing: it is the order each reader already publishes, and it is the same order every other surface in this app sees.

## 5. The table

**Two levels, because the windows belong to products.** Outside, the product and its own spend today. Inside, each of its windows on a line. The outer row is what makes the spend attributable without colour: on the collapsed line those parts had to be coloured numerals, and here each one sits beside its product's own name.

**A faint leader ties each product to its own figure.** `1` pt of white at `10%`, from `8` after the product's name to `8` before its spend, on the caption line's own middle — one step below the white-at-`15%` the panel's structural hairlines use, because it is joining two things rather than dividing anything. It is drawn on **outer rows only**, so having a leader is itself part of what says which level a line is on.

**Three columns inside, one figure outside, and one trailing edge for both.** The window at `24` — one step in from the panel's own `12` — the share right-aligned at `300`, and the timer right-aligned at `508`, which is where the product's spend is right-aligned too. **Indentation and the leader carry the level between them**: no box, rule or divider is drawn.

**`Resets in` is gone, and the column is a timer.** Repeated once a window it was noise, and what the column holds is a countdown — so it is written like every other countdown on this panel: `47m`, `2h`, `3d 12h`, two units at most. The absolute day survives in the accessible name, for anyone who wants Friday rather than four days (§8.5 question 04).

**The levels are three steps of brightness, and ~~hue~~ a badge names the group.** ~~The product in its own lit ink (`#6CB4FF` / `#D97757`)~~ — **the product is a badge** in the `Theme colour` pair ([`colour-v2.md`](colour-v2.md) §5) — its spend in `#C7C7CC`, everything inside it in `#7C7C80`. ~~A share past the threshold is the one thing inside a group that steps back up to `#C7C7CC` — so **every** window that could have spoken is visible here, not only the one that did.~~ Void since 3.3 (§4): **every window inside a group is `#7C7C80`, whatever its share.** The sentence was true and is now trivial — the table is where every window is, so there is no *only the one that did* left to correct.

**Brightness was always doing this work, and now it is doing all of it.** Three steps already separated the product, its spend and its windows; the lit ink only said *which* product, which the name inside the badge says outright. The badge's own ground is darker than the panel, so it adds a step downwards rather than a fourth step up, and the group's brightest thing is still its spend.

**Products in Settings' order; windows in the order the product reports them. Nothing on this table sorts.** ~~windows tightest first inside each~~ and ~~This is deliberately *not* the speaking line's order — that one picks by spend, because it is a selection rather than a list, and a reference that re-sorted itself every minute would be unreadable.~~ are both void: the line went with the threshold (§4), and the sort was overruled on 2026-09-05.

**The reader's order is fixed, published and already the one the rest of the app sees.** `ClaudeCodeUsageReader.windows` is a static pair — `Current session:` as `5 h`, then `Current week (all models):` as `7 d` — and Codex reports a single unlabelled window. `MonitorStore.footerRules` maps `snapshot.quota.windows` straight through, so **this rule is the absence of code rather than any**.

Three things follow, and the third is the one that could not have been got by sorting:

- **[`expanded-header-v2.md`](expanded-header-v2.md) §4.3 rule 02 is restored at both levels rather than one.** *Nothing re-sorts — not by count, not by urgency, not by which agent moved last* was written about the band's columns; the table now keeps it between products **and** inside one. Version 3.0's flat list could hold it at neither.
- **One list has one order.** `Quota.remainingPercent` and `resetsAt` read `windows.first`, so a sort applied in `footerRules` alone would have made the footer's first inner row a different window from the one every single-rule surface calls first. Two orders for one list is a defect waiting to be found, and there is now no place for it to arise.
- **A row that becomes unreadable does not move.** Under a share sort, `-- left` needed a tie-break rule of its own — *unanswerable last* — and a window would have jumped position at the moment its reading failed, which is precisely the extra marking §8.3 refuses. With a fixed order, an unreadable field changes a field. The tie-break rule is deleted along with the sort.

**A product with no limits still gets its row** — an outer row and no inner ones. Its spend is attributed and the absence of lines says there is nothing to report. That is also how a connected product this app does not yet read quota for appears: present and counted, with nothing claimed about it. The current footer has no form for this at all.

**It grows by `19` a window and `28` a product, and by nothing else.** No column widens, no caption shortens, and nothing is dropped for want of room — which is what §5.2 had to do when Claude Code's third window would not fit in a half. That window is now simply a line.

**The control never moves and folding cannot close the panel.** The chevron rides the spend line, which is the footer's first line and is always drawn, so the table opens beneath it. Folding removes rows below a pointer sitting `6` to `22` above the folded bottom edge — inside it — which reverses the trap §5.4 records.

## 6. Heights

| Connected | P | W | Footer today | Collapsed | Opened | Panel today | Panel now |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Codex alone | 1 | 1 | `30` | **22** | `66` | 316 | **308** |
| Claude Code alone | 1 | 2 | `53` | **22** | `85` | 339 | **308** |
| Both products | 2 | 3 | `84` | **22** | `134` | 370 | **308** |
| Three products | 3 | 4 | `115` | **22** | `183` | 401 | **308** |
| Three, six windows | 3 | 6 | `115` | **22** | `221` | 401 | **308** |

> The `Opened` column is `19W + 30P + 17` — §2's badge-carrying form. It read `64` / `83` / `130` / `177` / `215` at `19W + 28P + 17`, which is the arithmetic this page was written with and §2 then corrected; the two disagreed until [`panel-v2.md`](panel-v2.md) §3.2 settled it.

Panel figures are `46 + 240 + footer` — three live rows at the reference menu bar, with the footer collapsed. **Every connected form gets smaller**, the single-product case included.

| Form | Footer | Panel | Caused by |
| --- | --- | --- | --- |
| Collapsed | `22` | 308 | nothing — every connected form |
| ~~A window speaking~~ | ~~`47`~~ | ~~333~~ | void (§4) — no share reaches the closed footer |
| Opened, two products | `134` | 420 | the control |
| Opened, three and six | `221` | 507 | the control |

The table is the only thing here that grows, and it grows because somebody opened it.

## 7. Accessibility

- The collapsed line reads `518.7 million tokens today`, and the control is `Show limits` / `Hide limits`.
- The table is announced as a two-level list: each product with its spend, then its windows. `Codex, 310.1 million tokens today. Weekly, 72% left, resets in 3 days 12 hours.`
- **The absolute reset survives here**: where the column draws `4d 6h`, the accessible name says `resets Friday at 09:00`.
- **A field drawn as `--` reads `unavailable`** — never zero, and never the two characters. That covers the today total, a product's spend, a window's share and a window's timer alike (§8.3).
- The leader is decoration and is not announced.

## 8. What this reaches outside the footer

### 8.1 Two recorded behaviours reverse

§5.4's fold no longer closes the panel (§5 above), and its default inverts: the small form is what the footer **is**, not what it collapses to. `quotaFolded` becomes `quotaExpanded`, default `false` — a rename rather than a flipped boolean, so the change is visible in review.

### 8.2 A recorded risk is fixed for free

§5.2's per-model weekly cap. Its argument — *letting one half report different windows at different times turns a rule meant for a glance into one that must be read first* — was about a **half**, and there are no halves any more. Where the cap sits permanently at 100% for someone who never uses that model, it is simply one more line inside its product, which is where it belongs. ~~it never crosses §4's threshold and never speaks~~ — since 3.3 there is no threshold for any window to cross (§4), which fixes the same risk one step earlier.

### 8.3 One new rule, and it is `--`

~~The `15%` threshold, used on both the share and the time.~~ Void — there is no threshold (§4). What this page adds instead is a fallback, and it is the answer to §8.5 question 01, decided by the board's owner on 2026-09-05.

**A field this app cannot read draws `--` in the place the figure would have had, and is marked in no other way.** No dimming, no icon, no word, no extra line, and nothing appears anywhere else on the panel to announce it. The unit stays, because the unit is not the part that could not be read.

| Field | Readable | Unreadable |
| --- | --- | --- |
| Today's tokens, on the collapsed line | `518.7M today` | `-- today` |
| A product's spend, on an outer row | `310.1M today` | `-- today` |
| A window's share, in the table | `72% left` | `-- left` |
| A window's timer, in the table | `3d 12h` | `--` |

**The timer has no unit to keep**, so its unreadable form is the two characters alone — which is the general rule stated without an exception: replace the field, add nothing.

**Two of the four were already how this app behaved.** `UsageSummaryFormatter` wrote `-- left` and `-- today`. The timer was the one that moved: `resetText` returned `Reset unavailable`, and under this rule it returns `--`. **`Not started` is not covered and stays** — a window that has not begun is a window this app read successfully, and saying `--` for it would be the failure report the current code was written to stop making.

The accessible name says `unavailable` in every one of these cases (§7). `--` is a reading for the eye; a screen reader gets the word.

**`Reset unavailable` is carrying a second job, and it has to keep it.** [`non-public-codex-integration-features.md`](non-public-codex-integration-features.md) lists *a rule with consumed usage showing a percentage but saying `Reset unavailable`* among the signals that Claude Code's `/usage` wording has moved, and [`tech-design.md`](tech-design.md) §13 says that line must go on saying the reading is unavailable. **The signal survives the rename intact**, because it never rested on the words: what distinguishes it is a *consumed* window with no reset, against an unconsumed one at `100% left`, which reads `Not started`. After this change the signal is a percentage beside a `--` timer. **Both documents were amended on 2026-09-05**, in the change that built the footer, exactly as this paragraph said they would be.

**Version 3.1's fallback is rejected, not deferred.** It proposed a single dimmed `--` before the chevron, drawn only while no window anywhere had a share — a marker standing away from the thing it described, in a place no figure had been, and legible only to somebody who knew what its absence meant. It also cost `20` points of width in the state it was for. The rule that landed puts the `--` where the figure was, which needs no width and no explanation.

### 8.4 The Usage Ring was considered and declined

[`figma-design.md`](figma-design.md) §4.3's `18 × 18` ring is the system's other gauge, and swapping one gauge for another does not answer §1.1: a ring still draws as an angle a fraction the figure beside it prints exactly, and it costs `18` points of line where 11 pt text costs `14`. Its colour thresholds are unusable here — amber and red would put a second meaning on hue, which is identity everywhere on this panel. **Since 3.3 they are unusable anywhere**: they are the same critical threshold §4 removed, and [`figma-design.md`](figma-design.md) §4.3 voids them at the source. The ring's `Unavailable` variant, which reads `--`, is the one part of it that survives — as the general rule in §8.3.

### 8.5 Open questions

| | Question | Where it stands |
| --- | --- | --- |
| 01 | How does a user learn that quota is unreadable? | **Answered by the board's owner — the field says so itself.** An unreadable field draws `--` in its own place, with its unit if it has one and no other marking anywhere: `-- today`, `-- left`, `--`. §8.3 is the rule and the four fields it covers. Version 3.1's dimmed `--` before the chevron is rejected rather than deferred — a marker away from the thing it describes, `20` points wide, in a place no figure ever was |
| 02 | ~~Is today's spend the right way to pick which product speaks?~~ | **Moot since 3.3.** It was answered *yes* on 2026-09-04 and the thing it selected for was removed on 2026-09-05: nothing speaks, so nothing is picked (§4). Kept because the two hazards it named — an `11%` drawn ahead of an `8%`, and the line moving product mid-afternoon — are the clearest statement of what a selection rule costs, and are the argument against reintroducing one |
| 03 | Is `15%` right on both sides? | **Answered by the board's owner — the question is void with its subject.** There is no critical threshold: the concept is removed rather than re-tuned, and no quota figure on this surface is drawn differently for being low. §4 is the decision, the eight rules it voids, and what it costs and buys. The **pace** test this row proposed as the next step is not taken and not held in reserve — there is nothing left for it to trigger |
| 04 | With one product, the outer row's figure repeats the collapsed total. Acceptable? | **Answered — it stands.** They are in different registers: a summary line, and a labelled group header inside a table somebody opened. The alternative is a table whose shape changes with the product count, which is the thing this page exists to undo |
| 05 | The timer column drops `Friday` for `4d 6h`. Is the anchor worth keeping? | **Answered — durations throughout.** A column mixing `2h` with `Friday` reads as two different kinds of thing, and what the column holds is a countdown. The absolute day is kept in the accessible name (§7) |
| 06 | Should the table be reachable when nothing is close? | **Answered — always.** The control is drawn whenever there is at least one connected product. A control that appeared only in trouble would be one nobody had used at the moment they first needed it |
| 07 | What is drawn with nothing connected at all? | **Answered — no footer.** No products, no windows and no tokens is nothing to say, and a wing with nothing to say is removed rather than left blank |

### 8.6 The data model was already right

`MonitorStore.footerRules` returns one `FooterRule` per connected product, each holding its `FooterWindow`s — which is exactly §5's outer and inner levels. Version 3.0 flattened it into a single sorted list of windows; grouping is both truer to the data and what lets products keep Settings' order while windows keep the reader's. Since 3.4 **neither level sorts at all**, so the accessor needs no change whatever: `footerRules` already returns both orders correctly by doing nothing to them.

## 9. What this replaces

> **Version 3.3 replaces something of its own, and not by drafting a better version of it.** §4's speaking rule was removed by decision, and the record of what it said and what its removal costs is in §4 rather than here — an overruled rule belongs where a reader looks for the rule, not in a list of drafts that lost on their merits.

### 9.1 Version 3.1, on this same page

Version 3.1 stacked one spoken line per window past the threshold, tightest first and uncapped, and drew the table's outer rows with no leader. Both were settled at 3.2: the line was **one**, chosen by today's spend, so the speaking footer was one height at any count (`45` as written, `47` once the product name is a badge); and each outer row carries a faint leader between the product and its figure (§5). **The first of those is now moot** — 3.3 removed the line rather than capping it (§4). The leader stands.

### 9.2 Version 3.0, on this same page

The first draft of the gaugeless footer kept a `59% left` figure at the trailing end of the collapsed line and drew its per-product spend as coloured numerals beside the total, and its table was a **flat** list of windows sorted tightest-first across products. Both were folded into the two-level table: the outer row labels each product's spend so colour is not needed to attribute it, and grouping lets each level hold an order of its own — which the flat list could not do without contradicting [`expanded-header-v2.md`](expanded-header-v2.md) §4.3 rule 02. ~~while windows sort by tightness~~ was the inner order 3.0 and 3.2 both assumed; 3.4 makes it the reader's own and sorts nothing (§5). The collapsed line lost its quota figure with it; 3.3 makes that permanent (§4) and answers §8.5 question 01 with a fallback that reports only unreadability (§8.3). `Resets in` went too, repeated once a window.

### 9.3 Version 2.0, on page 07

Version 2.0 of this document kept the rule and folded it to the tightest window: one `496 × 3` gauge, its caption, and the spend, at `53` for every connected form, with every window stacked behind the control. It is drawn on `07 — The quota footer (superseded)` and is kept because two of its arguments survive into this version — **windows are a list rather than a layout**, and **a minimum is ordinal and folds to one member** — while its central object does not.

Two things were wrong with it. It answered §1.3 and left §1.1 and §1.2 standing: a bar per quota is still a bar per quota when there is only one of them. And it made the Codex-only machine pay `23` points for a uniform height, which was the strongest objection to it; taking the gauge out makes every connected form smaller instead, so the objection goes away rather than having to be argued for.

## 10. Verification

Checked on 2026-09-05. The heights, orders and readings are pinned by tests in
`NotchlineTests.swift`; the drawing was read off the running app against Figma
page `08` and page `11` §03.

- [x] The collapsed footer is `22` with one product connected, two, three and four, and draws the whole spend and the control and nothing else.
- [x] **No window is drawn collapsed, whatever its share.** A window at `2%` with four days to run changes nothing above the control, and the panel stays `308`.
- [x] **No figure anywhere on the footer changes ink, weight or size with its value.** Every inner row is `#7C7C80` at `2%` and at `98%`; every outer spend is `#C7C7CC`; brightness separates the table's levels and nothing else.
- [x] **An unreadable field draws `--` in its own place and nothing else changes**: `-- today` on the collapsed line and on an outer row, `-- left` in the share column, `--` in the timer column. No marker is drawn beside the chevron, on the band, or on the mark.
- [x] A window that has not started still reads `Not started`, and is never drawn as `--`.
- [x] Every `--` announces as `unavailable`, and no figure announces as zero.
- [x] Opened, there is one outer row per connected product and one inner row per window it reports, the per-model weekly cap included.
- [x] A connected product with no windows draws its outer row and no inner ones.
- [x] Products are in Settings' order; windows inside a product are in the order the reader published them — `5 h` before `7 d` for Claude Code — and **no list on this footer is sorted by any value it draws**. A window whose share changes, or stops being readable, keeps its row.
- [x] The window column is indented `12` from the product's; the share is right-aligned at `300` and the timer at `508`, where the product's spend is right-aligned too.
- [x] No reset draws the words `Resets in`, and no timer draws more than two units.
- [x] Folding the table from any product and window count leaves the pointer inside the panel.
- [x] The footer draws identically under a `46` pt menu bar and a `22` pt one.
- [x] The panel is `308` at three live rows on every connected form.

## 11. Implementation mapping

**Implemented on 2026-09-05.** The two levels needed no change — `footerRules` already returned one `FooterRule` per connected product, each holding its `FooterWindow`s (§8.6) — but what those two types *carry* did: a `FooterWindow` was a `0–1` fill and one caption string, and it is now the three columns the table draws plus the spoken form of its timer. `FooterRule` gains the product's own spend.

| Symbol | Change |
| --- | --- |
| `PanelMetrics.footerHeight(rules:isFolded:)` | Became `footerHeight(rules:isExpanded:)`: `22` or `19W + 30P + 17` (§2's badge-carrying form — `19W + 28P + 17` is the pre-badge figure), and **`0` with nothing connected** (§8.5 question 07), which is the one shape the old function had no answer for. The four constants behind it went, with `footerRuleHeight` and `footerWindowSpacing`; `footerWindowRowHeight`, `footerWindowIndent`, `footerShareTrailingEdge` and `footerLeaderClearance` replace them, and all four are compositions of measurements this file already had |
| `MonitorStore.footerRules` | **Unchanged, entirely.** It already maps `snapshot.quota.windows` straight through in the reader's order, which is what §5 now asks for. ~~Sorts each rule's windows by remaining share ascending, unanswerable last~~ — void (§5), and the only line of this table that retires without being replaced. ~~Gains `spokenWindows`~~ — void (§4); no window is selected, and nothing reads a share against a threshold |
| `MonitorStore.footerTodayText` | Became `footerToday`, a `SpendReading`: it lost its `rules.count > 1` guard, its product names and its parts, and returns the whole alone. Each product's own figure moved onto its `FooterRule`. **The reading is two parts rather than one string**, which the design did not say and the drawing needs — the figure is `#C7C7CC` and `today` is `#7C7C80`, and that is the same split §8.3's fallback needs, so there is one split rather than two |
| `UsageSummaryFormatter.resetText` | Gained the compact countdown — `47m`, `2h`, `3d 12h`, two units at most — and `spokenResetText` keeps the absolute form for the accessible name (§7). **Returns `--` where it returned `Reset unavailable`** (§8.3); `Not started` is unchanged, and so is the reasoning above it in `MonitorDomain.swift` that tells the two apart. A reset already past reads `Now` rather than `Resets now`, which the design did not specify: it is the one instant the column holds no duration, and a word there keeps it a countdown rather than inventing a `0m` that is not true. `summary(...)` and `UsageMeter` retire with the rules they wrote |
| `MonitorStore.quotaFolded` | Renamed `quotaExpanded`, default `false` (§8.1). `toggleQuotaFold()` became `toggleQuotaTable()` |
| `ExpandedPanelFooter` | Three line types — the spend line with its control, a product row, a window row — and no rule view at all. ~~a spoken line~~ is void (§4). `FooterRuleRow` and the half-width split went, and `FooterCaption` now hugs its text rather than filling: this footer is a table, and every column's edge is placed by the line that holds it |
| `aFoldedFooterIsTheSameHeightForEveryShape` | Became `theFooterIsTwentyTwoForEveryConnectedForm`; `foldingLiftsThePanelsBottomEdgePastTheChevronThatWasClicked` inverted into `foldingCannotStrandThePointer`, which also keeps the stranding guard honest by checking a shrink that *would* strand; `aProductWithNoLimitsKeepsItsRow` is new. ~~`aQuietWindowIsNotDrawn`~~ became `noShareReachesTheClosedFooter` — sweeping the share across its whole range and asserting the closed footer is identical is a stronger pin than one quiet window, and it is what §4 actually claims. `anUnreadableFieldDrawsTwoDashes`, `everyDashAnnouncesAsUnavailable`, `theResetColumnCountsDownInTwoUnitsAtMost` and `theOpenedTableIsNineteenAWindowAndThirtyAProduct` are new (§8.3, §7, §5, §2) |

[`dual-agent-design.md`](dual-agent-design.md) §5.1, §5.2 and §5.4 were amended in the same change, as was [`tech-design.md`](tech-design.md) §13's `Reset unavailable` wording and the matching signal row in [`non-public-codex-integration-features.md`](non-public-codex-integration-features.md) — §8.3 said both would be amended when the footer was built, and the footer is built.
