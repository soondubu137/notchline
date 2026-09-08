# Figma Design

Figma：[Codex in Notch — V1](https://www.figma.com/design/B9qIi46zhdjbQYbjZo3AnM/Codex-in-Notch-%E2%80%94-V1)

Design Doc：[figma-design.md](../docs/figma-design.md)

## The README anatomy figure

`assets/07-readme/notchline-anatomy.png` is generated, not drawn. Both specimens
on it are `NotchOverlayView` over a fixed `MonitorStore`, and every label is
anchored to a `PanelMetrics` figure rather than to a point read off a
screenshot — so a change to the mark, a row's shape or the footer's arithmetic
moves the label with the part it names.

`assets/07-readme/notchline-answering.png` is built the same way and labelled
not at all: two `OpenRow`s on the panel's own ground — a permission request, and
one question out of a set of three — at the height the store composes for each.

To regenerate them, see the header of
[`AnatomyFigureRenderer.swift`](../Notchline/NotchlineTests/AnatomyFigureRenderer.swift).
Two things it says that are worth repeating here:

- **Render from a clean tree.** The figures are a drawing of `master`, and
  uncommitted work in the views ends up in them.
- **Run that test on its own.** Drawing the specimens holds the main actor for
  a few seconds, and the answering tests running beside it time out waiting for
  their own arming window. The switch that enables it is spent as it is read,
  so it cannot be left set by accident.
