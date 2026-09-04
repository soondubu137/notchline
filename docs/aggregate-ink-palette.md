# The aggregate mark's ink — a palette, and eventually a preference

**Status: recorded, not implemented.** V2's collapsed bar draws one matrix for every product at
once ([`figma-design.md`](figma-design.md) is still V1; the V2 board is
[Notchline V2](https://www.figma.com/design/c3CQBBk3Boiu0oM00Vvs9Y/Notchline-V2?node-id=2-2)).
With one aggregate mark, hue stops meaning *which product* and becomes free. This document records
the 36 inks that were drawn for it and the rule that generates them, so that the choice can be
handed to the user rather than made once here.

## 1. Why there is no single right answer

The obvious move — borrow the app's own colour — is not available. `design/assets/01-mark` is
Codex blue and Claude terracotta split on a diagonal and nothing else, so "Notchline's hue" is
the two products' hues. The aggregate mark cannot be either of them without claiming to be one
of them.

What is left is a constraint rather than an answer: **the aggregate mark must never read as a dim
version of a product mark.** Codex sits at `258°` in OKLCH and Claude Code at `42°`. The two hues
equidistant from both are `150°` (108° from each, the maximum any hue can be) and `330°` (72° from
each). Everything else is closer to one product than the other, and everything else is taste.

Taste is the user's, so the set is recorded whole and one entry is made the default.

## 2. The rule

Every ink is a pair — unlit and lit — generated from three fixed numbers and two that vary:

| | Value | Why |
| --- | --- | --- |
| Lit lightness | `L 0.922` | Exactly `#E5E5EA`'s lightness, the greyscale this replaces. |
| Unlit lightness | `L 0.235` | Exactly `#1E1E1E`'s. |
| Unlit chroma | `0.55 ×` the lit chroma | Products run theirs at ≈ `0.25 ×`; at these chromas that is invisible, so the ratio is raised until the dark grid carries the hue at all. |
| Hue | 12 values | §3. |
| Chroma | `0.008` / `0.016` / `0.028` | `whisper` / `hint` / `tint`. |

**The palette is the greyscale, rotated.** Lightness is identical for all 36 entries, so changing
colour cannot change brightness — and brightness is this surface's attention channel
([`dual-agent-design.md`](dual-agent-design.md) §10). A preference that could dim the mark asking
for a person would be a preference that changes what the mark *means*; this one cannot.

## 3. The 36

Hue distances are to Codex `258°` and Claude Code `42°`. The last column is whether the unlit
colour clears the resting grey's luminance — see §4.

| | Unlit | Lit | Chroma | Clears `#151515` |
| --- | --- | --- | --- | --- |
| **Steel** · 250° — 8° / 152° | | | | |
| whisper | `#1D1E20` | `#E1E6EA` | 0.008 | ✓ |
| hint | `#1B1E22` | `#DEE6F0` | 0.016 | ✓ |
| tint | `#191F25` | `#D8E7F8` | 0.028 | ✓ |
| **Ice** · 225° — 33° / 177° | | | | |
| whisper | `#1C1F20` | `#E0E6E9` | 0.008 | ✓ |
| hint | `#1A1F21` | `#DBE8ED` | 0.016 | ✓ |
| tint | `#162024` | `#D2EAF4` | 0.028 | ✓ |
| **Cyan** · 200° — 58° / 158° | | | | |
| whisper | `#1C1F1F` | `#DFE7E7` | 0.008 | ✓ |
| hint | `#191F20` | `#DAE9E9` | 0.016 | ✓ |
| tint | `#162021` | `#D1EBED` | 0.028 | ✓ |
| **Sea** · 172° — 86° / 130° | | | | |
| whisper | `#1C1F1E` | `#E0E7E4` | 0.008 | ✓ |
| hint | `#1A1F1E` | `#DBE9E4` | 0.016 | ✓ |
| tint | `#17211D` | `#D4ECE3` | 0.028 | ✓ |
| **Sage** · 150° — 108° / 108° ★ | | | | |
| whisper | `#1D1F1D` | `#E2E7E2` | 0.008 | ✓ |
| **hint (default)** | `#1B1F1C` | `#DEE8E0` | 0.016 | ✓ |
| tint | `#19201A` | `#D9EBDC` | 0.028 | ✓ |
| **Moss** · 118° — 140° / 76° | | | | |
| whisper | `#1E1E1C` | `#E4E6E0` | 0.008 | ✓ |
| hint | `#1E1F1A` | `#E4E7DB` | 0.016 | ✓ |
| tint | `#1D1F17` | `#E3E8D3` | 0.028 | ✓ |
| **Sand** · 92° — 166° / 50° | | | | |
| whisper | `#1F1E1C` | `#E7E5DF` | 0.008 | ✓ |
| hint | `#1F1E19` | `#E9E5DA` | 0.016 | ✓ |
| tint | `#211E16` | `#ECE5D1` | 0.028 | ✓ |
| **Clay** · 58° — 160° / 16° ⚠ | | | | |
| whisper | `#201E1C` | `#E9E4E0` | 0.008 | ✓ |
| hint | `#211D1A` | `#EEE3DB` | 0.016 | ✓ |
| tint | `#241C17` | `#F4E1D3` | 0.028 | ✓ |
| **Rose** · 25° — 127° / 17° ⚠ | | | | |
| whisper | `#201D1D` | `#EAE3E2` | 0.008 | ✓ |
| hint | `#221D1C` | `#F0E1E0` | 0.016 | ✓ |
| tint | `#251B1A` | `#F8DFDC` | 0.028 | ✓ |
| **Blush** · 0° — 102° / 42° | | | | |
| whisper | `#201D1E` | `#EAE3E5` | 0.008 | ✓ |
| hint | `#221C1E` | `#EFE1E5` | 0.016 | ✓ |
| tint | `#241B1E` | `#F6DEE4` | 0.028 | ✓ |
| **Mauve** · 330° — 72° / 72° ★ | | | | |
| whisper | `#1F1D1F` | `#E8E3E8` | 0.008 | ✓ |
| hint | `#211D20` | `#ECE2EA` | 0.016 | ✓ |
| tint | `#221C22` | `#F1DFEE` | 0.028 | ✓ |
| **Violet** · 292° — 34° / 110° | | | | |
| whisper | `#1E1E20` | `#E5E4EA` | 0.008 | ✓ |
| hint | `#1E1D22` | `#E5E4EF` | 0.016 | ✓ |
| tint | `#1E1D25` | `#E5E2F7` | 0.028 | ✓ |

★ equidistant from both products. ⚠ within 20° of a product hue — kept, because taste may win,
but never the default.

## 4. What every entry satisfies

- **Its unlit colour is brighter than the resting grey.** `#151515` is deliberately the darkest
  thing on the surface, so that "an agent is connected" never looks dimmer than "nothing is
  connected" ([`dual-agent-design.md`](dual-agent-design.md) §2, `NotchPalette.restingInk`). The
  darkest unlit here is `#191F20`'s `0.0125` against the resting grey's `0.0075` — the whole set
  clears it with room, because lightness is fixed at `L 0.235` and only chroma moves.
- **It cannot change how bright the mark gets.** §2.
- **It is a `MatrixInk`**, so nothing downstream changes shape: the four animation tracks, the
  `+0.06` chip lift, and the dissolve all read the pair and are indifferent to what is in it.

## 5. Making it a preference — what that still needs

1. **Does the resting grey take the hue?** Recommend no. `#151515` means *nothing is connected*,
   and tinting it would say the user's colour applies to a state that has no agent in it. The hue
   should arrive with the first connection.
2. **The user can now break §1's constraint.** Picking Steel puts the aggregate mark 8° from Codex,
   which is exactly the confusion the hue analysis exists to avoid. Recommend the picker orders by
   hue distance and marks the two starred entries, but does not block — it is their bar.
3. **36 rows is too many for a Settings list.** Recommend 12 hues at `hint`, with `whisper`/`tint`
   behind an intensity control only if it earns its place. The full set is recorded here either way.
4. **Where it lives.** [`figma-design.md`](figma-design.md) §8.4 `Display` already holds
   `Hide the wings` and `Outline the panel`.
5. **What existing installs get.** Sage · hint, `#1B1F1C` → `#DEE8E0`.

## 6. The picker

The swatches were chosen against a live page that draws all 36 in the real Running state — the
36-frame radar track from `MatrixTrack.radar`, each cell delayed by the bearing of its own centre —
with controls for both lightnesses, a chroma multiplier and the unlit ratio, at sizes down to the
true `16.6`. It generates the `MatrixInk` for whatever is selected.

It lives at `.claude/tmp/matrix-ink.html`, which is **local and gitignored**, following the same
rule the README figure generators do: the generator stays out of the repo and its output comes in.
This table is that output. Rebuild the page from these parameters if it is needed again — or move
it into `design/` and commit it when the Settings feature is actually being built.
