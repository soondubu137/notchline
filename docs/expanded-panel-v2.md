# Notchline — Expanded panel V2

| Field | Value |
| --- | --- |
| Status | **Designed, not implemented.** §2 can be built on its own. **§3 is superseded entire by [`answer-in-notch.md`](answer-in-notch.md)**, which designs the whole answering experience and corrects four of its clauses; read that file instead, and keep this one for §2. |
| Version | 2.0 |
| Date | 2026-09-04 |
| File | [Notchline V2](https://www.figma.com/design/c3CQBBk3Boiu0oM00Vvs9Y/Notchline-V2) — `06 — The expanded panel` |
| Scope | The expanded panel's session viewport only: the region between the band and the quota footer. The band is [`expanded-header-v2.md`](expanded-header-v2.md), the footer is [`dual-agent-design.md`](dual-agent-design.md) §5, and both collapsed forms are [`compact-view-v2.md`](compact-view-v2.md). None of the three is touched. |
| Supersedes | [`figma-design.md`](figma-design.md) §5.1's "removed automatically" as the end of a row's life, and §5.3's fixed `Approval requested` string. Narrows two [`PRD.md`](PRD.md) §3 non-goals and moves a third — §8.1, §8.2. |

## 1. What V2 changes here, and why

The band and both collapsed forms have been redrawn. The viewport between them has not, and it carries two faults that are not about drawing at all.

**A row that ends is deleted, not dimmed.** Membership is the monitoring lifecycle: the instant a Turn is terminal and its product records the Thread as read, the row is removed ([`figma-design.md`](figma-design.md) §5.1). That is correct — it is no longer anything to attend to — and it means the list is exactly right and permanently forgetful. The row it throws away is the one you just looked away from, and no gesture on this surface gets it back.

**A row states a question it cannot take an answer to.** `Approval needed` is drawn on the brightest ground the panel owns, and everything you can do about it is leave: the click opens Codex, where the dialogue actually is. The panel has already interrupted, has already been looked at, and already knows which Turn is asking. What it does not have is one field and one button.

**V2 gives the list a floor it continues past, and makes the two waiting grounds the two controls.** Neither addition asks for a new region, a new ink, a new corner or a point of height at the count where the list is busiest.

## 2. Recent — the list continues past its own end

### 2.1 Composition

| Object | Height | Where it comes from |
| --- | --- | --- |
| A live row | `80` | Unchanged |
| The seam | `32` | `9` + a `14` pt caption line + `9` |
| A row that has left | `40` | Half a live row, exactly |

The viewport is **its content, capped at `240`** — which is what `80 × min(rows, 3)` already was, restated in points so that rows of two heights can share it.

### 2.2 The seam

A label, a hairline and a chevron, on one `32` pt line at the foot of the live list.

- `Recent · 5` in `11` pt at `#7C7C80`, at the panel's own `12` — the caption idiom exactly, separator included.
- The hairline is **the list's own top rule drawn again**: `1` pt of white at `15%`, from `8` after the label to the content box's trailing edge at `508`. It therefore lands on the same `x` as the footer's quota rules and the band's matrix.
- The chevron is the quota block's control unchanged — `16 × 16` at `x = 492`, a `9 × 4.5` glyph at `1.4` stroke with round caps, in `#7C7C80`, pointing down when folded and up when open.
- The seam draws **no colour bar** in any attribution option, so it keeps the panel's own `12` margin while the rows beside it move to `20`.

### 2.3 A retired row

One line: **product · project · subject**, `13` pt Regular. ~~The product name takes that product's caption ink (`#4D81B7` / `#9C553E`)~~ — **the product is a badge** ([`colour-v2.md`](colour-v2.md) §5), ground and text from the `Theme colour` pair, drawn only while more than one product is connected. `· project ·` takes `#7C7C80`, and the subject takes `#C7C7CC` — one step below a live title's white-at-98% and one step above a caption. It ends in a fade like every other line here.

**The badge is `16` on a `13` pt line**, which is the same two points a live row's caption pays (§2.1). The line's own `40` is unchanged: it was measured from the half-row it has to equal, not from its text, and `16` still clears it.

The trailing reading is an **age** — `now`, `2m`, `9m`, `1h` — bare, `13` pt Light `#7C7C80`, tabular. The ground family does not travel below the rule: bare / white / dim answers *which of these wants me*, and nothing down here wants anybody. A bare age cannot be confused with a bare Running reading, being one line tall, under a rule, and counting the other way.

### 2.4 The rules

| | Rule | |
| --- | --- | --- |
| 01 | **It is the last five rows to leave, not the last five threads.** Every member was on the list a moment ago and was handed over by its product before it was ever given a row. Unsearchable, unpageable, holding nothing the list did not itself hold, and never containing a Thread this run has not watched | §8.1 |
| 02 | **Five, because the viewport says five.** A retired row is half a live one and the seam is `32`, so a seam and five rows is `232` against the viewport's own `240`. A sixth would scroll on a panel with nothing live, which is the one state where the queue should be readable at a glance | |
| 03 | **It is empty at launch.** Nothing has departed yet. A stored queue would be the one thing on this surface promising navigation to a Thread nobody vouched for this run, which is exactly what [ADR 0017](adr/0017-a-row-requires-a-thread-the-app-server-vouches-for.md) forbids the live list. Memory, not history | |
| 04 | **A row that retires halves; it does not vanish.** Completed sorts last, so a retiring row is already at the foot of the live list and the seam is directly beneath it: it drops from `80` to `40`, gives up two of its three lines and its ground, and passes under the rule. One local exchange, nothing travelling. A row dismissed by hand from the middle of the list is the exception — removed and re-inserted, with only the halving drawn | |
| 05 | **Everything that left is in it, whatever took it out.** Read, dismissed, or dismissed while still running. The reading is an age rather than a duration, so it stays honest in all three; and nothing below the rule claims a status, because the rule's meaning is that the list stops there | |
| 06 | **The ground family does not travel below the rule.** §2.3 | |
| 07 | **Folded by default, remembered, on the quota block's own control.** One setting, `recentFolded`, defaulting to folded. Unlike the quota's, folding this one never closes the panel: the footer stands between the control and the bottom edge, so that edge cannot travel past a still pointer ([`dual-agent-design.md`](dual-agent-design.md) §5.4) | |
| 08 | **The whole seam is the target, and that is a departure.** §5.4 gave the quota's chevron a `16 × 16` hit area because the rest of that line is a reading someone might want to select. This line carries only its own name, so the seam takes the row's own hover fill and the row's own click | |
| 09 | **Click opens the Thread; right-click takes the row out of the queue.** Both are the live row's own gestures meaning the same things. Right-click is the only way out other than being pushed by a sixth departure | |
| 10 | **The band never counts it, and the menu bar never hears about it.** The totals and their columns say what is running, and nothing below the rule is. The collapsed bar is untouched | |

### 2.5 The cost, and when it is paid

`32` whenever the queue is non-empty and the seam is on screen; `200` more while unfolded; **nothing at all at three live rows**, where the seam is below the fold and the viewport was already full.

**That is also where the discoverability cost sits**, and it is paid deliberately. With three things waiting on you, what you finished twenty minutes ago is not the question. What makes it affordable is that the seam returns exactly when it gains a member: three live rows becoming two puts it at `192`, inside the viewport, at the moment something retires into it. Pinning the seam to the foot of the viewport was evaluated and declined — §8.5 question 01.

## 3. Answering in the notch

> **Superseded entire by [`answer-in-notch.md`](answer-in-notch.md).** That document keeps this section's idea — the bright ground is the control — and corrects four clauses of it: §3.1's opening gesture, §3.2's fade and its three-line cap, §3.4's forces on the affirmative, and §3.5's close-on-send. It also designs the six request shapes this section never saw. What follows is kept as the reasoning that led there.

### 3.1 The ground becomes the control

**The text is the Thread; the ground is the answer.** A click on a row's text still opens that Thread in its product, unchanged ([`figma-design.md`](figma-design.md) §9.2). The reading's ground beside it — which exists on exactly the two waiting states and nowhere else — opens the row instead. Under the pointer that ground draws the word `Answer` in place of the reading, at the same `16` height and `4` corner: one word for both states, because it covers approving and refusing alike.

**Opening is required, and the requirement is the safety.** There is no one-click Approve on a closed row. A shell command approved from a hover panel by a pointer that happened to be passing is precisely what this surface must not make possible, and the request's remaining lines are the thing worth reading first.

### 3.2 The open row

The head does not move. The preview line — which for an Approval row is now **the request itself** rather than the fixed `Approval requested` — is lifted onto the panel's one recessed ink and given the rest of itself, up to three lines.

```
13.5 + caption 14 + 2 + title 17 + 2 + request block + 10 + answer row 28 + 13.5
```

| Form | Request block | Row |
| --- | --- | --- |
| Approval, one line | `34` (`18` + `8` each side) | `134` |
| Approval, three lines | `70` | `170` |
| Input needed, one line | `18`, no ground | `118` |

**Three lines is not a taste.** `170` leaves `70` of the viewport's `240`, which is enough of the next row to still read as a row. A longer request fades at the third line and is read in full in the product; nothing scrolls inside a row.

The request is set in **SF Mono 12/18** at `#C7C7CC` on a `#242424` ground at corner `4`, inset `10` horizontally and `8` vertically, the full `496` content width. An **Input needed** question stays on the preview line in prose and off that ground: the recessed ink is for machine text, and a question is not machine text.

### 3.3 One control, two configurations

Both products ask the same three-part question — yes; yes and don't ask again; **no, and tell it what to do differently**. That third option is an input, so refusing an approval and answering a question are the same gesture with the same field.

```
Approval needed   [ what to do instead…            ]   Deny   [ Approve ]
Input needed      [ your answer…                            ]  [ Send ]
```

- The affirmative is the **waiting reading's ground grown from `16` to `28`**: `#FFFFFF`, corner `4`, `12` padding each side, `13` pt Medium at `#0D0D0F`.
- The field and the request block are the **finished reading's ground grown the same way**: `#242424`, corner `4`.
- `Deny` is bare `13` pt Medium `#C7C7CC` with the gear's own `12%` white hover square at corner `4`.
- Nothing here is a new ink, a new corner or a new region.

**`Always` is not offered.** It is a policy about every future request, taken from a panel showing three lines of the current one; Notchline answers this request and hands policy back to the product. Adding it later is cheap and taking it back would not be — §8.5 question 05.

### 3.4 The white ground is the Enter key

Empty, the white ground sits on `Approve`. The moment there is text in the field it crosses to `Deny` and the affirmative drops to the recessed ink — still clickable, still discarding what was typed, but no longer the key. **The brightest thing on the row is always what Enter will do, and the user's own typing is what moves it**, so the change is always attributable. Neither button moves.

`⏎` sends the white one. `⇧⏎` makes a new line. `⎋` closes the row and hands the keyboard back.

### 3.5 Latching

**A click latches the panel; hover stops holding it.** Hover is browsing and a click is engaging. From the moment a row opens, the panel stops answering the pointer and takes the keyboard, closing on `⎋`, on the answer being sent, or on a click outside it. Without this the panel would shut mid-sentence, because moving to the keyboard is not a pointer movement and any drift is.

**One row is open at a time, and it is the subject.** Opening scrolls that row to the top of the viewport and holds it there against re-sorting ([`figma-design.md`](figma-design.md) §5.2), lays the hover fill under it permanently, and drops every other row to `45%`. Opening another closes the first; text typed but not sent stays with its row for as long as that row lives.

**Answered elsewhere wins, and says so by closing.** Settled in the product, cancelled, or the Thread gone: the block closes and the row becomes whatever it now is, and what was typed is dropped because there is nothing left to send it to. A send that fails leaves the row waiting with the text still in the field.

## 4. Heights

The panel is `panelHeight + viewport + footer`, with the viewport its content capped at `240`. At the `46` reference with both products and the quota expanded:

| What is in the list | Content | Viewport | Panel | Today |
| --- | --- | --- | --- | --- |
| Nothing live, nothing retired | — | `48` | **178** | 178 |
| Nothing live, the queue folded | `32` | `32` | **162** | 178 |
| Nothing live, the queue open | `232` | `232` | **362** | 178 |
| One live row, the queue folded | `112` | `112` | **242** | 210 |
| Two live rows, the queue folded | `192` | `192` | **322** | 290 |
| Three live rows — the seam is below the fold | `272` | `240` | **370** | 370 |
| Four live rows — it scrolls, as it already does | `352` | `240` | **370** | 370 |
| One live row, opened at three lines | `202` | `202` | **332** | 210 |
| Three live rows, one of them opened | `362` | `240` | **370** | 370 |

**Each connected form gets a new floor**, because an empty list stops spending `48` points saying it is empty and spends `32` offering the five things you last did:

| Connected | Footer | Floor today | Floor now |
| --- | --- | --- | --- |
| Both products | `84` | 178 | **162** |
| Claude Code alone | `53` | 147 | **131** |
| Codex alone | `30` | 124 | **108** |
| Either, quota folded | `22` | 116 | **100** |

Width is [`expanded-header-v2.md`](expanded-header-v2.md)'s `520` in every state above.

## 5. Sorting and membership

The live list's four-value sort is unchanged. The queue continues it:

```text
Approval needed > Input needed > Running > Completed   │ the seam │   most recently departed, descending
```

A retiring row therefore crosses one boundary and moves `40` points. A Thread that submits again leaves the queue and reappears above the seam as a live row — **the rule is a membrane and rows cross it in both directions**, as the same row.

## 6. Accessibility

- The seam is a disclosure control with the accessible name `Recent, 5 sessions` and an expanded state; the whole `32` pt line is its target.
- A retired row spells its line out and appends the age as words — `Codex, notchline, Redraw the mark at five rows, left 2 minutes ago`.
- The open row's controls are a group named after the row's subject. `Approve` and `Deny` (or `Send`) are buttons; the default-button state moves with the white ground, so a screen reader announces the same thing the ground says.
- The `Answer` word is drawn only under the pointer, so the closed waiting row keeps the accessible action `Answer this request` regardless of hover, and it is the same action a keyboard reaches.

## 7. Motion

- **A row retiring** takes the panel's own slot curve (`PanelMotion.slot(isOpening:)`): the row's height animates `80 → 40` while its second and third lines and its ground fade, and the seam rises over it. The edge leads opening and waits `50 ms` closing, exactly as the collapsed wings do.
- **Folding the queue** is the quota fold's own timing, and it does not strand the pointer (§2.4 rule 07).
- **Opening a row** grows it in place on the same curve; the request's second and third lines fade in behind the ground rather than being revealed by it.
- Nothing here introduces a new curve.

## 8. What this reaches outside the viewport

### 8.1 Two stated non-goals move, and only these two

[`PRD.md`](PRD.md) §3 rules out "sending input, granting permission, answering questions, cancelling, archiving or deleting threads" and "history search, the last N, or a fixed time window".

**§3 reverses the first for exactly one payload** — the request a row is already reporting — and for nothing else. No cancelling, no archiving, no deleting, no starting a Turn.

**§2 does not so much reverse the second as fall outside it.** The queue is not a query against history: it is a record of departures from this list, holding only rows this run drew and this run's products vouched for, unsearchable, unpageable, and empty at launch. That sentence in §3 needs amending to say which of the two it bans.

### 8.2 A third is narrowed rather than moved: raw tool arguments

§3 also rules out showing "tool arguments, command output, file diffs, sensitive paths or approval rationale" — and an approval request **is** a tool argument. It cannot be otherwise, because nobody can approve a command they have not been shown. So the ban narrows to one exception, **the payload of a request the product is already blocked on**, and every other item in that sentence stands, output and diffs included. It is also the one place this app draws a path it did not choose, which is why the request is set as machine text on a recessed ground rather than as prose, and why it fades at the third line instead of growing.

### 8.3 The panel has to be able to take the keyboard

Latching means the `NSPanel` becomes key, which takes focus from whatever the user was in and must give it back on `⎋`, on send, and on a click outside. This is the one genuinely new mechanic: `PanelMetrics` has nothing to say about it and `OverlayPanelController` has everything.

### 8.4 A write path per product, which does not exist yet

Notchline observes through hooks, and a hook is a notification. To answer a live approval or a question, each product has to offer a way in. **Until one does, §3 is a drawing** — and that is the feature's real cost, the drawing being the cheap half. It is a capability question rather than a design one, and it is the one thing here that should stop the work: a panel offering `Approve` that cannot deliver it is worse than a panel that offers nothing.

§2 has no such dependency and can be built alone.

### 8.5 Open questions

| | Question | Where it stands |
| --- | --- | --- |
| 01 | Does the seam pin to the foot of the viewport rather than scroll with the list? | **Standing recommendation: it scrolls.** Pinning would make the queue permanently findable and would cost `32` at exactly the count where the panel is most crowded — buying visibility for the one thing here that is deliberately secondary. §2.5 is what makes scrolling affordable. Worth watching on a machine that genuinely runs four rows at once |
| 02 | One line below the seam, or two? | **Answered as one**, and it is what fixes every height. Two lines would want `44` and would draw the no-preview row the `Colour bar` option already specifies. One line at `40` is exactly half a live row, and the breadcrumb carries product, project and subject anyway |
| 03 | Does the queue survive a quit? | **Answered — no.** §2.4 rule 03 |
| 04 | Should approving be possible without opening the row? | **Answered — no.** §3.1 |
| 05 | Is `Always` ever offered? | **Standing recommendation: not from here.** §3.3. If it is ever added it belongs beside `Approve` in the recessed ink and never on the white ground, because the white ground is the Enter key and a policy about every future request must not be what Enter does |
| 06 | What happens to a retired row whose product has gone dark? | **Open — the only genuinely unanswered question here.** A row below the seam still claims a destination, and the queue has no equivalent of the live list's hand-over check because it never re-asks. Two candidates: re-ask on click and say so when the answer is no, or drop the row when its product disconnects. The first keeps the queue stable and costs one local read at the click, which is what the live list already pays per row. Recommended, not decided |
| 07 | Does the seam draw with the quota folded and nothing else on the panel? | **Answered — yes**, and that is the `100` pt form |

### 8.6 Two smaller reaches

- **Membership gains a second question, answered in memory.** The store holds the last five departures in order, with what took each of them out, and answers navigation for them from what the product last vouched for. Nothing is persisted and nothing is re-read at launch.
- **Product attribution reaches below the seam.** ~~All four presentations apply: `Name and colour` and `Name only` land on the breadcrumb's prefix, `Badge` replaces that prefix, and `Colour bar` becomes a `2` pt bar the height of the one line.~~ **There is one presentation** ([`colour-v2.md`](colour-v2.md) §5): the badge replaces the breadcrumb's prefix, on the same presence rule as a live row's, and the setting that chose between four is retired ([`dual-agent-design.md`](dual-agent-design.md) §4).

## 9. Verification

- [ ] A live row is `80`, the seam `32`, a retired row `40`, at every menu bar height.
- [ ] The viewport is its content capped at `240`, and is `80 × min(rows, 3)` when nothing has retired.
- [ ] The panel is `162` with nothing live and the queue folded, and `100` with the quota folded too.
- [ ] Three live rows draw no seam and cost the queue nothing; the third retiring puts the seam back inside the viewport.
- [ ] A retiring row halves in place and the seam rises over it; nothing travels the length of the panel.
- [ ] Nothing below the seam draws a status ground, and every age reads as an age.
- [ ] The queue is empty at launch, holds at most five, and pushes the oldest out on the sixth departure.
- [ ] Folding the queue does not close the panel at any connected form.
- [ ] The seam's hairline lands on the same `x` as the footer's rules and the band's matrix, in every attribution option.
- [ ] Only `Approval needed` and `Input needed` rows draw `Answer` under the pointer; no other row becomes clickable.
- [ ] An opened row is `134` at one request line, `170` at three and `118` for Input, and never exceeds the viewport.
- [ ] While a row is open the panel does not close on pointer exit, holds the keyboard, and returns it on `⎋`, on send and on an outside click.
- [ ] The white ground is on `Approve` with an empty field and on `Deny` with a non-empty one, and neither button moves when it crosses.
- [ ] A request settled elsewhere closes the open row within one publish.
- [ ] The band, both collapsed forms and the quota footer draw identically to pages 01 to 05 in every state above.

## 10. Implementation mapping

Nothing here is implemented. The work lands in five places:

| Symbol | Change |
| --- | --- |
| `PanelMetrics.sessionViewportHeight(forSessionCount:)` | Becomes a height rather than a row count: the list's own composed height, capped at `sessionViewportHeight`'s existing `240`. `maximumVisibleSessionCount` retires with it |
| `PanelMetrics` | New: `retiredRowHeight = sessionRowHeight / 2`, `recentSeamHeight`, `openRowHeight(requestLines:)` |
| `MonitorStore` | A bounded five-element departure queue with its reason, fed wherever a row leaves today; `recentFolded` beside `quotaFolded` |
| `NotchOverlayView` | `RecentSeam`, `RetiredRow`, and `SessionRow`'s open state; `emptyListMessage` draws only when the queue is empty too |
| `OverlayPanelController` | Latching: key window on open, restore on close, and hover suspended for the duration (§8.3) |

`docs/PRD.md` §3 needs the two amendments in §8.1 and the narrowing in §8.2 before any of it is built.
