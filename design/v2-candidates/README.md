# Notchline V2 logo candidates

Five marks to choose between. Nothing here is shipped: `design/assets` is
still V1's set and stays that way until one of these is picked, at which
point it gets built out the way that folder is — mark, lockups, app icon,
menu bar templates, favicon, README.

The pitch, with the reasoning and the specimens at any size:
<https://claude.ai/code/artifact/224f9463-fca2-49c4-a5fe-8b7a900df7eb>

## The brief

V1 kept the app's identity in **colour** — Codex blue and Claude
terracotta, split on a diagonal, and nothing else. V2 took that channel
away, in three moves:

| | V1 | V2 |
| --- | --- | --- |
| Grid | 4×4, viewBox 123 | **5×5**, viewBox 155 — same 27/32 pitch, the cell paid for the row |
| Marks | one matrix per product | **one aggregate mark** for every product at once |
| Hue | said *which product* | **the user's** — 12 near-neutrals in Settings, default Sage |

So the constraint is narrow: **a mark whose colour the user chooses cannot
be identified by its colour.** Every candidate has to be recognisable as a
shape. The five span one axis on purpose — how much of the two-product
identity the brand keeps, now that the product itself dropped it.

## The five

| | Direction | Ink | Cells |
| --- | --- | --- | --- |
| `01-fifth-row` | V1's out-of-phase halves, redrawn native to the odd grid. The new centre cell is cut on the diagonal and carries the seam. | both products | 21 |
| `02-seam` | One solid square divided by a single diagonal — what `NotchPalette.MatrixSplit` already describes. Each half falls to 0.55 at the cut. | both products | 25 |
| `03-bars` | The Completed pattern at frame 0: three level rules at 1.00 / 0.80 / 0.43 with a clear row between. **Recommended.** | aggregate | 25 |
| `04-notch` | Row 0 keeps only its outer two cells — the menu bar with the notch taken out — and the panel hangs below it. | aggregate | 22 |
| `05-wedge` | The Input-needed pattern's front, drawn directly rather than sampled. | aggregate | 25 |

Three of the five come from the app's own animation tracks. `03-bars` is a
real frame. `05-wedge` is **not**, and that is deliberate: the wedge takes
the distance behind its front *around* the grid, so every one of its forty
frames has tail cells re-lit on the far side and reads as scatter when
held still. Rain wraps the same way and fails the same way, which is why
there is no Running candidate. Both were drawn to be watched; a logo is
looked at once.

## Treatments

The two V1 defined, unchanged — see `design/assets/README.md`:

- **paper and transparent** — the lit ink *thinned* by the cell's level.
- **black** — the lit ink *blended* toward that ink's own unlit colour,
  fully opaque.

The aggregate candidates add the one thing the palette forces. Sage's lit
`#DEE8E0` is all but invisible on white, so on paper an aggregate mark
**inverts** and is drawn in its unlit `#1B1F1C` instead — a near-black
that still carries the hue. That inversion is the point: it is what lets
one mark survive all twelve preferences and still work as a menu bar
template.

There is no lift under the thinning. A lifted floor was tried and is
wrong: on black a cell at the floor all but disappears, so a paper cell
that stays plainly visible turns `03-bars`' three rules into five and
reports a pattern the app does not draw.

## Contents

Per candidate: `mark`, `horizontal` and `icon` as SVG, plus PNG at
512/128/32 for the mark and 1024 for the lockup. Marks and lockups come on
all three grounds (transparent, `-white`, `-black`); the icon is black
only, an 824 body in a 1024 canvas at 185.4 radius, with the mark held at
V1's 512-unit optical size.

Clear space is V1's: one pitch, 32 units, on all four sides, baked in.

## Regenerating

```bash
python3 design/v2-candidates/gen_candidates.py
```

Geometry comes from `MatrixGrid` and the frozen patterns from
`MatrixTrack`, both in `Notchline/Notchline/NotchStatusMatrix.swift`, via
the same formulas `docs/assets/gen_matrices.py` uses. If the Swift moves,
regenerate rather than redraw.

PNGs are rasterised with `qlmanage`, which is the only rasteriser on this
machine and is approximate about scale. The SVGs are the masters; treat
the PNGs as previews until a candidate is chosen.
