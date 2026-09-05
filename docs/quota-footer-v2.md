# Notchline — Quota footer V2

| Field | Value |
| --- | --- |
| Status | **Designed, not implemented.** Nothing here needs a capability the app lacks: the data model is already a list of products each holding a list of windows (`MonitorStore.footerRules`), and only the layout is written for two. |
| Version | 3.0 |
| Date | 2026-09-04 |
| File | [Notchline V2](https://www.figma.com/design/c3CQBBk3Boiu0oM00Vvs9Y/Notchline-V2) — `08 — The footer without a gauge`. `07 — The quota footer (superseded)` is kept as the record of the direction this one leaves (§9). |
| Scope | The expanded panel's footer only: the quota rules and today's tokens. The band is [`expanded-header-v2.md`](expanded-header-v2.md), the session list is [`expanded-panel-v2.md`](expanded-panel-v2.md), both collapsed forms are [`compact-view-v2.md`](compact-view-v2.md). None is touched, and the panel's width does not move. |
| Supersedes | [`dual-agent-design.md`](dual-agent-design.md) §5.1 (structure and the four heights), §5.2 (which windows are drawn), §5.4 (the fold, its default and its trap). |

## 1. What V2 changes here, and why

### 1.1 The gauge is redundant with the number beside it

A `496 × 3` rule draws `59%` as a length, and its own caption prints `59%` two points to the right, exactly. The bar is a decoration of a figure it stands next to. Its one real advantage is **pre-attentive comparison** — seeing which of several is shortest without reading — and that is worth nothing in a footer that has already chosen the one that matters, and nothing again in a detail view somebody opened on purpose and is reading.

### 1.2 The footer is a dashboard on a surface that is an attention queue

The mark shows the most urgent thing. Rows appear when they want the user and leave when they stop. A wing with nothing to say is removed rather than left blank; a column with no sessions is not drawn; a zero is never drawn anywhere. **Only the footer draws its subject whether or not it has anything to say** — four numbers, every time the panel opens, on nearly all of which not one of them needs anything. It spends between a fifth and a third of the panel's height saying so.

### 1.3 And it does not survive a third product

Width is split per window: Codex takes the full `496` because it has one, Claude Code is halved because it has two. Thirds are `160`, against a caption of `182` — so `/usage`'s third window was **removed from the design rather than from the product**, and §5.2 wrote the cost down: *a user who exhausts the per-model weekly cap sees two healthy rules and is still refused.* Height grows per product (`30` / `53` / `84` / `115`), and the today line names products in words, running to `340` at three of them against the `496` it has.

**V2 takes the gauge out.** One figure while nothing is wrong, a sentence when something is, and a table for anyone who wants to look rather than be told.

## 2. Composition

**At rest — `22`, every connected form, every product count.**

```
12 →  518.7M today · 310.1M · 208.6M                    59% left    ⌄  ← 508
      ─ 6 ─
```

**Speaking — `22 + 23k`.**

```
      518.7M today · 310.1M · 208.6M                                ⌄
      Claude Code · 5 h · 8% left · Resets in 47 minutes
```

**The table — `22n + 23`.**

```
      518.7M today · 310.1M · 208.6M                                ⌃
      Claude Code · 5 h                8% left        Resets in 47 minutes
      Codex · weekly                  72% left        Resets in 3 days 12 hours
      Claude Code · 7 d               85% left        Resets Friday
```

| Term | Value | Constant it already is |
| --- | --- | --- |
| The spend line, carrying the control | `16` | `quotaFoldControlSize` |
| Before whatever follows it | `9` | `footerRuleSpacing` |
| A spoken line, and the gap after it | `14 + 9` | `footerCaptionHeight` + `footerRuleSpacing` |
| A table row, and the gap after it | `14 + 8` | `footerCaptionHeight` + `footerWindowSpacing` |
| Below the last line | `6` | `footerBottomMargin` |

`footerRuleHeight` (`3`) and `footerCaptionSpacing` (`5`) retire with the rule; the other five do the same jobs in a different shape. **No new measurement is introduced**, and `footerWindowSpacing` — the `8` between two half-width rules — becomes the `8` between two table rows.

## 3. At rest

**One figure stands for every limit there is**: the tightest remaining share across every window of every connected product, at the trailing end where this panel already puts its readings. A minimum is ordinal, so it folds and has exactly one member — the same reason the band draws one mark for the most urgent status anywhere. The word `left` is what makes a bare percentage parseable beside a token count.

**It is never silent.** A window with no share cannot be a minimum, so it is skipped; and if no window anywhere has one, the figure reads `-- left`. So the resting footer tells *nothing is close* apart from *nothing is known* — the distinction a footer that simply drew no quota when all was well would have lost, and the reason this design draws a figure rather than nothing.

**The spend is the only per-product thing left, and it is numerals.** The whole in `#C7C7CC`, `today` in `#7C7C80`, one part per product that has spent something today in that product's lit ink, and **no product ever named in words at any count**. That removes §5.4's *name the products only when there are two*, and with it the last per-product prose on the panel. It is about `160` wide at two products and `246` at four — the half of the line with room to grow, while the figure beside it never grows at all.

Rules 01–03 of [`expanded-header-v2.md`](expanded-header-v2.md) §4.3 carry over unchanged: the whole is always drawn, parts arrive beside it, a product with nothing today has no part, and a decomposition into one term is the whole said twice — so a single-product footer reads `310.1M today` in grey and colour arrives with the second product.

## 4. When a limit speaks

| | Rule | |
| --- | --- | --- |
| 01 | **A window speaks when less than a sixth of it is left and more than a sixth of its time is.** `15%` is [`figma-design.md`](figma-design.md) §4.3's own critical threshold, used twice — below `15%` of the share, above `15%` of the time. The second half stops a window nagging in its last minutes, when running out costs nothing because the reset is arriving anyway. Both are fractions of things already known (`remainingPercent`, and `resetsAt` against the window's nominal length), so **nothing is estimated and no burn rate is inferred** | §8.3 |
| 02 | **The quiet figure gives way to the line; the footer never draws both.** They are the same fact at two volumes, and a decomposition into one term is the whole said twice. The trailing end of the spend line empties as the line arrives beneath it, which makes the escalation something you see happen rather than something you have to notice | |
| 03 | **The line is words, not a gauge.** Once presence carries the alarm, the content should be precise rather than graphic: which product, which window, how much, when it comes back. There is exactly one of these to read and it was chosen for you | |
| 04 | **It is drawn one step brighter, and nothing changes hue.** `#C7C7CC` against the caption grey, with the product's name in its **lit** ink rather than its caption ink. Brightness is this surface's attention channel and hue stays identity. No ground: white means a Turn is waiting on a person, and a limit running low is not that | |
| 05 | **More than one speaks, more than one line**, tightest first, each carrying its own figure. No cap — the number of windows that can sit below `15%` with time still to run is small, and capping it would hide the one that matters | |
| 06 | **Opened, the table replaces the spoken lines entirely.** A window that is speaking is the table's first row, so repeating it above would be the same sentence twice | |

## 5. The table

Three columns: **the subject** at the panel's own `12`; **the share** right-aligned at `300`, so the figures read down a column and their shared `% left` suffix lines up; **the reset** right-aligned at `508`, where every other trailing thing on this panel already is. One line per window at `14`, `8` apart.

- **A table compares better than a stack of bars, in the one place comparison matters.** Right-aligned figures in a column read against each other digit by digit. Full-width bars on separate rows share an origin but sit on different baselines, and each costs `22` points of height to say what six characters say exactly.
- **Sorted tightest first, unanswerable last** — the order the resting figure already implies, so the first row is always the window that figure came from.
- **The subject is the caption this panel already writes**: `Claude Code · 5 h`, the product in its caption ink. Same string the spoken line leads with, same shape a session row's caption has. A product with one window drops the window; nothing else is ever abbreviated.
- **It grows by `22` per window and by nothing else.** Six windows is `155`; four products with one each is `111`. No column widens, no caption shortens, and **nothing is dropped for want of room** — so §5.2's per-model cap comes back as one more row.
- **The control never moves and folding cannot close the panel.** The chevron rides the spend line, which is the footer's first line and is always drawn, so the table opens beneath it. Folding removes rows below a pointer sitting `6` to `22` above the folded bottom edge — inside it — which reverses the trap §5.4 records.

## 6. Heights

| Connected | Windows | Footer today | Footer now | Panel today | Panel now |
| --- | --- | --- | --- | --- | --- |
| Codex alone | 1 | `30` | **22** | 316 | **308** |
| Claude Code alone | 2 | `53` | **22** | 339 | **308** |
| Both products | 3 | `84` | **22** | 370 | **308** |
| Three products | 4 | `115` | **22** | 401 | **308** |
| Four products | 5 | `146` | **22** | 432 | **308** |

Panel figures are `46 + 240 + footer` — three live rows at the reference menu bar. **Every connected form gets smaller**, the single-product case included.

| Form | Footer | Panel | Caused by |
| --- | --- | --- | --- |
| At rest | `22` | 308 | nothing — every connected form |
| One window speaking | `45` | 331 | a share crossing `15%` |
| Two speaking | `68` | 354 | `+23` each, no cap |
| The table, 3 windows | `89` | 375 | the control |
| The table, 6 windows | `155` | 441 | the control |

## 7. Accessibility

- The resting figure's accessible name spells out what it stands for: `Tightest limit anywhere: 59% remaining`, and `Usage unavailable` when it reads `--`.
- A spoken line reads as written; the table's rows read subject, share, reset, in the order drawn.
- Today's line spells the colour out: `518.7 million tokens today; Codex 310.1 million, Claude Code 208.6 million` — the answer §9 already gives for the band's colour-coded columns, with the same permanently fixed order behind it.
- The `--` is spoken as `unavailable`, never as zero.
- The control is `Show all 3 limits` / `Show fewer`.

## 8. What this reaches outside the footer

### 8.1 Two recorded behaviours reverse

§5.4's fold no longer closes the panel (§5 above), and its default inverts: the small form is what the footer **is**, not what it collapses to. `quotaFolded` becomes `quotaExpanded`, default `false` — a rename rather than a flipped boolean, so the change is visible in review.

### 8.2 A recorded risk is fixed for free

§5.2's per-model weekly cap. Its argument — *letting one half report different windows at different times turns a rule meant for a glance into one that must be read first* — was about a **half**, and there are no halves any more. Where the cap sits permanently at 100% for someone who never uses that model, it is never the tightest and never surfaces.

### 8.3 One new rule, and its number is not new

The `15%` threshold, used on both the share and the time. Everything else on this page is a rearrangement of measurements that already exist.

### 8.4 The Usage Ring was considered and declined

[`figma-design.md`](figma-design.md) §4.3's `18 × 18` ring is the system's other gauge, and swapping one gauge for another does not answer §1.1: a ring still draws as an angle a fraction the figure beside it prints exactly, and it costs `18` points of line where 11 pt text costs `14`. Its colour thresholds are unusable here — amber and red would put a second meaning on hue, which is identity everywhere on this panel.

### 8.5 Open questions

| | Question | Where it stands |
| --- | --- | --- |
| 01 | Is a bare `59% left` parseable next to a token count? | **Standing recommendation: yes**, and `left` is what makes it so — `59%` alone reads as a share of the spend beside it. If it proves ambiguous the cheapest fix is the accessible name and a tooltip, not a label; a label would put a word back on the line this page has just cleared |
| 02 | Should the resting figure take the tightest window's product hue? | **Answered — no.** The hue would change as the worst window moved between products, which is a change nobody caused, and it would put a third coloured numeral on a line whose other colours already mean something specific |
| 03 | Is `15%` right on both sides? | **Open — the one number here worth measuring.** It is §4.3's own value used twice for symmetry rather than because both sides were tested. A 7-day window at 14% with five days to run is a genuine emergency; a 5-hour window at 14% with four hours left is merely tight; one threshold says the same about both. If it misfires the next step is a **pace** test — remaining share against time-remaining share — which needs no new data, only each window's nominal length |
| 04 | Should the table be reachable when nothing is close? | **Answered — always.** The control is drawn whenever there is at least one window. A control that appeared only in trouble would be one nobody had used at the moment they first needed it |
| 05 | What is drawn with nothing connected at all? | **Answered — no footer.** No windows and no tokens is nothing to say, and a wing with nothing to say is removed rather than left blank |

## 9. The direction this replaces

Version 2.0 of this document kept the rule and folded it to the tightest window: one `496 × 3` gauge, its caption, and the spend, at `53` for every connected form, with every window stacked behind the control. It is drawn on `07 — The quota footer (superseded)` and is kept because two of its arguments survive into this version — **windows are a list rather than a layout**, and **a minimum is ordinal and folds to one member** — while its central object does not.

Two things were wrong with it. It answered §1.3 and left §1.1 and §1.2 standing: a bar per quota is still a bar per quota when there is only one of them. And it made the Codex-only machine pay `23` points for a uniform height, which was the strongest objection to it; taking the gauge out makes every connected form smaller instead, so the objection goes away rather than having to be argued for.

## 10. Verification

- [ ] The footer is `22` with one product connected, two, three and four, and at one window or six.
- [ ] The resting figure is the tightest share across every connected product's windows, and reads `--` when no window has one.
- [ ] No window is drawn at rest, whatever its share, unless it crosses the threshold.
- [ ] A window below `15%` with more than `15%` of its time left draws a line; one below `15%` with less does not.
- [ ] The resting figure is not drawn while any window is speaking, and returns when none is.
- [ ] A spoken line draws `#C7C7CC` with the product's name in its lit ink, and no ground.
- [ ] The table is sorted tightest first with unanswerable windows last, and its first row is the window that spoke.
- [ ] Every window the product reports appears in the table, the per-model weekly cap included.
- [ ] Folding the table from any window count leaves the pointer inside the panel.
- [ ] Today's line draws the whole always, one part per product that spent something, no parts with one such product, and no product name at any count.
- [ ] The footer draws identically under a `46` pt menu bar and a `22` pt one.
- [ ] The panel is `308` at three live rows on every connected form.

## 11. Implementation mapping

Nothing here is implemented. The data model needs no change — `footerRules` already returns one `FooterRule` per connected product, each holding its `FooterWindow`s.

| Symbol | Change |
| --- | --- |
| `PanelMetrics.footerHeight(rules:isFolded:)` | Becomes `footerHeight(spokenCount:tableCount:)`: `22`, `22 + 23k`, or `22n + 23`. The four constants behind it go, with `footerRuleHeight` and `footerCaptionSpacing` |
| `MonitorStore.footerRules` | Flattens to `footerWindows: [FooterWindow]` carrying its agent, sorted by remaining share ascending with unanswerable last; `tightestShare` is the first answerable member and `spokenWindows` the ones past the threshold |
| `MonitorStore.footerTodayText` | Loses its `rules.count > 1` guard and its product names; returns a whole plus zero or more coloured parts |
| `MonitorStore.quotaFolded` | Renamed `quotaExpanded`, default `false` (§8.1) |
| `ExpandedPanelFooter` | Three row types — the spend line with its control, a spoken line, a table row — and no rule view at all. `FooterRuleRow` and the half-width split go |
| `aFoldedFooterIsTheSameHeightForEveryShape` | Becomes `theFooterIsTwentyTwoForEveryConnectedForm`; `foldingLiftsThePanelsBottomEdgePastTheChevronThatWasClicked` inverts into `foldingCannotStrandThePointer`; and `aQuietWindowIsNotDrawn` is new |

[`dual-agent-design.md`](dual-agent-design.md) §5.1, §5.2 and §5.4 need amending before any of it is built.
