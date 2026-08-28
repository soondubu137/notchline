"""Regenerate the README header's dark-theme twin.

`design/assets/07-readme/` ships the horizontal lockup on three grounds:
transparent (dark ink), white, and black (white ink, cells blended toward the
unlit inks). The README needs a pair -- one file per theme -- and neither
shipped file works on GitHub's dark theme, which is `#0d1117` rather than
black: the transparent file's `#17171A` wordmark disappears into it, and the
black file reads as a rectangle darker than the page around it.

This lifts the ground out of the black file instead of redrawing anything. The
lockup is composited over opaque `#000000`, so every pixel is its own ink
premultiplied by coverage; dividing a pixel by the ink it belongs to recovers
that coverage as alpha. The mark's inks are the six blended cell colours and
the wordmark's is white, and the two never share a column, so which ink a
pixel belongs to follows from which side of the gap it falls on. The result is
the same image with the rectangle gone, which the assertion at the end checks:
composited back over black it must reproduce the file it came from.

Run this after regenerating `design/assets` -- that pipeline rewrites the whole
tree and takes this file's output with it. The lockup's proportions have
changed before (1200x178 -> 1200x259), so nothing here is hardcoded to a size.
"""

import sys
from PIL import Image

SRC = "design/assets/07-readme/notchline-readme-header-black.png"
OUT = "design/assets/07-readme/notchline-readme-header-dark.png"

# NotchPalette's lit inks blended toward the unlit ones, per design/assets/README.md.
MARK_INKS = [(0x6C, 0xB4, 0xFF), (0x55, 0x8E, 0xC9), (0x3E, 0x68, 0x93),
             (0x7D, 0x45, 0x32), (0xAB, 0x5E, 0x45), (0xD9, 0x77, 0x57)]
WORDMARK_INK = (0xFF, 0xFF, 0xFF)
FLOOR = 2          # below this a pixel is ground, not faint ink


def split_column(load, w, h):
    """The column between the mark and the wordmark.

    The mark is four cell columns separated by narrow gaps; the wordmark sits
    after a much wider one. Finding it by runs rather than by a constant keeps
    this correct when the lockup is redrawn at other proportions.
    """
    runs, start = [], None
    for x in range(w):
        lit = max(max(load[x, y]) for y in range(h)) > FLOOR * 2
        if lit and start is None:
            start = x
        elif not lit and start is not None:
            runs.append((start, x - 1))
            start = None
    if start is not None:
        runs.append((start, w - 1))
    if len(runs) < 5:
        raise SystemExit(f"{SRC}: expected four cell columns then a wordmark, got {len(runs)} runs")
    return (runs[3][1] + runs[4][0]) // 2


def main():
    src = Image.open(SRC).convert("RGB")
    w, h = src.size
    sp = src.load()
    split = split_column(sp, w, h)

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = sp[x, y]
            m = max(r, g, b)
            if m <= FLOOR:
                continue
            if x >= split:
                ink = WORDMARK_INK
            else:
                # Coverage cancels in the ratio, so a normalised pixel is its ink.
                ink = min(MARK_INKS, key=lambda c: sum(
                    (ch / m - cc / max(c)) ** 2 for ch, cc in zip((r, g, b), c)))
            op[x, y] = (*ink, min(255, round(m / max(ink) * 255)))

    check = Image.alpha_composite(Image.new("RGBA", (w, h), (0, 0, 0, 255)), out).convert("RGB").load()
    worst = max(max(abs(p - q) for p, q in zip(check[x, y], sp[x, y]))
                for y in range(h) for x in range(w))
    if worst > 2:
        raise SystemExit(f"unkey changed the image: max channel diff {worst} recompositing over black")

    out.save(OUT, "PNG", optimize=True)
    print(f"{OUT}: {w}x{h}, split at {split}, recomposite exact to within {worst}/255")


if __name__ == "__main__":
    sys.exit(main())
