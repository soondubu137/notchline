# Notchline — Expanded panel V2

| Field | Value |
| --- | --- |
| Status | **Designed, not implemented.** §2 can be built on its own. **§3 is superseded entire by [`answer-in-notch.md`](answer-in-notch.md)**, which designs the whole answering experience and corrects four of its clauses; read that file instead, and keep this one for §2. |
| Version | 2.1 |
| Date | 2026-09-04, amended 2026-09-05 |
| Amended | **§2's queue is a five-hour window, not a five-row queue.** Membership is every row that left within the past five hours; five is now the number the viewport *draws* rather than the number the store *holds*. Touched: §2.2, §2.3, §2.4 (rules 01, 02, 05, 09 and a new 11), §2.5, §4, §5, §6, §7, §8.1, §8.5, §8.6, §9, §10. **No metric moves** — `32 + 5 × 40 = 232 ≤ 240 < 272` already said "five, then scroll", and it now says it about the fold instead of the store. One thing gets worse and is stated rather than finessed: the queue is now literally the "fixed time window" [`PRD.md`](PRD.md) §3 bans, and §8.1 rewrites that sentence instead of arguing with it. |
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

- `Recent · N` in `11` pt at `#7C7C80`, at the panel's own `12` — the caption idiom exactly, separator included. **`N` is what the window holds, not a constant**: it climbs as rows retire and falls as they age out, and it is the one thing on the seam that says there is more below than is drawn. A two-digit count widens the label by about `6` and the hairline simply starts `8` further along; the hairline's trailing edge at `508` does not move, so nothing downstream of the seam is width-dependent.
- The hairline is **the list's own top rule drawn again**: `1` pt of white at `15%`, from `8` after the label to the content box's trailing edge at `508`. It therefore lands on the same `x` as the footer's quota rules and the band's matrix.
- The chevron is the quota block's control unchanged — `16 × 16` at `x = 492`, a `9 × 4.5` glyph at `1.4` stroke with round caps, in `#7C7C80`, pointing down when folded and up when open.
- The seam draws **no colour bar** in any attribution option, so it keeps the panel's own `12` margin while the rows beside it move to `20`.

### 2.3 A retired row

One line: **product · project · subject**, `13` pt Regular. ~~The product name takes that product's caption ink (`#4D81B7` / `#9C553E`)~~ — **the product is a badge** ([`colour-v2.md`](colour-v2.md) §5), ground and text from the `Theme colour` pair, drawn only while more than one product is connected. `· project ·` takes `#7C7C80`, and the subject takes `#C7C7CC` — one step below a live title's white-at-98% and one step above a caption. It ends in a fade like every other line here.

**The badge is `16` on a `13` pt line**, which is the same two points a live row's caption pays (§2.1). The line's own `40` is unchanged: it was measured from the half-row it has to equal, not from its text, and `16` still clears it.

The trailing reading is an **age** — `now`, `2m`, `9m`, `1h`, `4h` — bare, `13` pt Light `#7C7C80`, tabular. **Its ceiling is `4h`, and that is the window agreeing with the reading rather than a coincidence:** nothing here can read `5h`, because at five hours the row is gone (§2.4 rule 11). The age therefore stays two characters for the whole of a member's life and the column never has to widen.

The ground family does not travel below the rule: bare / white / dim answers *which of these wants me*, and nothing down here wants anybody. A bare age cannot be confused with a bare Running reading, being one line tall, under a rule, and counting the other way.

### 2.4 The rules

| | Rule | |
| --- | --- | --- |
| 01 | **It is every row that left within the past five hours, not the last five threads.** Membership is a window, not a count: a row enters when it leaves the live list and stays until that departure is five hours old. Every member was still on the list a moment ago and was handed over by its product before it was ever given a row, so the queue remains unsearchable, unpageable, holds nothing the list did not itself hold, and can never contain a Thread this run has not watched. **Five hours is a constant, not a setting** — a window the user can widen is the history browser this app is not | §8.1 |
| 02 | **Five is what the viewport draws, and it needs no rule of its own.** A retired row is half a live one and the seam is `32`, so a seam and five rows is `232` against the viewport's own `240`, and a sixth is `272`. The arithmetic that used to justify a five-element store now describes a five-row fold exactly: **the queue draws five and scrolls past them in the panel's own viewport** — no second scroller, no nested scroll chaining, no new metric, and nothing to snap. And the `8` points the viewport has left over fall in the sixth row's own top padding — a retired row is `12 + 16 + 12` — so **they carry no ink at all**. There is no partial line, no sliver of a subject, nothing to notice: an over-full queue is drawn exactly like a full one, `8` points taller. That is why §2.2 makes the count live. It is not a redundant hint; it is the only one | |
| 03 | **It is empty at launch.** Nothing has departed yet. A stored queue would be the one thing on this surface promising navigation to a Thread nobody vouched for this run, which is exactly what [ADR 0017](adr/0017-a-row-requires-a-thread-the-app-server-vouches-for.md) forbids the live list. Memory, not history | |
| 04 | **A row that retires halves; it does not vanish.** Completed sorts last, so a retiring row is already at the foot of the live list and the seam is directly beneath it: it drops from `80` to `40`, gives up two of its three lines and its ground, and passes under the rule. One local exchange, nothing travelling. A row dismissed by hand from the middle of the list is the exception — removed and re-inserted, with only the halving drawn | |
| 05 | **Everything that left is in it, whatever took it out.** Read, dismissed, or dismissed while still running. The reading is an age rather than a duration, so it stays honest in all three; and nothing below the rule claims a status, because the rule's meaning is that the list stops there. **The window is measured from the departure instant, not from the Turn's end** — that is the moment this list stopped reporting the row, it is the only moment of the three the app itself observed, and it is what the age already counts | |
| 06 | **The ground family does not travel below the rule.** §2.3 | |
| 07 | **Folded by default, remembered, on the quota block's own control.** One setting, `recentFolded`, defaulting to folded. Unlike the quota's, folding this one never closes the panel: the footer stands between the control and the bottom edge, so that edge cannot travel past a still pointer ([`dual-agent-design.md`](dual-agent-design.md) §5.4) | |
| 08 | **The whole seam is the target, and that is a departure.** §5.4 gave the quota's chevron a `16 × 16` hit area because the rest of that line is a reading someone might want to select. This line carries only its own name, so the seam takes the row's own hover fill and the row's own click | |
| 09 | **Click opens the Thread; right-click takes the row out of the queue.** Both are the live row's own gestures meaning the same things. Right-click is the only way out that anybody performs; the other is the window closing behind the row | |
| 10 | **The band never counts it, and the menu bar never hears about it.** The totals and their columns say what is running, and nothing below the rule is. The collapsed bar is untouched | |
| 11 | **A row ages out, and the queue can empty itself.** Five hours after it left, a row goes — panel open or shut, folded or not. When the last member goes the seam goes with it and the panel returns to its empty floor: the first region on this surface that disappears with nobody touching it. This is the second way to be empty, and it makes rule 03 truer rather than weaker — the queue is memory, and memory of the morning is not owed at teatime | §7, §10 |

### 2.5 The cost, and when it is paid

`32` whenever the queue is non-empty and the seam is on screen; `40 × min(N, 5)` more while unfolded — never more than the `208` the viewport has left once the seam has taken its `32`, however long the window's list has grown; **nothing at all at three live rows**, where the seam is below the fold and the viewport was already full.

**And the cost now ends by itself.** Five quiet hours take the seam away and return the panel to its `178` floor, with nothing to fold and nothing to dismiss. It is the only thing on this panel that tidies up after itself, and it is the reason an unbounded membership is affordable: the queue is long exactly while the last five hours were busy, which is exactly when a long one is worth having.

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
| Nothing live, five in the window, open | `232` | `232` | **362** | 178 |
| Nothing live, twelve in the window, open | `512` | `240` | **370** | 178 |
| One live row, the queue folded | `112` | `112` | **242** | 210 |
| Two live rows, the queue folded | `192` | `192` | **322** | 290 |
| Three live rows — the seam is below the fold | `272` | `240` | **370** | 370 |
| Four live rows — it scrolls, as it already does | `352` | `240` | **370** | 370 |
| One live row, opened at three lines | `202` | `202` | **332** | 210 |
| Three live rows, one of them opened | `362` | `240` | **370** | 370 |

**Every row from the fourth down carries a folded queue**, and that is what its `32` is doing in the content column: `272` is three live rows *and a seam*, `352` is four and a seam, and `202` is one opened row and a seam. Read without it the column looks like it disagrees with §2.1 — which it does not, and a first attempt at pinning this table in a test failed on exactly that reading.

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

There is now a third exit as well as those two crossings, and it goes neither up nor down: a row can leave the queue by ageing out. It is the only departure anywhere on this surface with no gesture behind it, which is why §7 gives it the quietest exit the panel owns.

## 6. Accessibility

- The seam is a disclosure control with the accessible name `Recent, 12 sessions` — the window's own count, which changes under the reader as rows age out — and an expanded state; the whole `32` pt line is its target.
- A retired row spells its line out and appends the age as words — `Codex, notchline, Redraw the mark at five rows, left 2 minutes ago`, and `left 4 hours ago` at the far end of the window.
- A row that ages out is removed, not announced. Nothing here is worth interrupting a reader for, and the count on the seam has already changed.
- The open row's controls are a group named after the row's subject. `Approve` and `Deny` (or `Send`) are buttons; the default-button state moves with the white ground, so a screen reader announces the same thing the ground says.
- The `Answer` word is drawn only under the pointer, so the closed waiting row keeps the accessible action `Answer this request` regardless of hover, and it is the same action a keyboard reaches.

## 7. Motion

- **A row retiring** takes the panel's own slot curve (`PanelMotion.slot(isOpening:)`): the row's height animates `80 → 40` while its second and third lines and its ground fade, and the seam rises over it. The edge leads opening and waits `50 ms` closing, exactly as the collapsed wings do.
- **Folding the queue** is the quota fold's own timing, and it does not strand the pointer (§2.4 rule 07).
- **Opening a row** grows it in place on the same curve; the request's second and third lines fade in behind the ground rather than being revealed by it.
- **A row ageing out** must not read as a gesture, because nobody made one. Folded, or with the seam off screen, it is simply not there the next time the queue is drawn. Open and on screen, it fades on the closing half of the slot curve and the rows below it rise — the dismissal's exchange without the dismissal's hover fill, since there is no pointer on it.
- Nothing here introduces a new curve.

## 8. What this reaches outside the viewport

### 8.1 Two stated non-goals move, and only these two

> **The second amendment is applied.** [`PRD.md`](PRD.md) `0.13` carries it: the window is goal 9 of §2, and §3's sentence now bans retrieval rather than the shape. The first — answering — is still owed, and belongs to [`answer-in-notch.md`](answer-in-notch.md) rather than to this file. What follows is the reasoning that produced the new wording.

[`PRD.md`](PRD.md) §3 rules out "sending input, granting permission, answering questions, cancelling, archiving or deleting threads" and "history search, the last N, or a fixed time window".

**§3 reverses the first for exactly one payload** — the request a row is already reporting — and for nothing else. No cancelling, no archiving, no deleting, no starting a Turn.

**§2 now meets the second head-on, and the honest thing is to say so.** This section's earlier draft claimed the queue fell *outside* "history search, 'the last N', or a fixed time window". That was arguable while the queue was a five-element store. It is not arguable now: **the queue is a fixed time window, in those words**, and dressing it as anything else would be the design arguing with its own rule.

What the ban protects is nonetheless intact, and it is worth separating from the wording. The queue is not a query against history. It holds departures **this run watched** — rows this run drew, for Threads this run's products vouched for — unsearchable, unpageable, empty at launch and empty again after five quiet hours. Nothing is stored, nothing is re-read, and no Thread can enter it that was not on the live list a moment earlier. **The window bounds what is remembered; it does not reach for anything.** Reaching is what §3 is refusing.

So §3's sentence should name what it bans rather than banning a shape: **searching or paging past threads, and any window that reaches back beyond what this run watched.** On that wording the queue is inside the rule rather than excused from it — and "the last N", which is precisely what the queue used to be, becomes banned in a place it previously was. The amendment is not a loosening; it swaps two words the design had outgrown for the one property that was doing the work.

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
| 01 | Does the seam pin to the foot of the viewport rather than scroll with the list? | **Standing recommendation: it scrolls** — but the window has given the question a second half. Pinning would make the queue permanently findable and would cost `32` at exactly the count where the panel is most crowded, buying visibility for the thing here that is deliberately secondary; §2.5 is what makes scrolling affordable, and that has not changed. What has changed is that a five-row queue could never scroll past its own seam, and a twelve-row one can — taking the count and the fold control off the top with it. Still recommended as it stands, and now worth watching on an ordinary busy afternoon rather than only on a machine running four rows at once |
| 02 | One line below the seam, or two? | **Answered as one**, and it is what fixes every height. Two lines would want `44` and would draw the no-preview row the `Colour bar` option already specifies. One line at `40` is exactly half a live row, and the breadcrumb carries product, project and subject anyway |
| 03 | Does the queue survive a quit? | **Answered — no**, and the window makes the answer cheaper rather than harder: a queue that empties itself after five hours was never going to be worth the launch-time promise §2.4 rule 03 refuses to make. §2.4 rules 03 and 11 |
| 04 | Should approving be possible without opening the row? | **Answered — no.** §3.1 |
| 05 | Is `Always` ever offered? | **Standing recommendation: not from here.** §3.3. If it is ever added it belongs beside `Approve` in the recessed ink and never on the white ground, because the white ground is the Enter key and a policy about every future request must not be what Enter does |
| 06 | What happens to a retired row whose product has gone dark? | **Open — the only genuinely unanswered question here.** A row below the seam still claims a destination, and the queue has no equivalent of the live list's hand-over check because it never re-asks. Two candidates: re-ask on click and say so when the answer is no, or drop the row when its product disconnects. The first keeps the queue stable and costs one local read at the click, which is what the live list already pays per row. Recommended, not decided — and the window raises the stakes slightly, since a row can now sit below the seam for hours rather than until the fifth departure after it |
| 07 | Does the seam draw with the quota folded and nothing else on the panel? | **Answered — yes**, and that is the `100` pt form |
| 08 | Does the window need a ceiling behind it? | **Open, and it is a guard rather than a design.** Membership is unbounded in count: a heavy five hours might retire fifty rows at a couple of hundred bytes each — nothing to hold, and unusable to scroll. **Recommendation: the window stays the only rule anyone can see, with a generous ceiling of `50` behind it purely so the store cannot grow without limit.** If it ever binds, that is a fact about the machine rather than a defect, and the seam's count will have said so long before. What must not happen is the ceiling becoming the visible rule again — that is the "last N" §8.1 just finished banning |

### 8.6 Two smaller reaches

- **Membership gains a second question, answered in memory.** The store holds every departure of the past five hours in order, with what took each of them out and when, and answers navigation for them from what the product last vouched for. Nothing is persisted and nothing is re-read at launch — and the store now has a clock, since it is the only thing that can drop its own members.
- **Product attribution reaches below the seam.** ~~All four presentations apply: `Name and colour` and `Name only` land on the breadcrumb's prefix, `Badge` replaces that prefix, and `Colour bar` becomes a `2` pt bar the height of the one line.~~ **There is one presentation** ([`colour-v2.md`](colour-v2.md) §5): the badge replaces the breadcrumb's prefix, on the same presence rule as a live row's, and the setting that chose between four is retired ([`dual-agent-design.md`](dual-agent-design.md) §4).

## 9. Verification

- [ ] A live row is `80`, the seam `32`, a retired row `40`, at every menu bar height.
- [ ] The viewport is its content capped at `240`, and is `80 × min(rows, 3)` when nothing has retired.
- [ ] The panel is `162` with nothing live and the queue folded, and `100` with the quota folded too.
- [ ] Three live rows draw no seam and cost the queue nothing; the third retiring puts the seam back inside the viewport.
- [ ] A retiring row halves in place and the seam rises over it; nothing travels the length of the panel.
- [ ] Nothing below the seam draws a status ground, and every age reads as an age.
- [ ] The queue is empty at launch, admits every departure, and drops each one five hours after it left — with the panel open, folded, and never opened at all.
- [ ] Six retirements draw five rows and a seam reading `Recent · 6`; the sixth is reached by the panel's own viewport scroller, and no second scroller appears anywhere.
- [ ] Five quiet hours empty the queue, take the seam with them, and return the panel to its `178` floor with nothing left to fold.
- [ ] No age reads `5h` or longer, and the age column never widens.
- [ ] The seam's label and hairline redraw correctly at a two-digit count, with the hairline's trailing edge still at `508`.
- [ ] At six or more in the window the panel is `370` and the last `8` points below the fifth row are empty — no partial line is drawn.
- [ ] Folding the queue does not close the panel at any connected form.
- [ ] The seam's hairline lands on the same `x` as the footer's rules and the band's matrix, in every attribution option.
- [ ] Only `Approval needed` and `Input needed` rows draw `Answer` under the pointer; no other row becomes clickable.
- [ ] An opened row is `134` at one request line, `170` at three and `118` for Input, and never exceeds the viewport.
- [ ] While a row is open the panel does not close on pointer exit, holds the keyboard, and returns it on `⎋`, on send and on an outside click.
- [ ] The white ground is on `Approve` with an empty field and on `Deny` with a non-empty one, and neither button moves when it crosses.
- [ ] A request settled elsewhere closes the open row within one publish.
- [ ] The band, both collapsed forms and the quota footer draw identically to pages 01 to 05 in every state above.

## 10. Implementation mapping

**The first row has landed**; the rest is ahead. The work lands in six places:

| Symbol | Change |
| --- | --- |
| ~~`PanelMetrics.sessionViewportHeight(forSessionCount:)`~~ **Built.** | Became a height rather than a row count: `sessionListContentHeight(liveRowCount:retiredRowCount:isRecentExpanded:)` capped at `sessionViewportCap`, which is the same `240`. `maximumVisibleSessionCount` retired with it, and `expandedContentHeight` now asks the *viewport* whether to draw the apology rather than the live count |
| `PanelMetrics` | **Built:** `retiredRowHeight = sessionRowHeight / 2` and `recentSeamHeight`. Still owed: `openRowHeight(requestLines:)`, which belongs to §3 |
| `MonitorStore` | A departure queue keyed on the departure instant, holding every row that left within `recentWindow` (`5 × 3600`) together with the reason it left, fed wherever a row leaves today; `recentFolded` beside `quotaFolded` |
| `MonitorStore` (the clock) | **Eviction is a read-time filter, not a timer** — a queue nobody watched for six hours is empty the moment it is read, with no background work while the panel is shut. The timer exists only to make the change visible to somebody watching, and one one-minute tick while the panel is open serves both eviction and the ages, which already have to move `2m` → `3m` |
| `NotchOverlayView` | `RecentSeam`, `RetiredRow`, and `SessionRow`'s open state; `emptyListMessage` draws only when the queue is empty too |
| `OverlayPanelController` | Latching: key window on open, restore on close, and hover suspended for the duration (§8.3) |

**Nothing in `PanelMetrics` changes for this amendment.** The five-row fold is `240` doing what it already did, and the only new constant lives in the store.

`docs/PRD.md` **is amended for §2** — `0.13`, goal 9 and the rewritten §3 sentence — so nothing in this section is blocked on it. §8.1's first amendment and §8.2's narrowing are still owed, and both belong to §3's work rather than this one's.
