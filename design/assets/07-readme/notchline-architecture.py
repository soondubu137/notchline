#!/usr/bin/env python3
"""Regenerate the README architecture diagram.

Usage: python3 notchline-architecture.py [output-directory]
Writes notchline-architecture.svg and notchline-architecture-dark.svg.
"""

from html import escape

W, H = 1120, 1100

SANS = "ui-sans-serif, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"
MONO = "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, 'Liberation Mono', monospace"

TITLE_FS = 14.5
SUB_FS = 11.5
GROUP_FS = 14.5
NOTCH_FS = 15.5
EDGE_FS = 11
ANNOT_FS = 11
LEGEND_FS = 11.5

LIGHT = dict(
    bg="#ffffff",
    ink="#1f2328",
    muted="#59636e",
    faint="#818b98",
    edge="#8c959f",
    boxFill="#ffffff",
    boxStroke="#d0d7de",
    notchFill="#f6f8fa",
    notchStroke="#cfd7df",
    codex="#1f6091",
    claude="#a8492c",
    codexGroupFill="#f5f9fd",
    codexGroupStroke="#cadff3",
    claudeGroupFill="#fdf7f4",
    claudeGroupStroke="#f0d6c9",
    codexTint="#eaf3fc",
    claudeTint="#fbefe9",
)

DARK = dict(
    bg="#0d1117",
    ink="#e6edf3",
    muted="#9198a1",
    faint="#767e88",
    edge="#6e7681",
    boxFill="#171d25",
    boxStroke="#333b45",
    notchFill="#12171e",
    notchStroke="#2a313b",
    codex="#6cb4ff",
    claude="#d97757",
    codexGroupFill="#0e1620",
    codexGroupStroke="#1e3450",
    claudeGroupFill="#150f0a",
    claudeGroupStroke="#3d2317",
    codexTint="#101b26",
    claudeTint="#21120d",
)


def approx_w(text, size, mono=False, bold=False):
    ratio = 0.60 if mono else (0.555 if bold else 0.525)
    return len(text) * size * ratio


class Canvas:
    def __init__(self, pal):
        self.p = pal
        self.o = []

    def add(self, s):
        self.o.append(s)

    # ---------- primitives ----------

    def rect(self, x, y, w, h, fill, stroke, r=8, sw=1, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.add(
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" ry="{r}" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>'
        )

    def text(self, x, y, s, size, fill, anchor="start", weight=400, mono=False,
             ls=0, opacity=None):
        fam = MONO if mono else SANS
        op = f' opacity="{opacity}"' if opacity is not None else ""
        lsa = f' letter-spacing="{ls}"' if ls else ""
        self.add(
            f'<text x="{x}" y="{y}" font-family="{fam}" font-size="{size}" '
            f'font-weight="{weight}" fill="{fill}" text-anchor="{anchor}"{lsa}{op}>'
            f"{escape(s)}</text>"
        )

    def arrowhead(self, x, y, dx, dy, color, size=5.0, length=8.0):
        n = (dx * dx + dy * dy) ** 0.5
        ux, uy = dx / n, dy / n
        px, py = -uy, ux
        bx, by = x - ux * length, y - uy * length
        pts = f"{x:.1f},{y:.1f} {bx + px * size:.1f},{by + py * size:.1f} {bx - px * size:.1f},{by - py * size:.1f}"
        self.add(f'<polygon points="{pts}" fill="{color}"/>')

    def path(self, pts, color, dashed=False, head=True, sw=1.35, tail_head=False):
        """pts: list of (x, y). Arrowhead at the last point (and first if tail_head)."""
        d = ' stroke-dasharray="4 4"' if dashed else ""
        # shorten the final segment so the line does not poke through the head
        draw = list(pts)
        if head:
            (x0, y0), (x1, y1) = draw[-2], draw[-1]
            n = ((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5
            ux, uy = (x1 - x0) / n, (y1 - y0) / n
            draw[-1] = (x1 - ux * 7, y1 - uy * 7)
        if tail_head:
            (x0, y0), (x1, y1) = draw[1], draw[0]
            n = ((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5
            ux, uy = (x1 - x0) / n, (y1 - y0) / n
            draw[0] = (x1 - ux * 7, y1 - uy * 7)
        pl = " ".join(f"{x:.1f},{y:.1f}" for x, y in draw)
        self.add(
            f'<polyline points="{pl}" fill="none" stroke="{color}" '
            f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"{d}/>'
        )
        if head:
            (x0, y0), (x1, y1) = pts[-2], pts[-1]
            self.arrowhead(x1, y1, x1 - x0, y1 - y0, color)
        if tail_head:
            (x0, y0), (x1, y1) = pts[1], pts[0]
            self.arrowhead(x1, y1, x1 - x0, y1 - y0, color)

    # ---------- composites ----------

    def box(self, x, y, w, h, title, subs=(), fill=None, stroke=None,
            title_mono=False, title_color=None):
        p = self.p
        self.rect(x, y, w, h, fill or p["boxFill"], stroke or p["boxStroke"], r=8)
        n = len(subs)
        block = 20 + 16 * n
        top = y + (h - block) / 2
        self.text(x + 12, top + 15, title, TITLE_FS, title_color or p["ink"],
                  weight=600, mono=title_mono)
        for i, s in enumerate(subs):
            self.text(x + 12, top + 20 + 16 * i + 12, s, SUB_FS, p["muted"])

    def nolink(self, x, y, color):
        p = self.p
        self.add(f'<circle cx="{x}" cy="{y}" r="8.5" fill="{p["bg"]}" '
                 f'stroke="{color}" stroke-width="1.35"/>')
        for a, b, c, d in ((-3.6, -3.6, 3.6, 3.6), (-3.6, 3.6, 3.6, -3.6)):
            self.add(f'<line x1="{x + a}" y1="{y + b}" x2="{x + c}" y2="{y + d}" '
                     f'stroke="{color}" stroke-width="1.6" stroke-linecap="round"/>')


def build(pal):
    c = Canvas(pal)
    p = pal
    c.add(f'<rect width="{W}" height="{H}" fill="{p["bg"]}"/>')

    # ================= feedback loop (drawn first, sits behind) =================
    loop = p["faint"]
    c.path([(1036, 958), (1080, 958), (1080, 20), (140, 20), (140, 48)], loop, dashed=True)
    for bx in (920, 675):
        c.path([(bx, 20), (bx, 48)], loop, dashed=True)
        c.add(f'<circle cx="{bx}" cy="20" r="2.4" fill="{loop}"/>')
    lbl = "click a row → back to the originating Thread or host"
    lw = approx_w(lbl, EDGE_FS)
    c.add(f'<rect x="{400 - lw / 2 - 8}" y="10" width="{lw + 16}" height="20" fill="{p["bg"]}"/>')
    c.text(400, 24, lbl, EDGE_FS, p["faint"], anchor="middle")

    # ================= product groups =================
    c.rect(28, 48, 488, 216, p["codexGroupFill"], p["codexGroupStroke"], r=12)
    c.rect(564, 48, 488, 216, p["claudeGroupFill"], p["claudeGroupStroke"], r=12)

    def group_label(x, name, rest, accent):
        c.text(x, 74, name, GROUP_FS, accent, weight=600)
        c.text(x + approx_w(name, GROUP_FS, bold=True) + 7, 74, rest, SUB_FS, p["muted"])

    group_label(44, "Codex", "— the product and its own local data", p["codex"])
    group_label(580, "Claude Code", "— the product and its own local data", p["claude"])

    # Codex products
    c.box(44, 84, 190, 72, "Codex Desktop", ["threads, approvals, its UI"])
    c.box(268, 84, 232, 72, "App Server A",
          ["Codex Desktop’s own,", "in-process"],
          fill=p["codexTint"], stroke=p["codexGroupStroke"], title_color=p["codex"])
    c.path([(234, 120), (268, 120)], p["edge"], head=True, tail_head=True)

    c.box(300, 176, 200, 68, "~/.codex",
          ["thread rollout files,", "global state, hooks.json"], title_mono=True)

    # Claude products
    c.box(580, 84, 190, 72, "Claude Code CLI", ["terminal-hosted sessions"])
    c.box(804, 84, 232, 72, "Claude Desktop",
          ["hosts its own sessions and", "keeps its own records"])
    c.path([(770, 120), (804, 120)], p["edge"], head=True, tail_head=True)

    c.box(700, 176, 336, 68, "~/.claude",
          ["settings.json, transcripts, Claude Desktop session",
           "and focus records"], title_mono=True)

    # ================= Notchline group =================
    c.rect(28, 320, 1024, 704, p["notchFill"], p["notchStroke"], r=12)

    # The label is painted last, over the connectors that cross this row.
    notch_sub = ("— one LSUIElement process, no network client: every socket, "
                 "subprocess and file read below is local")

    def notch_label():
        nw = approx_w("Notchline", NOTCH_FS, bold=True)
        c.rect(38, 334, nw + 16 + approx_w(notch_sub, SUB_FS), 22,
               p["notchFill"], "none", r=0, sw=0)
        c.text(44, 348, "Notchline", NOTCH_FS, p["ink"], weight=600)
        c.text(44 + nw + 8, 348, notch_sub, SUB_FS, p["muted"])

    # ---- boundary row ----
    BY, BH = 372, 96
    c.box(44, BY, 120, BH, "Hook socket",
          ["hook.sh →", "hook.sock (0600)", "always exit 0"])
    c.box(176, BY, 168, BH, "codex app-server",
          ["App Server B —", "Notchline’s own", "read-only subprocess"],
          fill=p["codexTint"], stroke=p["codexGroupStroke"],
          title_mono=True, title_color=p["codex"])
    c.box(356, BY, 144, BH, "Desktop state",
          ["Project, unread and", "approval routing —", "private, read-only"])

    c.box(580, BY, 120, BH, "Hook socket",
          ["hook.sh →", "hook.sock (0600)", "always exit 0"])
    c.box(712, BY, 168, BH, "CLI subprocesses",
          ["claude agents --json", "and claude -p /usage", "— ours, not the user’s"],
          fill=p["claudeTint"], stroke=p["claudeGroupStroke"], title_color=p["claude"])
    c.box(892, BY, 144, BH, "Local readers",
          ["transcripts, Desktop", "records, controlling", "tty and host lookup"])

    # ---- product -> boundary edges ----
    e = p["edge"]
    c.path([(100, 156), (100, BY)], e)                      # Codex Desktop -> hook socket
    c.path([(400, 156), (400, 176)], e, dashed=True)        # App Server A -> ~/.codex
    c.path([(320, 244), (320, BY)], e, dashed=True)         # ~/.codex -> App Server B
    c.path([(430, 244), (430, BY)], e, dashed=True)         # ~/.codex -> Desktop state

    c.path([(636, 156), (636, BY)], e)                      # Claude CLI -> hook socket
    c.path([(740, 156), (740, 176)], e, dashed=True)        # Claude CLI -> ~/.claude
    c.path([(936, 156), (936, 176)], e, dashed=True)        # Claude Desktop -> ~/.claude
    c.path([(800, 244), (800, BY)], e, dashed=True)         # ~/.claude -> CLI subprocesses
    c.path([(966, 244), (966, BY)], e, dashed=True)         # ~/.claude -> local readers

    # ---- the A / B non-link ----
    c.path([(280, 156), (280, 196)], p["codex"], dashed=True, head=False)
    c.path([(280, 224), (280, BY)], p["codex"], dashed=True, head=False)
    c.nolink(280, 210, p["codex"])
    for i, line in enumerate(["A and B never talk —",
                              "they share only the",
                              "records on disk"]):
        c.text(262, 196 + 14 * i, line, ANNOT_FS, p["codex"], anchor="end")

    # ---- hook reducer row ----
    RY, RH = 500, 64
    c.box(44, RY, 190, RH, "HookEventRepository", ["exact Turn state,", "in memory only"])
    c.box(580, RY, 190, RH, "HookEventRepository", ["exact Turn state,", "in memory only"])
    c.path([(104, BY + BH), (104, RY)], e)
    c.path([(640, BY + BH), (640, RY)], e)

    c.add(f'<line x1="234" y1="532" x2="580" y2="532" stroke="{p["faint"]}" '
          f'stroke-width="1.1" stroke-dasharray="3 4"/>')
    shared = "one implementation, one instance per product"
    sw_ = approx_w(shared, EDGE_FS)
    c.add(f'<rect x="{407 - sw_ / 2 - 8}" y="522" width="{sw_ + 16}" height="20" fill="{p["notchFill"]}"/>')
    c.text(407, 536, shared, EDGE_FS, p["faint"], anchor="middle")

    # ---- service row ----
    SY, SH = 596, 80
    c.box(44, SY, 456, SH, "LiveCodexMonitorService",
          ["the one orchestrator — membership, metadata, quota,",
           "navigation pre-flight and every degradation rule"])
    c.box(580, SY, 456, SH, "ClaudeCodeMonitorService",
          ["the same shape for Claude Code — sessions, read",
           "evidence, quota and host discovery"])
    c.path([(104, RY + RH), (104, SY)], e)
    c.path([(640, RY + RH), (640, SY)], e)
    for x in (260, 796):                       # request / response over stdio
        c.path([(x, BY + BH), (x, SY)], e, tail_head=True)
    for x in (428, 964):
        c.path([(x, BY + BH), (x, SY)], e)

    # ---- merge ----
    c.box(340, 724, 400, 60, "MonitorSnapshot",
          ["one contract: availability, sessions, quota, diagnostics"])
    c.path([(272, SY + SH), (272, 700), (420, 700), (420, 724)], e)
    c.path([(808, SY + SH), (808, 700), (660, 700), (660, 724)], e)
    c.text(288, 694, "AgentSnapshot", EDGE_FS, p["faint"])
    c.text(792, 694, "AgentSnapshot", EDGE_FS, p["faint"], anchor="end")

    c.box(340, 816, 400, 60, "MonitorStore",
          ["@MainActor — the only state the overlay reads"])
    c.path([(540, 784), (540, 816)], e)

    # ---- presentation ----
    PY, PH, PW = 916, 84, 239
    xs = [44, 295, 546, 797]
    content = [
        ("Overlay panel", ["OverlayPanelController —", "NSPanel geometry, anchoring", "and CALayer motion"]),
        ("Notch overlay", ["NotchOverlayView — collapsed", "matrices, expanded Thread", "list and quota footer"]),
        ("Settings and onboarding", ["product switches, display", "choice, hook install and", "removal"]),
        ("Navigation", ["codex:// deep link, or raise", "the terminal or Claude", "Desktop host"]),
    ]
    for x, (t, s) in zip(xs, content):
        c.box(x, PY, PW, PH, t, s)

    c.path([(540, 876), (540, 896)], e, head=False)
    c.add(f'<line x1="163.5" y1="896" x2="916.5" y2="896" stroke="{e}" '
          f'stroke-width="1.35" stroke-linecap="round"/>')
    for x in (163.5, 414.5, 665.5, 916.5):
        c.path([(x, 896), (x, PY)], e)

    notch_label()

    # ================= legend =================
    LY = 1058
    c.add(f'<line x1="28" y1="{LY - 4}" x2="52" y2="{LY - 4}" stroke="{e}" stroke-width="1.35"/>')
    c.arrowhead(56, LY - 4, 1, 0, e)
    c.text(66, LY, "flow inside Notchline", LEGEND_FS, p["muted"])

    x2 = 66 + approx_w("flow inside Notchline", LEGEND_FS) + 30
    c.add(f'<line x1="{x2}" y1="{LY - 4}" x2="{x2 + 24}" y2="{LY - 4}" stroke="{e}" '
          f'stroke-width="1.35" stroke-dasharray="4 4"/>')
    c.arrowhead(x2 + 28, LY - 4, 1, 0, e)
    c.text(x2 + 38, LY,
           "read-only observation of product-owned files, protocols and processes",
           LEGEND_FS, p["muted"])

    c.nolink(36, LY + 18, p["muted"])
    c.text(52, LY + 22,
           "no connection — the two App Servers never exchange live state; a Turn’s status reaches Notchline only through the hook socket",
           LEGEND_FS, p["muted"])

    body = "\n  ".join(c.o)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" '
        f'height="{H}" role="img" aria-label="Notchline architecture: Codex and Claude '
        f'Code boundaries converging on one merged snapshot and one overlay">\n  '
        f"{body}\n</svg>\n"
    )


import os
import sys

out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
open(f"{out}/notchline-architecture.svg", "w").write(build(LIGHT))
open(f"{out}/notchline-architecture-dark.svg", "w").write(build(DARK))
print("written")
