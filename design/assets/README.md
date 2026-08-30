# Notchline logo assets

**Direction:** *Out of Phase / Outward 50%.*

The mark is the app's own 4x4 status matrix (`MatrixGrid` in
`Notchline/NotchStatusMatrix.swift` — 27-unit cells on a 32 pitch, 2-unit
corner radius, 123 viewBox) with its two halves stepped one row apart:

- **Codex** — columns 0-1, rows 0-2
- **Claude Code** — columns 2-3, rows 1-3

12 cells, square footprint. Each half is at full strength at its far edge and
falls to half strength at the seam — in three steps, 1.00 / 0.75 / 0.50.

**How it dims depends on the ground.** A dark background and a light one want
opposite things, so there are two treatments and the assets already use the
right one:

| Ground | Treatment | Codex | Claude Code |
| --- | --- | --- | --- |
| transparent, white | the lit ink **thinned** (alpha 1.00 / 0.75 / 0.50) | `#6CB4FF` | `#D97757` |
| black | **blended** toward that product's own unlit ink, fully opaque | `#6CB4FF` `#558EC9` `#3E6893` | `#D97757` `#AB5E45` `#7D4532` |

The blend targets are `NotchPalette`'s unlit inks, `#101B26` and `#21120D`.
Never use the black treatment on paper: `#101B26` on white is a hole, not a dim
cell. Never use the thinned treatment on black: the ground swallows it.

## Clear space in the files

Every mark and lockup file carries **one pitch of clear space** (32 units, 26% of
the mark) on all four sides, baked in — nothing sits on a cut edge. The named
PNG size is the **full image width**, padding included.

Three files are deliberately tight to their own box, because they fill a
fixed-size slot the OS or browser supplies: the app icon (which has Apple's own
100-unit inset), the menu bar templates, and the favicon.

## Wordmark

Tahoma Regular, tracking 0. Measured metrics for "Notchline": advance
**4.106 em**, ascender height **0.7598 em**.

Both lockups align on the **ink box** — the painted extents, not the advance
width — so the 0.0737 em left bearing and the 0.0151 em descender overshoot are
accounted for: ink box 4.0059 em wide x 0.7749 em tall.

- **Horizontal lockup** — the wordmark's painted height equals the mark's
  height (font size = mark / 0.7749 = mark x 1.290). Gap = mark height x 0.354.
- **Stacked lockup** — the wordmark's painted width equals the mark's width
  (font size = mark / 4.0059 = mark x 0.2496). Gap = mark width x 0.117.

## Contents

| Folder | Contents |
| --- | --- |
| `01-mark` | SVG and PNG (1024/512/256/128), transparent / white / black |
| `02-horizontal` | SVG and PNG (1024/512/256/128 wide), three backgrounds |
| `03-stacked` | SVG and PNG (1024/512/256/128 wide), three backgrounds |
| `04-app-icon` | macOS icon — 824 body in a 1024 canvas, 185.4 radius, on `#0A0A0B` |
| `05-menubar` | Template images: black at per-cell alpha, 16/18/22 pt at 1x and 2x |
| `06-favicon` | SVG and PNG 16/32/48 |
| `07-readme` | 1200 px horizontal lockup for the README header, and the architecture diagram (`notchline-architecture*.svg`, light and dark) |

## Rules

- Clear space: one pitch (32 units, 26% of the mark) on all four sides.
- Minimum sizes: mark 16 px; horizontal lockup 110 px wide; stacked 64 px wide.
  Below 16 px use the menu bar template image, which is drawn for that size.
- On black the 0.50 cells go quiet against the app's real unlit inks. That is
  intended — it is what the mark does in the notch.
- Do not recolour a half, close the stagger, add a container to the bare mark,
  or set both halves at equal brightness.

## Notes

- SVG wordmarks are **live Tahoma text**, with `textLength` pinning the advance
  so a fallback font still keeps the measure. Convert to outlines before
  shipping them anywhere Tahoma may be absent; the PNGs are already flattened.
- The 2x menu bar files are named `-2x`. Rename to `@2x` when dropping them
  into an Xcode asset catalog.
- To build `.icns`: put the `04-app-icon` PNGs into
  `Notchline.iconset/icon_<size>x<size>.png` (and `@2x`) and run
  `iconutil -c icns Notchline.iconset`.
