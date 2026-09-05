# Notchline — Quota footer V2

| Field | Value |
| --- | --- |
| Status | **Designed, not implemented.** Nothing here depends on a capability the app does not have; the data model already is a list of products each holding a list of windows (`MonitorStore.footerRules`), and only the layout is written for two. |
| Version | 2.0 |
| Date | 2026-09-04 |
| File | [Notchline V2](https://www.figma.com/design/c3CQBBk3Boiu0oM00Vvs9Y/Notchline-V2) — `07 — The quota footer` |
| Scope | The expanded panel's footer only: the quota rules and today's tokens. The band is [`expanded-header-v2.md`](expanded-header-v2.md), the session list is [`expanded-panel-v2.md`](expanded-panel-v2.md), and both collapsed forms are [`compact-view-v2.md`](compact-view-v2.md). None is touched, and the panel's width does not move. |
| Supersedes | [`dual-agent-design.md`](dual-agent-design.md) §5.1 (structure and the four heights), §5.2 (which windows are drawn), and §5.4 in every part except the control's own geometry. |

## 1. What V2 changes here, and why

The footer is the last surface on this panel still drawn per product, and it fails in three places at once.

**Width is split per window, and the caption breaks first.** Codex takes the full `496` because it has one window; Claude Code is halved because it has two. That is not a rule that generalises — it is two products' window counts written down as a layout. Thirds are `160`, and `5 h · 59% left · Resets in 2 hours` measures about `182` at 11 pt, so the captions collide well before the rules look crowded.

**So a window was removed from the design rather than from the product.** `/usage` reports three windows and §5.2 draws two, fixed, because the third has nowhere to go — and §5.2 records the cost in its own words: *a user who exhausts the per-model weekly cap sees two healthy rules and is still refused.* It is the one place in V2 where a limitation of the drawing is paid for in what the user is told.

**Height grows per product, and the two single-product forms are different shapes.** `84` with both, `53` with Claude Code alone, `30` with Codex alone, `31` more for a third. §5.1 records the single-product asymmetry as known and accepted; it is the same failure at the smallest count there is.

**And the today line enumerates products in words.** `Codex 310.1M · Claude Code 208.6M today` is about `230` at two products and `340` at three, against the `496` it has. It also carries a conditional nothing else on the panel needs — name the products only when there are two — where every other surface answers whose a number is with colour, for no width at all.

**V2 gives the footer the band's own shape.** A minimum is ordinal, so it folds to one member. A sum is cardinal, so it decomposes into parts. Ordinal facts fold; cardinal facts decompose — [`expanded-header-v2.md`](expanded-header-v2.md)'s sentence, applied at the other end of the same panel.

## 2. Composition

**The summary — `53`, at every product count and every connected form.**

```
12 →  ═════════════════════════════════════════════ ← 508    496 × 3, the tightest window, its product's ink
      Claude Code · 5 h · 59% left · Resets in 2 hours    ⌄
      518.7M today · 310.1M · 208.6M
      ─ 6 ─
```

| Term | Value | Constant it already is |
| --- | --- | --- |
| Rule | `3` | `footerRuleHeight` |
| Rule to its caption | `5` | `footerCaptionSpacing` |
| First caption line, carrying the control | `16` | `quotaFoldControlSize` |
| Every other caption line | `14` | `footerCaptionHeight` |
| Between one block and the next | `9` | `footerRuleSpacing` |
| Today's line | `14` | `footerCaptionHeight` |
| Below the last line | `6` | `footerBottomMargin` |

```text
summary  =  24 + 9 + 14 + 6                     =  53
list     =  24 + 9 + 31 × (n − 1) + 14 + 6      =  31n + 22
```

`n = 1` gives `53`, which is why a product with one window has nothing to open and draws no control — and the line that control would ride is still billed at `16`, which is what holds the footer at `53` in every form. **No new measurement is introduced on this page**, and `footerInlineRuleBlockHeight` — the constant that exists today only to serve the Codex-only special case — becomes the first block of every footer.

## 3. The summary

One rule, at the full `496`, for **the tightest window anywhere**: the lowest remaining percentage across every window of every connected product. Ties go to whichever resets soonest, then to Settings' order.

The caption reads `<Product> · <window> · <n>% left · Resets <when>`, and **names only what distinguishes**:

| Connected | Windows | Caption |
| --- | --- | --- |
| Codex alone | 1 | `72% left · Resets in 3 days 12 hours` |
| Claude Code alone | 2 | `5 h · 59% left · Resets in 2 hours` |
| Both | 3 | `Claude Code · 5 h · 59% left · Resets in 2 hours` |

That is `showsProductAttribution`'s own rule applied to a caption instead of a row: the product is named when more than one is connected, and the window when its product has more than one.

**The product's name takes its caption ink and the rule above it its lit one** — `#4D81B7` under `#6CB4FF`, `#9C553E` under `#D97757` — the pair a session row already uses. The footer therefore teaches the hue mapping in the same glance it uses it, which is what lets §5 name nobody at all.

**Below 15% the `n% left` clause steps from `#7C7C80` to `#C7C7CC`.** Brightness, not hue: hue means product everywhere on this panel and cannot mean urgency here, so the usage ring's amber and red ([`figma-design.md`](figma-design.md) §4.3) do not travel. The structural guard matters more than the treatment — the tightest window is the one drawn, so the limit about to stop you can never be the one you did not open the list to find.

## 4. The list

The control opens the summary into every window, **one full-width rule and caption each, sorted tightest-first**.

| | Rule | |
| --- | --- | --- |
| 01 | **What folds is a minimum, and a minimum has one member.** The band folds status and draws no parts because its decomposition would be one animated mark per agent. The tightest window *is* a member of the set, so the fold and the first row of the list are the same object: opening adds rows beneath and changes nothing already on screen | |
| 02 | **Tightest-first, and that contradicts a settled rule deliberately.** [`expanded-header-v2.md`](expanded-header-v2.md) §4.3 rule 02 says nothing re-sorts. That rule governs per-agent counts, which change many times an hour, where a column closing up under the eye is a real cost. A window's remaining share moves on the scale of hours and resets on a schedule, and tightest-first is the only order that makes the folded form a truthful summary of the open one — Settings' order would make the fold arbitrary | §8.1 |
| 03 | **Windows stack; they never share the width.** Halving worked only because Claude Code's two captions happen to be short. A full-width rule is also the most readable form of the gauge, and a full-width caption the only one that can carry four clauses. Stacking costs height, and height is what a control is for | |
| 04 | **The control rides the first caption line, not the last, and that fixes a known trap.** §5.4 records that folding the quota usually closes the panel: the chevron sits `6` to `22` above the bottom edge and folding lifts that edge past a still pointer. On the first caption line it stands `29` above the folded bottom edge and never travels, so folding at any window count leaves the pointer inside. The `16 × 16` hit area, the `9 × 4.5` glyph and the `1.4` stroke are unchanged | |
| 05 | **Folded is the default, and the `22` pt form goes.** §5.4's fold existed to put `62` points of rules away; the summary answers the same question in one `24` pt block, so there is nothing left worth hiding and no third state | §8.3 |
| 06 | **A window with no answer is never the summary.** It has no percentage, so it cannot be a minimum. It is drawn in the list as an empty track reading `-- left` ([`figma-design.md`](figma-design.md) §6.2), sorted last because it cannot be ranked. With every window unavailable the summary is an empty track on the first window in Settings' order | §8.5 q02 |
| 07 | **§5.2's excluded third window comes back, for free.** The per-model weekly cap was dropped because there was no half left to put it in. In a list it is one more line, drawn when the product reports it — and where it sits permanently at 100% for someone who never uses that model, it is never the tightest and never surfaces | §8.2 |

## 5. Today's tokens

`518.7M today · 310.1M · 208.6M` — the total in `#C7C7CC`, `today` in `#7C7C80`, and one part per product in that product's **lit** ink.

| | Rule | |
| --- | --- | --- |
| 01 | **The total is always drawn; the parts arrive beside it.** [`expanded-header-v2.md`](expanded-header-v2.md) §4.1 rule 01 — expanding adds rather than replaces, so the figure the eye was on does not move, change colour or go away when a second product starts spending | |
| 02 | **One part per product that has spent something today, in Settings' order, packed.** A product with nothing today has no part — a zero is never drawn here — and the parts after it close up | |
| 03 | **With one part there are no parts.** A decomposition into one term is the total said twice (§4.3 rule 07), so a single-product footer reads `310.1M today` in grey and colour arrives with the second product | |
| 04 | **No product is ever named here.** Colour says which, for no width at all, and the rule above has already taught the mapping. This removes §5.4's *name the products only when there are two*, and with it the last piece of per-product prose on the panel | |
| 05 | **The two inks are the band's own two-step, rotated into hue.** `#C7C7CC` over `#6CB4FF` / `#D97757` — §4.3 rule 03. No new value | |
| 06 | **It scales as numerals rather than as names.** About `160` at two products and `215` at three, where the words were `230` and `340`. Eight products fit in the `496` where four did not | |

## 6. Heights

| Connected | Windows | Footer today | Footer now | Panel today | Panel now |
| --- | --- | --- | --- | --- | --- |
| Codex alone | 1 | `30` | **53** | 316 | **339** |
| Claude Code alone | 2 | `53` | **53** | 339 | **339** |
| Both products | 3 | `84` | **53** | 370 | **339** |
| Three products | 4 | `115` | **53** | 401 | **339** |
| Four products | 5 | `146` | **53** | 432 | **339** |

Panel figures are `46 + 240 + footer` — three live rows at the reference menu bar.

Opened, the footer is `31n + 22`: `53` at one window (nothing to open), `84` at two, `115` at three, `146` at four, `208` at six.

**The `23` points the Codex-only machine pays is the price of one shape**, and it is the same trade [`expanded-header-v2.md`](expanded-header-v2.md) §1 made for the band: a surface that is two sizes depending on what happens to be connected, and that changes size the first time a second agent connects, is worse than a surface that picks one and holds it.

## 7. Accessibility

- The summary rule's accessible name is `Tightest limit: Claude Code 5 hour window, 59% remaining, resets in 2 hours`.
- The control is `Show all 3 limits` / `Show fewer`, and the list's rows are read in the order they are drawn.
- Today's line spells the colour out: `518.7 million tokens today; Codex 310.1 million, Claude Code 208.6 million` — the answer §9 already gives for the band's colour-coded columns, with the same permanently fixed order behind it.
- The `--` of an unavailable window is spoken as `unavailable`, never as zero.

## 8. What this reaches outside the footer

### 8.1 One settled rule is contradicted deliberately

[`expanded-header-v2.md`](expanded-header-v2.md) §4.3 rule 02. §4 rule 02 above sets out why a list of limits is the exception and why the band's columns are not.

### 8.2 A recorded risk is fixed for free

[`dual-agent-design.md`](dual-agent-design.md) §5.2's per-model weekly cap. Its whole argument — *letting one half report different windows at different times turns a rule meant for a glance into one that must be read first* — was about a **half**, and there are no halves any more.

### 8.3 The default inverts, and the setting is renamed so that is visible

`quotaFolded` (default `false`) becomes `quotaExpanded` (default `false`): the same default value with the opposite meaning. Today the footer opens showing every rule; now it opens showing the summary. A rename rather than a flipped boolean, so a reader of the diff cannot miss which way it went.

### 8.4 Five constants and one special case retire

`expandedFooterHeight`, `claudeCodeOnlyFooterHeight`, `dualFooterHeight`, `foldedFooterHeight` and `footerWindowSpacing`, together with §5.4's Codex-only exception and `foldingKeepsTodaysTokensInEveryShape`. What replaces them is one constant and one function of a window count. `footerInlineRuleBlockHeight` survives and stops being a special case.

**And the panel's expanded height stops answering to what is installed** — `339` at three rows on every machine with the summary showing. That is the property the collapsed bar bought on page 01 and the band on page 05; the footer was the last surface without it.

### 8.5 Open questions

| | Question | Where it stands |
| --- | --- | --- |
| 01 | Is the tightest window the right representative, or should it be the one for the product being worked in? | **Standing recommendation: the tightest.** The panel is for both products at once and the band already summarises across them; a per-product answer would need to know which product the user is "in", which this app deliberately never infers. The cost is real — a Codex limit at 5% is drawn while you are in Claude Code — but it is the cost the aggregate mark already accepts, and the alternative hides the limit that will stop you |
| 02 | Should the summary say that a window is unanswerable? | **Open, and the one thing the fold genuinely hides.** Candidates: a dimmed marker after the caption, or nothing. Recommended nothing — the state resolves itself on the next read, so a marker would be drawn far more often than it is true |
| 03 | Does `53` hold under a 22 pt menu bar? | **Answered — yes.** Nothing in the footer is a share of the panel's height; every term is a fixed point value and the control is `16` whatever the bar is. Only the gear tracks the bar, and the gear is in the band |
| 04 | Should the list scroll rather than grow past some window count? | **Standing recommendation: grow.** Six windows is `208`; a scroll region inside a footer inside a hover-held panel is a worse object than a tall footer somebody opened on purpose. Revisit if a product reports more than four windows of its own |
| 05 | What ink does a third product's rule take? | **Out of scope, unchanged.** [`expanded-header-v2.md`](expanded-header-v2.md) §10 question 03 closed it and struck the placeholder values; the board draws a third and fourth product neutral so nothing can be built against a colour. Nothing in this page's geometry depends on the answer |

## 9. Verification

- [ ] The footer is `53` with one product, two, three and four connected, and at one window or six.
- [ ] The rule drawn folded is the tightest window across every connected product, not the first in Settings' order.
- [ ] A product is named only when more than one is connected; a window only when its product has more than one.
- [ ] Opening the list changes nothing on the first line and adds rows beneath it.
- [ ] The list is sorted tightest-first, with unanswerable windows last.
- [ ] Folding from any window count leaves the pointer inside the panel.
- [ ] `n% left` draws `#C7C7CC` below 15% and `#7C7C80` above it, and no rule ever changes hue.
- [ ] Today's line draws the total always, one part per product that spent something, no parts with one such product, and no product name at any count.
- [ ] Every window the product reports is drawn in the list, the per-model weekly cap included.
- [ ] The footer draws identically under a `46` pt menu bar and a `22` pt one.
- [ ] The panel is `339` at three live rows with the summary showing, on every connected form.

## 10. Implementation mapping

Nothing here is implemented. The data model needs no change — `footerRules` already returns one `FooterRule` per connected product, each holding its `FooterWindow`s.

| Symbol | Change |
| --- | --- |
| `PanelMetrics.footerHeight(rules:isFolded:)` | Becomes `footerHeight(windowCount:isExpanded:)`: `53`, or `31n + 22` when expanded. The four constants behind it go |
| `PanelMetrics.footerWindowSpacing` | **Retired** — nothing shares a width |
| `MonitorStore.footerRules` | Flattens to `footerWindows: [FooterWindow]` carrying its agent, sorted by remaining share ascending with unanswerable last; `tightestWindow` is its first member |
| `MonitorStore.footerTodayText` | Loses its `rules.count > 1` guard and its product names; returns a total plus zero or more coloured parts |
| `MonitorStore.quotaFolded` | Renamed `quotaExpanded`, default `false` (§8.3) |
| `ExpandedPanelFooter` / `FooterRuleRow` / `QuotaFoldLine` | One row type instead of three: a rule and a caption, drawn once folded and `n` times expanded, with the control on the first caption line |
| `aFoldedFooterIsTheSameHeightForEveryShape` | Becomes `theFooterIsOneHeightForEveryConnectedForm`, and `foldingLiftsThePanelsBottomEdgePastTheChevronThatWasClicked` inverts into `foldingCannotStrandThePointer` |

[`dual-agent-design.md`](dual-agent-design.md) §5.1, §5.2 and §5.4 need amending before any of it is built.
