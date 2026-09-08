# Figma Design

Figma：[Codex in Notch — V1](https://www.figma.com/design/B9qIi46zhdjbQYbjZo3AnM/Codex-in-Notch-%E2%80%94-V1)

Design Doc：[figma-design.md](../docs/figma-design.md)

## The README anatomy figure

`assets/07-readme/notchline-anatomy.png` is generated, not drawn. Both specimens
on it are `NotchOverlayView` over a fixed `MonitorStore`, and every label is
anchored to a `PanelMetrics` figure rather than to a point read off a
screenshot — so a change to the mark, a row's shape or the footer's arithmetic
moves the label with the part it names.

To regenerate it, see the header of
[`AnatomyFigureRenderer.swift`](../Notchline/NotchlineTests/AnatomyFigureRenderer.swift).
Render from a clean tree: the figure is a drawing of `master`, and uncommitted
work in the views ends up in it.
