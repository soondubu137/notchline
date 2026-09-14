# Notchline — Updates on the notch

| Field | Value |
| --- | --- |
| Status | **Decided, not built.** Proposed and decided on 2026-09-13; §7's five questions were answered by taking every recommendation. §8's measurement comes before §4 rule 07 is built. |
| Version | 1.0 |
| Date | 2026-09-13 |
| File | [Notchline — Updates](https://www.figma.com/design/e0NkP8hWtYDivF5uCesed8) — `Updates — Proposal` |
| Scope | How Notchline says that an update exists, answers Check for Updates, and installs. It covers the band's About mark, the About panel's version line and control row, and a Settings pane. The collapsed bar, the session list and the footer are untouched. |
| Reaches | `AppUpdater` gains a notch-drawn `SPUUserDriver` in place of `SPUStandardUpdaterController`'s windows. It also reaches `AboutButton`, `AboutPanelContent` / `AboutUpdateControl`, a fourth `SettingsPane`, and `SettingsClosingRow`. |
| Supersedes | Two bullets of [`technical-explorations/self-update`](technical-explorations/self-update/README.md) §5.2: *Presentation* (start with Sparkle's standard windows) and *Settings* (one switch). [ADR 0022](adr/0022-update-through-sparkle-signed-with-our-own-certificate.md) is unchanged: this is how its updater is drawn, not how it trusts an update. |

## 1. Why the notch, not Sparkle's windows

Notchline is `LSUIElement`, so it has no Dock icon and no menu. Even with gentle reminders, a scheduled Sparkle alert opens behind the front app, and nothing lets you bring it back. It would also be the only window Notchline ever opens unasked.

So an update is told the way everything else is: quietly, inside the panel you already open. Everything below reuses ink and controls that are already drawn.

- A found version is a dot on the About mark (§2).
- The About panel's one control carries the whole update (§3).

The one Sparkle surface that stays is the administrator prompt for a folder Notchline cannot write to.

## 2. A found version: a dot on the About mark

- **Where.** The band's About mark, the one control that stands for the app rather than the work. `expandedTrailingSideWidth` does not change and nothing re-lays out. The collapsed bar never changes for an update.
- **What.** The finished-turn dot: `4` pt, `NotchPalette.finishedDot` (`#C7C7CC`), still. It already means *something finished that you have not read*. It never breathes; breathing belongs to a Turn buried under the collapsed bar.
- **Geometry.** Centred on the terrace glyph's empty corner cell (4, 4), at `(11.87, 11.87)` in the `13` pt glyph (`13 × (128 + 13.5) / 155`). It overhangs the glyph square by `0.87`, stays inside the `32` pt control, and sits `4.0` clear of the nearest lit cell, (2, 2).
- **Pointer.** The mark brightens and takes its `12%` ground as today; the dot keeps its ink.
- **Clearing.** The dot clears when About opens with the version on it. Closing About without a choice brings it back at the next daily check (§7 q05). Skip clears it until a newer version; Install clears it for good.
- **Spoken.** The About button's accessibility value becomes `0.5.0 Alpha available`, and its `help` becomes `About Notchline — 0.5.0 Alpha is waiting`.

## 3. The About panel carries the update

`PanelMetrics.aboutPanelHeight` stays a constant, so no frame-changing publisher is needed. Two already-drawn lines change:

- **The version line** reads from and to while a version is waiting: `Version 0.4.3 Alpha (16)  →  0.5.0 Alpha (17)`. The arrow and the new version are in `sessionTitle`.
- **The control row** (`28` pt, centred, `8` apart) becomes whatever the update needs next, drawn with one of four weights:

| Weight | Drawing | Used by |
| --- | --- | --- |
| Bare label | `label` (`#7C7C80`) on nothing; takes the quiet ground under the pointer | Skip This Version, Cancel |
| Quiet tile | `themeInk.on` at `0.14`, `0.18` on hover, label `themeInk.on`. `AboutUpdateControl` today | Check for Updates, What's New ↗, Try Again, Relaunch Now, Show in Finder |
| Ground | `themeInk.on` at `1.0`, white on hover, label `themeInk.off`: the answer row's Approve | Install and Relaunch, Relaunch to Update. At most one per state, and only on the step that changes the app |
| Reading | Light 13 in `reading`, the gloss in `label`; a `120 × 3` meter whose track is `hairline` and whose fill is `themeInk.on` | Progress and answers |

The thirteen states, numbered as on the board:

| # | State | Control row |
| --- | --- | --- |
| 01 | Nothing known | [Check for Updates] |
| 02 | Checking | [Checking…], label dimmed, same width, no press. Held for at least `0.6` s |
| 03 | Up to date | `Up to date  ·  checked 14:02`, until About closes |
| 04 | A version is waiting | Skip This Version · [What's New ↗] · **[Install and Relaunch]** |
| 05 | Already downloaded | Skip This Version · [What's New ↗] · **[Relaunch to Update]** |
| 06 | Downloading | `Downloading` meter `3.1 of 8.4 MB` · Cancel. Redrawn at most 4 times a second |
| 07 | Verifying | `Verifying 0.5.0 Alpha`, full meter, still |
| 08 | Waiting on a request | `Ready. Relaunches once the approval is answered.` · [Relaunch Now] |
| 09 | Updated | [What's New in 0.5.0 ↗] in place of Check for Updates, until About closes once |
| 10 | Newer than the latest release | `Newer than 0.4.3 Alpha, the latest release` |
| 11 | Couldn't reach the feed | `Couldn't reach the update feed.` · [Try Again] |
| 12 | Didn't verify | `0.5.0 didn't verify, so nothing was installed.` · [Try Again] |
| 13 | Move to Applications | `Move Notchline to Applications to update it.` · [Show in Finder]. Install is not offered |

What's New opens the version's GitHub release page in the browser. That page resolves because the repository is going public ([ADR 0022](adr/0022-update-through-sparkle-signed-with-our-own-certificate.md)).

## 4. Rules

On the surface:

1. **The collapsed bar never changes for an update.** It summarises Turns, and a version is not one.
2. **Nothing opens by itself.** No window, no expanding panel, no activation, no sound. The dot is the only thing a check nobody asked for may draw.
3. **A check nobody asked for reports only a version.** Nothing new, offline and a broken feed all stay silent, and it tries again the next day.
4. **A check you asked for always answers** (03, 10, 11 or 04), and holds 02 for at least `0.6` s.
5. **The About panel never changes height.**
6. **Nothing spins.**

In the app:

7. **A relaunch waits for every row that is waiting for an answer.** An answer given on the notch goes back through Notchline to the hook's own stdout, and a relaunch would cut that connection. The relaunch goes the moment the last one is answered, or on Relaunch Now. A Running Turn does not hold it (§7 q03).
8. **Notchline never relaunches itself unasked.** Only a press relaunches. A background download installs when Notchline quits or the Mac restarts.
9. **Skip hides one version.** A newer one brings the dot back.
10. **A build ahead of the feed is never called up to date.**
11. **Sparkle's own UI appears only for the administrator prompt.**
12. **Settings and About drive one updater.** A download started in either shows its meter in both; neither keeps state of its own.

## 5. Settings: an Updates pane

A fourth toolbar pane, `Updates`, after Quota (§7 q02). The window keeps its one size, `580 × 579`.

- **Group `Notchline`**, one row:
  - Title: the running version.
  - Caption, with a status dot: `Up to date · checked today at 14:02` with the grey dot and [Check Now], or `0.5.0 Alpha is waiting` with the blue dot and [What's New] [Install and Relaunch] (accent).
  - Pressing Install swaps the caption for §3's meter and amount, with Cancel as the capsule.
- **Group `Automatic updates`**, two switches:
  - `Check for updates` — *Once a day, from the release feed on GitHub.* Bound to `automaticallyChecksForUpdates`, **on**. Debug builds still start with it off (`NOTCHLINE_UPDATE_CHECKS_AUTOMATICALLY = NO`).
  - `Download updates in the background` — *Installs when Notchline quits or the Mac restarts.* Bound to `automaticallyDownloadsUpdates`, **off** by default (§7 q01).
  - Footnote, one line: *Notchline never relaunches unasked, and waits for requests still waiting for an answer.*
- **The closing row under every other pane** gains a tail while a version is waiting: `Version 0.4.3 Alpha (16)  ·  0.5.0 Alpha is waiting`. The tail is in the accent and links to the pane. It is the only change to the three existing panes.

## 6. Declined

- **Sparkle's standard windows.** See §1.
- **A dot on the collapsed bar.** That dot already means a finished Turn you have not read, so an update dot there would say something false about your work. On a notched display it would also open a wing for a fact that is never urgent.
- **A row at the top of the session list.** Rows are Turns and the viewport holds three. A row that is not a Turn breaks grouping, the queue and the band's counts, and it would sit above your work until you dealt with it.
- **Release notes inside About.** About's height is a constant, and changelog bullets run 40–80 words each, which would need a scroll view on a surface that has none.

## 7. Decisions (answered 2026-09-13)

| # | Question | Decided |
| --- | --- | --- |
| q01 | Background downloads on by default? | **Off.** Every change Notchline makes to the Mac follows a switch you turned yourself. |
| q02 | A fourth pane, or rows at the foot of Products? | **A fourth pane.** Products lists the watched apps, and Notchline is not one of them. |
| q03 | Should a Running Turn hold the relaunch too? | **No, once measured (§8).** The monitor rebuilds from the current snapshot ([ADR 0006](adr/0006-rebuild-from-current-snapshot-not-event-replay.md)), so running rows should come back. |
| q04 | Where does What's New point while the repository is private? | **The GitHub release page, once the repository is public.** Hosting was decided in ADR 0022 on the same day, so no popover is designed. |
| q05 | Does the dot come back after About closes without a choice? | **Yes, at the next daily check**, Sparkle's own reminder cadence. |

## 8. Implementation mapping

The `SPUUserDriver` callbacks, as named in the Sparkle 2.10 checkout, map to the states above. This mapping is read from the protocol and has not been run.

| Callback | Draws |
| --- | --- |
| `showUserInitiatedUpdateCheckWithCancellation:` | 02 |
| `showUpdateNotFoundWithError:acknowledgement:` | 03 for `SPUNoUpdateFoundReasonOnLatestVersion`, 10 for `…OnNewerThanLatestVersion`. Nothing for a scheduled check |
| `showUpdaterError:acknowledgement:` | 11 or 12 for a check you asked for, 13 for `SURunningTranslocated`. Nothing for a scheduled check (rule 3) |
| `showUpdateFoundWithAppcastItem:state:reply:` | The dot when `state.userInitiated` is false. 04, or 05 when `state.stage` is downloaded. The reply is held until a press |
| `showDownloadInitiatedWithCancellation:`, `…ExpectedContentLength:`, `…ReceiveDataOfLength:` | 06 |
| `showDownloadDidStartExtractingUpdate`, `showExtractionReceivedProgress:` | 07 |
| `showReadyToInstallAndRelaunch:` | Reply `.install` at once, or 08 and hold the reply while a row waits (rule 7) |
| `showInstallingUpdateWithApplicationTerminated:…`, `showUpdateInstalledAndRelaunched:acknowledgement:` | Nothing, then 09 on the next About |
| `dismissUpdateInstallation` | 01 |
| `showUpdatePermissionRequest:reply:` | Never reached: `SUEnableAutomaticChecks` is set |
| `showUpdateInFocus` | Nothing; there is no window to bring forward |

**To measure before building rule 7.** Relaunch a copy while a Turn is Running, then check two things. Does the row come back? And is a hook event sent during the gap lost, or recovered from the snapshot? If it is lost, a Running Turn joins the rule-7 hold and q03 is reopened.

Translocation should be detected when the check starts, so that 13 replaces 04 before Install can be pressed.
