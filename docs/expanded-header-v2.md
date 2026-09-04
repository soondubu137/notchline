# Notchline — Expanded header V2

| Field | Value |
| --- | --- |
| Status | **Designed and settled, not implemented.** Every question §10 parked is now answered, closed or standing on its own recommendation, and the resting form's width is corrected (§5). No Swift has been written against any of it. |
| Version | 2.0 |
| Date | 2026-09-03 |
| File | [Notchline V2](https://www.figma.com/design/c3CQBBk3Boiu0oM00Vvs9Y/Notchline-V2) — `05 — The expanded header` |
| Scope | The expanded panel's top band only: the two shoulders either side of the physical cut-out. The session list, the quota footer, the settings window and both collapsed forms are untouched. |
| Supersedes | [`figma-design.md`](figma-design.md) §3.3's expanded widening rule and the fold behind it, and §4.2's expanded half. [`compact-view-v2.md`](compact-view-v2.md) §8's two parked questions and the `70.51` arithmetic that assumed per-product marks. [`compact-view-v2.md`](compact-view-v2.md) §3.2 rule 01 in this form only — see §4.3. |

## 1. What V2 changes here, and why

The band is the last surface still drawn the V1 way. It holds one animated matrix per product, each reserving that product's session-dot column, and it reserves the longest status name the aggregate can reach — `Approval needed`, `101.56 → 102` at 13 pt Light. The panel is pinned to the display's centreline, so every point the leading side takes is taken from the trailing side too, where there is a gear and nothing else.

```
12 + 50.51 + 12 + 102 + 8    leading, two products  =  184.51
 8 + 32 + 12                 trailing, one gear     =   52.00
```

| Cut-out | V1 · one product | V1 · two | V1 · three |
| --- | --- | --- | --- |
| `127 × 22` — Larger Text | 520 | 520 | 553 |
| `185 × 32` — default scaling | 520 | 555 | 611 |
| `200 × 46` — the file's reference | 520 | 570 | 626 |
| `220 × 38` — More Space | 533 | 590 | 646 |

The extra width is not wasted: rows are measured from the panel (`currentPanelSize.width − 12`), so it lands in their titles. What is wrong is where the number comes from. A two-agent panel is `570` because of a sentence and a one-agent panel is `520` because of a baseline, so the same object is two sizes depending on what happens to be open, and it changes size the first time a second agent connects.

Underneath that, the band is per-agent in the two places it should not be and folded in the one place it should not. It carries identity in the animation channel, which has to say something else; and it folds the counts into two totals, which throws identity away in the one place it could have been had for nothing, because the digits are drawn either way.

**V2 folds the marks, drops the name, keeps the totals, and decomposes the counts.**

## 2. Composition

```
12 + 16.6 + 4 + totals + 12 + columns + 8   │   cut-out   │   8 + gear + 12    expanded header
12 + 16.6 + 4 + totals + 8                  │   cut-out   │   8 + reading + 12  collapsed bar
```

The collapsed bar's composition entire, with two terms added in the middle and one swapped at the end.

| Term | Value | Note |
| --- | --- | --- |
| Panel inset | `12` | `expandedHorizontalPadding`, unchanged |
| Aggregate matrix | `16.6` | `statusMatrixSize`, unchanged, one for every agent at once |
| Mark-to-counts gap | `4` | The collapsed bar's own |
| The totals | `13.2` | Reserved at two digits, drawn whatever is connected (§4.1) |
| Totals-to-parts gap | `12` | `expandedReadoutSpacing` — the panel's own spacing, and the gap the status name used to take |
| The columns | `19.2` per working agent, less `6` | `13.2` reserved and `6` between (§4.2) |
| Clearance | `8` | `expandedNotchClearance`, both sides, unchanged |
| Gear | `32` at a `46` bar, `27.6` at `38` | `settingsButtonSize`, trailing-aligned, unchanged |

Two smaller things differ from the bar, and both are the panel being a panel: the columns **reserve** here and **hug** out there, because this panel is sized from a baseline while the bar is pinned to the cut-out with nothing beside it to protect; and the trailing side holds the one control this surface has, in place of a clock that is drawn in the row it belongs to. Each `8` still exists only where content stands on both sides of it.

**The mark stays folded, and it has to.** Status is ordinal — the aggregate is the most urgent status any agent is in — and a fold like that has no parts to show: its decomposition is one animated mark per agent, which is what [`compact-view-v2.md`](compact-view-v2.md) §2 removed and what four moving marks on a `46` pt band would be. The clock is a maximum and has no parts either. The counts are the one fold that is a sum.

## 3. The shoulders are measured from hardware

The panel is `520` by baseline and the cut-out is hardware, so the room beside it is `(520 − cut-out) ÷ 2` — a different number on every Mac, and `46.5` smaller on a machine at More Space than on one at Larger Text.

| Cut-out | Shoulder | Leading side, two agents | What is left |
| --- | --- | --- | --- |
| `127 × 22` | `196.5` | `98.2` | `98.3` |
| `185 × 32` | `167.5` | `98.2` | `69.3` |
| `200 × 46` | `160` | `98.2` | `61.8` |
| `220 × 38` | `150` | `98.2` | `51.8` |

**Anything drawn in a shoulder has to fit the smallest one.** Something wider than `51.8` draws for some people and not others, which is worse than not drawing it: the same panel would tell two people looking at the same thing two different things. That single rule decides the whole design.

| Candidate for the room the name left | Width | At `220` | Why it is or is not drawn |
| --- | --- | --- | --- |
| A third agent's column | `19.2` | fits | And a fourth. The fifth is where the panel moves — §6.2 |
| The status name, `Approval needed` | `102` | no | Removed from every surface; it only ever fitted here because the panel was widened until it did |
| Both agents named, `Codex · Claude Code` | `110.34` | no | Fits at `127` and nowhere else. Colour says which agent for no width at all |
| The first row's Project, `notchline` | `55.10` | no | Rejected anyway — the row it names is `46` pt below, saying it already |
| The longest reading, `10:00:00` | `64` | no | The clock belongs to the row the panel puts first, drawn in full with its own timer |
| What is out of view, `+3` | ≈ `14` | fits | Rejected. The totals already count the whole list, and a figure that changes as you scroll is a scrollbar with worse manners |

So the name could never have stayed, and the answer is not another word. Naming the agents costs `110.34` and fails the same test twice as hard as the word it would replace.

## 4. The decomposition

### 4.1 The totals stay

**Answered by the board's owner rather than recommended.** The collapsed bar's own column — sessions over subagents, reserved at two digits, in `#C7C7CC` over `#7C7C80` — is drawn in the same place at the same size the whole time the panel is open. The parts are set out `12` after it.

It decides three other things:

1. **Expanding adds rather than replaces.** The figure the eye was on when it hovered does not move, change colour, or go away.
2. **The parts can be selective.** An agent with nothing running leaves the band, because the sum is still on the surface (§4.3, rule 04).
3. **It costs `25.2` rather than `6.6` for the first agent**, which is where the four-agent ceiling at a `220` cut-out comes from (§6.2).

### 4.2 The columns

One column per **working** agent: that agent's session count over its subagent count, in that agent's own two inks, `13.2` reserved and `6` apart. The rows are the compact column's exact geometry — cap-top on the matrix's top edge, the small numeral's baseline on its bottom — so the whole block is `16.6` tall, asks for no height the mark did not already have, and draws identically under a `46` pt menu bar and a `22` pt one.

The price of reserving is visible at one digit: two single digits stand `12.6` apart, with `6.6` of held room between them. It is paid in black rather than in width, and it buys a band where a tenth session moves nothing.

### 4.3 The rules

| | Rule | |
| --- | --- | --- |
| 01 | **The totals stay, and the parts follow them.** | §4.1 |
| 02 | **One column per agent, in Settings' order, packed.** Nothing re-sorts — not by count, not by urgency, not by which agent moved last. Columns pack rather than hold a slot apiece, so an agent that empties gives its room back and the columns after it close up. §10, question 02 |
| 03 | **Hue says which agent; brightness says which number.** Sessions in the agent's lit ink, subagents in its caption ink — the same two steps the totals use, rotated into hue. [`compact-view-v2.md`](compact-view-v2.md) §3.2 rule 01 said hierarchy is size and brightness and never hue, and it was right about a single column: there was nothing to tell apart. There is now, and brightness still carries the hierarchy inside each column |
| 04 | **No zeros. An agent with nothing at all has no column.** §3.2 rule 03 — a zero is never drawn anywhere on this surface — holds here too, and the totals are what make it affordable. What the band shows is what is running, not what is installed |
| 05 | **One row or two, and a single row centres.** The subagent row is drawn when there are subagents anywhere, and then every column fills it. With none there is one row, and it stands on the matrix's middle rather than its top edge — half the matrix's leftover lower, `4.425` at the drawn cap, following §3.4 — so the band keeps one baseline at a time rather than one per agent |
| 06 | **A zero inside a drawn row is a dash.** An agent with sessions and no subagents reads `–` in its caption ink. A blank would leave the reader deciding whether the number was absent or the agent was; a `0` would be a figure that adds nothing in a row of figures that add. The dash can only appear in the lower row — the totals cannot show one, because that row is drawn only when the total is at least one |
| 07 | **One agent working, and there is nothing to decompose.** Whether it is the only agent configured or the only one of four with anything running, its column would repeat the totals digit for digit in a second ink. So the band draws the totals alone, in grey, and colour arrives with the second working agent. Colouring the totals instead was rejected: the same column would say the aggregate sometimes and an agent other times, and it is the one column that must never change what it is |

### 4.4 The inks

Every agent's pair is the two inks it already owns — its lit matrix colour over its row-caption colour ([`dual-agent-design.md`](dual-agent-design.md) §2) — standing in the same relation as the grey pair the totals keep. Nothing here is a new value, and nothing is brighter than what the bar already draws.

| | Sessions | Subagents |
| --- | --- | --- |
| The totals, kept from the bar | `#C7C7CC` | `#7C7C80` |
| Codex | `#6CB4FF` | `#4D81B7` |
| Claude Code | `#D97757` | `#9C553E` |
| ~~A third agent~~ | — | — |
| ~~A fourth~~ | — | — |

**The third and fourth pairs are struck rather than settled.** This product monitors Codex and Claude Code, and the rule that would generate a third pair is recorded at §10 question 03 for the day a third product exists. Nothing in the band's geometry depends on it: §6.2 sizes from a count, and the count is free of what colour each column is. The two placeholder values this table used to carry (`#57D9A3` / `#A78BFA`) are gone, so nothing can be built against them by accident.

## 5. States

True size, against the `200 × 46` reference cut-out.

| State | The band draws | Width |
| --- | --- | --- |
| Nothing connected | Resting grey mark, gear. No total, nothing to decompose, and no word | `304` — was `396` |
| One agent, connected, no rows | Steady mark, gear. A zero is never drawn | `520` |
| Two agents connected, one working | Mark, grey totals, gear. One term, so no parts (rule 07) | `520` |
| Two agents, running · 2 and 1 | `3` grey, `2` Codex, `1` Claude Code — one row, centred | `520` — was `570` |
| Approval needed, both rows | `3 / 4` grey, `2 / 1`, `1 / 3` | `520` — was `570` |
| Three agents, one idle | `3 / 5` grey, `2 / 1` Codex, `1 / 4` third agent; the idle one has no column and the third closes up into the slot it would have held | `520` — V1 would be `626` |
| Ten or more, one agent with no subagents | `15 / 7` grey, `12 / 7` Codex, `3 / –` Claude Code | `520` |
| Four agents | `9 / 4` grey and four columns — the widest count that fits at `220` | `520` |

The three- and four-agent rows are **width headroom, not a contract**: they say what the composition costs if a third product is ever monitored, and §4.4 no longer carries inks to draw them in. Everything this product ships is the rows above them.

**Nothing connected** is the resting form widening in place to put the gear within reach — and **it composes symmetrically, like every other width in this document**. The panel is centred on the display while it is expanded (`MonitorStore.currentPanelTrailingAnchor` is nil there, and `OverlayPanelLayout.frame` centres what it is given), so the room beside the cut-out is `(width − cut-out) ÷ 2` on *both* sides and a width added up as `leading + cut-out + trailing` does not survive being drawn. The trailing side is the wider of the two — `8 + gear + 12`, against a bare mark's `12 + 16.6 + 8` — so this form is `cut-out + 2 × (8 + gear + 12)` and the gear keeps its `8` at every cut-out.

| Cut-out | Gear | Trailing side | Resting width |
| --- | --- | --- | --- |
| `127 × 22` | `20` | `40` | **207** |
| `185 × 32` | `24.36` | `44.36` | **274** |
| `200 × 46` | `32` | `52` | **304** |
| `220 × 38` | `27.64` | `47.64` | **316** |
| no cut-out | by bar height | — | `12 + 16.6 + 8 + gear + 12`, sized to itself |

The gear is `settingsButtonSize(compactHeight:)`, which tracks the menu bar, so the cut-out and the gear move together and the two columns are one machine's answer rather than two.

**The additive figure this section first published — `288.6 → 289` — was V1's own composition with the word taken out of it, and V1's composition is where the fault is.** `12 + 16.6 + 12 + 82.96 + 8 + 200 + 8 + 12 + 32 + 12 = 395.56 → 396` gives `98` of shoulder to a leading side wanting `123.56`, so roughly `25` pt of `Disconnected` is drawn behind the cut-out — and `drawsCompactStatusName` is `isExpanded || noNotch`, which is to say that the hovered resting pill on a notched screen is precisely where that word is drawn. **Dropping the word is what makes the symmetric rule affordable**: the leading side falls to `36.6`, the trailing side binds, and `304` is still `92` narrower than the form that had the fault. This is the last surface that drew `MonitorStatus.displayName`; with it gone the name is drawn nowhere and said everywhere (§9). [`figma-design.md`](figma-design.md) §6.4's `400` and its checklist's `400.6` are void with the rest.

## 6. Widths

### 6.1 The panel

| Cut-out | V1 · one | V1 · two | V1 · three | Now, up to four agents |
| --- | --- | --- | --- | --- |
| `127 × 22` | 520 | 520 | 553 | **520** |
| `185 × 32` | 520 | 555 | 611 | **520** |
| `200 × 46` | 520 | 570 | 626 | **520** |
| `220 × 38` | 533 | 590 | 646 | **520** |
| no cut-out | 520 | 520 | 520 | **520** |

### 6.2 By working-agent count

| Agents | Totals + parts, reserved | Leading side | Panel at `220` | Panel at `200` |
| --- | --- | --- | --- | --- |
| 1 — nothing to decompose | `13.2` | `53.8` | 520 | 520 |
| 2 | `57.6` | `98.2` | 520 | 520 |
| 3 | `76.8` | `117.4` | 520 | 520 |
| 4 | `96.0` | `136.6` | 520 | 520 |
| 5 | `115.2` | `155.8` | **532** | 520 |
| 6 | `134.4` | `175.0` | **570** | **550** |

The totals are `13.2` and the `12` after them is the panel's own spacing, so the first working agent costs `25.2` and every one after it `19.2` — and all of it is the numbers, because the identity is the ink they are already drawn in. **Four agents at this machine's `220`; five at the reference and at default scaling; seven at Larger Text.** V1 was past `520` at the second product.

### 6.3 The branch that no longer fires

A side asks `98.2` with two agents against a trailing side wanting `52`, so the panel passes its baseline only where the cut-out is wider than `520 − 196.4 = 323.6` — half again the widest cut-out this product meets. What sets this width is now a count of working agents rather than a sentence.

`expandedNotchClearance` does not go: it stays as the guard that this band clears the hardware, and stops being the rule that decides a width. `everySentenceTheExpandedHeaderCanSayClearsTheCutOut` becomes a test with no sentence in it, and `theExpandedWidthAnswersToTheMarksAndNotToUnreachableNames` is answered by the width answering to neither.

**What the centreline costs now.** [`figma-design.md`](figma-design.md) §3.3 records the decision to pin the panel to the display's centreline rather than to the cut-out, knowingly paying for symmetry. That cost was `70` pt while the leading side wanted `184.51`. It is zero for every agent count a machine is likely to run. The argument survives intact and is no longer paid for.

## 7. What the band no longer says, and what it now says

| V1 channel | What it said | V2 |
| --- | --- | --- |
| One matrix per product | How many products, and each one's state | One aggregate matrix, most urgent status anywhere. The band and the bar draw the same mark |
| Matrix animation, per product | Which product is in which state | The animation stays, aggregate. Which agent is now said by the colour of a number, which asks for no attention |
| Per-product session-dot column | That product's open rows | Its own numeral, in its own ink |
| Status name | The aggregate status, in words | Not drawn. Every row below states its own status, and the band has no room for a sentence at any cut-out (§3) |
| — | — | **New:** how many of the sessions and subagents are whose |

## 8. What this reaches outside the band

1. **Nothing, by construction.** The list, the footer, the collapsed forms and the settings window are untouched. The panel's baseline is unchanged and its height is unchanged.
2. **One open hand-over.** The collapsed reading has nowhere to stand in the band, because the gear is there and the reading belongs to the row the panel puts first. §10, question 04.
3. **One thing the band can no longer say: which agents are connected.** An agent with nothing running has no column, and an agent that has gone dark drains its rows and then has none either, so the two look alike up here. That is the cost of drawing what is running rather than what is installed. The footer names each connected product beside its quota rules, and Settings has the whole list. Recorded rather than solved — it is the one thing a colour-coded row of numbers cannot do.

## 9. Accessibility

- **Colour is the only thing saying whose number a number is**, and it is the one channel §3 shows the band can afford. Two answers that cost no width: the accessible name spells each column out — `Codex, 2 sessions, 1 subagent` — and the order is permanently Settings' order, so position is a second channel for anyone who learns it. §10, question 05.
- **The dash is spoken as `none`**, not as a hyphen, and never as zero-sessions: it appears only in the subagent row.
- The status name **stops being drawn and does not stop being said**: it remains the accessibility label of the aggregate, exactly as [`compact-view-v2.md`](compact-view-v2.md) §10 has it for the collapsed forms.

## 10. Open questions

None are open. Three were answered by the board's owner, one is closed as out of scope, and two stand on the recommendations written here — recorded as standing rather than as decided, so that a later reader can see which is which.

| | Question | Where it stands |
| --- | --- | --- |
| 01 | Do the parts replace the totals? | **Answered — they do not.** §4.1 |
| 02 | Do the columns pack, or hold a slot per configured agent? | **Standing recommendation: packing, as drawn.** The movement is real and lands where it does least harm — the totals are anchored to the mark and never move. Worth watching on a machine that runs both agents in earnest |
| 03 | What colour is a third agent, and a fourth? | **Closed as out of scope.** The product monitors Codex and Claude Code; §4.4's third and fourth pairs are struck. The rule to settle when a third product arrives, unchanged: each new product takes the hue farthest in OKLCH from every product already configured, at the products' own chroma and their two lightnesses — the construction [`aggregate-ink-palette.md`](aggregate-ink-palette.md) used for its starred entries. Two collisions to judge on screen then: Completed is green in a row's status control, and the aggregate mark's default ink is a near-neutral at `150°`. Neither is fatal — hue means agent in this band and status in the row, which is already true of Codex blue standing beside Running blue |
| 04 | Where does the collapsed reading go when the panel opens? | **Answered — nowhere. It gives way to the gear.** The trailing slot holds one thing at a time: collapsed it is the reading, expanded it is the gear, and opening the panel cross-fades one into the other in place, on the slot curve the wings' contents already use. Nothing travels and nothing descends — the turn the reading was timing draws its own timer in the list below, from its own start, so the figure is not lost by being let go. It is also the cheaper answer: the reading re-rasters once a second, and a travelling raster would have to keep doing it in flight. The counts are the other half of the same rule, already drawn: the totals hold still and the parts fade in beside them |
| 05 | Is colour enough? | **Standing recommendation.** §9. If the accessible name and the fixed order are not enough, the panel is already a hover surface and a tooltip on the block can name the columns without drawing a word. What is not available is the word itself |
| 06 | Is `520` still the right baseline, now that nothing widens it? | **Standing recommendation: leave it.** That width was bought by a status name on a panel that changed size when a second agent connected, and a row that ends in a fade rather than an ellipsis loses characters, not meaning. The lever moves down — two agents need `196.4` plus the cut-out — and up costs a panel that is a different size on different machines again |

## 11. Verification

- [ ] The panel is `520` at every cut-out with one, two, three and four working agents.
- [ ] The leading group is identical collapsed and expanded: mark at `12`, totals at `32.6`, nothing moving on hover.
- [ ] The parts are absent with one working agent, and appear when a second starts.
- [ ] An agent with no sessions and no subagents draws no column, and its neighbours close up.
- [ ] A drawn subagent row is filled by every column, with `–` where an agent has none.
- [ ] With no subagents anywhere, every numeral centres `4.425` below the matrix's top edge, totals included.
- [ ] A tenth session widens nothing and moves no neighbouring column.
- [ ] The band draws identically under a `46` pt menu bar and a `22` pt one.
- [ ] Nothing connected composes `cut-out + 2 × (8 + gear + 12)` — `304` at the reference — and the gear stands a full `8` clear of the cut-out at every scaling step, measured against the window's own centred frame rather than the sum.
- [ ] No form of this band draws `MonitorStatus.displayName`, the hovered resting pill included.
- [ ] Opening the panel cross-fades the collapsed reading into the gear in place, with neither travelling.
- [ ] Every column has an accessible name naming its agent and both figures.

## 12. Implementation mapping

Nothing here is implemented. The work is concentrated in three places.

| Symbol | Change |
| --- | --- |
| `PanelMetrics.expandedWidth(centerOcclusionWidth:markCount:)` | Sizes from the working-agent count rather than from `workingStatuses`' widest readout. `markCount` becomes a count of columns |
| `PanelMetrics.expandedStatusReadoutWidth(status:markCount:)` | Retired. Nothing in the band is a status readout any more |
| `PanelMetrics.marksWidth(_:areProductMarks:)` | No longer reached from the band: the header draws one aggregate mark, so `drawnMarksWidth` governs both forms |
| `PanelMetrics.restingExpandedWidth(…)` | Drops `statusLabelWidth(.disconnected)` and stops adding its two sides up: composes `centerOcclusionWidth + 2 × (expandedNotchClearance + gear + expandedHorizontalPadding)`, which is `304` at the reference cut-out and a `46` bar. The trailing gap becomes `expandedNotchClearance` rather than `expandedReadoutSpacing`, and the no-cut-out branch keeps composing to itself |
| `OverlayHeader` / `StatusReadout` | The header stops passing `text`/`showsText`, and gains the per-agent columns after the aggregate column |
| `NotchPalette.MatrixInk` | Gains the per-agent numeral pair, which is the existing lit ink over the existing caption ink — no new values for the two shipped products |
| `everySentenceTheExpandedHeaderCanSayClearsTheCutOut`, `theExpandedWidthAnswersToTheMarksAndNotToUnreachableNames` | Both retire with the sentence they check. What replaces them is a test that the leading side clears the cut-out at four working agents, and that the panel is `520` at every cut-out this product meets |

This document depends on [`compact-view-v2.md`](compact-view-v2.md) being implemented first: the band draws that document's aggregate mark and that document's counts column, and it has no meaning while the collapsed bar still draws one matrix per product.
