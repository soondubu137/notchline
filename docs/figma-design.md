# Notchline — Figma design specification

| Field | Value |
| --- | --- |
| Status | The V1 SwiftUI four-status contract is in sync. The status matrix is now 4×4 on four new curves with waiting split into Input and Approval treatments (§4.1); the external Figma component sets still need syncing. The settings window is rebuilt for macOS 26. System status has narrowed to `Disconnected` / `Connected`, with presence and widths implemented. The subagent marker has converged to **one badge, one total, an inverting ground**, one per product when collapsed, each in its own ink. Each matrix in the leading wing has gained a vertical session-count dot column to its right (as tall as the matrix, `+5.66` per mark). All implemented (§4.6, [`dual-agent-design.md`](dual-agent-design.md) §10–§11). External Figma `807:91` / `807:102` / `808:527` are still the old text variants, to be swapped for the ones in `12 — Counting: sessions and subagents` at the next sync. **The four row states are now told apart by the reading's ground, the body-line searchlight is restored, and the collapsed reading takes the same ground with its `8` permanently reserved** (§4.7 / §4.8 / §6.4, Figma `14 — Telling row states apart`), all three implemented, so the notch-less fixed widths are `209` / `238` / `136`. **The session-dot column now breathes while a finished, unread Turn is buried under a mark drawing something else** (§4.8, [`dual-agent-design.md`](dual-agent-design.md) §12, Figma `15 — The column breathes`), implemented, and it moves no width on this surface |
| Version | 1.7 |
| Date | 2026-08-28 |
| File | [Codex in Notch — V1](https://www.figma.com/design/B9qIi46zhdjbQYbjZo3AnM/Codex-in-Notch-%E2%80%94-V1) |

## 1. Design principles

1. The top component is a live summary of current Turns, not an entry point into history.
2. Notched and notch-less collapsed geometry differ, but both share one expanded content structure.
3. The expanded component always hugs the top edge and locks to the horizontal centre; the top summary region grows only horizontally.
4. Status, quota, Project, title, current content and processing time all come from real product semantics, never approximations.
5. Data that cannot be obtained reliably degrades explicitly, and is never filled in with mock, cached or approximate values.
6. Every Figma text layer uses SF Pro; Inter, SF Compact and other product typefaces must not be introduced.

## 2. Figma file structure

| Page | Purpose | Key nodes |
| --- | --- | --- |
| `00 — Cover & Notes` | File notes | — |
| `01 — Getting Started` | Usage notes | — |
| `02 — Foundations` | Colour, layout, type, motion, responsive corners | `99:38`, `99:39`, `287:2` |
| `03 — Status Components` | Status Dot, Readout, Usage Ring, Badge | `108:18`, `153:202`, `154:24` |
| `04 — Session Row` | Session row, list and status name pill; `807:91` / `807:102` are the Completed row's subagent trailing variants (§4.6) | `112:28`, `140:201`, `198:72`, `807:91`, `807:102` |
| `05 — Panel` | Collapsed and expanded Panel variants; `808:527` is the no-notch collapsed count+timer composite reading (§4.6) | `115:82`, `300:253`, `300:263`, `808:527` |
| `06 — Notch Core` | Core product states and menu-bar height references | `118:73`, `185:292`, `304:630`, `304:641` |
| `07 — Integration States` | Partial degradation; hidden previews and the thin-layer states are retired or merged into the two system states (§6.6) | `227:3`, `307:30` |
| `08 — Onboarding` | The first-run flow | `232:95`, `750:2` |
| `09 — Settings` | The macOS 26 settings window (light and dark), integration management and the `Session list` group | `609:2` (current); `233:3`, `591:2` (v1 reference) |
| `10 — Double Apps` | Two-product (Codex + Claude Code) design; `08 — Presence` defines the collapsed presence rules | `540:2`, `624:1560` |
| `11 — Subagent UI Concepts` | Subagent marker candidate review. The chosen `C — Numeral Chip` is superseded by page `12` (the split treatment is void entirely); kept as a review record | `812:2`, `815:116` |
| `12 — Counting: sessions and subagents` | **Current.** The subagent badge (one, a total, an inverting ground, one per product in its own ink when collapsed) and the session-count dots (a vertical column right of the matrix, as tall as it, the third dot stretching into a bar past three). §02 records the trade-offs across six treatments (including the void "below the matrix"), and §04 is the four-way record of "what to do past three". Rules in [`dual-agent-design.md`](dual-agent-design.md) §10–§11 | `857:2` |
| `13 — State matrices: the four marks` | The four collapsed Turn statuses' animated marks (Radar / Double Knock / Advance / Lull), 4×4 grid, `16.6` footprint unchanged. | `920:2` |
| `14 — Telling row states apart` | **Current.** How expanded rows distinguish the four states: the reading's ground (§4.7), the body-line searchlight (§4.8), and the collapsed reading taking the same ground with its `8` permanently reserved (§6.4). §05 records the five rejected alternatives | `932:2` |

This file describes the single-product contract. The design for monitoring Codex and Claude Code together is in [`dual-agent-design.md`](dual-agent-design.md), which supersedes two things here: the settings gear's position (§4.5, now the expanded top bar's top-right, applying to single-product too) and the two-product footer's quota composition (§4.3). Everything else is unaffected.

The current SwiftUI and this document recognise four session status variants only: Running, Input needed, Approval needed, Completed. Historical session-status variants beyond those four in the external Figma are no longer part of the product contract and should be deleted at the next sync; until then this document and the code govern. `Usage Ring`'s 7 legal variants, `Usage Indicator`'s 4, and `Panel`'s 8 (with `808:527` added 2026-08-23, §4.6) are unaffected by that narrowing.

## 3. Foundations

### 3.1 Typography

The file's local text styles and every existing and new text layer use `SF Pro`:

| Use | Weight | Size / line height |
| --- | --- | --- |
| Large title | Bold | `24–32 / 29–38` |
| Panel / window title | Semibold | `13–15 / 17–20` |
| Session title | Medium | `13 / 17` |
| Body and preview | Regular | `12–14 / 16–20` |
| Project / secondary | Regular | `11 / 14–15` |
| Status label | Semibold | `13 / 16` |

If the font is absent, install SF Pro before editing the file; a similar typeface must never be a permanent substitute. The current design environment provides the required Regular, Medium, Semibold and Bold weights.

**Known exception: the two `closing note` texts on `609:2` (light `665:3` / `665:5`, dark `667:3` / `667:5`) are currently Inter Regular.** Editing over MCP, `listAvailableFontsAsync()` lists SF Pro and `loadFontAsync` does not error, but glyph metrics come back empty: `characters` is written while node width and rendering stay at the old values — measured, the same button still read as the `49 pt` `Recheck` under SF Pro and immediately reflowed to the `115 pt` `Quit Codex in Notch` under Inter. Of the two harms: staying on SF Pro draws **copy that does not exist** for everyone who looks at the board, while switching to Inter reads correctly with one wrong font. The latter is chosen, recorded on the verification checklist, and awaits re-typing in a Figma desktop client that has SF Pro.

**Exception widened (2026-08-23, subagent support sync):** the two new trailing text nodes on `112:28` (Session Row) — `807:101` "2 subagents" and `807:112` "1 subagent" (§4.4 / §4.6) — and `808:562` on `115:82` (Panel, the no-notch collapsed trailing wing's composite "2 │ 1:23") moved to Inter for the same reason. All three are **new copy** rather than edits of existing SF Pro nodes — but creating a text node in SF Pro with `figma.createText()` does not render either (blank, zero width), so the limitation covers creation as well as editing. `808:562` has a second exception: the separator should be `U+2502` (BOX DRAWINGS LIGHT VERTICAL), which Inter does not have in this file (it renders blank), so ASCII `|` stands in for now. All three nodes carry the same note and to-do in their `description`. This is not a precedent — Inter is not to be used for new copy because it is convenient, only when the same rendering limitation blocks SF Pro again, and it must be recorded on the spot.

### 3.2 Colour

- Panel background: pure black, or the existing `surface/notch` / `surface/panel` tokens.
- Panel outline stroke (optional, off by default): `#5D5D60` (three-quarters of the Running timer's grey), `0.8 pt`, drawn inside the contour, and never along the top edge (§8.4).
- Primary text: white on the dark panel, near-black in native windows.
- Secondary text: neutral grey.
- Running: blue. Input/Approval: amber. Completed: green. Disconnected / version unavailable: purple.

Those tokens serve the notch component. **Native windows (Settings, Onboarding) have their own set, `Color / macOS Window`**, the only set in this file with `Light` and `Dark` modes, carrying macOS window semantics: `window/bg`, `window/titlebar`, `window/stroke`, `group/bg`, `group/stroke`, `separator`, `text/primary｜secondary｜tertiary`, `accent`, `control/bg`, `control/stroke`, `switch/off-track`, `knob`, `status/green`, `product/codex`, `product/claude`. Native light and dark must come from that set's modes, never from two hard-coded copies.

### 3.3 Layout tokens

| Item | Value |
| --- | --- |
| Expanded header | `520` wide, height = the real `menuBarHeight`; content width `496` at `46` |
| Session viewport | `508 × 240` |
| Session row | `508 × 80` |
| Horizontal panel padding | `12` |
| Session row gutter / padding | `6` + `6`; `12` + `8` while drawing `Colour bar`, below |
| Status dot | `8 × 8` |
| Usage ring | `18 × 18`, stroke `2` |
| Row badge | `24` tall |

> **Collapsed and expanded overall sizes are no longer tokens; they are compositions.** Earlier revisions of this table carried `348 × 46`, `168 × 46`, `200 × 46`, `520 × 302`, a `256` content region and a `520 × 94` thin state, and every one of those is stale. Collapsed widths are composed by `PanelMetrics` from measured text and rounded up: the notch-less single-product working set is one fixed `209` (so `Running` and `Input needed` are the same width, not `168` and `200`), two products `238`, and `Disconnected` `136` (§6.4). The notched form is two wings plus the occlusion, varying with the cut-out and the menu bar: under a `200 × 46` cut-out, resting is `246` for one product and `274` for two, becoming `299` / `327` with a `1:23` timer (§5). **Those are the numbers for one scaling step, not for "this machine"** — the cut-out is measured, and another step gives another set: this machine currently measures `220 × 38`, giving `265` / `293` and `319` / `347`. The first three were `201` / `230` / `136` before the reading's ground (§4.7) and `196` / `218` / `240` before the session-count dots; `Disconnected` is unchanged by both, having neither a dot column nor a reading. **Expanded height is `menuBarHeight + 240 viewport + footer`**, so at a `46` menu bar it is `316` (Codex only), `339` (Claude Code only), `370` (both) and `308` (quota block folded) — never `302`. Those four were `326` / `340` / `370` / `314` while each footer was a constant of its own; they are now composed from their content plus one shared `6` bottom margin ([`dual-agent-design.md`](dual-agent-design.md) §5.1). The thin expanded state is a `48` body plus the footer, `124` at that height. Read §5, §6.4 and §6.8 for current numbers; these notes exist only to date older files.

**A session row is two `6`s wider than the rest of the panel.** The row block is inset `6` from the panel edge rather than `12`, so the hover fill does not hit the edge, and the row adds `6` back, putting in-row text at `12` — the same margin as the header's status matrix and the footer's quota rules. The two numbers are therefore defined by each other (`PanelMetrics.sessionRowGutter` and `sessionRowPadding = expandedHorizontalPadding − sessionRowGutter`) rather than being two hard-coded `6`s; `aRowsTextLandsOnTheSameMarginAsTheRestOfThePanel` pins the relationship. The row block is `520 − 6 − 6 = 508` and the content box `520 − 12 − 12 = 496`.

**Drawing the `Colour bar` changes the inset to `12` + `8`.** The bar is drawn at the row block's leading edge, so the block's inset is the bar's position: left at `6` it sits half a `12` inside the status matrix above and the quota rules below, and nearly-aligned reads worse than not aligned. So **only while the bar is drawn** (both products connected, [`dual-agent-design.md`](dual-agent-design.md) §4) the block gives up a full `12`, and the in-row padding goes from `6` to `8` — it now measures distance from that `2 pt` line rather than from the panel edge, and `6` makes line and text read as one thing — putting in-row text at `20`, standing behind the bar rather than riding on it. The block is then `520 − 12 − 12 = 496`, the same as the content box. With one product there is no bar, the block returns to `6` + `6`, and text still lands at `12`. This geometry comes from `MonitorStore.sessionRowGutter` and `sessionRowPadding`, pinned by `theAttributionRailLandsOnThePanelsOwnMargin` and `theRowBlockOnlyGivesUpItsGutterWhileTheRailIsDrawn`.

When the target display's menu bar is not `46`, the top summary region uses the real height and the total is that plus the viewport and footer. With a physical notch, width also grows with the central unavailable region so that the longest reachable status names stay fully inside the displayable area. One side is computed from **the side actually drawn** in the top bar: `12 + marks + 12 + longest reachable status name + 8`.

- Marks are `PanelMetrics.marksWidth(markCount)`, including each product's reserved session-count dot column (§4.6): `22.26` for one product, `50.51` for two.
- "Longest reachable" means what `MonitorAggregation.status` can actually produce, the longest being `Approval needed` (`102` at the label's own ceiled width). The four sentences like `Version unsupported` (`125`) appear only in the settings window, cannot be said by the top bar, and **are not reserved for**.

So one side is `156.25` for one product and `184.51` for two: under a `200` occlusion, one product still takes the `520` baseline and two take `570`; under `220`, `533` and `590`.

**The panel is centred, so it can only widen symmetrically — deliberately.** The expanded panel is pinned to the display's centreline (`OverlayPanelLayout.frame` receives a `nil` `trailingAnchor` while expanded), so every extra point the leading side wants is taken from the trailing side too: the leading side wants `184.51` while the trailing holds only a gear (`12 + 27.6 + 8 = 47.6`), leaving about `137` with nothing to put in it under two products. Pinning to the cut-out as the collapsed form does (`trailingAnchor = centerOcclusionMaxX + trailing wing`) would let each side take what it needs — `184.51 + 220 + 47.6 = 452`, under the `520` baseline, so the cut-out branch would never fire and both cases would stay at `520`. **Evaluated and rejected**: an expanded panel is meant to be centred on the display, symmetric widening is the intent rather than an oversight, and the cost (`590` rather than `520` under this machine's `220` cut-out with two products) is knowingly accepted.

**The cut-out really is centred, so this needs no further worry.** The collapsed form deliberately does not assume it (it reads `centerOcclusionMaxX` and pins the right edge there); the expanded form does. Measured here: `frame (0, 0, 1800, 1169)`, `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` `790` wide each, cut-out `790…1010`, centre `900`, differing from the display centreline by `0.0000`. On real hardware the assumption costs nothing; in theory it could differ by half a point at scaling steps where `(frame width − cut-out width)` is odd, and the panel's own `ceil` already leaves `0.25`–`0.49` of slack.

> **This widening now depends on how many products are connected, and did not before.** The old expression computed from one bare `16.6` matrix, written in the single-product era with no dot columns, and folded the longest name over `MonitorStatus.allCases`, reserving `23.3` extra for a `Version unsupported` the top bar cannot say. That over-reservation happened to cover the second matrix's `22.6` (with `0.72` to spare) until the dot columns' `11.31` overdrew it by `10.59` — under a `200` occlusion with two products at `Approval needed`, the last `2.57` fell under the notch, with the `8` of clearance long gone. Both were fixed together: a side is measured from `marksWidth`, and the fold narrowed to what the top bar can genuinely say. Pinned by `everySentenceTheExpandedHeaderCanSayClearsTheCutOut` and `theExpandedWidthAnswersToTheMarksAndNotToUnreachableNames`; the assertion they replaced used `expandedStatusReadoutWidth` as the "required width", which is the same expression it was checking, so it passed at any mark count.

The panel outline has **two** corner radii, because the notch has two: where the sides meet the top of the screen there is a small outward fillet, and the two lower corners are twice it. Neither is a constant; both are fixed ratios of the menu-bar height:

```text
shoulderRadius     = max(0, menuBarHeight) / 8    // the upper fillet, and the "shoulder" each side of the window
bottomCornerRadius = max(0, menuBarHeight) / 4    // the lower corners
```

**Ratios rather than constants**, because the hardware is: the notch is a cut-out of fixed millimetres, a notched screen's menu bar is exactly as tall as it (to within a point, §3.4), and both shrink together in points as scaling coarsens — `220 × 38` under *More Space*, `185 × 32` by default, `127 × 22` at *Larger Text*. A hard-coded radius is right at one step and too round at every other; the old code fixed `10` on notched screens, which is `25%` rounder than the real cut-out at default scaling and nearly a capsule at `22`.

The ratios come from Iconfactory's Notchmeister, which traces the outline directly onto the hardware cut-out: `notchUpperRadius = 4` and `notchLowerRadius = 8` for the default `185 × 32`. The upper fillet matches the `13.5%` measured in Apple's own machine icon (`com.apple.macbookpro-14-2021`); the icon draws the lower corners rounder (about `40%`), but that is illustration-scale exaggeration and the trace governs. Both arcs are **true circular arcs** (`0.5523` control handles), matching the cut-out's edge.

Reference values: `38 → 4.75 / 9.5`, `32 → 4 / 8`, `28 → 3.5 / 7`, `24 → 3 / 6`, `22 → 2.75 / 5.5`, `19 → 2.375 / 4.75`. Notched and notch-less use one rule — the notch-less form imitates that same cut-out, and the new lower ratio (`25%`) almost coincides with the old formula's `26.32%`, so external displays look unchanged and only the upper fillet halves. Figma's responsive examples (`287:8`, `287:12`, `287:16`) are still the old single radius `10 / 6.316 / 5` and **are not yet synced**.

### 3.4 Panel body, window and notch alignment

Only `PanelContour`'s top edge fills the rectangle it is given; below that it narrows to vertical sides inset by one shoulder width (`shoulderRadius`), leaving a "shoulder" each side that holds the fillet back up to the menu bar.

So every reference size in this file describes the **panel body** — the black that is actually drawn — while the `NSPanel` carrying it is one shoulder wider on each side (`OverlayPanelLayout.frame(on:panelSize:surfaceShoulder:trailingAnchor:)`'s `surfaceShoulder`). Opening the window at body size is simply wrong: the collapsed form's right edge falls a shoulder inside the notch and the bottom corner eats a radius more, so the notch's lower-right looks bitten off.

The notched collapsed panel is **anchored to the cut-out's right edge**: `NSScreen.auxiliaryTopRightArea.minX` plus the trailing wing's width, no longer derived from screen centre plus an offset. The old form was equivalent only when the cut-out was exactly centred and the body width was not rounded; rounding slack now lands in the leading wing, which is whitespace and can absorb half a point, whereas a hardware-aligned right edge cannot. The expanded and notch-less forms still lock to the screen's horizontal centre.

**Panel height is the band the menu bar occupies, on notched screens too.** `NSScreen` gives two numbers a point apart: `safeAreaInsets.top` is the camera cut-out, and `frame.maxY - visibleFrame.maxY` is the height the menu bar **occupies**, the extra point being the gap `visibleFrame` leaves below the menu bar for window content. Measured on a 14-inch M3 Pro under *More Space*: safe area `38`, occupied `39`.

`menuBarHeight` takes the larger, so the panel is one point taller than the hardware cut-out on a notched screen (two pixels at 2x). That is deliberate: one rule for every screen, where collapsed means "fill the menu bar band it is in", and taking height from the cut-out would make the panel look shorter than the notch. Pinned by `aNotchedPanelIsAsTallAsTheBandTheMenuBarOccupies`.

**With an empty trailing wing, the right edge does not sit exactly on the reported edge but steps a little past it**: `menuBarHeight / 16` (`PanelMetrics.winglessTrailingOvershoot(menuBarHeight:)`, `2.375` at `38` and `1.375` at `22`). `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` describe the cut-out as a rectangle and the hardware is not one: where the cut-out meets the top of the screen the glass flares outwards, and the black there is wider than the rectangle. With the right edge exactly on the reported value, the upper half of the shoulder's fillet is drawn behind that flare, reading as the panel stopping short of the notch rather than continuing out of it. It is visible only once `Outline the panel` (§8.4) is on: what is cut is the hairline, and pure black has nothing to compare against.

That flare **cannot be read**, so this is a deliberate nudge rather than a derived value: the system gives only the rectangle, and a screenshot is no second opinion — the framebuffer draws right under the notch, so capturing that strip yields wallpaper rather than the black a person sees. Getting the real outline would mean per-model hardware dimensions, and this panel only needs to *clear* it. Taking a ratio of the menu-bar height follows the same logic as the two corner radii (§3.3): what occludes it is hardware of fixed millimetres, and both shrink together in points as scaling coarsens.

Only the trailing side takes this step, and only when that wing is empty: a wing wide enough to draw a timer or a badge has long since cleared the flare, and the leading side is either a wing that clears it too or a resting form that should not be visible anyway. That latter case (`drawsCompactMarks == false`, meaning resting and `Hide the wings`) **does sit exactly on the reported value** — that form's body is the cut-out itself, and stepping outwards would hang a black edge beside the notch. The panel absorbs the step into its own width, widening the anchor and window together, so the left edge and everything measured from it stay put. Pinned by `aWinglessTrailingEdgeStepsClearOfTheCutOut`.

Content (including the `12` horizontal padding) is laid out inside the body, so padding is measured from the black edge; the pointer region likewise covers only the body, with the shoulders yielding clicks to the menu bar items beneath them.

## 4. Core components

### 4.1 Status Dot

`Status Dot` holds two families that are never mixed: session-level Running, Input Needed, Approval Needed, Completed; and system-level Idle, Connecting, Disconnected, Update Required, Unsupported Version, Setup Required.

- Idle (the old name) was only ever the summary for a healthy empty set and has merged into `Connected`.
- Disconnected is never used on a session row.
- **System-level values have narrowed to two**: `Disconnected` and `Connected` (§6.4). `Idle` merged into `Connected`, and `Connecting`, `Update Required`, `Unsupported Version` and `Setup Required` have left the collapsed state (§6.6), appearing only in the expanded panel and Settings, so their component variants are kept.

#### The matrix's five treatments

The mark is a **4×4** matrix whose geometric ratios are identical to its 3×3 form: cell `27`, pitch `32`, corner `2`, four to a side, so the viewBox goes from `91` to `123`. The mark's outer size is unchanged — `PanelMetrics.statusMatrixSize` is still `16.6` — and the cell it buys shrinks from `4.92` to `3.64`. The animation curves are the SVGs in `design/assets/matrix-states/`, with per-cell opacity at 30fps:

| Treatment | Status | Period | Pattern | Darkest |
| --- | --- | --- | --- | --- |
| Radar | Running | `1.2 s` (36 frames) | A beam sweeps clockwise about the mark's centre; a cell reaches full as the beam crosses it, then decays exponentially back to `0.139` with a 10.2-frame (`341 ms`) time constant. Each cell's phase is the bearing of its own centre from the mark's centre | `0.139` |
| Double knock | Approval needed | `1.2 s` (36 frames) | The whole matrix reaches full, knocks twice `300 ms` apart with a 3-frame decay each, then rests at `0.05` for `900 ms` | `0.05` |
| Advance | Input needed | `0.8 s` (24 frames) | The top three rows light one full column at a time, `200 ms` each, left to right; the bottom row does not take part and rests at `0.3` | `0.05` |
| Lull | Completed | `2 s` (60 frames) | A crest travels the anti-diagonal (the mark's own seam) in six steps using 48.7 of the 60 frames; a cell falls to `0.182` behind the crest and sits at the trough for about three-quarters of a second | `0.182` |
| (still) | Connected / Disconnected | — | Does not move | `0.15` |

**A mark fades between the still and a pattern, and cuts between two patterns.** Going dim to lit and lit to dim is the mark starting or stopping having something to say — a turn beginning, a finished one being read. Cut, those read as a light being thrown: louder than the quiet events they carry. So the two lit stacks are crossed over — `MatrixDissolve`, `0.32 s` on a symmetric ease, `0.12 s` under Reduce Motion, which shortens the hand-over rather than removing it (a dissolve is what movement is replaced *with*) — and the pattern comes up out of the still and goes back down into it. **The curve is not `PanelMotion`'s, and that is the whole of why the first version could not be seen.** `(0.22, 1, 0.36, 1)` is an arrival: right for a panel that should reach its size and settle, and `96%` across at its own midpoint, so a `0.20 s` dissolve was finished inside `60 ms` and landed as the hard swap it was there to replace. Nothing about a cross-fade is an arrival and the part worth seeing is the middle, where the mark is genuinely half of each, so the dissolve is symmetric and long enough to have a middle at all. `aMarkFadesBetweenTheStillAndAPatternButNotBetweenTwoPatterns` reads the curve back and pins that it is about half way across half way through. **The unlit bed is no part of the fade**: it draws the same sixteen cells whatever the pattern is, so fading it would fade the mark itself away rather than the pattern on it. **The pattern leaving goes on running while it goes**, both stacks drawing for the length of the fade, so a completed mark's crest is still crossing as it dissolves rather than freezing on a frame and then vanishing. **A change between two live patterns is cut** — Running to Completed, Input to Approval — because the product is saying a different thing and there is no moment at which it is half of each; it is also the fade the eye would read least, both sides being lit and moving. `MatrixIndicatorView.dissolves(from:to:)` is the rule, pinned by `aMarkFadesBetweenTheStillAndAPatternButNotBetweenTwoPatterns`.

**Input and Approval became two patterns.** They previously shared one flash, so the collapsed state could say "something wants you" but not which kind; with two patterns the mark distinguishes "a question the keyboard can answer" from "a decision it cannot get past", which is what a user needs to decide whether to put down what they are doing. The cost is that onboarding's row goes from four swatches to five (§7), and the summary priority now also decides which pattern a bar holding both kinds of wait draws — see [`PRD.md`](PRD.md) §6.2 (Approval before Input).

**Each treatment has its own darkness, so readability no longer requires deviating from the design files.** The previous version's two tracks (waiting and terminal) were changed in code to bottom out at `0.100` rather than the file's `0.200`, because the file rested every dark cell at one level and "waiting for you" was as black as "nothing running". These four files rest at three different levels — `0.05` for knock and advance, `0.139` for radar, `0.182` for lull — with the resting level threaded between them, so darkness alone still separates a mark waiting on the user from one that is merely present, and that deviation was removed entirely.

**Resting moved from `0.18` to `0.15`.** That level comes from no design file — there is no still frame in `matrix-states/` — so it follows the four live tracks. `0.18` was set while lull still rested at `0.343`, and the redrawn lull's trough is `0.182`, making "this Turn ended" and "nothing is running" equally dark at the trough. Lowering it restores the ordering: both waits' `0.05` below it, lull's `0.182` above it, radar's `0.139` below. Only the first of those three gaps is a darkness difference the eye genuinely reads — a mark waiting on the user is three times darker than resting, and that is the pair that must never be confused. The other two are ordering and need not carry weight on their own: neither radar nor lull ever has all sixteen cells at the trough, so a live mark always has a lit cell while a resting one has none. What `eachStateDrawsThePatternItsDesignFileDraws` pins is that ordering, not these three numbers.

**The seam direction now has other witnesses.** The four old patterns were vertically symmetric, so a wrong `isFlipped` showed only on onboarding's diagonal (§7). Three of the four new ones are asymmetric: radar sweeps backwards, advance's bottom row moves to the top, and lull walks the wrong diagonal. `theSplitMatrixCutsOnTheSameDiagonalAsTheMark` is still the most direct assertion, and `eachStateDrawsThePatternItsDesignFileDraws` pins all four tracks and their phases cell by cell.

**The glow keeps the old treatment and did not change with them.** Each file carries one `feGaussianBlur stdDeviation=12.65` layer (about `0.09` cells) at alpha `0.55`; the code still draws three blur layers plus a solid copy, the widest at `10.5/27` cells. Adopting the file's version is right on an `800px` board and would shrink the glow to `0.33 pt` on a `16.6 pt` mark — effectively none — while the glow at this size is exactly what lets a `3.64 pt` cell hold up against a wallpaper. The pattern changed; the layer drawing it did not.

**4×4 did not take the session-count dots with it.** The dot column still measures in the `91` units (dot `2.74`, gap `2.92`, bar `4.93`, column `5.66`), for the reasoning and values in [`dual-agent-design.md`](dual-agent-design.md) §11 and the comment on `PanelMetrics.sessionDotViewBox`: read in the new units it would give a `2.02` dot, already uncountable.

Implementation: `MatrixGrid` (geometry), `MatrixTrack` (the four curves and three phase rules), `NotchMatrixState` (status to treatment) and `MatrixIndicatorView` (layers and glow), all in `NotchStatusMatrix.swift`.

### 4.2 Status Readout

Both the Compact and Expanded contexts carry full status text. In Expanded the dot-to-name gap is `12`, **and it is `12` at every session count**: the reserved-but-undrawn part of the dot column lands after the status name, so the name follows the marks actually drawn and shares their open/close curve ([`dual-agent-design.md`](dual-agent-design.md) §11). A status name must never be occluded by the physical notch.

### 4.3 Usage Ring and Indicator

- At `100%` it is a fully lit ring; as the remainder falls, a dark arc grows anticlockwise from twelve o'clock while the lit arc shortens to match, and a partial ring has round caps.
- The lit full ring and the dark arc share a `9 pt` centreline radius and a `2 pt` centred stroke; the dark arc must never shrink inwards.
- `0%` is a fully dark ring. Unavailable also shows only the full track colour, but its value reads `--` and must never be confused with a real `0%`.
- `> 50%` white, `15%–50%` amber, `< 15%` red.
- Unavailable is a grey ring and never shows a fabricated percentage.
- The expanded leading value is always the remaining percentage; Running does not replace the quota text.

The Figma `Usage Ring` set (`108:18`) has seven variants — `100`, `72`, `50`, `32`, `10`, `0` and `Unavailable` — and `Usage Indicator` (`153:202`) has four: Healthy, Warning, Critical, Unavailable.

### 4.4 Session Row

Each row shows Project, title and current content on the left, with the status control on the right.

- Running always shows the blue `Running` status name badge.
- Other statuses show a dot by default, expanding to the name badge on hover.
- Left-hand text alpha-fades as it nears the trailing control, never wrapping and never showing an ellipsis.
- At most three rows are visible; more scroll vertically.

### 4.5 Panel

The Panel set keeps Notch Compact, No Notch Compact and Expanded.

- The header is `46` in the reference design (the real menu-bar height in practice), and expanding grows it only horizontally.
- The session viewport is `240` (three `80` rows).
- **Total expanded height is composed, never a constant**: `menuBarHeight + 240 + footer`, which is `316` / `339` / `370` / `308` at the `46` reference (§3.3), the footer itself being its content plus one shared `6` bottom margin. Earlier revisions of this section carried `444 × 310` and then `520 × 302` with a `256` content region; all three predate the footer.
- The existing `06 — Notch Core` Running Desktop board has been re-centred to `x = 496` for a `1512` screen.

The Figma `Panel` set (`115:82`) uses `Mode`, `Content` and `Menu Bar` properties. Besides the `46` reference it includes the notch-less `24` menu bar's Compact Running (`300:253`, corner `6.316`) and Expanded (`300:263`, corner `6.316`). Every variant uses the same outer contour as SwiftUI's `PanelContour`, never a plain rounded rectangle.

### 4.6 Processing time

PRD §8.2 and the technical design settled authoritative time semantics, waiting/sleep behaviour, accessibility copy and refresh cost, so processing time is in scope. It is not a separate runtime badge: an unfinished row uses the timer text itself as its status marker, and a row only ever carries one marker. ~~Waiting on a person is amber Medium, Running is dark Light, and Completed shows no timer, only the green dot.~~ **Those three treatments are superseded by the ground, §4.7.**

### 4.7 The reading's ground: four states told apart by outline

**The old treatment used two channels, presence and brightness, and both are comparisons.** "No timer" reads as finished only when the row beside it has one; "the timer is white" reads as waiting only when the row beside it is darker. Cover the neighbours, or let the list happen to hold one state throughout, and neither question can be answered — which is why those two states were hard to find, not that they were drawn too dimly.

**Instead the reading gets a ground: one slot, one mark, three outlines** (Figma `14 — Telling row states apart`):

| Status | Treatment | Ink |
| --- | --- | --- |
| Running | A bare reading, no ground | `#7C7C80` Light 13, monospaced digits |
| Approval / Input needed | The same reading on a white ground | ground `#FFFFFF`, text `#0D0D0F` Medium |
| Completed | The reading on a dark ground, holding **how long this Turn took** | ground `row ground + 0.06` (so `#242424` on black), text `#7C7C80` Light |

The ground is §4.6's subagent badge scaled to the reading's width: the same `16` height, `4` corner and `4` each side. It was always "a reading on a ground that inverts", and that one mark now answers for both this Turn and the subagents it spawned, so **combining them on one row needs no special case at all** — a finished row with subagents still running keeps the slot for the badge, the outline unchanged, with a count inside instead of a duration.

Three derived rules:

- **Running is the only bare one.** A family of outlines needs one member that is "nothing at all", and it should be the state that occupies most of the list; it is also the collapsed state's most-drawn form, so the two interfaces stay consistent on the most common row.
- **The dark ground is a `0.06` lift of the row's ground, not a fixed value.** A row brightens to `#2B2B2E` under the pointer and `#3A3A3D` when pressed, both above a hard-coded `#242424` — so hard-coded, the mark would turn into a hole at exactly the moment the pointer lands on it. Taking the brighter of the ink and the row ground and lifting that keeps the historical `#242424` at rest and rises with the row. This also fixed the subagent badge, which was hard-coded and had the same flaw. Pinned by `theDimGroundStaysAboveTheRowItIsDrawnOn`.
- **A finished row gets a number back.** The slot has to draw something, and the only honest thing was already computed and thrown away: how long this Turn took — a fact nothing else on this surface reports, and what turns the mark from an absence into a record. It comes from the Turn's own last event (`MonitoredSession.finishedAt`), a stamp deliberately not moved forward by subagent activity, which is exactly the property this reading needs. Pinned by `aFinishedRowDrawsTheLengthOfTheTurnItRan`.

**The collapsed state uses the same family, and the ground's `8` is always reserved.** See §6.4.

### 4.8 The searchlight: the body line's third channel

**An unfinished Turn's body line has a white sweep crossing it, and a finished one does not.** The ground answers which state; the sweep answers running versus ended — the one channel here readable without looking directly at it, and a menu-bar panel is looked at peripherally by nature.

- Only the body line (current content) sweeps; the title and caption never sweep in any state.
- It sweeps only in the three timed states: Running, Input needed, Approval needed.
- **A finished Turn does not sweep even with subagents still running.** The sweep follows the Turn, not the thread: the line it crosses is this Turn's own final output, and what is still in flight is said by the badge in the slot.
- Reduce Motion turns it off entirely — which is precisely why the ground must state the status on its own; two channels only help if they fail under different conditions.
- Treatment: a second white raster of the same glyphs, masked by a gradient band (`0 / 0.40 / 0.50 / 0.60 / 1`, peak in the middle), translated on the render server on a `2 s` linear loop; the band is four times the width it crosses, so the peak reaches the glyphs only at 40% of the loop. Phase comes from the clock rather than install time, so every row is in phase and replacing the text does not restart the loop (`NotchTextRaster.installSweep`).

Pinned by `sessionRowTextSweepsOnlyWhileItsTurnIsUnfinished` and `onlyAnUnfinishedTurnSweepsItsBody`. The sweep was always in the design files, drawn on every example row on pages `12` and `14`; the product side removed it in `bc3735e` and it is now restored.

**The row-end position has one more thing to say once the timer stops, and only one — a text marker like `N subagents` is replaced by a numeral badge** (`15 × 15`, corner `4`, [`dual-agent-design.md`](dual-agent-design.md) §10). While this Thread's Turn has ended and subagents it spawned are still running or waiting on approval (both products reach this), the same position draws a `SubagentBadgeView`: **the number is every subagent** (waiting ones included), and **the ground says whether anything is waiting on you** — all running is ground `#242424` with text `#7C7C80`, and one stopped at approval or input inverts it to ground `#FFFFFF` with text `#0D0D0F`. There is only ever one, never split into "waiting" and "running": splitting puts two numbers at the row end at exactly the moment a person is needed, and the ground says the same thing for free. In the expanded state this badge is always neutral and never takes a product ink — the row has already said which product through its attribution marker or Project caption. This **does not violate "one marker per row"** — there is one position, the timer gets it first, and the badge only follows once there is no timer; the two never coexist. A running row draws no badge, because it is already saying this Thread is working. Product reasoning and status semantics in [`PRD.md`](PRD.md) §6.1 and §9.3. SwiftUI: `SubagentBadgeView` (`NotchStatusMatrix.swift`), data from `MonitoredSession.subagentBadge` (`MonitorDomain.swift`). **External Figma to clean up**: `807:91` / `807:102` on `112:28` are still the old text markers and should become the badge variants at the next sync, per `12 — Counting: sessions and subagents` §01.

**The same fact is drawn differently when collapsed, under two different rules: there the badge and the timer coexist, and there is one per product, each in its own ink.** The row-end position belongs to one row while the collapsed trailing wing belongs to the whole list, so it states totals and has no "saying it twice" problem — the timer describes the longest Turn while the badges describe how many subagents each product still has. Badges sit before the timer, Codex always first (the same ordering rule as the leading wing's matrix pair, never reordered by urgency); with every Turn ended and subagents still running or waiting there is no timer to read and only badges remain. The colouring rule is the inverse of the expanded row's: **each badge takes its own product's ink** (Codex text `#6CB4FF` / ground `#1F2A35`, inverting to `#101B26` / `#6CB4FF`; Claude Code `#D97757` / `#30211C` and `#21120D` / `#D97757`), because a bar has no caption line and ink is the only thing that can answer whose it is. A product with no subagents has no badge and no space reserved. Two badges are `6` apart (taken from the `6` between the matrices) and a badge is `8` from the timer. **Inverting changes no width**: nothing on the bar moves when a product goes from all-running to something-waiting. A collapsed state reading `Running` with no timer in the trailing wing is that form's normal appearance, not a gap ([`PRD.md`](PRD.md) §6.2). **There is an even shorter form: `Running` with an entirely empty trailing wing.** It appears between a Claude Code subagent wrapping up and the parent Turn waking — measured 50–130 ms — when nothing is timing and no subagent is countable while the Thread really is still working (`PRD.md` §6.2 band 3). It is too brief to warrant a variant; the point is that an **empty** trailing wing does not mean the status word is wrong, so do not add a placeholder reading when you see that combination. SwiftUI: `CompactTrailingReading.badges` / `PanelMetrics.subagentBadgeWidth` / `subagentBadgesWidth` / `compactTrailingReadingWidth` (`MonitorStore.swift`), aggregated by `MonitorStore.compactSubagentBadges`. **External Figma to clean up**: `808:527` on `115:82` (the `2 │ 1:23` composite reading) likewise needs the capsule variant from `12 — Counting: sessions and subagents` §03.

**The leading wing gained one more thing: a vertical column of session-count dots right of each matrix.** One dot per row from the top edge at `5.84` pitch, three dots filling the mark's height, and past three rows the third stretches into a `4.93` bar meaning "more than three". That pitch was the matrix's own row pitch while it was 3×3, and the dot column **did not follow** the matrix to 4×4 (§4.1). The colour is the product's lit colour at `85%`, and it never joins the matrix's animation — though the column now has **one movement of its own**, and only one: it breathes while that product's list holds a finished, unread Turn its own mark is not drawing ([`dual-agent-design.md`](dual-agent-design.md) §12). That is the one state the summary can lose — Approval outranks everything, Input loses only to Approval with the mark still saying a person is wanted, and a Running Turn that loses asks for nobody — so it is the one state that needed a second place to stand. Opacity only, `0.85` to `0.50` over `2.8 s`, slower than lull so it cannot read as a fifth pattern; no width changes anywhere, and the expanded top bar draws the same columns still. **The column is exactly as tall as the matrix** (`2 × 5.84 + 4.93 = 16.6`), so it needs no vertical space the matrix did not already have and draws identically at the `46` and `22` steps. What it costs is width: each product's mark goes from `16.6` to `22.26` (gap `2.92` + dot `2.74`), **and it is that width at any session count** — letting the panel flex with the count would shift the matrix itself sideways when a thread starts or the last row is removed. Reserved is reserved, but a connected product with no rows **does not draw** the column (an empty one would stretch the paired `6` to `11.66`), and the width it gives up lands **after the status name**, not between the marks and the name. So "status matrix" in the geometry tables below always reads as "mark `22.26`", except the resting grey mark (no product behind it, so still `16.6`). Full rules, values, and why it was first drawn as a numeral square right of the matrix and then as a row of dots below it, in [`dual-agent-design.md`](dual-agent-design.md) §11.

Collapsed, the right of the notch shows the global longest running time, forming the second wing beside the leading status readout; with no unfinished Turn and no subagent running, that wing disappears entirely rather than rendering a second false notch. The expanded state does not repeat that summary. Timer text uses monospaced digits, so the trailing wing's width changes only when a digit is added.

**The leading wing is handled per form** (§6.4): with no agent connected, the notched form drops the leading wing too and keeps only the `200` occlusion, while the notch-less form keeps it, drawing a grey matrix plus `Disconnected` — a control that vanishes from the menu bar takes its position with it, so holding the position matters more than saving a wing.

Collapsed width is not a design constant: the implementation measures real rendered text and rounds up, so width is the result of layout rather than a number someone chose. **Figma variants' timer and status text layers must therefore hug contents and never have a fixed width.** Fixed width is the one failure mode worth remembering — a previous sync fixed the timer TEXT at `34` (natural width about `28.6`), making the notched timer variant `5.4` too wide overall, and the notch-less pair likewise ran over by more than ten points.

One fixed value can be checked directly: the notched form's leading wing = `12` padding + `22.26` mark (matrix `16.6` + dot column `5.66`) + `8` clearance = `42.26`, giving a `242.26` body with a `200` occlusion; with an empty trailing wing the right edge also steps out by `menuBarHeight / 16` (§3.4), which is `2.875` at `46`, so the rounded collapsed width is `246` (`240` predates the dot column and `237` predates the step). That series is the arithmetic for the `200 × 46` step; this machine currently measures `220 × 38`, and the same arithmetic gives `42.26 + 220 + 2.375 = 265`. The trailing wing starts at `x = 250.26` (`42.26 + 200 + 8`) and its width follows what it actually draws — `CompactTrailingReading` composes the badges' width (`PanelMetrics.subagentBadgesWidth`) and the timer text's into one reading (`compactTrailingReadingWidth`), so a badge appearing or a second one arriving simply lengthens that composite and the wing follows. One badge measures its own digits plus `4` padding each side with a `15 × 15` floor (two digits widen it rather than overflowing); two badges are `6` apart (`PanelMetrics.subagentBadgeSpacing` is literally `compactMatrixSpacing`), and a badge is `8` from the timer. The notch-less fixed width reserves a `00:00:00` (Medium) timer slot; when a badge-plus-timer combination does not fit, the pill widens rather than clipping the badge — the **only** place content moves that fixed width, because permanently widening every menu-bar pill for a reading that almost never appears is the worse side. Pinned by `theCollapsedCountGrowsTheSlotItSharesWithTheTimer`. The notch-less form otherwise no longer composes by content: the whole working set shares one fixed width (§6.4), and there is no longer a menu-bar-height-dependent minimum — apart from §3.4's step, nothing in `PanelMetrics` computes width from the menu-bar height, which decides only panel height and corners; that step is the exception because it clears a hardware shape, like the two radii. These relationships are pinned by `compactGeometryComposesTheNotchWings`, and no other width enters the contract.

> This paragraph has carried two rounds of older numbers: `18.4` / `50.4` / `251` predate the matrix moving to `16.6` (`13 × 1.2778`, `PanelMetrics.statusMatrixSize`), and `48.6` / `249` date from `24` side padding. After padding narrowed to `12` (`PanelMetrics.expandedHorizontalPadding`) the leading wing is `36.6` and the body `236.6`; `compactGeometryComposesTheNotchWings` previously asserted the `237` that rounds to, and asserts `240` after §3.4's step. §6.4's width table writes `16.62` for this same `16.6`; the `0.02` difference gives identical widths after `ceil`, so that table is unaffected. The trailing wing's composition was previously a single measured string (`2 │ 1:23`); replacing it with two separately measured readings summed gives the same number for a pure timer reading, and both `theCollapsedCountGrowsTheSlotItSharesWithTheTimer` and `compactGeometryComposesTheNotchWings` were re-run after that change.

## 5. The live monitored list

### 5.1 Membership semantics

A row is a navigable root Thread. Running, Input needed and Approval needed are always shown; Completed shows only while that product's desktop app still believes the user has not seen it, and is removed automatically once it is read, archived, deleted or no longer navigable. **A Claude Code session in a terminal is answered by its terminal** (ADR 0012's fifth path); only a session with neither a Desktop record nor a controlling terminal keeps its Completed row until that session's next submission, the session disappearing, or manual removal (right-click on the row; ~~clear the list~~ — clear-all was removed, §8.2). The annotation cards must state that difference, or the board looks as though every row disappears by itself.

The list covers every Project and `Chats` under the current account, does not follow the sidebar selection, never shows subagents, and does not serve as a history browser.

### 5.2 Sorting

```text
Approval needed
> Input needed
> Running
> Completed
```

Ties sort by most recent trustworthy update, descending. Sorting updates live, but must never force the viewport anchor to move while the user is scrolling or hovering.

### 5.3 Current content

| Status | Content |
| --- | --- |
| Input needed | The current question |
| Approval needed | The fixed `Approval requested` |
| Running | The latest public progress, falling back to this Turn's input |
| Completed | The start of the final answer; failing that, the last public progress |

All four take what the product has already shown the user. Raw reasoning, tool arguments, command output and diffs are absent not because they are forbidden but because this path never fetched them — showing them would mean adding a read, which is a new feature judged on its value ([`PRD.md`](PRD.md) §7).

## 6. Integration States

`07 — Integration States` (`227:3`) holds:

### 6.1 Content previews hidden (retired)

This cell drew a row with the preview switch off. That switch and the privacy promise it honoured are both deleted ([`PRD.md`](PRD.md) §7) and previews are always shown, so the cell no longer corresponds to any reachable state. Kept on the board, no longer an acceptance item.

### 6.2 Quota unavailable

The quota ring is a grey unavailable while the thread list, statuses and click behaviour keep working. This expresses partial degradation, never Disconnected.

### 6.3 Monitoring lifecycle

The annotation card states: a Turn enters on submission; an active Turn is always kept; a terminal Turn is kept only while the desktop app still shows it unread; it is removed automatically on read, archive, delete or loss of navigability; the notch never marks anything read; and **a terminal row whose read state cannot be answered does not take part in automatic removal**.

### 6.4 Presence: two system states

Design in `10 — Double Apps`'s `08 — Presence` (`624:1560`).

With two products supported, the app can no longer assume which one the user uses, so a matrix permanently dimmed for a product they never open has to go. But a control that vanishes from the menu bar takes its position with it, and a notch-less screen has no cut-out to hide behind — the pill must stay put. The solution is for the matrix to stop reporting our own connection health and report something the user can verify instead: **whether any coding agent is open**.

System states therefore narrow from six to two:

| Status | Holds when | Collapsed |
| --- | --- | --- |
| `Disconnected` | No coding agent is connected (§6.7) | Notched: draw nothing. Notch-less: a grey matrix plus the status name, holding the pill's position |
| `Connected` | At least one agent is connected and none is working | That product's own matrix, extinguished; no timer, since no Turn is unfinished |
| The four session statuses | A Turn is in progress | Unchanged: Running, Input needed, Approval needed, Completed |

`Idle` merged into `Connected`, and that rename is worth it: `Idle` described the empty list we see, which the user cannot verify, while `Connected` describes something they can check with a glance at their own Dock.

The matrix therefore carries three channels rather than two:

| Channel | Meaning |
| --- | --- |
| **Presence** | Whether that product is open. New — the channel the old design lacked and faked by always drawing an extinguished matrix |
| Hue | Which product. Unchanged |
| Brightness | Whether the user is needed. Unchanged |

Grey is not a fourth colour, and it is the **darkest** thing in the interface: `#151515` is the brightest neutral grey still at or below both products' extinguished brightness — relative luminance `0.0075`, against `#21120D`'s `0.0079` and `#101B26`'s `0.0104`. So "an agent is connected" can never look darker than "nothing is connected". Within a product, the lit/extinguished `15%` relationship is unchanged.

Resting and hover:

| Form | Resting | Hover |
| --- | --- | --- |
| Notched | Draws nothing, occupying only the `200` occlusion | The pill expands horizontally around the notch: grey matrix and status name leading, gear trailing |
| Notch-less | Grey matrix + `Disconnected` | Expands horizontally, adding the gear at the trailing end |

**The "notched, resting" cell is also the collapsed state with `Hide the wings` on.** That preference (§8.4) generalises this cell from "no product connected" to any time: neither matrix nor timer is drawn and the collapsed width equals the occlusion. It changes only the collapsed state; the hover column is unchanged. Both of this cell's reasons carry over unchanged — a notched screen's cut-out is already a shape on the screen and a second one beside it carries no information; and a screen whose cut-out cannot be measured (notch-less, or reporting a notch without an occlusion width) has no shape to shrink onto, which is why that row is disabled in settings.

**Hover only expands the pill; it does not drop the panel.** With no agent connected there is nothing to put in a panel, and the only point of expanding is to make the gear reachable; the reason lives in Settings, one action away.

> **Implementation record:** the `400 × 46` / `208 × 46` above and the `400.6 × 46` / `224.6 × 46` in §6.8's checklist contradict each other, and neither gives a composition. The implementation **computes it** like every other width here (`PanelMetrics.restingExpandedWidth`): leading padding `12` + matrix `16.6` + gap `12` + `Disconnected` `82.96` + gap `12` + gear + trailing padding `12`, with the notched form inserting `8 + occlusion + 8` in the middle. The gear scales with the menu bar (`32` at `46 pt`, `20` at `24 pt`, [`dual-agent-design.md`](dual-agent-design.md) §5.3), giving `179.56 → 180` notch-less and `395.56 → 396` notched (`200` occlusion) under this machine's `46 pt` menu bar. At `24` padding the same relationship gave `204` / `420`, now expired; `08 — Presence` has been redrawn at `396` / `180`. If the screen disagrees with the board, change this composition rather than hard-coding a number.

**The first product to open takes over the grey slot rather than being added beside it.** Grey means "no product", and once a product is present there is no "no product" to draw; a second slot appears only for a second product. Closing reverses step by step.

#### The fixed working width

The notch-less pill **does not change width across the whole single-product working set**: `Connected`, `Running`, `Approval`, `Input`, and timers up to `00:00:00` all use one width. It widens only when a second agent connects, and only by one matrix. `Disconnected` is the one state allowed to be narrower — no timer will follow it, and stretching it would leave a visibly empty pill beside a short name.

Widths are measured on this machine with `NSFont.systemFont(ofSize: 13)` and `monospacedDigitSystemFont`, the fonts the app actually renders:

| Component | Value |
| --- | --- |
| Leading padding | `12` |
| Status matrix | `16.62` |
| Gap | `12` |
| Widest compact name `Approval` (**the widest timeable status**, see below) | `52.74` |
| Clearance | `32` |
| Widest timer `00:00:00` (monospaced, Medium) | `57.91` |
| The reading ground's `4` each side (§4.7, **reserved whether drawn or not**) | `8` |
| Trailing padding | `12` |
| **Fixed working width** | **`203.27` → `204`** |

Everything else falls inside it: `Completed 118.43`, `Connected 118.67`, `Input + 00:00:00 + ground 180.98`, `Running + 00:00:00 + ground 199.52`, `Approval + 00:00:00 + ground 203.27`. Two products is `225.89 → 226` (one matrix plus a `6` gap), and `Disconnected` is `135.58 → 136` — it never times anything, so it reserves neither the timer slot nor the ground. Adding each product mark's session-count dot column (`5.655`, [`dual-agent-design.md`](dual-agent-design.md) §11) gives the actual `209` / `238` / `136`.

**The ground occupies its `8` whether drawn or not.** It fills white only while someone is waiting, but asking for `8` at that moment would shift every mark on the bar at exactly the instant attention is needed — the movement [`dual-agent-design.md`](dual-agent-design.md) §10 rejected for the badge's inversion, and §11's reason for the dot column reserving rather than flexing. Bought once, permanently, so inverting is only a colour change. Pinned by `theCompactReadingReservesItsGroundWhetherOrNotItIsFilled`.

Before the side padding narrowed from `24` to `12`, those three widths were `220`, `242` and `160`; nothing else in the table changed, and the difference is two `12`s.

**`Approval` is the widest *timeable* status, not the widest name.** `Connected` (`66.05`) and `Completed` (`65.81`) are both longer than `Approval` (`52.74`), but neither times anything, so both lose to "`Approval` plus a timer slot". Reserving the timer slot after the longest *name* rather than the longest *timeable status* would waste about `13 pt` — visible on a pill that lives in the menu bar. The implementation computes per status (`PanelMetrics.compactContentWidth`), pinned by name in `theFixedWidthFitsEveryWorkingStatusWithItsLongestTimer`.

The timer is **right-aligned** in its reserved space with monospaced digits, so a Turn crossing an hour grows leftwards into space that was already empty: the pill does not move, and neither do the menu-bar icons to its left.

This also closes the item registered in [`dual-agent-design.md`](dual-agent-design.md) §8: `Update Claude Code` once pushed the two-product pill from `189` to `202`. Having left the collapsed state it no longer sets any width, and it would still fit if it returned — `12 + 16.62 + 12 + 124.77 + 12 = 177.4`, inside `196`. (Measured here, `Update Claude Code` is `124.77`, matching the `124.8` recorded in §8, which is why the rest of that table is trustworthy.) The whole paragraph is now historical: the label itself no longer exists, and `updateAgent` says the product-free `Update` / `Update required` collapsed and expanded alike (§6.6).

### 6.5 How openness is decided

Both signals already existed in the code and neither was written for this — one retires the rows of dead sessions (`SessionEnd` is deliberately unregistered), and the other was already fetched every refresh:

| Product | What "open" means | Source | Implementation |
| --- | --- | --- | --- |
| Codex Desktop | The app is running | `NSRunningApplication.runningApplications(withBundleIdentifier:)`, fetched once per refresh and already fetched, to bind live hooks to one Desktop process lifetime | `LiveCodexMonitorService.desktopProcessIdentifier()` |
| Claude Code | At least one active session | `claude agents --json` through `ClaudeCodeSessionListing.liveSessions()`. With no app to ask, the session list is the presence signal | `ClaudeCodeSessionRegistry.swift` |

`ClaudeCodeSessionRegistry`'s own contract is exactly the line needed here: its output is byte-identical whether a session is working or idle — it answers which sessions exist, and the Turn reducer answers what they are doing. **Presence draws the matrix and the reducer lights it**, and the two must not be recombined.

`Connected` inherits the rule already written for `Idle`: an empty set may be read as "nothing is working" only when a current-state source confirms it really is empty, and never while we cannot see — otherwise `Connected` becomes the new lie.

One asymmetry is deliberately kept: Codex's presence is knowable the instant this app launches while its Turns are not (the product deliberately shows nothing from before launch). So a just-launched app can honestly show `Connected` for Codex while knowing nothing about the work — strictly better than today's blank.

Presence trustworthiness differs per product, and only the Claude Code side needs extra rules: `NSRunningApplication` is a kernel fact with no cache and no staleness, whereas `claude agents --json` is backed by `~/.claude/sessions/<pid>.json`, one file per session, with **no heartbeat field and no mtime update**, so the files cannot expire themselves. Two consequences:

1. **Ghost sessions — measured, and the official command already handles them, using exactly the right test.** A `SIGKILL`ed session genuinely cannot delete its own file, so the concern was right; but `claude agents --json` does not list it. Measured on 2.1.229: copying a live session's file byte for byte and **changing only `procStart`** makes it vanish from the output, and writing a session file pointing at a live but unrelated process (`pid 1`) does the same. So the command validates `pid` + `procStart` as a pair — the test needed here, and the one a bare `kill(pid, 0)` would be fooled by through PID reuse.

    This app therefore **does not and should not redo** that check: `--json` does not output `procStart` at all, so judging it ourselves would mean reading the private `~/.claude/sessions/<pid>.json` schema — registering a non-public dependency to duplicate a public implementation that is already correct (`AGENTS.md` §8). The conclusion is recorded on `runOfficialCommand` in [`ClaudeCodeSessionRegistry.swift`](../Notchline/Notchline/ClaudeCodeSessionRegistry.swift).
2. **Our own cache had no ceiling.** `ClaudeCodeSessionRegistry.refresh()` returns the previous result on a failed read without updating `readAt`. That is right for rows (one failure should not retire them all), but presence now decides `Connected` versus `Disconnected`: once `claude` is uninstalled or renamed the read fails permanently and the pill would show `Connected` forever. So "how often to re-read" (`freshness`, `30` seconds) is separated from "how long a stale answer is still believed" (`90` seconds, three consecutive failures).

Past the ceiling, presence is **unknown**, and unknown falls to `Disconnected`. Under §6.7's semantics that is not a compromise but the literal truth: we have no usable connection at all. It is the same rule written for `Idle`, applied symmetrically to a non-empty set.

### 6.6 Retired thin-layer states

| Retired | Where it went |
| --- | --- |
| The resting extinguished product matrix | Deleted. The grey slot names no product |
| `Idle` / `No active sessions` | Merged into `Connected` (§6.4) |
| `Connecting to Codex` | Deleted. Presence is answered directly by a system API, so there is no wait to explain |
| `Update Codex` | Settings' product rows, and the expanded panel when the user opens it; the product name is gone from it, below |
| `Codex version unsupported` | As above |
| `Set up integration` | Onboarding, and the settings switch |

`Codex disconnected` is not retired but redefined as `Disconnected`, §6.7. The thin layer is kept for the expanded panel only, and its height is composed (§3.3), not the `520 × 94` this section used to quote.

**The destinations remain, but the sentences reaching them no longer name a product.** `Connecting to [product]`, `Update [product]`, `[product] version unsupported` and `[product] disconnected` all become `Connecting`, `Update required`, `Version unsupported` and `Disconnected`: **which** product is unhealthy is the settings window's job, where each product is listed with its own status, and the notch need not say it for them. This also closes the expanded panel's per-product width fold (§3.3) — the longest sentence goes from `Claude Code version unsupported` to `Version unsupported`, narrowing one side by `79.55`.

### 6.7 What `Disconnected` means

Presence and observability are now independent facts and can therefore contradict each other. "Open but unobservable" is an ordinary first run rather than an edge case: both products' hook registration happens only once the user flips a switch in settings ([ADR 0016](adr/0016-write-the-users-claude-code-settings-and-keep-a-copy.md)), so on a freshly set-up machine the product being open while this app cannot reach it is the norm. ~~That sentence used to be justified by Claude Code's registration being left for the user to paste (ADR 0010); with writing taken back the justification changed and the conclusion did not.~~ Two states must cover it without becoming three.

**Decided: `Disconnected` means "no coding agent is connected", not "no coding agent is open".** That one change buys a lot: the status stays true when an agent is open but unreachable; no third state is needed; and the word finally means what it says — you cannot be disconnected from something never opened, but you certainly are from something opened and out of reach. The reason lives in Settings, one hover-expansion away.

Losing observation is a **transition, not a state**: each matrix first falls to its own extinguished colour (keeping its hue, so it is visible which product went dark), the rows drain after it, and only then does the whole fall to `Disconnected`.

### 6.8 Known costs and open items

Settled: `Disconnected`'s semantics (§6.7), grey being the darkest value (§6.4), and one shared width across the single-product working set (§6.4).

**Whether `Connecting` counts as connected: decided, it does not.** §6.5 says a just-launched app can honestly show `Connected` for Codex, and §6.7 says "open but unobservable" reads as `Disconnected`; the seconds while the App Server is still connecting fall between those sentences. "Does not count" is taken, because §6.7's definition is literal — the observation contract is not yet established, so nothing is connected — and the reverse would report a business state with no evidence, exactly the guess `AGENTS.md` §6.2 forbids. The cost is near zero: the notched form draws nothing at rest anyway, so a connecting product is "no mark yet" rather than "a wrong mark", and the mark arrives with the contract. §6.5's asymmetry still holds; it is about Turns being unknowable, not about a connection not yet made.

Three remain:

- **The word `Disconnected` itself.** It now names a real connection failure, so the objection is much weaker; but it is still the first sentence a new user reads when everything is fine and they simply have not opened anything. Alternatives `No agents` and `Nothing running`, to be judged on screen.
- **The notched form draws nothing at rest**, so `Disconnected` is a status name visible only in the notch-less form and on hover — the first time the two forms differ in whether a system status is visible at all, rather than merely in treatment.
- **A dead session holds a slot.** `SIGKILL` reports nothing, so presence must be corrected rather than merely subscribed to (§6.5).

## 7. First-run onboarding

The current design is `First run — one window` (`750:2`) on `08 — Onboarding`, **one `580`-wide window**, with light and dark as one set of nodes. `232:95`'s three-window flow is kept as a v1 reference and is no longer an acceptance target.

Each of the three windows carried one decision: value, consent, confirmation. But consent *is* the switch and confirmation *is* that row turning green — the other two windows were words around two controls. Merged onto one page, the space freed goes to something this flow never explained: what the notch is actually drawing.

The window uses the settings window's whole shape (§8.0: `22` group spacing, `8` from group title to card, `12` card corner, `14 × 11` row padding, capsule buttons), because it **becomes** the settings window — the same scene shows `OnboardingView` before `hasCompletedOnboarding` and `AppSettingsView` after, and nothing should have moved by the second opening. The title bar reads `Welcome to Notchline`, and the content area has no second heading.

Top to bottom:

1. **Hero**: the `52` app icon and one sentence, not repeating the window title.
2. **`Connect your agents`**: `ProductConnectionRows` — the **same view** as the settings window, not a copy. **A switch on each of the two rows** ([ADR 0016](adr/0016-write-the-users-claude-code-settings-and-keep-a-copy.md)); ~~previously a switch for Codex and a `Set Up…` for Claude Code, the two rows side by side being the only place ADR 0010's asymmetry was visible~~ — that asymmetry is gone. The footnote states that both switches write reversible definitions into `~/.codex/hooks.json` and `~/.claude/settings.json`, touch neither the user's own settings nor their hooks, and copy either file beside itself as a `.notchline-backup` before changing it; the trailing control is `Recheck`, because turning the Codex switch on is not the end — Codex keys trust to a definition's position in the file, so the user must trust it under `/hooks` and run a Turn before that row says `Connected`. Claude Code has no such step.
3. **`Reading the notch`**: five swatches and five status names, **with no explanatory sentences** — a status called `Running` does not need a sentence saying a Turn is running. Swatches are drawn at `PanelMetrics.statusMatrixSize` (`16.6`) on a small black ground, the real thing rather than a diagram, and **they are live**: the tracks are layer animations on the render server, and `Connected` simply does not move (its state has no period).
4. **A colour key**: two single-colour swatches and two product names, on the same grid as the row above.

**The swatches are split along the mark's diagonal into two colours** (Codex above, Claude Code below), a treatment unique to onboarding: each matrix on the notch belongs to one product, since hue is exactly what distinguishes two matrices. Splitting lets one row of five explain five treatments rather than two rows of ten, which would imply the pattern varies by product when it does not. Implementation in `NotchPalette.MatrixSplit` and `MatrixIndicatorView.trailingHalf`; the seam direction is pinned by `theSplitMatrixCutsOnTheSameDiagonalAsTheMark`. It used to be `isFlipped`'s only witness (the four old patterns were vertically symmetric) and is not any more — three of the four new treatments are asymmetric, §4.1.

The window requests neither Accessibility nor Screen Recording, and promises no silent bypass of Codex's trust step. The bottom row is that read-only statement plus the primary `Start` button, **with no gate**: it can be entered with no product connected at all, and the notch will honestly say `Disconnected`.

## 8. Settings

The current design is `609:2` (`Settings — redesigned for macOS 26`) on `09 — Settings`, rebuilt in the macOS 26 visual language, with complete light and dark windows plus two partial slices of the previews-off state. `233:3` and `591:2` are kept as v1 references and are no longer acceptance targets.

### 8.0 Window structure

The settings window is a **single panel with no sidebar**. V1 has three confirmed groups, and carrying them in a one-item source list declares a navigation that does not exist while forcing the content area to repeat a `General` heading. The window title is therefore `Notchline Settings` per the HIG, with no second heading in the content area.

| Item | Value |
| --- | --- |
| Window width | `580` (same as the onboarding window) |
| Window corner | `26` |
| Title bar | `52` tall, the window's own colour; no separator until content scrolls beneath it |
| Traffic lights | `12` diameter, `20` apart, `x = 20` |
| Content margins | `24` sides, `20` top, `22` bottom |
| Group spacing | `22`; `8` from group title to card |
| Card | `12` corner, 1px hairline stroke, very light shadow |
| Row padding | `14` sides, `11` top and bottom; `2` between the main label and its caption |
| Switch | `38 × 22`, knob `18` |
| Buttons and pop-ups | Capsule corners; a pop-up ends in an accent `18 × 18` double-chevron chip |

The board's three groups top to bottom are `Products`, `Session list` and `Privacy`; the implementation has `Products`, `Display` and `Session list` — `Privacy` is deleted (§8.3) and `Display` is not on the board (§8.4). Each group is "a small heading, one rounded card, and footnote text beneath the card". The footnote replaces v1's blue hint bar — macOS states consequences in a footnote rather than a colour block, and a colour block in a native window only reads as a control nobody can press.

The window's last row is the `closing note`: the read-only statement on the left and the capsule `Quit Notchline` on the right. Sharing a shape with `Recheck` is no accident — both are "explanatory text with the action it describes on the end". Quitting belongs to no group: it is not a setting, and the component it takes away has no window of its own to close, so Settings is the only interface that can carry it. This row takes no indent (the group footnotes' `2 pt` left indent belongs to the groups), so it sits on the same vertical line as the three group titles.

Every main label shares one left indent: a product row's green status dot moves to the start of its caption rather than standing left of the product name, so all three cards' title columns align.

Light and dark are **one set of nodes**: every colour binds to the two-mode `Color / macOS Window` set, and the dark window is a clone of the light one plus a mode override. Changing a colour once changes both, and two sets of values cannot drift apart. The implementation counterpart is `MacOSWindowColor` in [`SettingsWindow.swift`](../Notchline/Notchline/SettingsWindow.swift): each token is an `NSColor(name:dynamicProvider:)`, one declaration answering both appearances, the code equivalent of a two-mode set. The status dot is the exception and takes the system colour — `status/green`'s two values are already `systemGreen`'s two, and the system colour also follows Increase Contrast.

**The title bar renders as macOS's own, not as this table's row.** The board's title bar is the window's colour, `52` tall, with no separator; SwiftUI owns the scene window's title bar and re-applies its own configuration on every layout, and `titlebarAppearsTransparent`, `backgroundColor`, `titlebarSeparatorStyle` and `.fullSizeContentView` all measurably have no effect. What remains is `.hiddenTitleBar` plus a self-drawn `52` band and centred title — which would make the most conspicuous part of "use real controls, not approximations of them" the one approximation. So the title bar keeps the system material, and `52` is a board typography convention rather than an acceptance item.

**How the window appears: always frontmost, centred on the display Notchline is on.** This is not on the board because it is interaction rather than layout, and it is recorded here because it decides where the user first sees this window. This app's only permanent interface is in the notch, so a request to open Settings almost always comes while another app is frontmost — and SwiftUI only orders the window within this app, so from outside, clicking the gear appears to do nothing. Opening therefore activates the app first and then orders the window to the front. It lands on **the display the component is currently on** (the one selected in `Show Notchline on`, matched to an `NSScreen` by identifier rather than frame) rather than the one holding keyboard focus: everything this window changes is visible only in the notch, one of those things being which screen the notch is on; and it is an answer that cannot change during window ordering, which the focused screen never is — asked a step late, the answer is Settings' own screen, which merely restates the question. **It is placed on every open**, no longer only when the screen changes: horizontally centred with a third of the slack above, which is where macOS centres windows itself; the cost is overriding a position the user dragged, knowingly chosen. If the selected screen does not exist at that moment (just unplugged, with the store not yet caught up) it falls back to `NSScreen.main`. **Placement always happens while the window is invisible**: once as the view enters the window (before SwiftUI orders it on screen) and again every time the window is hidden, so the next appearance is correct on its first frame; placing it after it appears is the flash the user sees. If it is on another Space it is brought to the current one rather than sending the user there. Implementation: `SettingsWindowPresenter` and `SettingsWindowPlacement` in [`SettingsWindow.swift`](../Notchline/Notchline/SettingsWindow.swift).

### 8.1 Products

`Codex Desktop` and `Claude Code` are two rows in one card, not two groups. A third product costs a row, not a new panel.

- Each row has the product name on the left and a caption beginning with a status dot, stating the connection conclusion and capability (`Connected · compatible version`, `Connected · hooks installed`).
- **Beneath that caption there can be one more line, carrying failures that product reported itself — not on the board, the third divergence.** For example `Ignored 2 hook payloads that could not be read.` or `Claude Code is not running the PreToolUse hook, so Input needed and Approval needed cannot be shown.` It **appears only when there is something to say**: a permanent empty line for a failure that is not happening reads as though it is. This line is the only thing in this window that exists to report failure — integration failure in this product is naturally silent and the interface goes on saying `Connected` — so it accumulates for the run rather than reporting once and clearing ([`PRD.md`](PRD.md) §12, CR-029). It costs the same as the `Quota reading transcripts` row's "the card grows a line by itself", with the difference that when this line grows, the user needs it.
- The Codex row's trailing control is a native macOS switch that starts and stops that product's required lifecycle event definitions, disabled while a change is in flight.
- **The Claude Code row is a switch too, so the implementation and the board's two switches now agree.** ~~That row previously had no switch: ADR 0010 decided this app would never write `~/.claude/settings.json`, so it ended in the capsule `Set Up…` opening an in-card paste path with a JSON snippet, `Copy` and `Reveal Settings File`; the two rows side by side were the only visible sign of that asymmetry.~~ [ADR 0016](adr/0016-write-the-users-claude-code-settings-and-keep-a-copy.md) took writing back, and the paste card, snippet and two buttons are deleted. The form the board annotated as "if writing is ever restored" is the current implementation.
- The card's footnote explains that each switch installs only the definitions Notchline needs, removes them when off, and leaves the user's other settings and hooks untouched, and states that either file is copied beside itself as a `.notchline-backup` before any change. It previously named only the Claude Code copy while the Codex one was already being written; ~~before that it listed both `hooks.json.notchline-backup` and `settings.json.notchline-backup` in full~~ — two full names state two instances of one rule while taking half the footnote, so the full names live in [ADR 0016](adr/0016-write-the-users-claude-code-settings-and-keep-a-copy.md). **The definition counts are deliberately not restated here**: this line has read six, five, eleven and twelve at various times, always one event behind the code. Count them in `HookIntegration.swift`'s two `managedDefinitions`; `SessionEnd` is deliberately unregistered on both sides, and `Notification` was withdrawn on the Claude Code side after its types were measured (CC-011).
- **The card also holds a `Quota reading transcripts` row, not on the board, the second divergence.** Every Claude Code quota read is a real session and therefore leaves an approximately `3 KB` transcript in Claude Code's own project directory, which nothing ever cleans. This row reports their total size (`43.2 MB`), ending in a folder icon button (below). **Size only, never a file count.** It once read `43.2 MB · 1,284 files`, and the count half answers a question nobody asks: this row exists so someone can judge whether the leftovers are worth clearing, and how many files they are spread across does not change that judgement; anyone who really wants to count is one button from the directory.
  **The row is present from the first refresh, even with no number to write.** That directory is found rather than derived — it takes a completed quota read (a subprocess of a few seconds) to know where it is. Before that the row simply did not exist, so the card grew a line by itself just as the user opened the window. It now draws the state instead: `Calculating…` where the number goes, with `Show in Finder` disabled (it has nowhere to go, and a button that reveals nothing is worse than one plainly not ready); once the read lands it becomes the number and the button is enabled. Where the read has completed and the directory still cannot be found — the case on a machine with no `claude` — it reads `Unavailable` rather than continuing to say `Calculating…`, which is a statement about work in progress that has already finished (CC-020).
  **Report, never delete — a decision, not laziness.** Claude Code's project-directory naming rule is undocumented and is not injective after flattening separators and spaces (measured, `…/a b` and `…/a-b` share one directory), so that directory may also hold the user's real session history. Putting the number in front of the user and opening the door is more correct than deleting for them. This row is the same kind of thing as the `Display` group: existing behaviour given a place in the new shape, not a new feature pushed into settings.
- **All three rows carry a `Show in Finder` — a folder icon rather than a line of text, not on the board, the fourth divergence.** Each row is about a place on disk: the two product rows about the file holding their hooks registration (`~/.codex/hooks.json`, `~/.claude/settings.json`), and `Quota reading transcripts` about the directory the quota reads leave transcripts in. Pressing it opens the containing folder and selects the file.
  **An icon rather than a capsule button, because of the count.** The action was originally only on the transcripts row, written as the capsule `Reveal in Finder`; with all three rows carrying it, the same sentence appears three times down one card, pressed right against the switch each product row is really about. The icon carries the same action in a quarter of the width, with the sentence moved into a tooltip (`Show in Finder`). **It is also the accessibility label**: the button is drawn as a `Label` with `.iconOnly` rather than a bare `Image`, so VoiceOver reads `Show in Finder` rather than an SF Symbol's name.
  **No border, and a ground only under the pointer.** The symbol is drawn measured at `12 × 12` (landing at `12 × 9.5`, the second number being the folder's own aspect fitted into that box), with a `22 × 22` hit area (that is the hit area, not the picture: taking the hit area from the graphic's own size makes it something to aim at). **"12-point type" and "a 12-point icon" are not the same thing**: writing `.system(size: 12)` on an SF Symbol makes it sit well beside `12`-point *body text*, and `folder` measures `17 × 13` in that configuration; so `resizable` fits the glyph's own box into `12 × 12` and the number written is the size on screen. The ground is a `5`-corner patch, `black 7%` in light and `white 10%` in dark, appearing only on hover; when disabled there is no hover ground either — something that cannot be pressed should not light up under the pointer. Drawing a capsule around a symbol erects a second shape beside the switch competing to be the row's main control; with no border it reads as what it is, a way through to somewhere else, and "you can press this" is answered at the moment someone asks (the pointer arriving).
  **It goes last in each row, after the switch.** All three rows end with it, so the three icons sit on one trailing edge in a column — which only holds if nothing follows them. ~~It was previously before the switch, on the grounds that the switch belongs on the trailing edge; the cost was that the transcripts row has no switch, so its icon sat on the trailing edge and the three icons stood at two different x positions.~~ That misalignment was traded for "the switch is not on the trailing edge": the switch moves inwards by a fixed step and still forms its own column, and a symbol with no border is not read as the row's main control. Three matching icons failing to align is more conspicuous than a switch standing off the trailing edge.
  **The file may not exist at all, and that is normal rather than an error.** Both `~/.codex/hooks.json` and `~/.claude/settings.json` exist only once someone (this app or the user) has written to them, so a row whose switch was never turned on points at a path with no file at the end, and `activateFileViewerSelecting` does nothing for such a path, silently. So: select the file if it is there, open the folder that should contain it if it is not, and disable only when neither exists — the disabled test still coming from one source, "is there anywhere to go", the same rule as the transcripts row (CC-020).
- `Recheck` is the capsule at the end of the footnote row, re-detecting capability.
- Settings stays reachable after switching off; switching on again installs or repairs the complete set. The `/hooks` trust step after a first install or a changed definition is still Codex's.

### 8.2 Session list

The `Distinguish products` pop-up, valued `Name and colour` (default) / `Name only` / `Badge` / `Colour bar`, with semantics in [`dual-agent-design.md`](dual-agent-design.md) §4. The footnote explains it takes effect only while both products are connected (not requiring both to have threads right now, [`dual-agent-design.md`](dual-agent-design.md) §4); with one product it stays visible but has no effect, since hiding it would make it unfindable exactly when a user is preparing to connect a second product.

**The card has only this row.** ~~It also held `Clear the session list` with a trailing capsule `Clear`, disabled with an empty list. In v1 that was a destructive button inside the Codex card; the product group now discusses products only, and this action's object is the session list, so it belonged here. It was not on the board, because the board drew three confirmed settings and this is an action.~~ It was deleted once right-click removal of a single terminal row existed, and **the feature itself was deleted rather than merely its entry point** (`tech-design.md` §16.2 records the removed symbols): the two always shared one removal record, and a right-click is given while the user is looking at that row, whereas a clear-all in a settings window has to be opened first and then acts on a set of rows the user is not looking at, one of which may be an answer they have not read.

### 8.3 Privacy (deleted)

The board has this group and the implementation does not. `Show current content previews` existed only to honour a privacy promise that is now void ([`PRD.md`](PRD.md) §7), and the switch, `PrivacySettings` and the `privacySafeTitle` fallback are deleted with it, leaving the window one group shorter. Kept on the board as a historical form.

### 8.4 Display

Not on the board, present in the implementation, between `Products` and `Session list`. The card now holds three rows.

`Show Notchline on` is an existing control: the component appears on one display, chosen by the user, with the caption reporting that display's form and real menu-bar height (`Notch display · 39 pt menu bar`). Deleting it would take away a real feature, so it keeps the same shape — a small heading and one card. **No footnote**: ~~the footnote used to say the component occupies the selected display's menu bar and takes its geometry from it, a cut-out to work around or a pill where there is none.~~ Both rows' captions already report the conclusion for the currently selected display — its form, its menu-bar height, and why the wings cannot be hidden on this screen — and the footnote only restated the same thing abstractly.

#### `Hide the wings`

| Label | `Hide the wings` |
| --- | --- |
| Control | Native macOS switch, default off, remembered across launches (`hidesCompactWings`) |
| Caption (notched) | `Collapsed, Notchline is the cut-out and nothing else — no marks and no timer. Hovering still opens the panel.` |
| Caption (notch-less, disabled) | `Needs a notched display. Without a cut-out to hide behind there would be nothing left to hover.` |
| Caption (notched but unmeasurable, disabled) | `This display reports a notch but not where it is, so there is nothing to shrink the collapsed component onto.` |

The collapsed state is then the notch alone: neither wing is drawn, no matrix leading and no timer trailing, with the panel body's width exactly the occlusion width and its trailing edge on the cut-out's right edge. This **is not a new form**: §6.4's "notched, resting, draws nothing" is that form, and this preference merely generalises it from "no product connected" to any time.

**It affects the collapsed state only.** Hover still drops the panel, with its matrices, session rows and gear. The notch is this product's only entry point — no menu bar item, no Dock icon ([`PRD.md`](PRD.md) §11) — so hiding it too would hide the app for good.

**The condition is a *measurable* notch, not a *reported* one.** Hiding the wings means shrinking the panel body onto the hardware's own shape, so this app must know exactly where and how wide that shape is — nothing else on screen can locate it. Two kinds of display therefore fail the condition, for one reason stated twice:

- **A notch-less screen**: there is no such shape. Collapsing the pill would take its menu-bar position with it, leaving no shape on screen to hover.
- **A screen reporting a notch with no occlusion width**: this app cannot locate that shape. It is already treated as a **simulated notch** layout for exactly that reason (§6.4 and `PanelMetrics.size`), and shrinking onto a cut-out whose width reads `0` yields a zero-width panel — nothing drawn, and nothing to hover.

**Both are disabled rather than hidden, and the preference is not cleared.** The cost of hiding is the same argument as §8.2's: a switch that appears only on a notched display vanishes exactly as the user plugs in an external display and goes looking for it. A disabled row still explains what it would do and why this screen cannot — **with the two reasons written separately** rather than merged into one sentence about cut-outs: a built-in screen that reports a notch it cannot locate and an external display with no notch at all are different situations, and seeing `Needs a notched display` under a greyed switch on a MacBook only tells the user the app is broken. The preference belongs to the user rather than to whichever screen is plugged in, so changing screens only disables it and changing back restores it.

#### `Outline the panel`

| Label | `Outline the panel` |
| --- | --- |
| Control | Native macOS switch, default off, remembered across launches (`drawsSurfaceOutline`) |
| Caption | `A hairline edge, for dark wallpapers.` |
| Tooltip | `Traces the sides and lower corners in a grey just off Notchline's own black, collapsed and expanded alike.` |

A `0.8 pt` line along `PanelContour`, **applied identically collapsed and expanded** — the reason is the wallpaper behind the panel, and a wallpaper does not change on hover. `0.8 pt` does not land on the pixel grid: at 2x it covers one pixel and half of its neighbour, so the line is antialiased rather than hard. That is the intent rather than an oversight — a hard single-pixel line reads as "a border has been drawn", while a softer one reads as "this black ends here".

**The colour is derived rather than chosen: three-quarters of the Running timer's grey** (`#5D5D60`, `NotchPalette.surfaceEdge` = `label × 0.75`). The coefficient was judged by eye: `× 0.5` (`#3E3E40`) is nearly invisible on a wallpaper that is merely dark rather than black, while undimmed it reads as a mark, so the midpoint is taken. Deriving rather than writing a new value keeps this edge from drifting out of its own hue — it is still the neutral grey the darkest text on this surface uses, dimmed until it stops reading as a mark and starts reading as a boundary. **An edge is not information**: it exists only so this black still has a shape on a dark wallpaper, so it should sit **beneath** every mark that carries state rather than beside the dimmest of them.

**Stroked inside the contour, not straddling it.** The implementation strokes at double width and clips back with the same path: `PanelContour`'s bottom edge lands exactly on the panel's own boundary and the overlay clips to that boundary, so a centred stroke would lose its outer half and leave the bottom edge half as thick as the vertical sides. The width is a constant rather than a ratio of the menu-bar height: the two corner radii follow the hardware's shape, while a boundary has no reason to thicken because the menu bar got taller.

**The top edge is not drawn.** That edge is not the panel's but the screen's: the panel hangs from the very top of the display, and a line along it reads as "a rule above the menu bar" rather than "the boundary of the thing beneath". So the stroke takes an **open path** — from the top-right corner, through the shoulder, vertical edge and lower corner, ending at the top-left, truncated flush with the top at both ends (`PanelContour.spansTopEdge`, with fill and clipping still using the closed path). What is traced is the two shoulders, the two vertical edges and the two lower corners.

**Available on every display, never disabled.** The opposite of `Hide the wings`: that needs a measurable cut-out, while this needs only an edge — and there is one notched or not, collapsed or expanded.

**The one case it is not drawn is the collapsed state with `Hide the wings` already in effect.** That form's panel body is exactly the occlusion width, so all that remains lit on the outline is the two shoulders, tracing as two grey hooks either side of the notch — in the very form whose entire point is drawing no mark at all. So the two preferences do not fight: while that form is on screen the stroke stands down, and the panel dropped on hover has its own edge, so the stroke returns with it (`MonitorStore.showsSurfaceOutline`, pinned by `theOutlineIsRememberedAndStandsDownOnlyForTheHiddenCompactSurface`).

This is not an exception to "do not add unconfirmed features": the rule below forbids pushing undecided features into settings, whereas `Show Notchline on` is existing behaviour given a place in the new shape, and `Hide the wings` and `Outline the panel` are two display preferences added alongside it on the same card — they add no monitored object and change no status decision, deciding only how much of this surface is drawn. Divergences between board and window are recorded here to be resolved when the board is updated.

Do not add login items, animation, notification, model selection or other unconfirmed features to the V1 settings board.

## 9. Interaction

### 9.1 Expand / collapse

- Hover intent, reference `150 ms`.
- Expansion, reference `180–220 ms`.
- Collapse `250 ms` after the pointer leaves.
- Every intermediate frame keeps the same `maxY`. Horizontally, the expanded and notch-less forms keep the same `midX`, while the notched collapsed form anchors to the cut-out's right edge (§3.4).
- Reduce Motion uses a short cross-fade, never a visible spring or scale.

**There is no keyboard collapse, and there cannot be one here.** This list used to promise `Escape collapses immediately`, and the code carried an `NSEvent` local monitor for it that had never once run in normal use. A local monitor sees only events routed to this application, and this application is never the one they are routed to: the overlay is a `.nonactivatingPanel` whose `canBecomeKey` is `false`, so keystrokes go to whichever app holds the foreground — which, the panel being opened by hover, is always some other app. Measured with the panel expanded and Ghostty in front: `Escape` did not reach the monitor and the panel stayed open.

Both ways of reaching it were measured and both are worse than the loss:

- **Letting the panel become key.** It works — `Escape` arrives and collapses the panel — but the panel then takes *every* keystroke. An inert `F13` sent while `lsappinfo front` still reported Ghostty landed in this app instead, and it kept arriving after the panel had collapsed. That is a person's typing disappearing into a notch overlay, which is not a trade any collapse gesture is worth.
- **A global key monitor.** `NSEvent.addGlobalMonitorForEvents` delivers key events only to a process trusted for Accessibility. This app takes no Accessibility permission at all — see [`non-public-codex-integration-features.md`](non-public-codex-integration-features.md), where "no Accessibility, no GUI automation" is part of what the read-state path is measured against — and one convenience gesture is not what spends that.

A third option, a Carbon `RegisterEventHotKey` held only while the panel is open, was rejected rather than disproved: it needs no permission and would deliver this line as written, but it takes `Escape` away from the frontmost app for as long as the pointer rests on the notch, and a process that dies before releasing it leaves `Escape` dead machine-wide until relaunch.

The panel already collapses `250 ms` after the pointer leaves, and the pointer is by definition on the panel while it is open, so what is lost is a gesture whose whole saving is not moving the mouse.

#### Handing the status name between the two forms

Collapsing changes the word and the width at once: `Approval needed` → `Approval`, `Input needed` → `Input`, `Update required` → `Update`. Both must run on one curve. Change the word first and narrow after, and the short glyphs are stretched to the old reading's width and squeezed back — the glyph layer was framed by `bounds`, and `CALayer`'s `contentsGravity` stretches by default.

The conventions:

- Glyphs are always framed at **their own raster size**, leading-aligned and vertically centred. Only the view around them is animated, and the view clips the glyphs; what is clipped is the horizontal counterpart of "every intermediate frame keeps the same `maxY`".
- The old reading fades out **above** the new one, at the panel's own duration and curve (`PanelMotion`: `200 ms` / `cubic-bezier(0.22, 1, 0.36, 1)`, `80 ms` under Reduce Motion). The word being dropped fades out under the closing edge rather than vanishing.
- **When one reading is a prefix of the other, the new one does not fade in.** The shared glyphs are the same pixels in the same place, and another fade layer only dims a word that never moved (about 75% at the composite minimum). Only genuinely different readings (`Running` → `Approval`) cross-fade both ways.
- Reduce Motion shortens this handover rather than cancelling it: what that setting removes is displacement, and the fade is what replaces displacement — the panel still closing while the word hard-cuts is not the quieter option.
- The timer reading and session row body text **do not take part**: they are replaced whole-frame on their own cadence, and overlapping fades at a rate faster than the fade duration smear (see `system-architecture.md` §6).

### 9.2 Clicking a session

- A successful click reaches the same Desktop thread and collapses the panel.
- A Notch click never changes read state; it waits for the blue dot to disappear.
- On a failed navigation the panel and the row stay, and opening a home page is never counted as success.
- Session rows offer no approve, answer, cancel or archive action.
- **A right-click on a terminal row removes it**, with no menu and no confirmation: the panel collapses as soon as the pointer leaves, and a one-item menu would spend a second click on an action that deletes nothing. The other three statuses install no such response, so a right-click falls through rather than landing on a handler that decides to do nothing. Not on the board, because it has no form to draw.

## 10. Accessibility

- Every status must have text or an accessible name, never colour alone.
- System-level and the four session-level statuses use distinct copy and semantics.
- Long status names must be fully readable in the notched expanded geometry.
- Reduce Motion must not affect the comprehensibility of any status.

Spoken examples:

```text
Notchline, three current Turns, status input needed, quota 72 percent remaining
Confirm the unread lifecycle, Project Notchline, input needed
Awaiting approval, Chats, approval needed
```

**Neither the subagent badge nor the session-count dots may speak through colour alone.** The badge's number can be read, but "the ground inverted" cannot, so its spoken copy states the state as a word: a row reads `3 subagents, waiting for you` (`MonitoredSession.spokenSubagentSummary`), and the collapsed state also names the product, because two side by side are told apart only by ink — `Codex 3 subagents, Claude Code 4 subagents, waiting for you` (`MonitorStore.spokenRunningSubagentText`). Both badge views are `accessibilityHidden`, spoken by the row or top bar containing them, so one number is never read twice. The session-count dots are not spoken separately: they count how many rows the list has, and the list itself is read row by row below. **Their breath is**, because it is the one thing on this surface said by motion alone — the collapsed label gains `2 turns finished and unread` on exactly the terms the column moves on (`MonitorStore.spokenBuriedCompletionText`, [`dual-agent-design.md`](dual-agent-design.md) §12). It says how many, which the movement never does; the number is already known and nothing about the drawing has to change to hand it over.

## 11. Verification checklist

- [x] Expanded width `520`; **height composed as `menuBarHeight + 240 + footer`** (§3.3), not a constant — the `302` this line used to carry predates the footer.
- [x] Header at the real menu-bar height (`46` reference), growing only horizontally.
- [x] Three `508 × 80` rows and the scrolling contract.
- [x] File-wide SF Pro.
- [x] Quota unavailable as partial degradation.
- [x] ~~No active sessions, Connecting, Disconnected, Update, unsupported, setup thin layers.~~ Narrowed to the two system states `Disconnected` and `Connected`, §6.4 and §6.6.
- [x] Collapsed presence rules and the open/close sequence (§6.4, `624:1560`): matrices appear and leave as agents open and close, and the first product takes over the grey slot. **The treatment landed with [#35](https://github.com/soondubu137/notchline/issues/35)**: one matrix per connected product each running its own curve, one grey resting mark when there is none, and the whole leading wing gone at rest in the notched form.
- [x] Hover expands the pill horizontally only and does not drop the panel, with the gear at the trailing end. **Width is computed by composition**, §6.4's implementation record.
- [x] `Disconnected` redefined per §6.7 as "no agent is connected"; grey is `#151515`, the darkest value in the interface (§6.4).
- [x] The notch-less pill is one fixed width across the single-product working set, currently `209`, with two products `238` and `Disconnected` `136` (§6.4) — measured with the system font on this machine. (This line previously carried `196` / `218`, which predate the reading's ground.)
- [ ] The session row's `alpha fade mask` is still a fixed `273`. After the row went from `472` to `508` and padding narrowed from `16` to `6`, the fade ends `56` further from the right edge than it did; the mask should follow the row, or be measured from the trailing edge.
- [x] Row margins split into a `6` block gutter plus `6` in-row padding, so in-row text lands at `12` with the status matrix and quota rules (§3.3); pinned by `aRowsTextLandsOnTheSameMarginAsTheRestOfThePanel`.
- [x] Folding the quota block ([`dual-agent-design.md`](dual-agent-design.md) §5.4, Figma §09): folded footer `22` and panel always `520 × 308`; the control is `16 × 16`, its two states one chevron rotated `180°`. **Implemented**; the hit area is that `16 × 16` (hover lays a `12%` white ground at corner `4`), state in `quotaFolded`.
- [x] `Colour bar` as the fourth `Distinguish products` option ([`dual-agent-design.md`](dual-agent-design.md) §4, Figma §06): a `2`-wide bar, corner `1`, in-row `x = 0`, height taken from the row's real text height (`53` with three lines, `33` with no preview), no longer half the row height at `40`. **Implemented**; the pop-up now has four items, and in that form the block inset is `12` with `8` in-row padding (§3.3), putting the bar on the same margin as the status matrix and quota rules.
- [ ] §3.3's compact reference baselines disagreed with the file's components before this change and were not corrected with it; the components are currently `237` (notched resting), `285` (notched with timer) and `165` (notch-less).
- [ ] Whether the word `Disconnected` is kept (alternatives `No agents`, `Nothing running`), to be judged on screen.
- [x] ~~First Claude Code presence correction: filter ghost sessions by `pid` + `procStart`.~~ **Withdrawn after measurement: `claude agents --json` validates exactly that itself**, and does not output `procStart`, so redoing it would mean reading a private schema. §6.5.
- [x] Second Claude Code presence correction: a ceiling on the stale cache (`90` seconds = three consecutive failures), past which presence is unknown and falls to `Disconnected`. `freshness` and `trustCeiling` are now two parameters.
- [x] The first-run flow.
- [x] Settings integration management.
- [x] Settings rebuilt for macOS 26 as a single-panel window, with light and dark driven by `Color / macOS Window`'s two modes. **Implemented** ([`SettingsWindow.swift`](../Notchline/Notchline/SettingsWindow.swift)), with every divergence from the board recorded: the title bar keeps the system material (§8.0), the Products card has an extra `Quota reading transcripts` row (§8.1), product rows have an extra failure-report line beneath the caption (§8.1), all three Products rows have a `Show in Finder` folder icon (§8.1), there is an extra `Display` group of three rows rather than one (§8.4), and there is no `Privacy` group (§8.3). ~~An extra `Clear the session list` row (§8.2)~~ is resolved — deleted once right-click removal replaced it. ~~The Claude Code row is `Set Up…` rather than a switch (§8.1)~~ is also resolved: it is a switch, and the board's two switches now match the implementation (ADR 0016).
- [ ] Open `609:2` in a Figma desktop client with SF Pro and confirm glyphs render and multi-line footnote wrapping lands as expected.
- [ ] In the same session, re-type the `closing note`'s four Inter texts (`665:3`, `665:5`, `667:3`, `667:5`) as SF Pro Regular, per §3.1.
- [x] Session rows carry Running / waiting-on-a-person / Completed timer treatments, with one marker per row.
- [x] That marker is now "a reading plus a ground" in three outlines — bare, white, dark — with the finished row's ground holding how long the Turn took (§4.7). **Implemented**; pinned by `aFinishedRowDrawsTheLengthOfTheTurnItRan` and `theDimGroundStaysAboveTheRowItIsDrawnOn`.
- [x] The body-line searchlight is restored: unfinished Turns sweep, finished ones (including those with subagents still running) do not, and Reduce Motion turns it off (§4.8). **Implemented**; pinned by `sessionRowTextSweepsOnlyWhileItsTurnIsUnfinished` and `onlyAnUnfinishedTurnSweepsItsBody`.
- [x] The collapsed reading takes the same ground, neutral and uninked, with its `8` permanently reserved so inverting moves nothing (§6.4). **Implemented**; pinned by `theCompactReadingReservesItsGroundWhetherOrNotItIsFilled`, giving the notch-less fixed widths `209` / `238` / `136`.
- [ ] Figma `04 — Session Row` (`112:28`) and `05 — Panel` (`115:82`) have not been back-filled with page `14`'s ground treatment; the page's example nodes are the current source of truth.
- [x] The subagent marker converged to one badge: the number is every subagent and the ground inverts to say whether anything is waiting; neutral in an expanded row, one per product in its own ink when collapsed with Codex first (§4.6, [`dual-agent-design.md`](dual-agent-design.md) §10). Pinned by `theCollapsedBadgesAreOnePerProductInAFixedOrder` and `aWaitingBadgeIsTheSameWidthAsARunningOne`.
- [x] The session count is drawn as a vertical dot column right of the matrix, one dot per row, the third stretching into a bar past three; **the column is exactly as tall as the matrix**, so it draws identically at every menu-bar height ([`dual-agent-design.md`](dual-agent-design.md) §11). Pinned by `theSessionDotColumnIsExactlyAsTallAsTheMatrix`.
- [x] The column is reserved at `+5.66` per product mark and absent from the resting grey mark, so the leading wing is a constant per mark count and does not vary with thread count. Connected with no threads **draws no column**, and the width given up lands **after the status name** rather than being returned to the panel — so at rest a matrix pair is its own `6` apart, the status name is `12` from the mark beside it at every count, and the leading matrix never moves horizontally at any thread count. Pinned by `theSessionDotColumnIsReservedInWidthAndPackedInDrawing`, `theStatusNameKeepsOneDistanceFromTheMarkItNames` and `theLeadingMatrixNeverMovesWhateverTheCountsDo`. ~~The width given up lands between the marks and the status name~~ is void: with neither product holding rows that gap was `23.3` while two matrices in the same glance were `6` apart, so the name read as belonging to nothing. ~~Connected with no threads draws an empty column~~ is void: an empty column stretched the paired `6` to `11.66`, past the line where they stop reading as a pair. ~~Originally drawn below the matrix, free in width~~ is void: that spends height, and a `22` menu bar leaves only `2.7` below the matrix, narrower than a dot, forcing the whole row to be omitted.
- [x] The status matrix is 4×4 on the per-cell curves in `design/assets/matrix-states/` (radar / double knock / advance / lull), with waiting split into Input and Approval treatments, so onboarding's row goes from four swatches to five (§4.1, §7). Pinned cell by cell, with phases, by `eachStateDrawsThePatternItsDesignFileDraws`.
- [x] A mark fades into and out of the still and cuts between two live patterns (§4.1). Pinned by `aMarkFadesBetweenTheStillAndAPatternButNotBetweenTwoPatterns`.
- [ ] **External Figma to clean up**: the `Status Matrix / Codex` and `Status Matrix / Claude Code` sets are still 3×3 with four variants (waiting shared). The next sync should redraw them 4×4 per §4.1 and split out Input and Approval; until then `design/assets/matrix-states/` and the code govern.
- [ ] `12 — Counting: sessions and subagents`'s specification has not been back-filled into the cross-page `Session Row` (`112:28`), `Panel` (`115:82`) and `Status Readout` sets; the page's example nodes are the current source of truth.
- [ ] Collapsed timer variants' text layers should hug contents (§4.6), removing the overall over-width caused by fixed text widths.
- [ ] The timer TEXT in the notched timer variant does not render (node data correct, coordinates matching the implementation, and the same text fine in a `24`-tall panel); confirm in a Figma desktop client whether this is a rendering problem or a file defect.
- [ ] Historical Runtime Badge variants deleted from the external Figma; the timer is not a separate badge but an unfinished row's only status marker.
- [x] The Usage Ring is synced to a dark consumption arc growing anticlockwise from twelve o'clock, covering the `100`, `0` and Unavailable boundaries.
- [ ] The panel outline in Figma is still a single radius (`38 → 10`, `24 → 6.316`, `19 → 5`) and needs §3.3's two radii — shoulder `menuBarHeight / 8`, lower corner `menuBarHeight / 4` — across the `38`, `32`, `24` and `22` steps. **`10 — Double Apps` is done**: that page's 27 `surface / PanelContour` vectors are redrawn for a `46` menu bar at shoulder `5.75` and lower corner `11.5` (incidentally fixing a lower-right control handle in the old path that was not a true circular arc). What remains is the `Panel` set itself (`115:82`) and §3.3's responsive examples (`287:8`, `287:12`, `287:16`) — the set is shared across pages, so changing it touches the others, hence listing it separately.
- [x] Figma component set structure is legal, with no Inter, old sizes or old timer copy left inside the synced scope.
- [ ] Delete historical session-status variants outside the four-status model from the external Figma.
- [ ] Native geometry verification at different real menu-bar heights and on at least two physically notched devices.
- [ ] Phase 0 capability verification of real integration events, Project, unread state and exact navigation.

## 12. Implementation mapping

Product and technical behaviour are governed by [`PRD.md`](PRD.md), [`tech-design.md`](tech-design.md), [`CONTEXT.md`](../CONTEXT.md) and [`docs/adr`](adr/). Figma nodes are for visual and layout acceptance and are never a source of truth about a product's protocol.
