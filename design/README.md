# Figma Design

Figma：[Codex in Notch — V1](https://www.figma.com/design/B9qIi46zhdjbQYbjZo3AnM/Codex-in-Notch-%E2%80%94-V1)

Design Doc：[figma-design.md](../docs/figma-design.md)

## The README hero

`assets/07-readme/notchline-hero.webp` is an animated WebP: 1760x552 canvas,
323 frames at 40ms (25fps), infinite loop, ~1.05MB. It is the `design/*.mov`
screen recording (3600x1130, gitignored) at its **full frame ratio** — the
recording is framed as the top strip of the display, and cropping in on the
panel throws away the one thing the two figures below cannot show: where the
panel sits. Trimmed to 3.2s-16.1s so the loop opens and closes on the compact
bar.

**How to rebuild:** decode with `AVAssetReader` (sequential; per-frame
`AVAssetImageGenerator` seeking is far slower), scale with `CIContext`, then
encode in Pillow with `save_all=True, duration=40, loop=0, quality=80,
method=6, minimize_size=True`. **`minimize_size` is not optional** — the same
323 frames encode to 6.5MB without it and 1.07MB with it, and a 1:1 comparison
against the source frames shows no loss at q80. Verify by parsing the RIFF
chunks for the `ANIM` loop count and the `ANMF` durations; Pillow reports WebP
frame duration as `None` on read even when the file is correct.

GitHub serves a relative-path `.webp` as `image/webp` into a plain `<img>`, and
strips `style`, so any rounding or shadow would have to be baked into the
frames. This figure has none: it is a screen crop that bleeds to its own edges,
like the two figures below.

## The README anatomy figure

`assets/07-readme/notchline-anatomy.png` is generated, not drawn. Both specimens
on it are `NotchOverlayView` over a fixed `MonitorStore`, and every label is
anchored to a `PanelMetrics` figure rather than to a point read off a
screenshot — so a change to the mark, a row's shape or the footer's arithmetic
moves the label with the part it names.

`assets/07-readme/notchline-answering.png` is built the same way and labelled
not at all: two `OpenRow`s on the panel's own ground — a permission request, and
one question out of a set of three — at the height the store composes for each.
They hang from a shared top edge, which is the edge a panel opened at the top of
the screen actually has; the shorter one's difference falls under it as page.

To regenerate them, see the header of
[`AnatomyFigureRenderer.swift`](../Notchline/NotchlineTests/AnatomyFigureRenderer.swift).
Two things it says that are worth repeating here:

- **Render from a clean tree.** The figures are a drawing of `master`, and
  uncommitted work in the views ends up in them.
- **Run that test on its own.** Drawing the specimens holds the main actor for
  a few seconds, and the answering tests running beside it time out waiting for
  their own arming window. The switch that enables it is spent as it is read,
  so it cannot be left set by accident.
