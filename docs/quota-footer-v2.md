# Notchline — Quota footer V2

| Field | Value |
| --- | --- |
| Status | **Designed, not implemented.** Nothing here needs a capability the app lacks: the data model is already a list of products each holding a list of windows (`MonitorStore.footerRules`), and only the layout is written for two. |
| Version | 3.2 |
| Date | 2026-09-04 |
| File | [Notchline V2](https://www.figma.com/design/c3CQBBk3Boiu0oM00Vvs9Y/Notchline-V2) — `08 — The footer without a gauge`. `07 — The quota footer (superseded)` is kept as the record of the direction this one leaves (§9). |
| Scope | The expanded panel's footer only: the quota rules and today's tokens. The band is [`expanded-header-v2.md`](expanded-header-v2.md), the session list is [`expanded-panel-v2.md`](expanded-panel-v2.md), both collapsed forms are [`compact-view-v2.md`](compact-view-v2.md). None is touched, and the panel's width does not move. |
| Supersedes | [`dual-agent-design.md`](dual-agent-design.md) §5.1 (structure and the four heights), §5.2 (which windows are drawn), §5.4 (the fold, its default and its trap). |
| Superseded in | §2's two heights, by [`colour-v2.md`](colour-v2.md) §5 — the product name is a badge, so the spoken line is `47` and the table `19W + 30P + 17`. Nothing else here moves. |

## 1. What V2 changes here, and why

### 1.1 The gauge is redundant with the number beside it

A `496 × 3` rule draws `59%` as a length, and its own caption prints `59%` two points to the right, exactly. The bar is a decoration of a figure it stands next to. Its one real advantage is **pre-attentive comparison** — seeing which of several is shortest without reading — and that is worth nothing in a footer that has already chosen the one that matters, and nothing again in a detail view somebody opened on purpose and is reading.

### 1.2 The footer is a dashboard on a surface that is an attention queue

The mark shows the most urgent thing. Rows appear when they want the user and leave when they stop. A wing with nothing to say is removed rather than left blank; a column with no sessions is not drawn; a zero is never drawn anywhere. **Only the footer draws its subject whether or not it has anything to say** — four numbers, every time the panel opens, on nearly all of which not one of them needs anything. It spends between a fifth and a third of the panel's height saying so.

### 1.3 And it does not survive a third product

Width is split per window: Codex takes the full `496` because it has one, Claude Code is halved because it has two. Thirds are `160`, against a caption of `182` — so `/usage`'s third window was **removed from the design rather than from the product**, and §5.2 wrote the cost down: *a user who exhausts the per-model weekly cap sees two healthy rules and is still refused.* Height grows per product (`30` / `53` / `84` / `115`), and the today line names products in words, running to `340` at three of them against the `496` it has.

**V2 takes the gauge out.** One figure while nothing is wrong, a sentence when something is, and a table for anyone who wants to look rather than be told.

## 2. Composition

> **The product names below become badges** ([`colour-v2.md`](colour-v2.md) §5). This footer is the one surface that already named products in words rather than in colour, so the decision costs it almost nothing — the name moves inside a `16` pt chip in the user's theme ink, and only two heights follow it. The spoken line's `Claude Code ·` and the table's outer-row `Codex` are the two places affected; the window rows, the spend figures, the leader and the control are untouched.
>
> | | Written here | With the badge |
> | --- | --- | --- |
> | Speaking | `45` | **`47`** |
> | Opened table | `19W + 28P + 17` | **`19W + 30P + 17`** |
>
> One term moves and no constant is introduced: a caption line carrying a badge is the badge's own `16` rather than `footerCaptionHeight`'s `14`, so a product group is `16 + 19w`. Collapsed is unchanged at `22` — it names no product.

**Collapsed — `22`, every connected form, every product count.**

```
12 →  518.7M today                                                  ⌄  ← 508
      ─ 6 ─
```

Today's tokens and the control. Nothing else.

**Speaking — `45`, one line whatever the count.**

```
      518.7M today                                                  ⌄
      Claude Code · 5 h · 8% left · 47m
```

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
| The spoken line, and the gap before it | `9 + 14` | `footerRuleSpacing` + `footerCaptionHeight` |
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

**Nothing about a limit is drawn while nothing is close.** A wing with nothing to say is removed rather than left blank; a column with no sessions is not drawn; a zero is never drawn anywhere.

**What this gives up, stated plainly.** Version 3.0 kept a `59% left` figure at the trailing end, which told *nothing is close* apart from *nothing is known*. Without it the collapsed footer says nothing about limits at all, and a window whose share cannot be read never speaks — so an hour of unreadable quota looks exactly like an hour of healthy quota. §8.5 question 01 records the cheapest way back.

## 4. When a limit speaks

| | Rule | |
| --- | --- | --- |
| 01 | **A window speaks when less than a sixth of it is left and more than a sixth of its time is.** `15%` is [`figma-design.md`](figma-design.md) §4.3's own critical threshold, used twice — below `15%` of the share, above `15%` of the time. The second half stops a window nagging in its last minutes, when running out costs nothing because the reset is arriving anyway. Both are fractions of things already known (`remainingPercent`, and `resetsAt` against the window's nominal length), so **nothing is estimated and no burn rate is inferred** | §8.3 |
| 02 | **It is the only thing the collapsed footer says about a limit.** The line above carries the spend and nothing else, so a window crossing the threshold is not competing for a slot: it arrives as a line that was not there a moment ago, which is the plainest change this surface can make. It is also the whole of the collapsed footer’s coverage — a window whose share cannot be read never speaks (§3) | §8.5 q01 |
| 03 | **The line is words, not a gauge.** Once presence carries the alarm, the content should be precise rather than graphic: which product, which window, how much, and how long. There is exactly one of these to read and it was chosen for you | |
| 04 | **It is drawn one step brighter, and nothing changes hue.** `#C7C7CC` against the caption grey, with the product's name in its **lit** ink rather than its caption ink. Brightness is this surface's attention channel and hue stays identity. No ground: white means a Turn is waiting on a person, and a limit running low is not that | |
| 05 | **There is one line, never two, and the product that has spent the most today gets it.** Tokens today is the best proxy this app has for which product the user is actually working in, and a limit on a product you are barely using is not the one that is going to stop you. So among the windows past the threshold, the line belongs to whichever product has spent the most — and, inside that product, to its tightest window. Ties go to Settings' order | §8.5 q02 |
| 06 | **Which means the figure above chooses what goes below it.** The collapsed line is the whole spend, and the selection is made from the parts of that same number. Nothing new has to be read or computed, and the two lines are about one thing: how much you have used, and what that is about to run into | |
| 07 | **What the one-line rule costs, and where it is paid back.** A tighter limit on a quieter product is not drawn — the rule can put an `11%` ahead of an `8%`. It is paid back by the control: every window past the threshold is in the table, in the lit grey, one click away. And it is the same trade the aggregate mark makes, showing the most urgent status anywhere and letting the list carry the rest | |
| 08 | **Opened, the table replaces the spoken line entirely.** The window that spoke is the first window inside its product's group, still in the lit grey, so repeating it above would be the same sentence twice | |

## 5. The table

**Two levels, because the windows belong to products.** Outside, the product and its own spend today. Inside, each of its windows on a line. The outer row is what makes the spend attributable without colour: on the collapsed line those parts had to be coloured numerals, and here each one sits beside its product's own name.

**A faint leader ties each product to its own figure.** `1` pt of white at `10%`, from `8` after the product's name to `8` before its spend, on the caption line's own middle — one step below the white-at-`15%` the panel's structural hairlines use, because it is joining two things rather than dividing anything. It is drawn on **outer rows only**, so having a leader is itself part of what says which level a line is on.

**Three columns inside, one figure outside, and one trailing edge for both.** The window at `24` — one step in from the panel's own `12` — the share right-aligned at `300`, and the timer right-aligned at `508`, which is where the product's spend is right-aligned too. **Indentation and the leader carry the level between them**: no box, rule or divider is drawn.

**`Resets in` is gone, and the column is a timer.** Repeated once a window it was noise, and what the column holds is a countdown — so it is written like every other countdown on this panel: `47m`, `2h`, `3d 12h`, two units at most. The absolute day survives in the accessible name, for anyone who wants Friday rather than four days (§8.5 question 04).

**The levels are three steps of brightness, and ~~hue~~ a badge names the group.** ~~The product in its own lit ink (`#6CB4FF` / `#D97757`)~~ — **the product is a badge** in the `Theme colour` pair ([`colour-v2.md`](colour-v2.md) §5) — its spend in `#C7C7CC`, everything inside it in `#7C7C80`. A share past the threshold is the one thing inside a group that steps back up to `#C7C7CC` — so **every** window that could have spoken is visible here, not only the one that did.

**Brightness was always doing this work, and now it is doing all of it.** Three steps already separated the product, its spend and its windows; the lit ink only said *which* product, which the name inside the badge says outright. The badge's own ground is darker than the panel, so it adds a step downwards rather than a fourth step up, and the group's brightest thing is still its spend.

**Products in Settings' order; windows tightest first inside each.** This is deliberately *not* the speaking line's order — that one picks by spend, because it is a selection rather than a list, and a reference that re-sorted itself every minute would be unreadable.  Which restores [`expanded-header-v2.md`](expanded-header-v2.md) §4.3 rule 02 at the level where it belongs — nothing re-sorts between products — and keeps ordering by tightness where it is the only order that means anything. **The grouping is what lets both be true at once**, and it is the one thing version 3.0 could not do.

**A product with no limits still gets its row** — an outer row and no inner ones. Its spend is attributed and the absence of lines says there is nothing to report. That is also how a connected product this app does not yet read quota for appears: present and counted, with nothing claimed about it. The current footer has no form for this at all.

**It grows by `19` a window and `28` a product, and by nothing else.** No column widens, no caption shortens, and nothing is dropped for want of room — which is what §5.2 had to do when Claude Code's third window would not fit in a half. That window is now simply a line.

**The control never moves and folding cannot close the panel.** The chevron rides the spend line, which is the footer's first line and is always drawn, so the table opens beneath it. Folding removes rows below a pointer sitting `6` to `22` above the folded bottom edge — inside it — which reverses the trap §5.4 records.

## 6. Heights

| Connected | P | W | Footer today | Collapsed | Opened | Panel today | Panel now |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Codex alone | 1 | 1 | `30` | **22** | `64` | 316 | **308** |
| Claude Code alone | 1 | 2 | `53` | **22** | `83` | 339 | **308** |
| Both products | 2 | 3 | `84` | **22** | `130` | 370 | **308** |
| Three products | 3 | 4 | `115` | **22** | `177` | 401 | **308** |
| Three, six windows | 3 | 6 | `115` | **22** | `215` | 401 | **308** |

Panel figures are `46 + 240 + footer` — three live rows at the reference menu bar, with the footer collapsed. **Every connected form gets smaller**, the single-product case included.

| Form | Footer | Panel | Caused by |
| --- | --- | --- | --- |
| Collapsed | `22` | 308 | nothing — every connected form |
| A window speaking | `45` | 331 | a share crossing `15%`, one line at any count |
| Opened, two products | `130` | 416 | the control |
| Opened, three and six | `215` | 501 | the control |

The table is the only thing here that grows, and it grows because somebody opened it.

## 7. Accessibility

- The collapsed line reads `518.7 million tokens today`, and the control is `Show limits` / `Hide limits`.
- A spoken line reads as written, with the timer expanded: `Claude Code, 5 hour window, 8% left, 47 minutes to reset`.
- The table is announced as a two-level list: each product with its spend, then its windows. `Codex, 310.1 million tokens today. Weekly, 72% left, resets in 3 days 12 hours.`
- **The absolute reset survives here**: where the column draws `4d 6h`, the accessible name says `resets Friday at 09:00`.
- A window with no share reads `unavailable`, never zero.
- The leader is decoration and is not announced.

## 8. What this reaches outside the footer

### 8.1 Two recorded behaviours reverse

§5.4's fold no longer closes the panel (§5 above), and its default inverts: the small form is what the footer **is**, not what it collapses to. `quotaFolded` becomes `quotaExpanded`, default `false` — a rename rather than a flipped boolean, so the change is visible in review.

### 8.2 A recorded risk is fixed for free

§5.2's per-model weekly cap. Its argument — *letting one half report different windows at different times turns a rule meant for a glance into one that must be read first* — was about a **half**, and there are no halves any more. Where the cap sits permanently at 100% for someone who never uses that model, it never crosses §4's threshold and never speaks — it is simply one more line inside its product, which is where it belongs.

### 8.3 One new rule, and its number is not new

The `15%` threshold, used on both the share and the time. Everything else on this page is a rearrangement of measurements that already exist.

### 8.4 The Usage Ring was considered and declined

[`figma-design.md`](figma-design.md) §4.3's `18 × 18` ring is the system's other gauge, and swapping one gauge for another does not answer §1.1: a ring still draws as an angle a fraction the figure beside it prints exactly, and it costs `18` points of line where 11 pt text costs `14`. Its colour thresholds are unusable here — amber and red would put a second meaning on hue, which is identity everywhere on this panel.

### 8.5 Open questions

| | Question | Where it stands |
| --- | --- | --- |
| 01 | How does a user learn that quota is unreadable? | **Open, and the thing version 3.1 gives up.** Version 3.0 kept a `-- left` figure before the chevron, which told *nothing is close* apart from *nothing is known*; the collapsed line no longer carries it, and a window whose share cannot be read never speaks. Cheapest way back if it bites: a single dimmed `--` before the chevron, drawn only while **no** window anywhere has a share — silent in every normal state, and about `20` points of width in the one state it is for |
| 02 | Is today's spend the right way to pick which product speaks? | **Answered by the board's owner — yes**, and it is the best proxy this app has for the product a person is actually working in, taken from a number the line above already draws. Two things to watch on a real machine: it can put an `11%` ahead of an `8%`, and it moves — a long Codex session can hand the line to Codex mid-afternoon. Both are covered by the table being one click away with every threshold-crossing window drawn in it |
| 03 | Is `15%` right on both sides? | **Open — the one number here worth measuring.** It is §4.3's own value used twice for symmetry rather than because both sides were tested. A 7-day window at 14% with five days to run is a genuine emergency; a 5-hour window at 14% with four hours left is merely tight; one threshold says the same about both. If it misfires the next step is a **pace** test — remaining share against time-remaining share — which needs no new data, only each window's nominal length |
| 04 | With one product, the outer row's figure repeats the collapsed total. Acceptable? | **Answered — it stands.** They are in different registers: a summary line, and a labelled group header inside a table somebody opened. The alternative is a table whose shape changes with the product count, which is the thing this page exists to undo |
| 05 | The timer column drops `Friday` for `4d 6h`. Is the anchor worth keeping? | **Answered — durations throughout.** A column mixing `2h` with `Friday` reads as two different kinds of thing, and what the column holds is a countdown. The absolute day is kept in the accessible name (§7) |
| 06 | Should the table be reachable when nothing is close? | **Answered — always.** The control is drawn whenever there is at least one connected product. A control that appeared only in trouble would be one nobody had used at the moment they first needed it |
| 07 | What is drawn with nothing connected at all? | **Answered — no footer.** No products, no windows and no tokens is nothing to say, and a wing with nothing to say is removed rather than left blank |

### 8.6 The data model was already right

`MonitorStore.footerRules` returns one `FooterRule` per connected product, each holding its `FooterWindow`s — which is exactly §5's outer and inner levels. Version 3.0 flattened it into a single sorted list of windows; grouping is both truer to the data and what lets products keep Settings' order while windows sort by tightness.

## 9. What this replaces

### 9.1 Version 3.1, on this same page

Version 3.1 stacked one spoken line per window past the threshold, tightest first and uncapped, and drew the table's outer rows with no leader. Both are settled here: the line is **one**, chosen by today's spend (§4 rule 05), so the speaking footer is `45` at any count; and each outer row carries a faint leader between the product and its figure (§5).

### 9.2 Version 3.0, on this same page

The first draft of the gaugeless footer kept a `59% left` figure at the trailing end of the collapsed line and drew its per-product spend as coloured numerals beside the total, and its table was a **flat** list of windows sorted tightest-first across products. Both were folded into the two-level table: the outer row labels each product's spend so colour is not needed to attribute it, and grouping lets products hold Settings' order while windows sort by tightness — which the flat list could not do without contradicting [`expanded-header-v2.md`](expanded-header-v2.md) §4.3 rule 02. The collapsed line lost its quota figure with it; §8.5 question 01 records what that costs. `Resets in` went too, repeated once a window.

### 9.3 Version 2.0, on page 07

Version 2.0 of this document kept the rule and folded it to the tightest window: one `496 × 3` gauge, its caption, and the spend, at `53` for every connected form, with every window stacked behind the control. It is drawn on `07 — The quota footer (superseded)` and is kept because two of its arguments survive into this version — **windows are a list rather than a layout**, and **a minimum is ordinal and folds to one member** — while its central object does not.

Two things were wrong with it. It answered §1.3 and left §1.1 and §1.2 standing: a bar per quota is still a bar per quota when there is only one of them. And it made the Codex-only machine pay `23` points for a uniform height, which was the strongest objection to it; taking the gauge out makes every connected form smaller instead, so the objection goes away rather than having to be argued for.

## 10. Verification

- [ ] The collapsed footer is `22` with one product connected, two, three and four, and draws the whole spend and the control and nothing else.
- [ ] No window is drawn collapsed, whatever its share, unless it crosses the threshold.
- [ ] A window below `15%` with more than `15%` of its time left draws a line; one below `15%` with less does not.
- [ ] A spoken line draws `#C7C7CC` with the product's name in its lit ink, and no ground.
- [ ] Opened, there is one outer row per connected product and one inner row per window it reports, the per-model weekly cap included.
- [ ] A connected product with no windows draws its outer row and no inner ones.
- [ ] Products are in Settings' order; windows inside a product are tightest first, unanswerable last.
- [ ] The window column is indented `12` from the product's; the share is right-aligned at `300` and the timer at `508`, where the product's spend is right-aligned too.
- [ ] No reset draws the words `Resets in`, and no timer draws more than two units.
- [ ] Folding the table from any product and window count leaves the pointer inside the panel.
- [ ] The footer draws identically under a `46` pt menu bar and a `22` pt one.
- [ ] The panel is `308` at three live rows on every connected form.

## 11. Implementation mapping

Nothing here is implemented. **The data model needs no change** — `footerRules` already returns one `FooterRule` per connected product, each holding its `FooterWindow`s (§8.6).

| Symbol | Change |
| --- | --- |
| `PanelMetrics.footerHeight(rules:isFolded:)` | Becomes `footerHeight(rules:isSpeaking:isExpanded:)`: `22`, `45`, or `19W + 28P + 17`. The four constants behind it go, with `footerRuleHeight` and `footerWindowSpacing` |
| `MonitorStore.footerRules` | Unchanged in shape. Gains `spokenWindows` — the windows past §4's threshold, tightest first — and sorts each rule's windows by remaining share ascending, unanswerable last |
| `MonitorStore.footerTodayText` | Loses its `rules.count > 1` guard, its product names and its parts: it returns the whole alone. Each product's own figure moves onto its `FooterRule` |
| `UsageSummaryFormatter.resetText` | Gains a compact countdown form — `47m`, `2h`, `3d 12h`, two units at most — and keeps the absolute form for the accessible name (§7) |
| `MonitorStore.quotaFolded` | Renamed `quotaExpanded`, default `false` (§8.1) |
| `ExpandedPanelFooter` | Four line types — the spend line with its control, a spoken line, a product row, a window row — and no rule view at all. `FooterRuleRow` and the half-width split go |
| `aFoldedFooterIsTheSameHeightForEveryShape` | Becomes `theFooterIsTwentyTwoForEveryConnectedForm`; `foldingLiftsThePanelsBottomEdgePastTheChevronThatWasClicked` inverts into `foldingCannotStrandThePointer`; `aQuietWindowIsNotDrawn` and `aProductWithNoLimitsKeepsItsRow` are new |

[`dual-agent-design.md`](dual-agent-design.md) §5.1, §5.2 and §5.4 need amending before any of it is built.
