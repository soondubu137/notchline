"""Draw the five V2 logo candidates, on the grid the app actually draws.

V1's mark carried the app's identity in *hue*: Codex blue and Claude
terracotta, split on a diagonal, and nothing else
(`design/assets/README.md`). V2 took that channel away. The collapsed
surface now draws one aggregate mark rather than one per product, and its
hue is a user preference — twelve near-neutrals, default Sage
(`docs/compact-view-v2.md` §2.2, `docs/aggregate-ink-palette.md`). A mark
whose colour the user chooses cannot be identified by its colour, so every
candidate here has to be recognisable as a *shape*.

The other change is the grid: 4×4 became 5×5, `MatrixGrid` in
`Notchline/Notchline/NotchStatusMatrix.swift`. Odd grids can draw figures
even ones cannot — a true centre cell, and three bars with a clear row
between them — and two of the five candidates are only available because
of it.

The five span one axis deliberately: **how much of the two-product
identity the brand keeps, now that the product itself dropped it.**
`fifth-row` and `seam` keep both product hues; `bars`, `notch` and `wedge`
follow the surface into the near-neutral the aggregate mark uses.

Frozen patterns are not eyeballed. `bars` and `wedge` are the app's own
tracks sampled at one named frame, using the formulas in
`docs/assets/gen_matrices.py`, which are in turn `MatrixTrack`'s. If the
Swift changes, this is regenerated rather than redrawn.
"""

import math
import os
import subprocess

# MARK: The grid, from `MatrixGrid`

CELL = 27
PITCH = 32
RADIUS = 2
SIDE = 5
VIEW = SIDE * PITCH - (PITCH - CELL)  # 155
PAD = PITCH  # one pitch of clear space, as V1's files carry
BOX = VIEW + PAD * 2  # 219

# MARK: Inks

CODEX = {"lit": "#6CB4FF", "unlit": "#101B26"}
CLAUDE = {"lit": "#D97757", "unlit": "#21120D"}
# Sage · hint, the aggregate mark's default (`aggregate-ink-palette.md` §3).
SAGE = {"lit": "#DEE8E0", "unlit": "#1B1F1C"}

WORD_LIGHT = "#17171A"
WORD_DARK = "#FFFFFF"
ICON_GROUND = "#0A0A0B"

# Wordmark metrics, measured on Tahoma Regular and carried over from V1.
WORD_INK_W = 4.0059  # em, painted extents
WORD_INK_H = 0.7749
WORD_ADVANCE = 4.106
WORD_BEARING = 0.0737
WORD_DESCENDER = 0.0151


def hexrgb(value):
    value = value.lstrip("#")
    return tuple(int(value[n : n + 2], 16) for n in (0, 2, 4))


def blend(unlit, lit, level):
    """The black-ground treatment: opaque, mixed toward the unlit ink.

    `#101B26` on white is a hole rather than a dim cell, which is why this
    is never used on paper — see `design/assets/README.md`.
    """
    a, b = hexrgb(unlit), hexrgb(lit)
    return "#%02X%02X%02X" % tuple(
        round(a[n] + (b[n] - a[n]) * level) for n in range(3)
    )


# MARK: The app's own tracks, for the two frozen-pattern candidates

FLOOR = 0.15


def _stretched(tracks, floor=FLOOR):
    samples = [v for track in tracks for v in track]
    low, high = min(samples), max(samples)
    if high - low < 1e-9:
        return tracks
    scale = (1 - floor) / (high - low)
    return [[floor + (v - low) * scale for v in track] for track in tracks]


WEDGE = _stretched(
    [[math.exp(-((f / 40 * SIDE) % SIDE) / 1.3) for f in range(40)]]
)[0]


def wedge_offset(row, col):
    return (col * 8 + abs(row - (SIDE - 1) // 2) * 6) % len(WEDGE)


BARS = [0.32 + 0.68 * (0.5 * (1 + math.cos(2 * math.pi * f / 60))) for f in range(60)]


def bars_offset(row):
    return row // 2 * 11


# MARK: The five candidates
#
# A candidate is a list of cells. A cell is (row, col, ink, level), or
# (row, col, ink_above, level_above, ink_below, level_below) for the one
# cell a seam runs through — cut on the anti-diagonal, the same lower-left
# to upper-right cut `NotchPalette.MatrixSplit` names.


def fifth_row():
    """V1's gesture, redrawn native to the odd grid.

    Two halves, out of phase by one row, each falling from full strength at
    its far edge to half at the seam — V1's rule exactly, except that four
    rows a half means four steps where V1 had three. That is the fifth row
    being paid for.

    The odd grid gives the mark a true centre for the first time, and the
    honest thing to do with it is let it *be* the seam: cell (2,2) is cut on
    the diagonal, Codex above and Claude below. One cell carries the whole
    idea the mark is built on.
    """
    cells = []
    for row in range(4):
        level = 1.0 - (row / 3) * 0.5
        for col in (0, 1):
            cells.append((row, col, CODEX, level))
    for row in range(1, 5):
        level = 0.5 + ((row - 1) / 3) * 0.5
        for col in (3, 4):
            cells.append((row, col, CLAUDE, level))
    # The seam column: Codex on top, Claude below, and the centre split.
    cells.append((0, 2, CODEX, 1.0))
    cells.append((1, 2, CODEX, 1.0 - (1 / 3) * 0.5))
    cells.append((3, 2, CLAUDE, 0.5 + (2 / 3) * 0.5))
    cells.append((4, 2, CLAUDE, 1.0))
    cells.append((2, 2, CODEX, 2 / 3, CLAUDE, 2 / 3))
    return cells


def seam():
    """One solid field, cut once.

    Every cell present, so the mark is a square rather than two blocks, and
    a single diagonal divides it — which is what the app's own
    ``MatrixSplit.products`` already describes: the cut runs lower-left to
    upper-right, Codex above and Claude below. The five cells the cut passes
    through are cut in two.

    Each half is brightest at its far corner and falls toward the seam, so
    V1's one real gesture survives on a shape that says the V2 thing: one
    mark, both agents in it.
    """
    cells = []
    for row in range(SIDE):
        for col in range(SIDE):
            d = row + col
            level = 0.55 + 0.45 * (abs(d - 4) / 4)
            if d < 4:
                cells.append((row, col, CODEX, level))
            elif d > 4:
                cells.append((row, col, CLAUDE, level))
            else:
                cells.append((row, col, CODEX, level, CLAUDE, level))
    return cells


def bars(frame=0):
    """The Completed pattern, frozen at frame 0.

    Rows 0, 2 and 4 breathe eleven frames apart and rows 1 and 3 are the
    gaps between them. Sampled at frame 0 the three land on 1.00 / 0.80 /
    0.43 — within a few hundredths of V1's own 1.00 / 0.75 / 0.50 ramp, so
    the mark keeps V1's three-step fall and turns it from a diagonal into
    three level rules.

    "Three evenly spaced rules with a clear row between each is a figure
    only an odd grid can draw, and a level, closed, horizontal one carries
    nothing that could be read as a fault" — `NotchStatusMatrix.swift`. It
    is also, plainly, a set of lines.
    """
    cells = []
    for row in range(SIDE):
        if row % 2 == 1:
            level = FLOOR
        else:
            level = BARS[(frame - bars_offset(row)) % len(BARS)]
        for col in range(SIDE):
            cells.append((row, col, SAGE, level))
    return cells


def notch():
    """The cut-out, and what hangs under it.

    Row 0 keeps only its outer two cells: that is the menu bar with the
    notch taken out of it, and those two ears are the only part of the bar
    the hardware leaves. Everything below is the panel that drops from the
    cut-out, falling away as it goes.

    The one candidate that says the product's name rather than describing
    its grid. It is also the only one whose silhouette is unique — the
    other four are all full or near-full squares.
    """
    cells = [(0, 0, SAGE, 0.45), (0, 4, SAGE, 0.45)]
    for row, level in zip(range(1, 5), (1.0, 0.72, 0.5, 0.32)):
        for col in range(SIDE):
            cells.append((row, col, SAGE, level))
    return cells


def wedge():
    """The Input-needed pattern's front, held — its shape, not one of its frames.

    This is the one candidate that is *not* a sampled frame, and the reason
    is worth recording. The wedge takes the distance behind its front
    **around** the grid rather than across it, so the band always wraps:
    every one of the forty frames has tail cells re-lit on the far side of
    the mark. Sampled at any of them the figure reads as scatter rather
    than as a chevron — frame 16, which centres the apex, is the best of
    them and still does. Rain wraps for the same reason and fails the same
    way; both were drawn to be *watched*, and a logo is looked at once.

    So the front is drawn directly: the leading cell of each row at full,
    the cell behind it one column back down the pattern's own exponential
    (``WEDGE`` eight frames in, `0.53`), and the rest of the grid at the
    floor. The middle row leads by a column, which is the `0.75` of a cell
    the real pattern's middle row leads by, rounded to the grid.

    The result is the only silhouette in the set with a direction, and the
    one that survives 16 px best: a chevron is still a chevron after every
    cell boundary has gone.
    """
    front = {0: 1, 1: 2, 2: 3, 3: 2, 4: 1}
    behind = WEDGE[8]
    cells = []
    for row in range(SIDE):
        for col in range(SIDE):
            if col == front[row]:
                level = 1.0
            elif col == front[row] - 1:
                level = behind
            else:
                level = FLOOR
            cells.append((row, col, SAGE, level))
    return cells


CANDIDATES = [
    ("01-fifth-row", "Fifth Row", fifth_row()),
    ("02-seam", "Seam", seam()),
    ("03-bars", "Bars", bars()),
    ("04-notch", "Notch", notch()),
    ("05-wedge", "Wedge", wedge()),
]


# MARK: Drawing


def paint(ink, level, ground):
    """One cell's fill and opacity on a given ground.

    Two treatments, as V1 had. On black the lit ink is *blended* toward its
    own unlit colour and stays opaque; on paper it is *thinned*, because
    `#101B26` on white is a hole rather than a dim cell.

    The aggregate ink is the exception the palette forces. Sage's lit
    `#DEE8E0` is all but invisible on white, so on paper the aggregate mark
    inverts and is drawn in its *unlit* colour instead — a near-black that
    still carries the hue. That inversion is the point: it is what lets one
    mark survive all twelve preferences and still work as a menu bar
    template.

    The thinning is the level itself either way, with no lift under it. A
    lifted floor was tried and is wrong: on black a cell at ``FLOOR`` all
    but disappears, so a paper cell that stays plainly visible turns the
    three bars of `bars` into five and reports a pattern the app does not
    draw.
    """
    if ground == "black":
        return blend(ink["unlit"], ink["lit"], level), 1.0
    if ink is SAGE:
        return ink["unlit"], level
    return ink["lit"], level


def cell_svg(x, y, cell, ground, cell_size, radius):
    row, col = cell[0], cell[1]
    del row, col
    parts = []
    if len(cell) == 4:
        fill, alpha = paint(cell[2], cell[3], ground)
        parts.append(
            f'<rect x="{x:.2f}" y="{y:.2f}" width="{cell_size:.2f}" '
            f'height="{cell_size:.2f}" rx="{radius:.2f}" fill="{fill}"'
            + (f' fill-opacity="{alpha:.3f}"' if alpha < 0.999 else "")
            + "/>"
        )
        return parts
    # A split cell: two triangles clipped to the rounded square, cut on the
    # anti-diagonal so the seam runs lower-left to upper-right.
    key = f"c{int(x * 100)}_{int(y * 100)}"
    s = cell_size
    parts.append(
        f'<clipPath id="{key}"><rect x="{x:.2f}" y="{y:.2f}" '
        f'width="{s:.2f}" height="{s:.2f}" rx="{radius:.2f}"/></clipPath>'
    )
    above_fill, above_a = paint(cell[2], cell[3], ground)
    below_fill, below_a = paint(cell[4], cell[5], ground)
    parts.append(f'<g clip-path="url(#{key})">')
    parts.append(
        f'<polygon points="{x:.2f},{y:.2f} {x + s:.2f},{y:.2f} '
        f'{x:.2f},{y + s:.2f}" fill="{above_fill}"'
        + (f' fill-opacity="{above_a:.3f}"' if above_a < 0.999 else "")
        + "/>"
    )
    parts.append(
        f'<polygon points="{x + s:.2f},{y:.2f} {x + s:.2f},{y + s:.2f} '
        f'{x:.2f},{y + s:.2f}" fill="{below_fill}"'
        + (f' fill-opacity="{below_a:.3f}"' if below_a < 0.999 else "")
        + "/>"
    )
    parts.append("</g>")
    return parts


def mark_body(cells, ground, ox=PAD, oy=PAD, cell_size=CELL, pitch=PITCH, radius=RADIUS):
    parts = []
    for cell in cells:
        x = ox + cell[1] * pitch
        y = oy + cell[0] * pitch
        parts.extend(cell_svg(x, y, cell, ground, cell_size, radius))
    return "\n  ".join(parts)


GROUNDS = {"": None, "-white": "#FFFFFF", "-black": "#000000"}


def mark_svg(cells, ground):
    fill = GROUNDS[ground]
    bg = f'<rect width="{BOX}" height="{BOX}" fill="{fill}"/>\n  ' if fill else ""
    treatment = "black" if ground == "-black" else "light"
    return (
        f'<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg" '
        f'width="{BOX}" height="{BOX}" viewBox="0 0 {BOX} {BOX}">\n  '
        f"{bg}{mark_body(cells, treatment)}\n</svg>\n"
    )


def icon_svg(cells):
    """macOS app icon: an 824 body in a 1024 canvas, mark at V1's optical size.

    V1 drew its 123-unit mark across 512 of the canvas. Holding that span
    keeps the icon's mark exactly as large as it used to look, and the 5×5
    grid pays for its extra row out of the cell rather than the box — which
    is the same trade `MatrixGrid` makes on the notch itself.
    """
    scale = 512 / VIEW
    body = mark_body(
        cells,
        "black",
        ox=256,
        oy=256,
        cell_size=CELL * scale,
        pitch=PITCH * scale,
        radius=RADIUS * scale,
    )
    return (
        '<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg" '
        'width="1024" height="1024" viewBox="0 0 1024 1024">\n  '
        f'<rect x="100" y="100" width="824" height="824" rx="185.4" '
        f'fill="{ICON_GROUND}"/>\n  {body}\n</svg>\n'
    )


def horizontal_svg(cells, ground):
    """The wordmark's painted height equals the mark's, gap = mark × 0.354.

    Both figures are V1's, and both are measured on the ink box rather than
    the advance, so the left bearing and the descender overshoot are
    accounted for (`design/assets/README.md`).
    """
    mark = VIEW
    size = mark / WORD_INK_H
    gap = mark * 0.354
    x = PAD + mark + gap - WORD_BEARING * size
    baseline = PAD + mark - WORD_DESCENDER * size
    width = round(x + WORD_ADVANCE * size + PAD - WORD_BEARING * size, 1)
    fill = GROUNDS[ground]
    bg = f'<rect width="{width}" height="{BOX}" fill="{fill}"/>\n  ' if fill else ""
    treatment = "black" if ground == "-black" else "light"
    ink = WORD_DARK if ground == "-black" else WORD_LIGHT
    return (
        f'<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg" '
        f'width="{width}" height="{BOX}" viewBox="0 0 {width} {BOX}">\n  '
        f"{bg}{mark_body(cells, treatment)}\n"
        f'  <text x="{x:.1f}" y="{baseline:.1f}" '
        f'textLength="{WORD_ADVANCE * size:.1f}" lengthAdjust="spacing" '
        f'font-family="Tahoma, Verdana, Geneva, sans-serif" '
        f'font-size="{size:.1f}" fill="{ink}">Notchline</text>\n</svg>\n'
    )


# MARK: Output


def rasterise(svg_path, size, out_path):
    """qlmanage is the only rasteriser on this machine; it writes
    `<name>.png` into a directory, so the result is renamed into place."""
    out_dir = os.path.dirname(out_path)
    subprocess.run(
        ["qlmanage", "-t", "-s", str(size), "-o", out_dir, svg_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    produced = os.path.join(out_dir, os.path.basename(svg_path) + ".png")
    if os.path.exists(produced):
        os.replace(produced, out_path)
        return True
    return False


def write(path, text):
    with open(path, "w") as handle:
        handle.write(text)


def main():
    root = os.path.dirname(os.path.abspath(__file__))
    for slug, _name, cells in CANDIDATES:
        out = os.path.join(root, slug)
        os.makedirs(out, exist_ok=True)
        for ground in GROUNDS:
            write(os.path.join(out, f"mark{ground}.svg"), mark_svg(cells, ground))
            write(
                os.path.join(out, f"horizontal{ground}.svg"),
                horizontal_svg(cells, ground),
            )
        write(os.path.join(out, "icon.svg"), icon_svg(cells))

        for ground in GROUNDS:
            for size in (512, 128, 32):
                rasterise(
                    os.path.join(out, f"mark{ground}.svg"),
                    size,
                    os.path.join(out, f"mark{ground}-{size}.png"),
                )
            rasterise(
                os.path.join(out, f"horizontal{ground}.svg"),
                1024,
                os.path.join(out, f"horizontal{ground}-1024.png"),
            )
        rasterise(os.path.join(out, "icon.svg"), 512, os.path.join(out, "icon-512.png"))
        rasterise(os.path.join(out, "icon.svg"), 128, os.path.join(out, "icon-128.png"))
        print(f"{slug}: {len(cells)} cells")


if __name__ == "__main__":
    main()
