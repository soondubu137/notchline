# The aggregate mark's ink — a palette, and the preference it became

> **Superseded, 2026-09-06.** The `Theme colour` picker this document designed is gone —
> `AggregateInk`'s twelve cases, the Display group's row, and the stored preference all retired
> together, along with the reference-specimen view they shared. The app now draws one fixed ink,
> `NotchPalette.themeInk` (`NotchStatusMatrix.swift`), holding exactly the `hint` row's `sage`
> values this document already recorded (`#1B1F1C` → `#DEE8E0`) — so nothing the palette actually
> reasoned about was wrong, only the choice of handing it to the user. This page stays as the
> record of that reasoning; do not build against it as a contract for a control that no longer
> exists. See `docs/artifacts.md` for the stale `aggregateInk` preference key this leaves behind.

> **Nothing here is void, and the palette's reach has grown.** [`colour-v2.md`](colour-v2.md)
> makes this the app's *only* hue: no product owns one any more, and the same twelve pairs now
> tint the badge that names a product on a row and in the footer — ground from the unlit value,
> text from the lit one. The picker is `Theme colour` rather than `Mark colour` for that reason.
> Two things below are affected and neither changes a value: §1's constraint is retired, and §7's
> reference mark now stands for more than the mark.

**Status: superseded — see the note above.** The twelve `hint` inks were `AggregateInk`, the picker was
the Display group's `Theme colour` (`Mark colour` until [`colour-v2.md`](colour-v2.md) §6, built 2026-09-05), §5's five questions are answered below in the
order they were asked, and §7 is what the row drew beside the names. What stays recorded rather than built is the other
twenty-four entries — `whisper` and `tint` — which no longer have a control to wait on.

The collapsed surface draws **one mark for every product at once**
([`compact-view-v2.md`](compact-view-v2.md) §2; the drawings are on
[Notchline V2](https://www.figma.com/design/c3CQBBk3Boiu0oM00Vvs9Y/Notchline-V2?node-id=2-2)).
With one aggregate mark, hue stops meaning *which product* and becomes free. This document records
the 36 inks that were drawn for it and the rule that generates them, and the choice is now the
user's rather than one made once here.

## 1. Why there is no single right answer

The obvious move — borrow the app's own colour — is not available. `design/assets/01-mark` is
Codex blue and Claude terracotta split on a diagonal and nothing else, so "Notchline's hue" is
the two products' hues. The aggregate mark cannot be either of them without claiming to be one
of them.

What is left is a constraint rather than an answer: ~~**the aggregate mark must never read as a dim
version of a product mark.**~~ **Retired by [`colour-v2.md`](colour-v2.md)** — there is no product
mark, and no product ink, for it to be a dim version of. Every entry below is now unconstrained by
anything except the two fixed lightnesses in §2, and the two `⚠` marks in §3 (within `20°` of a
product hue) mean nothing any more. They are left in place because the ordering they belong to is
shipped, and because this section is the argument that produced the default. Codex sits at `258°` in OKLCH and Claude Code at `42°`. The two hues
equidistant from both are `150°` (108° from each, the maximum any hue can be) and `330°` (72° from
each). Everything else is closer to one product than the other, and everything else is taste.

Taste is the user's, so the set is recorded whole and one entry is made the default.

## 2. The rule

Every ink is a pair — unlit and lit — generated from three fixed numbers and two that vary:

| | Value | Why |
| --- | --- | --- |
| Lit lightness | `L 0.922` | Exactly `#E5E5EA`'s lightness, the greyscale this replaces. |
| Unlit lightness | `L 0.235` | Exactly `#1E1E1E`'s. |
| Unlit chroma | `0.55 ×` the lit chroma | Products run theirs at ≈ `0.25 ×`; at these chromas that is invisible, so the ratio is raised until the dark grid carries the hue at all. |
| Hue | 12 values | §3. |
| Chroma | `0.008` / `0.016` / `0.028` | `whisper` / `hint` / `tint`. |

**The palette is the greyscale, rotated.** Lightness is identical for all 36 entries, so changing
colour cannot change brightness — and brightness is this surface's attention channel
([`dual-agent-design.md`](dual-agent-design.md) §10). A preference that could dim the mark asking
for a person would be a preference that changes what the mark *means*; this one cannot.

## 3. The 36

Hue distances are to Codex `258°` and Claude Code `42°`. The last column is whether the unlit
colour clears the resting grey's luminance — see §4.

| | Unlit | Lit | Chroma | Clears `#151515` |
| --- | --- | --- | --- | --- |
| **Steel** · 250° — 8° / 152° | | | | |
| whisper | `#1D1E20` | `#E1E6EA` | 0.008 | ✓ |
| hint | `#1B1E22` | `#DEE6F0` | 0.016 | ✓ |
| tint | `#191F25` | `#D8E7F8` | 0.028 | ✓ |
| **Ice** · 225° — 33° / 177° | | | | |
| whisper | `#1C1F20` | `#E0E6E9` | 0.008 | ✓ |
| hint | `#1A1F21` | `#DBE8ED` | 0.016 | ✓ |
| tint | `#162024` | `#D2EAF4` | 0.028 | ✓ |
| **Cyan** · 200° — 58° / 158° | | | | |
| whisper | `#1C1F1F` | `#DFE7E7` | 0.008 | ✓ |
| hint | `#191F20` | `#DAE9E9` | 0.016 | ✓ |
| tint | `#162021` | `#D1EBED` | 0.028 | ✓ |
| **Sea** · 172° — 86° / 130° | | | | |
| whisper | `#1C1F1E` | `#E0E7E4` | 0.008 | ✓ |
| hint | `#1A1F1E` | `#DBE9E4` | 0.016 | ✓ |
| tint | `#17211D` | `#D4ECE3` | 0.028 | ✓ |
| **Sage** · 150° — 108° / 108° ★ | | | | |
| whisper | `#1D1F1D` | `#E2E7E2` | 0.008 | ✓ |
| **hint (default)** | `#1B1F1C` | `#DEE8E0` | 0.016 | ✓ |
| tint | `#19201A` | `#D9EBDC` | 0.028 | ✓ |
| **Moss** · 118° — 140° / 76° | | | | |
| whisper | `#1E1E1C` | `#E4E6E0` | 0.008 | ✓ |
| hint | `#1E1F1A` | `#E4E7DB` | 0.016 | ✓ |
| tint | `#1D1F17` | `#E3E8D3` | 0.028 | ✓ |
| **Sand** · 92° — 166° / 50° | | | | |
| whisper | `#1F1E1C` | `#E7E5DF` | 0.008 | ✓ |
| hint | `#1F1E19` | `#E9E5DA` | 0.016 | ✓ |
| tint | `#211E16` | `#ECE5D1` | 0.028 | ✓ |
| **Clay** · 58° — 160° / 16° ⚠ | | | | |
| whisper | `#201E1C` | `#E9E4E0` | 0.008 | ✓ |
| hint | `#211D1A` | `#EEE3DB` | 0.016 | ✓ |
| tint | `#241C17` | `#F4E1D3` | 0.028 | ✓ |
| **Rose** · 25° — 127° / 17° ⚠ | | | | |
| whisper | `#201D1D` | `#EAE3E2` | 0.008 | ✓ |
| hint | `#221D1C` | `#F0E1E0` | 0.016 | ✓ |
| tint | `#251B1A` | `#F8DFDC` | 0.028 | ✓ |
| **Blush** · 0° — 102° / 42° | | | | |
| whisper | `#201D1E` | `#EAE3E5` | 0.008 | ✓ |
| hint | `#221C1E` | `#EFE1E5` | 0.016 | ✓ |
| tint | `#241B1E` | `#F6DEE4` | 0.028 | ✓ |
| **Mauve** · 330° — 72° / 72° ★ | | | | |
| whisper | `#1F1D1F` | `#E8E3E8` | 0.008 | ✓ |
| hint | `#211D20` | `#ECE2EA` | 0.016 | ✓ |
| tint | `#221C22` | `#F1DFEE` | 0.028 | ✓ |
| **Violet** · 292° — 34° / 110° | | | | |
| whisper | `#1E1E20` | `#E5E4EA` | 0.008 | ✓ |
| hint | `#1E1D22` | `#E5E4EF` | 0.016 | ✓ |
| tint | `#1E1D25` | `#E5E2F7` | 0.028 | ✓ |

★ equidistant from both products. ⚠ within 20° of a product hue — kept, because taste may win,
but never the default.

## 4. What every entry satisfies

- **Its unlit colour is brighter than the resting grey.** `#151515` is deliberately the darkest
  thing on the surface, so that "an agent is connected" never looks dimmer than "nothing is
  connected" ([`dual-agent-design.md`](dual-agent-design.md) §2, `NotchPalette.restingInk`). The
  darkest unlit here is `#191F20`'s `0.0125` against the resting grey's `0.0075` — the whole set
  clears it with room, because lightness is fixed at `L 0.235` and only chroma moves.
- **It cannot change how bright the mark gets.** §2.
- **It is a `MatrixInk`**, so nothing downstream changes shape: the four animation tracks, the
  `+0.06` chip lift, and the dissolve all read the pair and are indifferent to what is in it.

## 5. Making it a preference — what that still needs

1. **Does the resting grey take the hue?** ~~Recommend no.~~ **No, and implemented as no.**
   `#151515` means *nothing is connected*, and tinting it would say the user's colour applies to a
   state that has no agent in it. The hue arrives with the first connection —
   `NotchPalette.aggregateInk(_:isConnected:)` returns `restingInk` until then, and
   `theDisplayPreferencesReachTheSurfaceTheyDescribe` pins it.
2. **The user can now break §1's constraint.** ~~Recommend the picker orders by hue distance…~~
   **It does.** `AggregateInk.ordered` runs farthest-from-the-nearer-product first — Sage `108°`,
   then Sea, Moss, Mauve — and Steel `8°` last; nothing is blocked. It is their bar. ~~The two
   equidistant entries carry a `★` in the picker.~~ **They no longer do**: the ordering is the
   argument, and a star beside two of twelve names reads as a rating on a choice nobody is
   marking. `isEquidistantFromBothProducts` still picks the default and still sorts the list; it
   is simply not said out loud any more. §7 is what the row spends that space on instead.
3. **36 rows is too many for a Settings list.** **12 at `hint`**, as recommended. `whisper` and
   `tint` are recorded here and are not offered; an intensity control can come later if it earns
   its place.
4. **Where it lives.** [`figma-design.md`](figma-design.md) §8.4 `Display`, second row, above
   `Hide the wings` (now `Hide Notchline`).
5. **What existing installs get.** Sage · hint, `#1B1F1C` → `#DEE8E0` — the same as everybody else,
   because until this preference existed the mark was drawn at exactly it. There is no hue to
   migrate.

## 6. The picker

The swatches were chosen against a live page that draws all 36 in the real Running state — the
48-frame loom track from `MatrixTrack.loom`, each cell delayed by its own place on the ring it sits on —
with controls for both lightnesses, a chroma multiplier and the unlit ratio, at sizes down to the
true `16.6`. It generates the `MatrixInk` for whatever is selected.

The local prototype and its generators have been removed. This table preserves their output; rebuild the page from these parameters if it is needed again.

**The Settings feature is built and the page did not have to come with it**: §3's table is the
whole input, `AggregateInk` carries the twelve `hint` pairs verbatim, and what the picker needed on
top of them was an ordering rule rather than a re-look at the swatches. The page earns its place
again only if the other two chromas are ever offered.

## 7. The reference mark

**The row shows the mark, not a swatch.** What it hands over is the ink of the one 5×5 mark the
collapsed surface draws — on black, at `16.6 pt`, lighting and falling away on a pattern — and a
disc of the lit value said almost none of that. Worse, it said it at the one lightness the whole
palette shares (§2): twelve discs at `L 0.922` and `C 0.016` are twelve pale circles, so the
control that existed to distinguish the hues was the place they were hardest to tell apart.

So the popup carries plain names, and beside it stands a specimen: `NotchStatusMatrix` at
`PanelMetrics.statusMatrixSize` on the same `NotchChip` the first-run legend uses, in the selected
ink.

- **At rest it is `inactive`** — dim, still, and the honest answer to what the mark looks like on a
  bar with nothing waiting on anybody.
- **A change of selection runs `running` twice round**, `2.4 s`, two whole turns of the loom. The
  hue is then seen lit, mid-decay and nearly out *at the same instant*, which is the range the eye
  wants drawn side by side rather than one reading after another.
- **It starts at its first frame** (`NotchStatusMatrix.startsAtItsFirstFrame`). A mark on the bar is
  anchored to a per-period grid so two of them saying the same thing say it in step; a specimen has
  nothing beside it to be in step with and runs for a counted two loops, so the grid would only
  start the rings at whatever bearing the clock was at and stop them the same distance short.
  Changing hue mid-sweep restarts it in the new colour rather than queueing behind the old one.
- **It cuts in and dissolves out**, both from the rule the mark already has
  (`MatrixIndicatorView.dissolves(from:to:)`) rather than from anything this row asks for: a hue
  change is a different drawing, so the sweep lands on the press; the return is the same ink
  changing state, so the loom sinks back into the still instead of snapping to it.

### Why the loom and not the double knock

The first build of this ran `approvalNeeded`. Both patterns loop in `1.2 s`, so the only thing
separating them is how much of that loop has colour in it — and the knock is mostly dark by design.
It is two beats `300 ms` apart and then `900 ms` at `0.05`, the darkest this surface ever goes: for
**20 of its 36 frames every cell together sits at or under `0.142`**, below even the `0.150` the
resting mark holds. Judging `Rose` against `Clay` from that means judging it from four flashes.

The loom always has two ring heads on the grid and a lit pivot between them, so it is never off
anywhere:

| Measured over one loop | Loom (`running`) | Double knock (`approvalNeeded`) |
| --- | --- | --- |
| Brightest cell, worst frame | `0.830` | `0.050` |
| Mean cell level, range across frames | `0.353` – `0.362` | `0.050` – `1.000` |
| Frames at or below the resting `0.150` | none | 20 of 36 |

Two `1.2 s` loops of the loom therefore show the hue continuously; two of the knock showed it for
about a tenth of the time it was on screen. The knock's other supposed advantage — that it has no
spatial reading to compete with the colour — turns out to be the same fact stated kindly: what it
has instead of a reading is silence.

> **The loom is the steadiest thing this row has ever run.** Its mean moves only between `0.353`
> and `0.362` across the whole loop — the radar's band was `0.330`–`0.417` and the rain's
> `0.253`–`0.309` — so the hue is held at very nearly one level while the shape underneath it
> keeps moving. That is what a swatch wants and what neither of the other two could give.

> The knock figure here was once `22 of 36`; its track has 20 samples at or under `0.150`, and 20
> is also the count at or under `0.142`. Corrected in passing.
