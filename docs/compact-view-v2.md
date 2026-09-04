# Notchline — Compact view V2

| Field | Value |
| --- | --- |
| Status | **Designed and settled, not implemented.** Every decision on the V2 board is answered; no Swift has been written against it. The board's four pages are the drawings, this document is the contract. |
| Version | 2.0 |
| Date | 2026-09-03 |
| File | [Notchline V2](https://www.figma.com/design/c3CQBBk3Boiu0oM00Vvs9Y/Notchline-V2) — `01 — Compact V2`, `02 — Aggregate ink palette`, `03 — Trailing wing & the word` (superseded), `04 — The subject and the wing that stops` |
| Scope | The collapsed surface only: the notched bar and the notch-less pill. The expanded panel keeps its V1 contract except where §8 says otherwise, and its top band is now [`expanded-header-v2.md`](expanded-header-v2.md). |
| Supersedes | [`figma-design.md`](figma-design.md) §4.6 (subagent badge, session-count dots), §6.4's collapsed compositions, §8.4's `Hide the wings`, and §10's reduce-motion premise as it applies to the collapsed forms. Everything else in that document stands. |

## 1. What V2 changes, and why

V1's collapsed bar spent three channels per product: one matrix, one session-dot column and one subagent badge. It therefore grew by `49.26` pt for every product installed — `372` at two, `421` at three, `471` at four — on a surface whose container does not grow with it.

Width was the visible half. The deeper cost is that all three channels answered *which product*, and that question is not actionable at this size: a person who wants to act on a waiting turn opens the panel regardless, and the matrix pair told them a colour rather than a row.

V2 spends nothing on it. One aggregate mark, two numerals, one reading — and, on the form with room, the name of the work. **Nothing on the collapsed surface is per-product any more**, so the bar moves when the work changes and never because something was installed.

| Product count | V1 | V2 |
| --- | --- | --- |
| 1 | 323 | 304 |
| 2 | 372 | 304 |
| 3 | 421 | 304 |
| 4 | 471 | 304 |
| 5 | 520 | 304 |

Measured at the same aggregate on both sides: three sessions, five subagents, longest unfinished turn at `1:23`.

## 2. The aggregate mark

### 2.1 One matrix, one ink

One `16.6` matrix stands for every connected product at once. It draws **the most urgent status any product is holding**, in the list's own order:

```text
Approval needed > Input needed > Running > Completed
```

This is [`figma-design.md`](figma-design.md) §5.2's sort, deliberately, so the mark and the panel's first row can never disagree about what is most urgent. It is *not* `SessionStatus.transitioned`'s within-row rule, where an approval yields to an input ([`tech-design.md`](tech-design.md) §6.2); that governs one row's own status, this governs which row is first.

The four animated patterns — Radar, Double Knock, Advance, Lull — are unchanged from V1 and now carry the whole state reading alone. **This is the one channel V2 does not touch.**

### 2.2 Hue is no longer identity

With one mark there is no product to name, so hue is free — and it is the user's. The ink is chosen from a recorded palette of 36 near-neutrals, all sharing `#E5E5EA`'s lightness lit and `#1E1E1E`'s unlit, so **the choice cannot change brightness**. Brightness is this surface's attention channel; a preference able to dim the mark asking for a person would be a preference that changes what the mark means.

Default **Sage · hint**, `#1B1F1C` → `#DEE8E0`. The full set, the generating rule and what the picker still needs are in [`aggregate-ink-palette.md`](aggregate-ink-palette.md).

The resting grey `#151515` does not take the hue. It means *nothing is connected*; the colour arrives with the first connection.

## 3. The counts column

Two numerals stacked in the height of one matrix, `4` after it.

### 3.1 Geometry

```text
7.85  large numeral cap   (sessions)
3.03  gap
5.71  small numeral cap   (subagents)
────
16.6  = the matrix's own height
```

The column asks for **no room the mark did not already have**, so it draws identically under a 46 pt menu bar and a 22 pt one. That is the test the V1 dot column was built to pass, and the reason a numeral set beside the matrix failed it.

Width hugs the digits: `6.6` at one, `13.2` at two. On the notched bar it gives the width back when the count drops; on the pill it is reserved at two digits (§6.1).

### 3.2 The five rules

| | Rule | Why |
| --- | --- | --- |
| 01 | Hierarchy is size and brightness, never hue. Sessions `#C7C7CC`, subagents `#7C7C80`. | Hue meant "which product"; there is no product left to name. White stays reserved for attention, which this column never signals. |
| 02 | Neither numeral moves once both are present. | A subagent count arriving or leaving fades in place. |
| 03 | Zero is never drawn. | No sessions, no column. No subagents, no second numeral. A bar at rest is one grey matrix — never a bar reading `0`. |
| 04 | The matrix carries attention; the numbers only count. | A subagent stopped on approval is already inside the aggregate the matrix animates, so V1's inverting badge ground has nowhere left to go. |
| 05 | Tabular figures. | Both numerals use the monospaced-digit face the reading already does. A proportional `1` would resize the leading wing every time a session opened. |

### 3.3 The large numeral counts the list

It counts **rows in the monitored list**, finished-but-not-yet-aged-out included — the same set the panel below it draws. It does not fall to zero the moment work stops; it falls when the row leaves. The same clock governs how long a stopped reading holds (§4.2).

### 3.4 The large numeral when it is alone

**Centred.** With no subagent the large numeral is optically centred on the matrix's `16.6`, its cap-top `4.37` below the matrix's top edge. When a subagent starts it **rises `4.37` into the fixed slot** — cap-top on the matrix's top edge — and the small numeral fades in beneath it. It drops back when the last subagent stops.

This takes a vertical move on the figure the eye is on, caused by something the user did not do. It is taken deliberately: the resting drawing is the one this surface spends most of its life showing.

## 4. The trailing wing

The wing carries one reading, on the clear ground every collapsed reading is already billed `8` pt for — `4` each side of the digits, charged inside the reading's own width on both forms so a reading costs the same wherever it is drawn ([`figma-design.md`](figma-design.md) §6.4).

| What it draws | Its width |
| --- | --- |
| `1:23` | 36 |
| `12:05` | 44 |
| `1:00:00` | 56 |
| `10:00:00` | 64 |

> `drawnTrailingReadingWidth` at `1:23` is **36**, not 37 — `ceil(27.78)` for the digits plus the ground's `8`. §6.4's own V1 figure confirms it to the point: `12 + 22.26 + 12 + 102 + 32 + 36 + 12 = 228.26 → 229`, exactly what that section publishes for the V1 pill at `1:23`.

### 4.1 Counting

The longest unfinished turn anywhere, as in V1. `longestRunningSessionStart` is unchanged, and **it does not follow the row the middle names** (§6.2).

### 4.2 Stopped

When the turn ends the reading does not leave. The digits freeze at the last value the timer showed, **the ground they were already standing on fills**, and the panel's edge does not move by a point.

- What it says: that turn's own length, from `MonitoredSession.finishedAt` — a stamp deliberately not moved forward by subagent activity, and the same number the expanded row has drawn since V1.
- How long it holds: while the aggregate says Completed, which is until the row leaves the monitored list (§3.3).
- Why a filled ground is allowed here when V1 §4.7 kept grounds off the bar: that argument holds for the white flip — "one of these wants you" needs a neighbour to mean anything — and the white flip stays gone. "This figure has stopped" is a property of the figure, not a comparison, and it is the one thing the digits cannot say alone.

### 4.3 The buried-finish dot

A turn that has finished while another is still running has no representative: the mark draws Radar, and the frozen reading belongs to a Completed aggregate that this is not. The dot is that reading's stand-in.

- **4 pt, 8 before the digits, in the wing's own `#7C7C80`.**
- Drawn only while the list holds a Completed row **and** the mark is drawing something else — `buriesAFinishedTurn`, which the domain already computes for V1's breath.
- Never when the aggregate is itself Completed; the frozen reading is then that row.
- On the notched bar it widens the trailing wing by `12`. On the pill it takes the same `12` out of the middle and moves nothing.

**It breathes**, by opacity within its own ink — `#7C7C80` modulated down and back, never up. Its slot stays a fixed `4`, so nothing on the wing changes width, and because the breath only ever dims the wing's own grey it never approaches the aggregate's lit ink and cannot be read as the one thing brightness means on this surface. This is V1's breath on a new carrier; §10 already speaks it.

## 5. The notched bar

### 5.1 Composition

```text
12 + leading wing + 8 + 200 + 8 + trailing wing + 12
```

Fixed middle, moving ends. The cut-out is hardware; each wing is exactly as wide as what it draws and gives the width back when the content goes; the panel is pinned to the cut-out, so a wing can move without moving anything a person reads. The trailing wing ceils to a whole number of points, so it cancels out of the sum that pins the panel — a digit arriving at the reading still cannot move the leading edge. **Both rules are V1's.**

- Leading wing: `12 + 16.6 + 4 + counts + 8` → `47.2` at one digit, `53.8` at two, `36.6` with no counts.
- Trailing wing: `8 + [dot 4 + 8] + reading + 12`.

### 5.2 Widths

| State | Leading | Cut-out | Trailing | Total |
| --- | --- | --- | --- | --- |
| Nothing connected | 0 | 200 | 0 | **200** |
| Connected, no rows | 36.6 | 200 | 0 | **237** |
| Running · 3 sessions | 47.2 | 200 | 56 | **304** |
| Running · 3 sessions, 5 subagents | 47.2 | 200 | 56 | **304** |
| Approval needed · 2 sessions, 1 subagent | 47.2 | 200 | 56 | **304** |
| Completed, subagent still up · frozen reading | 47.2 | 200 | 56 | **304** |
| Input needed · reading `12:05` | 47.2 | 200 | 64 | **312** |
| Running · 12 sessions, 7 subagents | 53.8 | 200 | 56 | **310** |
| Running, with a finished turn buried under it | 47.2 | 200 | 68 | **316** |

Four of the nine share one width.

**The notched bar never gets a subject.** It has no middle, and the only way to give it one is a wing — `102` pt of black beside the cut-out for the whole of every turn, which is the reservation both wings spent V1 and V2 getting rid of. This is permanent, not deferred.

## 6. The notch-less pill

### 6.1 Fixed ends, and a middle that gives way

```text
12 + 33.8 + 8 + the middle + 8 + trailing + 12  =  209
```

**One width in every connected state.** `209` is what this form last held still at — §6.4's reserved composition at one product, `12 + 22.26 + 12 + 52.74 + 32 + 65.91 + 12 = 208.91 → 209` — so the pill is never wider than it has already shipped.

The two forms are inverses. The notched bar has a fixed middle and moving ends; the pill has fixed ends and a moving middle, because it is centred on the display and pinned to nothing — every point either end took would be taken from both edges at once, and its contents would travel with them.

- **Leading group, `33.8`, anchored.** Mark `16.6`, gap `4`, counts column reserved at its two digits `13.2`, so a tenth session widens nothing and moves nothing. This is the one place the pill and the notched bar differ in composition rather than content.
- **Trailing group, anchored, growing inward.** The reading's last glyph stands `12 + 4` from the trailing edge in every state, so `9:59 → 10:00` adds its digit at the leading end and the seconds do not move. A buried finish puts its dot `8` in front of the reading and pushes the same way.
- **The middle is a subtraction.** `135.2` minus whatever the trailing group draws. No cap, no reservation, no constant of any kind.

| Trailing group | Its width | The middle |
| --- | --- | --- |
| Nothing being timed | 0 | 135.2 |
| `1:23` | 36 | 99.2 |
| `12:05` | 44 | 91.2 |
| `1:23`, a buried finish in front of it | 48 | 87.2 |
| `1:00:00` | 56 | 79.2 |
| `10:00:00` | 64 | 71.2 |
| `10:00:00`, a buried finish in front of it | 76 | 59.2 |

The reservation comes back, and this time the room it holds is not empty. §6.4 removed it on a finding that was correct when made — a reservation protects a neighbour, and nothing in the menu bar is laid out from this window — but both halves of that argument turned on the room being empty. It now holds the only thing on this surface a person reads as a word, and what the reservation protects is the pill's own contents: with the width fixed, the mark, the counts, the dot and the reading stand in the same place in every state, and the only thing that changes anywhere is how much of a name fits.

`Disconnected` is the one state still sized to itself — `12 + 16.6 + 12 = 40.6 → 41`. Nothing can follow it and there is no product behind it, so each `8` clearance, which exists only where content stands on both sides of it, is absent.

### 6.2 The subject, and the rotation

The middle draws **the name of the work**: the Project of each row in the monitored list, drawn from the middle's own leading edge — `54` from the pill's leading edge in every state that draws one — and fading where the middle ends.

Nothing on any collapsed form has ever named the work. Page 01 removed hue and the matrix pair on the argument that a product name is a colour rather than a row, and that was correct — but a Project name is the opposite of a product name. With five checkouts open it is the fact that decides whether you interrupt yourself, and it is the one thing the mark, the two numerals and the clock all leave unanswered.

**It cycles.** Every Project with an active row is named in turn:

- `5 s` each, cross-fading on the slot curve the wings' contents already use.
- The panel's own row order, **deduplicated**, first occurrence winning.
- The cycle **holds its place when the set changes** — a Project joining or leaving does not restart it.
- One Project does not cycle; it is simply named. None draws nothing.
- **Decoupled from urgency**: it advances whatever the mark is doing.

**The clock does not follow it.** Because the name belongs to no one row, the reading returns to its plain meaning — the longest unfinished turn anywhere. The bar stops claiming to be one row's report and becomes what it now is: two totals, a clock, and a rotating roster of the work behind them, with no term in it pretending to describe another.

> This is the cost, stated plainly: for one frame in every *N*, the name beside an urgent mark will be a Project that is not the one waiting. `double knock · notchline · 12:05` does not mean notchline is the one waiting, and cannot be read as though it does. The rotation is what makes that legible over a few seconds; a static glance cannot distinguish it. **This is the weakest point in the V2 collapsed surface and the thing to watch first on a real menu bar.**

### 6.3 Widths

| State | Total |
| --- | --- |
| Disconnected | **41** |
| Every connected state | **209** |

`notchline` measures `55.10`, so it fits whole in every row of §6.1's table; a name has to pass about ten characters before the longest reading this surface can draw is able to clip it.

## 7. What the collapsed surface no longer says

| V1 channel | What it said | V2 |
| --- | --- | --- |
| Matrix hue | Which product this mark belongs to. | Gone as identity. Returns as taste — one aggregate ink from 36. |
| One matrix per product | How many products, and each one's state. | One aggregate matrix, most urgent status anywhere. |
| Matrix animation | The state. | **Unchanged, and now alone.** |
| Session dot column, per product | That product's open rows, capped at three. | The large numeral. Aggregate, uncapped, exact. |
| The column's breath | A finished turn buried under the fold. | The trailing wing's dot, which breathes (§4.3). |
| Subagent badge, per product | That product's subagents. | The small numeral, aggregate, in the leading wing. |
| Badge ground inversion | A subagent stopped on approval or input. | Gone — already inside the aggregate the matrix animates. |
| Status name (`MonitorStatus.displayName`) | The aggregate status, in words. | **No longer drawn** on any collapsed form. Kept as the accessibility label, and still drawn by every expanded row. |
| Timer | The longest unfinished turn. | Unchanged, and it no longer leaves when the turn ends (§4.2). |
| Resting grey `#151515` | Nothing is connected. | Unchanged, and it stays neutral. |

## 8. What this reaches outside the collapsed bar

Two things, both consequences rather than choices:

1. **The expanded header stops drawing the status name.** Every row in the list under it already states its own status, so the header's word was a summary of the line below it. With the name gone the cut-out branch stops firing, `PanelMetrics.size` stops taking a `statusReadoutText`, and `everySentenceTheExpandedHeaderCanSayClearsTheCutOut` retires with the sentence it was checking. **The panel is `520` on every machine at every agent count a machine is likely to run.**
2. **`Hide the wings` (§9).**

~~With the name gone the widest a side can want is `70.51`, and `70.51 + 220 + 70.51 = 361`~~ is void: that figure kept one matrix per product in the header, which is the first of the two questions below, and both have since been answered the other way.

**The two questions this document parked are now answered**, on the board page this document said did not exist — [`expanded-header-v2.md`](expanded-header-v2.md), from `05 — The expanded header`. The header does **not** draw the collapsed reading: it belongs to the row the panel puts first, which is drawn in full below it. The header does **not** keep one matrix per product: it draws this document's aggregate mark and this document's counts column, unchanged and in the same place, and then decomposes the counts one colour-coded column per working agent — which is the one thing the collapsed surface has no room to say. Nothing in this document depends on either answer, and none of its widths move.

## 9. `Hide the wings`, under one mark

The setting survives, simplified. With one aggregate mark the leading wing is **simply present or absent**; §8.4's per-product table and its "which mark it is, is said by hue" sentence both go.

**What brings the wing out is unchanged.** Approval, input, and a Completed turn nobody has read — and the buried case still counts, with the mark drawing Radar, exactly as §8.4 already has it per product. `Working…` alone asks for nobody and keeps the bar at the cut-out.

**The trailing wing now comes out too, for the dot alone.** This is the one sentence in §8.4 that has to change rather than be re-scoped — and it changes on its own reasoning: "the badges and the elapsed reading say *how much* and *how long*, and neither says that a person is wanted." The reading still never comes out. The dot does, because a finished turn nobody has read is precisely a thing that wants a person.

| State | Body width |
| --- | --- |
| Nothing waiting | **200** — the cut-out and nothing else |
| A turn wants a person | **248** — `47.2 + 200`, mark and one session digit |
| …with a buried finish beside it | **272** — trailing wing `8 + 4 + 12 = 24` |

The setting still requires a *measurable* cut-out, so it is disabled on every screen the pill is drawn on. Nothing in §6 reaches it.

## 10. Accessibility

§10's rules carry over, with one honest amendment.

- `MonitorStatus.displayName` **stops being drawn, not being said.** It remains the accessibility label on both collapsed forms and the word every expanded row draws for itself.
- The dot's breath is spoken, on exactly the terms it moves on — `MonitorStore.spokenBuriedCompletionText`, `2 turns finished and unread`. It says how many, which the movement never does.
- **The amendment.** §10 records that Reduce Motion is not supported because "every status is already carried by text and by a ground that states it without movement". With the word gone, `Input needed` and `Approval needed` are told apart **by pattern alone** on both collapsed forms — one channel, made of movement. This is less a new loss than an extended one: the notched bar has been in exactly this position since V1, because it never had room for a word. What changes is that the pill joins it. The decision not to read `accessibilityDisplayShouldReduceMotion` stands, but **its stated reason no longer covers the collapsed surface**, and this document records that rather than leaving §10 looking sound.

## 11. Verification

- [ ] Notched bar totals match §5.2 at every state, including `316`.
- [ ] Pill is `209` in every connected state and `41` disconnected.
- [ ] The counts column draws identically at a 46 pt and a 22 pt menu bar.
- [ ] The large numeral rises `4.37` when the first subagent arrives and drops back when the last one leaves.
- [ ] The reading freezes rather than leaving, and the panel edge does not move at that instant.
- [ ] The dot appears only when `buriesAFinishedTurn`, breathes by opacity, and never changes the wing's width.
- [ ] The middle cycles at `5 s`, holds its place across set changes, and never restarts on join or leave.
- [ ] The clock is the longest unfinished turn anywhere, independent of which Project the middle names.
- [ ] All 36 inks clear `#151515`, and switching ink changes no width and no brightness.
- [ ] `Hide the wings` brings out the mark for a buried finish and the dot with it.

## 12. Implementation mapping

Nothing in this document is implemented. `NotchPalette.MatrixInk` today holds V1's per-agent pair (`codexInk`, `claudeCodeInk`, `restingInk`); there is no aggregate ink, no counts column and no middle.

**Settings — recorded, not drawn.** Three changes fall due when the settings window is next opened. They are decided here, so §8.4's standing rule against pushing undecided features into settings is satisfied.

| Row | Change |
| --- | --- |
| `Hide the wings` | Rewrite. The per-product table and the hue sentence go; caption and tooltip both need rewriting, and neither can keep the phrase "that product's mark". §9. |
| `Name the work on the pill` | **New.** Display, beside `Hide the wings` and `Outline the panel`. Default **on**, notch-less only. Off, the middle draws nothing and the pill holds its `209` rather than shrinking. |
| The aggregate mark's ink | **New.** Display. Twelve hues at `hint`, ordered by distance from both product hues, the two equidistant ones marked and neither blocked. Default Sage · hint; existing installs take the same. [`aggregate-ink-palette.md`](aggregate-ink-palette.md) §5. |
