# Notchline — Cover the words

| Field | Value |
| --- | --- |
| Status | **Built in full** — §13's minimum and the Settings row and the accessibility pass on 2026-09-10, §6's two hover bugs fixed and §7's peek built on 2026-09-11, with §4.4's searchlight, §7's glyph and §10's draw-on the same day. §12's five questions are still open. |
| Version | 1.1 |
| Date | 2026-09-10 |
| Amended | **The control is named `Privacy Mode`, and the pill is silenced rather than covered** (2026-09-10, by the board's owner, before any of it was built). Two decisions, and the second one costs something this document had been relying on. The name in Settings is `Privacy Mode`; *covering* stays the name of the mechanism, and §2 is unchanged and now matters more, not less. And the pill draws **nothing** where §4.1 had it draw a `48` pt bar — so **neither collapsed form can say the mode is on**, which §8 used to be able to claim of one of them. Touched: the header, §3, §4.1, §5, §8, §10, §11, §13. |
| File | [Notchline — Cover the words](https://www.figma.com/design/dVuKJLpd7BpL93n3sM40Ib/Notchline-%E2%80%94-Cover-the-words) — `01 — Cover the words` |
| Scope | What the notch surface draws while somebody else is looking at the screen. The pill's rotating name, a session row's three lines, a retired row's line, and the gesture that turns them off. No geometry moves, no metric in [`compact-view-v2.md`](compact-view-v2.md) or [`expanded-panel-v2.md`](expanded-panel-v2.md) changes, and the aggregate mark is untouched. |
| Reaches | One row in Settings' `Display` group, one flag on `MonitorStore`, the two accessibility labels that can carry a covered run, and the hover rule in `MonitorStore.pointerEnteredPanel()`. |

## 1. The leak is the hover, not a line of text

The case for this feature is usually put as *the notch carries project names and live preview text permanently, on the display people share*. Half of that is wrong, and the half that is wrong is the half that decides what to build.

| Surface | The words it draws | When they are on screen |
| --- | --- | --- |
| The notched bar | **none** | permanently |
| The pill | the rotating Project name | permanently, and `Name the work` defaults **on** |
| A live row | badge, Project, title, **the preview line** | after `0.15` s of pointer dwell |
| A retired row | `Project · title` | the same |
| An open row | the question, its options, a typed answer | after a click |
| The quota footer | product names, percentages, reset times | the same dwell |

The notched bar has no words at all and never will — [`compact-view-v2.md`](compact-view-v2.md) §5.2 makes that permanent. The pill's rotation is the one thing drawn without asking, and it already has a mute in Settings.

**What has no mute is the panel, and its exposure is not permanent — it is one accidental hover.** `hoverExpandDelay` is `0.15` s ([`MonitorClock.swift`](../Notchline/Notchline/MonitorClock.swift):149), the component stands over the cut-out and both shoulders, and a pointer on its way to a right-hand menu bar item rests there several times an hour. What unfurls is the prompt you typed and the model's live answer to it, at `13` pt, unasked, in front of everyone on the call.

So this document is not about a line of text being visible. **It is about a surface that opens itself.**

## 2. What this is not

**It is not a privacy promise, and it does not reinstate the one [`PRD.md`](PRD.md) §7 deleted.** That contract was about where message text lives — process memory, disk, which socket it arrived on — and it is void on its own terms. This is about what is *drawn on a screen somebody else is looking at*, which is a question about the surface and has nothing to say about the data behind it. Nothing here constrains where text goes, and no clause here may be cited to veto an engineering decision about storage or transport.

**It is not `Hide the wings`.** That control gives the cut-out back and slides the mark out when a turn needs a person ([`SettingsWindow.swift`](../Notchline/Notchline/SettingsWindow.swift):270). It is about the bar at rest, it deliberately breaks cover the moment something is waiting, and it does not touch the panel.

## 3. The rule

**Everything the component draws that a stranger could read as content is covered. Everything that says only how much and how urgent stays.**

| Covered | Kept |
| --- | --- |
| The pill's rotating Project name — **silenced, not covered** (§4.1) | The aggregate mark, at its full animated vocabulary |
| A row's Project name | The two numerals |
| A row's title | The clock, and the finished-turn dot with its breath |
| A row's preview line | Every product badge |
| A retired row's `Project · title` | Every row's status, ground and ordering |
| | The quota footer entire |

Three of those are decisions rather than consequences, and each is arguable.

**The mark keeps everything.** Covering is about words, not about whether something wants a person. A cover that also dimmed the mark would be a mute, and a mute is what quitting is for. The whole value of this feature is that it costs you nothing you were using the notch for.

**The badges stay.** `Codex` and `Claude Code` name the tool, not the work, and they are what keeps a covered panel legible as a list rather than a stack of bars. They are also the one exclusion worth revisiting: a demo where the sensitive fact is *which* assistant you run is a real demo, and §12 leaves it open.

**The footer stays.** It names no work. A percentage and a reset time say how much of your own week you have spent, which is not a thing an audience can do anything with.

## 4. The cover is drawn, not deleted

Each covered run is replaced by a **cover bar**: a fully rounded rectangle, `6` tall, corner `3`, in `#7C7C80` at `45%`.

**One ink and one alpha for every bar, and it is the panel's dim one.** A row ranks its three lines by brightness — white at `98%` for the title, `#7C7C80` for the caption and the preview. Ranking the covers would be ranking things nobody can read, and a bar in the title's white would be the brightest object on a covered panel, which hands this surface's attention channel to a mark that carries no attention. At `45%` three bars read as *the absence of text*, which is what they are.

### 4.1 The lengths are fixed, and they are not the text's

| What it covers | Length | As a fraction of the row's content box |
| --- | --- | --- |
| A row's Project name | `64` | `0.13` |
| A row's title | `160` | `0.32` |
| A row's preview line | `224` | `0.45` |
| A retired row's line | `160` | `0.32` |

**A bar sized to the run it covers leaks the shape of the work** — the length of a project's name, whether a prompt was one clause or four — and it would twitch line by line as a preview streams. The three lengths descend because the three lines descend; that is layout, and layout is not a channel anybody reads meaning off.

**The pill is the exception, and it draws nothing at all.** A `48` pt bar in the middle was the obvious fourth row of that table and is declined: it would be the state announcing itself on the one collapsed form *able* to announce it, while the notched bar — which draws no words — could never match it however much it wanted to. One rule for both collapsed forms is worth more than an indicator on one of them. So the middle goes as quiet as `Name the work` off, which is a drawing this surface already has, and the width does not move either way because the middle is a subtraction and both ends are anchored ([`compact-view-v2.md`](compact-view-v2.md) §6.1).

`Privacy Mode` does not *write* `Name the work`, and turning the mode off gives the name straight back. Two controls, one drawing, and neither reaches into the other.

### 4.2 Nothing moves

A live row is `72` covered and `72` uncovered. The panel's height does not change, the pill stays `209`, the notched bar's edge does not move by a point.

**This is the point of covering rather than collapsing**, and it is not a nicety. You take this gesture with an audience watching; a component that resizes at that moment is the one thing on the screen everybody's eye goes to. It also keeps the feature clear of the trap recorded against `frameChangingPublishers` — a control that moves the panel has to be hand-added to that list and no test finds the omission. This control moves nothing, so there is nothing to add.

### 4.3 It makes the overlay cheaper

A cover bar is a rectangle. It costs no text layout, and while it is drawn **the preview line stops being a continuously changing text run** — `MessageDisplay` deltas no longer reach anything that measures. Covered, the panel's re-render count falls to what the clock and the mark alone ask for. Against `AGENTS.md` §7's rule this feature is on the right side of the ledger, which is unusual for an addition.

Two alternatives are declined outright. **A blur** is the one effect this overlay has measured and taken back out. **A run of bullets or dashes** is text, needs the face loaded and measured, and puts the cost straight back.

### 4.4 The searchlight crosses the cover

**A covered body line keeps the sweep the words were carrying.** It is the channel that answers *live or finished* — the one thing on this panel that can be read without looking straight at it, which is how a menu-bar surface is actually watched — and covering is supposed to take the content away, not a reading. A covered running row that stopped sweeping would look exactly like a covered finished one, and the panel would have lost the reading it exists for at the moment somebody most needs it to be cheap.

**The body line only, which is exactly where it crossed the words.** A row's Project and its title never carried it, so their covers do not either. The rule is unchanged: `sweepsBody(for:)` is `status.keepsTiming`.

**It is the text's own sweep, at the text's own period**, installed through the same `NotchTextRaster.installSweep(on:across:height:period:)` — so a bar and the line it replaced cannot drift out of phase with each other or with any other row. That also decides the implementation: the bar is layer-backed like `SessionRowText`, because no continuously running animation in this overlay may be a SwiftUI one (`AGENTS.md` §7). §4.3's saving stands — a bar still costs no text layout, and this is the same single `CABasicAnimation` the line already had.

**The crest is the ink the bar is made of, at full strength**: `#7C7C80` at `45%` at rest, `100%` at the peak. Measured on the panel, `0.224` to `0.498` in brightness. It is the ceiling `compact-view-v2.md` §4.3 chose for the breathing dot, and for the same reason — the movement is tuned against a screen and the crest is chosen against a value, so a covered run can be seen to be live without the brightest object on a covered panel being a mark that carries no attention at all.

## 5. The gesture: a secondary click on the component

**A secondary press anywhere on the component that is not a row toggles the cover** — the collapsed bar, the band, the footer, the empty list.

One press, no menu, no window, no trip into Settings. [`SecondaryClickCatcher`](../Notchline/Notchline/NotchOverlayView.swift):4422 already establishes the idiom and says why a `contextMenu` is wrong here: the press *is* the whole interaction, on a panel that hides itself as soon as the pointer leaves. Rows keep the secondary click they have — `dismiss(session)` on a live one, `removeFromRecent(departure)` on a retired one — which is not an inconsistency: a secondary click has always been contextual to what is under it.

**Settings is where it is discovered, and the caption is what teaches the gesture.** One row in the `Display` group, second, straight after `Show Notchline on` — the only row in that group somebody opens the window in a hurry to find; everything under it is taste.

```
Privacy Mode                                                 ( ●)
Every name, title and line is drawn as a bar, and the pill stops
naming the work. The mark, the counts and the clock stay, and the
panel waits for a click instead of opening on hover.
Secondary-click the component to turn it on and off.
```

**The name in the window is `Privacy Mode`; the mechanism is still covering.** The two are kept apart deliberately, and §2 is the reason — a comment or a symbol about drawing must never be readable as a claim about data. `MonitorStore.privacyMode` is the flag, `coversWords(of:)` is the question a row asks, and `CoverBar` is what gets drawn.

**The gesture is claimed on the band**, which collapsed *is* the whole surface and expanded is the one strip present in every state. That is "anywhere that is not a row" drawn twice: rows already own the secondary press, and a catcher over the list would swallow it.

## 6. Covered, the panel opens on a click

**This is the half of the feature that answers the threat, and it costs no pixels.**

The leak is a `0.15` s dwell the user did not intend. While the cover is on, `pointerEnteredPanel()` does not schedule an expansion; a primary press on the collapsed component does. Brushing the notch on the way to a menu bar item then does nothing at all.

It is also the only thing that tells a notched display the cover is on (§8). The channel is behaviour rather than ink, which is a weak way to say something and the only one available.

**Hover still collapses it**, unchanged, and `pointerExitedPanel()`'s guard against closing a row somebody is reading still holds.

**An entry still answers a pending exit, covered or not.** Declining to *expand* on hover is not declining to hear the pointer: `scheduleHoverAction` begins by cancelling, so on the ordinary path an entry takes back an exit's pending collapse for free, and a covered `pointerEnteredPanel()` that returned early lost that for nothing. §11.2 is what it cost.

**And leaving the mode under a stationary pointer opens the panel.** The gesture is a press *on the component*, so the pointer is on it when the mode goes off — and `.onHover` is an `NSTrackingArea`, which speaks only when the pointer moves. The entry that would have opened the panel was delivered while the mode was still on and declined; nothing delivers another until the pointer leaves and comes back. So the store keeps `isPointerOnPanel`, and the flag going false re-offers that entry — through the ordinary dwell, because one path opens this panel on hover and this is that path being told the answer has changed. It is not offered when the pointer is elsewhere, which is what turning the switch off in Settings looks like.

## 7. A deliberate press reveals

The principle, stated once and applied twice: **the cover silences what is drawn unasked; it does not silence what you ask for.**

**Opening a row reveals that row.** Its Project, its title, its preview and its question body all draw normally for as long as it is open, and re-cover when it closes. A covered panel you cannot answer a question in is a panel people will simply switch back — and the click that opens a row is as deliberate as a gesture on this surface gets.

**A peek for closed rows** is the other half, and it is the reveal-password idiom: **one control in the band, held down, lifting every cover at once and putting them back on release.** The thing being read is the list, so it lifts the list rather than a row at a time.

**It is chosen for what it cannot do.** `Privacy Mode` is a mode somebody turns on before a call and forgets; a second switch that also lifted the covers would be a second thing to forget, and the state it left behind would be indistinguishable from the mode being off. A control that is only true while it is held cannot be left on — and the peek ends three ways, not one: the release, the panel closing, and the mode ending. The second matters because a release can land after the panel has gone (the pointer left while the button was down, the menu bar was concealed, a navigation closed it), and the covers would otherwise be up the next time it opened.

**Where it stands, and why not with the other two.** Flush to the left of the About mark and the gear, growing into the slack between them and the counts, so neither of the two controls a user has already learnt the position of moves. It is deliberately *not* a third member of that group: `PanelMetrics.expandedTrailingSideWidth` is two boxes wide and feeds `restingExpandedWidth`, so a third would move the panel's own edge — and `privacyMode` would then have to join `frameChangingPublishers`, a list nothing tests. Drawn only where there is something to lift (`hasCoveredRows`), which also keeps it off the one form narrow enough for that width to bind.

**A press, not a click.** `DragGesture(minimumDistance: 0)` reads the press and the release apart; a `Button` fires on the release and would give one frame of uncovered text at the moment the pointer let go, which is the opposite of what the control is for. The glyph does not change under the press — this surface says a control is on by being brighter and taking no ground, and a glyph that swapped for another mid-press is a second thing moving under a finger already holding something down.

**The glyph is the covers, not a picture of looking.** An eye stood here first and is the wrong register: everything else the band draws is a geometric mark in the app's own vocabulary — a `5 × 5` matrix, a brand mark, a gear — and a pictograph among them reads as borrowed. It is three stacked pills, short then medium then long, in the bar's own corner radius: the row this control lifts, drawn at glyph size, so the button *is* what it acts on. Unequal widths and fully rounded ends are also what keep it from reading as a hamburger, which is three equal bars with square ends. The literal `64 : 160 : 224` is not used — it puts the first at a fifth of the third, which at `13` pt is a dot beside a line — so what survives the rounding is the order and the character.

**The keyboard latches, and that is the one exception to "cannot be left on".** A held press has no keyboard equivalent, and *you may not read this list without a mouse* is not an answer — so VoiceOver's activation toggles instead, the label says which way the next one goes, and the latch dies with the panel like every other peek.

**Not a modifier, and not hover.** `⌥`-hover is the obvious design and is unavailable: the overlay is non-activating and never key, so `flagsChanged` reaches nothing, and a global keyboard monitor needs the Accessibility permission [`tech-design.md`](tech-design.md) §1146 refuses to ask for. Polling `NSEvent.modifierFlags` on mouse-moved works and updates only when the pointer moves, which is a control that ignores you until you jiggle the mouse.

**Not the row's primary click.** That is already *go to this thread*, and the row must keep it.

## 8. It persists, and neither collapsed form can say so

**The flag survives a relaunch.** A cover that quietly lapses is a leak; a cover you forgot is an annoyance. The two failures are not comparable, and the second one is what §6 exists to bound — on a covered machine the first pointer pass over the notch does nothing, which is noticed in seconds.

**And neither collapsed form can draw the state.** On the notched bar there is no free channel: brightness and size are the counts', hue is the user's and means one thing already, and width moving would break the rule that a wing gives its width back without moving what a person reads. The pill *could* have said it, and §4.1 declines to let it: an indicator on one of the two forms is worth less than one rule for both. A silent pill is also, from across a room, indistinguishable from `Name the work` off — which is a real cost and is accepted rather than argued away.

So the state is legible in the panel, in Settings, and on either collapsed form only through §6's behaviour: the first pointer pass does nothing.

This is stated rather than finessed, the way [`compact-view-v2.md`](compact-view-v2.md) §6.2 states the rotation's own cost. **It is the weakest point in this design and the first thing to watch on a real machine.**

## 9. Accessibility

**The tree describes the drawing.** A covered run is spoken as covered, not read out.

Four labels carry a title or a preview today — [`NotchOverlayView.swift`](../Notchline/Notchline/NotchOverlayView.swift):1707 folds `current content:` into the live row's label, :1734 and :1961 fold the Project and the title, and :3452 does both for a retired row. Each drops its covered runs and says so once. Everything else in those strings — the product, the status, the elapsed, the subagent counts — is unchanged, because none of it is covered.

## 10. Motion

**The rotation stops, and nothing replaces it.** The middle is not drawn at all, so `RotatingProjectName` is never mounted and `ProjectNameHandover` runs no transitions. Twelve handovers a minute on a shared screen is the thing every eye in the call follows; a bar in their place would have been still, and no bar at all is stiller.

**The finished-turn dot keeps its breath.** It says a turn finished and nobody has read it — attention, not content — and §3's rule keeps every attention channel.

**Entering and leaving the cover is a cross-fade in place**, on `PanelMotion`'s own curve, with no geometry change behind it. There is nothing to slide, because nothing moves.

**The peek draws itself on, dealt out a bar at a time.** It was the one abruptness on this surface anybody noticed: every other mark in the band arrives on `PanelMotion.fade(isArriving:)`, and this control blinked into existence at full ink and blinked out again. The fix is the one `FoldSeamRule` already uses — **keep the room, animate the mark**. The box stands in the band for as long as a peek could be offered at all (`MonitorStore.keepsPeekRoom`), and the mode decides only what is drawn in it, so switching it is a drawing rather than an insertion. That room is free here and nowhere else: the peek grows into the slack between the counts and the trailing pair (§7), so an empty box in it moves nothing and costs no width.

**The order is the covers.** The three pills grow out of their leading edge on the band's own fade, short then medium then long, `50 ms` apart — the row being covered, drawn at glyph size. Coming off they reverse on the shorter curve, `35 ms` apart, which puts the long bar — the run of preview text, the most of a row a stranger could read — out of the way first. The only thing this adds to the surface's vocabulary is that order; the curve and both durations are the ones every other mark in the band arrives on.

**Nothing waits for it.** The covers on the rows go on and come off on the same frame the switch is thrown; this is a control arriving after the fact and retiring after the fact, and the press it offers is live from the first frame of the draw. An empty box takes no press, draws no hover fill, and is not in the accessibility tree. Measured 2026-09-11 on the Release panel, sampling the panel's own content view at 60 Hz: first bar lit at `96 ms`, all three at full ink and full length by `312 ms`, and the glyph clear `181 ms` after the mode ends.

## 11. Implementation mapping

| This document | Where it landed |
| --- | --- |
| The flag | `MonitorStore.privacyMode`, `@Published`, defaults key `privacyMode`, read with `bool(forKey:)` — off on a fresh install |
| The reveal rule (§7) | `MonitorStore.coversWords(of:)` — the flag, minus the row that is open |
| The gesture (§5) | `MonitorStore.togglePrivacyMode()`, on a `SecondaryClickCatcher` over the band |
| The press that opens (§6) | `MonitorStore.openFromCollapsed()`, guarded on both sides, called from `OverlayPanel.sendEvent(_:)` via `handlePrimaryPress` — **not** from a catcher; see §11.1 |
| The hover rule (§6) | One `guard` at the top of `MonitorStore.pointerEnteredPanel()`; `pointerExitedPanel()` untouched |
| The bar (§4) | `CoverBar`, with `PanelMetrics.coverBar*` and `NotchPalette.coverBar` |
| A row's Project | `SessionRowCaption`'s `isCovered`, which the open row passes `false` |
| A row's title and preview line | `SessionRowContent`, against its own `isCovered` |
| A retired row | `RetiredRowContent.breadcrumb` |
| The pill (§4.1) | One clause in `MonitorStore.drawsCompactMiddle` |
| Settings | `SettingsWindow.privacyModeRow`, second in `displayGroup` |
| The labels (§9) | `SessionRow.accessibilityText` and `RetiredRow.accessibilityText` |
| The peek (§7) | `PeekButton` and `PeekGlyph` in the band; `MonitorStore.isPeeking`, `beginPeek()`, `endPeek()`, `togglePeek()` and `hasCoveredRows`, with `isExpanded`'s and `privacyMode`'s `didSet` clearing it |
| The searchlight (§4.4) | `CoverBarView`, beside `SessionRowTextView`, sharing its sweep mask and period; `NotchPalette.coverBarDrawingColor` |
| The peek's arrival (§10) | `MonitorStore.keepsPeekRoom` mounts the box and `hasCoveredRows` draws in it; `PeekGlyph.draw(isDrawn:index:)` staggers `PanelMotion.fade(isArriving:)` over the three bars |

### 11.1 Three things the code settled that this document had not

**A covered preview line is asked for and thrown away.** §4 says a covered run keeps its line, and a row whose preview is `nil` has no third line at all — so the cover has to ask the same question the drawing does, `store.previewLine(for:) != nil`, and then draw a bar instead of the answer. Dropping the line under a cover would take `20` points out of a `72` pt row and change the panel's height at the moment somebody reaches for the gesture, with an audience watching. That is exactly what §4.2 exists to prevent, so the wasted call is the cheaper half of the trade.

**A hit-testing catcher cannot take the press that opens the panel, and the window has to.** This was built as one catcher over the band taking both presses, keyed on `NSApp.currentEvent` the way `SecondaryClickCatcher` is. On the real panel the secondary press arrived every time and **the primary press never did**: `acceptsFirstMouse(for:)` is consulted for a primary press and not for a secondary one, so AppKit hit-tests the view *before* the event is the app's current event, the catcher answers `nil`, and the press lands on whatever is underneath. Measured 2026-09-10 on a `.nonactivatingPanel` whose `canBecomeKey` is false while nothing is latched, which is every collapsed state.

So the primary press is taken in `OverlayPanel.sendEvent(_:)` — where the file's own focus rule already says *only the window sees every press* — and handed to the store unconditionally. The event is passed on regardless: this is not a claim on the click, only a chance to notice it. Nothing had to be decided about what is underneath, because `openFromCollapsed()` is guarded on both sides and a covered panel is collapsed. The bespoke `BandPressCatcher` was deleted with the finding; the band keeps the `SecondaryClickCatcher` the rest of this surface uses.

### 11.2 What the two shipped bugs were, both of them this design's own

Both were reported on the real panel the day this was built, and both are the same mistake seen from either side: **a guard that skipped the hover path skipped more than the expansion.**

**A panel opened by a press shut itself a quarter of a second later.** Expanding writes a bigger window and SwiftUI rebuilds the tracking area around it — which delivers a spurious `exit` about `105 ms` after the resize and the matching `enter` about `112 ms` after that, with the pointer never moving. Traced in the unified log, not reasoned about; `panelResized(to:pointerAt:)` was innocent and reported `contains=true` throughout. On the ordinary path the entry cancels the exit's collapse for free. The covered path returned early, so the collapse stood and nothing was left to deliver another entry. The fix is one `cancelPendingHoverAction()` in the guard.

**And turning the mode off under the pointer left the panel shut.** The gesture is a press on the component, so this is the ordinary way out of the mode, not a corner: the entry had already been declined and the tracking area had nothing left to say. The fix is `isPointerOnPanel` and the re-offer above.

**What made them findable and what nearly hid them.** The first sample after the press was taken at `1.5 s` and showed the panel open, which is how this shipped: the collapse lands at about `0.5 s` and the window had settled by the time it was looked at. Sampling every `250 ms` showed it at once. And the first regression test for it *passed with the fix removed* — a scheduled task registers its sleep after the call returns, so an `advance` issued straight away outruns it and the collapse never fires either way. The test asserts `sleeperCount` before the entry now, so it fails when the entry stops cancelling.

## 12. Open questions

All five stand. None was closed by the amendment, and question 03 is now sharper: with the pill silent, nothing on a collapsed screen says the mode is on.

| | Question | Why it is open |
| --- | --- | --- |
| 01 | Do the product badges stay? | §3 keeps them, and a demo whose sensitive fact is which assistant you run is a real demo. Covering them would leave a row with nothing but a mark and a clock, which may be the honest answer. |
| 02 | Does the quota footer stay? | It names no work, but it does say how much of your allowance is gone, in front of the people you are pairing with. |
| 03 | Should the cover expire? | It does not. Nothing about a demo has a natural end, and a timer that un-covers you mid-call is the failure this feature exists to prevent. |
| 04 | Is a global shortcut worth it? | `RegisterEventHotKey` needs no permission, and a keyboard gesture is the only one that works *before* the pointer reaches the notch. It costs a shortcut recorder and a default that collides with nothing. Not proposed here; proposed if anybody asks twice. |
| 05 | Should `Hide the wings` and this one row be aware of each other? | Both quieten the collapsed surface from opposite ends, and a person who wants one may want the other. |

## 13. What shipped

**All of it**, over two days:

1. §3's rule and §4's bar over the panel's four runs, and §4.1's silence on the pill's one.
2. §5's secondary click, on the band.
3. §6's click-to-open while covered — and, after the bugs in §11.2, an entry that still cancels a pending collapse and a mode ending that re-offers the entry the tracking area will not repeat.
4. §5's Settings row, and §9's two labels.
5. §7's peek: one held control in the band, three ways out of it, and a latch for the keyboard — and, since a control that blinks in and out is a control people look at, §10's draw-on.

**What to watch first, on a real pairing session:** whether people live behind the bars for an hour, or turn it off inside five minutes. The peek is what that turned on before it was built, and it is the thing to ask about first now that it exists. **And second:** whether a silent pill is mistaken for `Name the work` being off — §8 accepts that cost, and a real machine is where it either bites or does not.
