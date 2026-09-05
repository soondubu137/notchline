# Notchline V2 logo assets — Terrace

*Download package. Folder layout mirrors `design/assets/` so it can be dropped in
as the V2 replacement.*

**Direction:** *Terrace / one mass, five steps.*

The mark is one connected mass on the app's own 5×5 status matrix (`MatrixGrid` in
`Notchline/NotchStatusMatrix.swift` — 27-unit cells on a 32 pitch, 2-unit corner
radius, 155 viewBox), hanging from the top edge with column heights 5, 4, 3, 2, 1.

15 cells, square footprint. **The level steps down with the mass, one step per
column:** `1.00 / 0.80 / 0.60 / 0.40 / 0.20`.

Every cell shares an edge with another cell. That is the rule this mark is drawn
to: one figure, no floating groups, no cells joined only at a corner. V1's mark
fails it — its two halves never touched.

## Why it looks nothing like V1

V1 kept the identity in **colour**: Codex blue and Claude terracotta, split on a
diagonal, and nothing else. V2 took that channel away in three moves.

| | V1 | V2 |
| --- | --- | --- |
| Grid | 4×4, viewBox 123 | **5×5**, viewBox 155 — same 27/32 pitch, the cell paid for the row |
| Marks | one matrix per product | **one aggregate mark** for every product at once |
| Hue | said *which product* | **the user's** — 12 near-neutrals in Settings, default Sage |

A mark whose colour the user chooses cannot be identified by its colour, so this
one is a shape in a single ink. What V1 spent on hue, it spends on level.

## Ink

**How it dims depends on the ground.** A dark background and a light one want
opposite things, so there are two treatments and the assets already use the right
one:

| Level | Paper / transparent — ink **thinned** | Dark — ink **blended**, fully opaque |
| --- | --- | --- |
| 1.00 | `#1B1F1C` | `#DEE8E0` |
| 0.80 | `#1B1F1C` @ 0.80 | `#B7C0B9` |
| 0.60 | `#1B1F1C` @ 0.60 | `#909892` |
| 0.40 | `#1B1F1C` @ 0.40 | `#696F6A` |
| 0.20 | `#1B1F1C` @ 0.20 | `#424743` |

The pair is Sage · hint, `NotchPalette.defaultAggregateInk` — `#1B1F1C` unlit and
`#DEE8E0` lit. **The brand takes the unlit end on paper and the lit end on dark.**
That inversion is the point: Sage's lit `#DEE8E0` is invisible on white, and the
other eleven Mark colour preferences would each want their own file. One mark
survives all twelve because it never claims to be any of them.

The dark values are the app's own compositing, not a picked ramp: a cell at level
*L* is the unlit colour with the lit colour over it at alpha *L*. Never use the
blended treatment on paper — `#424743` on white is a hole. Never use the thinned
treatment on black — the ground swallows it.

## Clear space in the files

Every mark and lockup file carries **one pitch of clear space** (32 units, 21% of
the mark) on all four sides, baked in. The named PNG size is the **full image
width**, padding included.

Three files are deliberately tight to their own box, because they fill a
fixed-size slot the OS or browser supplies: the app icon (which has Apple's own
100-unit inset), the menu bar template, and the favicon.

## Wordmark

Tahoma Regular, tracking 0 — unchanged from V1. Measured metrics for
"Notchline": advance **4.106 em**, ascender height **0.7598 em**.

Both lockups align on the **ink box** — the painted extents, not the advance
width — so the 0.0737 em left bearing and the 0.0151 em descender overshoot are
accounted for: ink box 4.0059 em wide × 0.7749 em tall.

- **Horizontal lockup** — the wordmark's painted height equals the mark's height
  (font size = mark / 0.7749 = mark × 1.290). Gap = mark height × 0.354.
  At the 155 mark: font 200.03, gap 54.87, box 1075.15 × 219.
- **Stacked lockup** — the wordmark's painted width equals the mark's width
  (font size = mark / 4.0059 = mark × 0.2496). Gap = mark width × 0.117.
  At the 155 mark: font 38.69, gap 18.14, box 219 × 267.12.

## Contents

| Folder | Contents |
| --- | --- |
| `01-mark` | SVG and PNG (1024/512/256/128), transparent / white / black |
| `02-horizontal` | SVG and PNG (1024/512/256/128 wide), three grounds |
| `03-stacked` | SVG and PNG (1024/512/256/128 wide), three grounds |
| `04-app-icon` | macOS icon — 824 body in a 1024 canvas, 185.4 radius, on `#0A0A0B`; PNG 1024/512/256/128/64/32/16 |
| `05-menubar` | Template images: black at per-cell alpha, 16/18/22 pt at 1× and 2× |
| `06-favicon` | SVG and PNG 16/32/48 |
| `07-readme` | 1200 px horizontal lockup for the README header, light and dark |

**The named PNG size is the full image width, clear space included.** Every
ground-less raster was scanned after export: the ink touches no edge, so the one
pitch of clear space is intact in the files themselves.

## Rules

- Clear space: one pitch (32 units, 21% of the mark) on all four sides.
- Minimum sizes: mark 16 px; horizontal lockup 110 px wide; stacked 64 px wide.
  Below 16 px use the menu bar template, which is drawn for that size.
- **The 0.20 column is the first thing to go at small sizes.** That is intended —
  the mark thins out as it goes — but check 16 px on a 1× display before shipping
  any new size.
- Do not recolour the mark to match a user's Mark colour preference. The
  preference applies to the app's status matrix, not to the brand.
- Do not add a product hue: blue or terracotta now claims to be one of the two
  products.
- Do not flatten the ramp, add a sixth step, close the staircase, or add a
  container to the bare mark.

## Notes

- SVG wordmarks are **live Tahoma text**, with `textLength` **and
  `lengthAdjust="spacingAndGlyphs"`** pinning the measure: Tahoma's own advance at
  the lockup size is exactly the pinned 821.31, so with the font present the scale
  is 1.0 and nothing moves — and a substituted face (Verdana measures 936.18 at
  the same size) is squeezed to that measure instead of overrunning the box.
  Convert to outlines anyway before shipping the SVGs somewhere Tahoma may be
  absent; the PNGs here are already flattened, rendered with real Tahoma.
- To build `.icns`: copy `04-app-icon`'s PNGs into
  `Notchline.iconset/icon_<size>x<size>.png` (and `@2x` — 32 is 16@2x, 64 is 32@2x,
  256 is 128@2x, 1024 is 512@2x) and run `iconutil -c icns Notchline.iconset`.
- The 2× menu bar files are named `-2x`. Rename to `@2x` when dropping them into
  an Xcode asset catalog.
- Geometry comes from `MatrixGrid` in `Notchline/Notchline/NotchStatusMatrix.swift`.
  If the Swift moves, regenerate rather than redraw.
