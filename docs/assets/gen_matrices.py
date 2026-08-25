import textwrap

CELL = 27
GAP = 5
PITCH = CELL + GAP
RADIUS = 2
SIDE = 91  # 3*PITCH - GAP

CODEX_ON = "#6CB4FF"
CODEX_OFF = "#101B26"
CLAUDE_ON = "#D97757"
CLAUDE_OFF = "#21120D"

RUNNING_EVEN = [0.500,0.371,0.250,0.146,0.067,0.017,0.000,0.017,0.067,0.146,0.250,0.371,0.500,0.629,0.750,0.854,0.933,0.983,1.000,0.983,0.933,0.854,0.750,0.629]
RUNNING_ODD  = [0.757,0.859,0.937,0.985,1.000,0.981,0.929,0.848,0.743,0.622,0.492,0.363,0.243,0.141,0.063,0.015,0.000,0.019,0.071,0.152,0.257,0.378,0.508,0.637]
ATTENTION_RING   = [0.100]*16 + [1.000,0.981,0.963,0.944,0.925,0.906,0.887,0.869]
ATTENTION_CENTRE = [1.000,0.981,0.963,0.944,0.925,0.906,0.887,0.869,0.850,0.831,0.813,0.794,0.775,0.756,0.738,0.719,0.700,0.681,0.663,0.644,0.625,0.606,0.588,0.569]
COMPLETED = [0.550,0.667,0.775,0.868,0.939,0.984,1.000,0.984,0.939,0.868,0.775,0.667,0.550,0.433,0.325,0.232,0.161,0.116,0.100,0.116,0.161,0.232,0.325,0.433]
INACTIVE = [0.180]

def fmt(values):
    return ";".join(f"{v:.3f}" for v in values)

def cell_track(index, state):
    row, col = divmod(index, 3)
    if state == "running":
        return RUNNING_EVEN if (row + col) % 2 == 0 else RUNNING_ODD
    if state == "attention":
        return ATTENTION_CENTRE if index == 4 else ATTENTION_RING
    if state == "completed":
        return COMPLETED
    return INACTIVE

def period(state):
    return {"running": 1.0, "attention": 1.2, "completed": 1.2}.get(state)

def matrix_group(x, y, on_color, off_color, state, anim_id_prefix):
    parts = [f'<g transform="translate({x},{y})">']
    for index in range(9):
        row, col = divmod(index, 3)
        cx = col * PITCH
        cy = row * PITCH
        track = cell_track(index, state)
        parts.append(
            f'<rect x="{cx}" y="{cy}" width="{CELL}" height="{CELL}" rx="{RADIUS}" ry="{RADIUS}" fill="{off_color}"/>'
        )
        opening = (
            f'<rect x="{cx}" y="{cy}" width="{CELL}" height="{CELL}" rx="{RADIUS}" ry="{RADIUS}" '
            f'fill="{on_color}" opacity="{track[0]:.3f}"'
        )
        if len(track) > 1:
            p = period(state)
            parts.append(
                opening + f'>'
                f'<animate attributeName="opacity" values="{fmt(track)}" dur="{p}s" '
                f'repeatCount="indefinite" calcMode="linear"/></rect>'
            )
        else:
            parts.append(opening + '/>')
    parts.append('</g>')
    return "\n    ".join(parts)

def build(state, title, caption):
    gap_between = 40
    pad = 22
    label_h = 22
    top_pad = 30
    width = pad * 2 + SIDE * 2 + gap_between
    height = top_pad + SIDE + label_h + 34
    bg = "#0B0B0D"
    stroke = "#232326"

    codex_x = pad
    claude_x = pad + SIDE + gap_between
    matrix_y = top_pad

    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" role="img" aria-label="{title}: Codex and Claude Code status matrix">
  <rect x="0" y="0" width="{width}" height="{height}" rx="14" ry="14" fill="{bg}" stroke="{stroke}" stroke-width="1"/>
  <text x="{width/2}" y="20" text-anchor="middle" font-family="-apple-system, 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif" font-size="13" font-weight="600" fill="#E7E7EA">{title}</text>
  {matrix_group(codex_x, matrix_y, CODEX_ON, CODEX_OFF, state, "codex")}
  {matrix_group(claude_x, matrix_y, CLAUDE_ON, CLAUDE_OFF, state, "claude")}
  <text x="{codex_x + SIDE/2}" y="{matrix_y + SIDE + 20}" text-anchor="middle" font-family="-apple-system, 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif" font-size="11" fill="#4D81B7">Codex</text>
  <text x="{claude_x + SIDE/2}" y="{matrix_y + SIDE + 20}" text-anchor="middle" font-family="-apple-system, 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif" font-size="11" fill="#9C553E">Claude Code</text>
  <text x="{width/2}" y="{height - 12}" text-anchor="middle" font-family="-apple-system, 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif" font-size="10.5" fill="#6C6C72">{caption}</text>
</svg>
'''
    return svg

states = [
    ("running", "Running", "Diagonal sweep — a turn is executing"),
    ("attention", "Input needed / Approval needed", "Ring flash — the turn is waiting on you"),
    ("completed", "Completed", "Slow breath — finished, still unread"),
    ("idle", "Connected, no active turn", "Dim and still — the product is open, nothing is running"),
]

import os
outdir = os.path.dirname(os.path.abspath(__file__))
for state, title, caption in states:
    svg = build(state, title, caption)
    path = os.path.join(outdir, f"matrix-{state}.svg")
    with open(path, "w") as f:
        f.write(svg)
    print("wrote", path)
