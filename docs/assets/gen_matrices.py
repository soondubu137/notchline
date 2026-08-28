"""Regenerate the README's status-matrix thumbnails.

The patterns are the ones in `design/assets/matrix-states/`, reduced to two
products side by side on a card. Keep this in step with `MatrixTrack` in
`Notchline/Notchline/NotchStatusMatrix.swift`: same waveforms, same offsets,
same periods. The Swift side is the one the product ships; this file only has
to draw the same thing at a size a README can show.
"""

import math
import os

CELL = 27
GAP = 5
PITCH = CELL + GAP
RADIUS = 2
SIDE = 4
VIEW = SIDE * PITCH - GAP  # 123

CODEX_ON = "#6CB4FF"
CODEX_OFF = "#101B26"
CLAUDE_ON = "#D97757"
CLAUDE_OFF = "#21120D"

# Radar: full brightness as the beam crosses, then an exponential fall to a
# 0.139 floor with a 10.2-frame time constant.
RADAR = [
    1.0, 0.93, 0.853, 0.784, 0.721, 0.664, 0.613, 0.566,
    0.523, 0.485, 0.45, 0.418, 0.389, 0.363, 0.34, 0.318,
    0.299, 0.281, 0.265, 0.251, 0.238, 0.226, 0.215, 0.205,
    0.196, 0.188, 0.181, 0.174, 0.168, 0.163, 0.158, 0.153,
    0.149, 0.146, 0.142, 0.139,
]
# Advance: one column at full for a quarter of the loop, the rest dark.
ADVANCE = [1.0] * 6 + [0.05] * 18
ADVANCE_BASELINE = 0.3
# Double knock: two beats 300 ms apart, each falling away over three frames,
# then 900 ms at the darkest level on the surface.
KNOCK = [
    1.0, 1.0, 0.731, 0.538, 0.399, 0.3, 0.229, 0.179, 0.142,
    1.0, 1.0, 0.731, 0.538, 0.399, 0.3, 0.229, 0.179, 0.142,
    0.116, 0.097, 0.084, 0.074, 0.067, 0.062, 0.059, 0.056, 0.055,
    0.053, 0.052, 0.052, 0.051, 0.051, 0.051, 0.05, 0.05, 0.05,
]
# Lull: a crest crossing the anti-diagonal, then about three quarters of a
# second in the trough.
LULL = [
    0.359, 0.407, 0.454, 0.505, 0.561, 0.616, 0.673, 0.73, 0.784, 0.834,
    0.884, 0.918, 0.952, 0.975, 0.988, 1.0, 0.988, 0.975, 0.952, 0.918,
    0.884, 0.834, 0.784, 0.73, 0.673, 0.616, 0.561, 0.505, 0.454, 0.407,
    0.359, 0.325, 0.291, 0.263, 0.242, 0.22, 0.21, 0.199, 0.192, 0.188,
    0.183, 0.183, 0.182, 0.182, 0.182, 0.182, 0.182, 0.182, 0.182, 0.183,
    0.183, 0.188, 0.192, 0.199, 0.21, 0.22, 0.242, 0.263, 0.291, 0.325,
]
# Connected and disconnected: a still, threaded between the live floors —
# above the 0.05 the knock and the advance fall to, below the lull's 0.182.
INACTIVE = [0.15]

PERIODS = {"running": 1.2, "input": 0.8, "approval": 1.2, "completed": 2.0}


def delayed(track, offset):
    return [track[(n - offset) % len(track)] for n in range(len(track))]


def radar_offset(row, col):
    """The frame the beam reaches this cell on: its bearing, swept clockwise."""
    centre = (SIDE - 1) / 2
    bearing = math.atan2(row - centre, col - centre) % (2 * math.pi)
    return math.ceil(bearing / (2 * math.pi) * len(RADAR)) % len(RADAR)


def lull_offset(row, col):
    """The crest crosses the six diagonal steps in 48.7 of the 60 frames."""
    return round((row + col) * 48.7 / 6)


def cell_track(index, state):
    row, col = divmod(index, SIDE)
    if state == "running":
        return delayed(RADAR, radar_offset(row, col))
    if state == "input":
        if row == SIDE - 1:
            return [ADVANCE_BASELINE]
        return delayed(ADVANCE, col * len(ADVANCE) // SIDE)
    if state == "approval":
        return KNOCK
    if state == "completed":
        return delayed(LULL, lull_offset(row, col))
    return INACTIVE


def fmt(values):
    # The loop is closed with a repeat of the opening frame, as the app does,
    # so N frames play across N intervals instead of N-1.
    return ";".join(f"{v:.3f}" for v in [*values, values[0]])


def matrix_group(x, y, on_color, off_color, state):
    parts = [f'<g transform="translate({x},{y})">']
    for index in range(SIDE * SIDE):
        row, col = divmod(index, SIDE)
        cx, cy = col * PITCH, row * PITCH
        track = cell_track(index, state)
        parts.append(
            f'<rect x="{cx}" y="{cy}" width="{CELL}" height="{CELL}" '
            f'rx="{RADIUS}" ry="{RADIUS}" fill="{off_color}"/>'
        )
        opening = (
            f'<rect x="{cx}" y="{cy}" width="{CELL}" height="{CELL}" '
            f'rx="{RADIUS}" ry="{RADIUS}" fill="{on_color}" '
            f'opacity="{track[0]:.3f}"'
        )
        if len(track) > 1:
            parts.append(
                opening + ">"
                f'<animate attributeName="opacity" values="{fmt(track)}" '
                f'dur="{PERIODS[state]}s" repeatCount="indefinite" '
                f'calcMode="linear"/></rect>'
            )
        else:
            parts.append(opening + "/>")
    parts.append("</g>")
    return "\n    ".join(parts)


def build(state, title, caption):
    gap_between = 40
    pad = 22
    label_h = 22
    top_pad = 30
    width = pad * 2 + VIEW * 2 + gap_between
    height = top_pad + VIEW + label_h + 34
    bg = "#0B0B0D"
    stroke = "#232326"
    font = (
        "-apple-system, 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
    )

    codex_x = pad
    claude_x = pad + VIEW + gap_between
    matrix_y = top_pad

    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" role="img" aria-label="{title}: Codex and Claude Code status matrix">
  <rect x="0" y="0" width="{width}" height="{height}" rx="14" ry="14" fill="{bg}" stroke="{stroke}" stroke-width="1"/>
  <text x="{width / 2}" y="20" text-anchor="middle" font-family="{font}" font-size="13" font-weight="600" fill="#E7E7EA">{title}</text>
  {matrix_group(codex_x, matrix_y, CODEX_ON, CODEX_OFF, state)}
  {matrix_group(claude_x, matrix_y, CLAUDE_ON, CLAUDE_OFF, state)}
  <text x="{codex_x + VIEW / 2}" y="{matrix_y + VIEW + 20}" text-anchor="middle" font-family="{font}" font-size="11" fill="#4D81B7">Codex</text>
  <text x="{claude_x + VIEW / 2}" y="{matrix_y + VIEW + 20}" text-anchor="middle" font-family="{font}" font-size="11" fill="#9C553E">Claude Code</text>
  <text x="{width / 2}" y="{height - 12}" text-anchor="middle" font-family="{font}" font-size="10.5" fill="#6C6C72">{caption}</text>
</svg>
'''


states = [
    ("running", "Running", "Radar — a beam sweeps, each cell holds its afterglow"),
    ("approval", "Approval needed", "Double knock — two beats, then a silence"),
    ("input", "Input needed", "Advance — a column steps across a held baseline"),
    ("completed", "Completed", "Lull — one crest down the diagonal, then a trough"),
    ("idle", "Connected, no active turn", "Dim and still — the product is open, nothing is running"),
]

outdir = os.path.dirname(os.path.abspath(__file__))
for state, title, caption in states:
    path = os.path.join(outdir, f"matrix-{state}.svg")
    with open(path, "w") as handle:
        handle.write(build(state, title, caption))
    print("wrote", path)
