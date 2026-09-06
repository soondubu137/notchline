# The panel takes the keyboard by activating, and gives the application back

A row that can be answered has a field in it, and a field is no use to a panel the keyboard does not reach. [`answer-in-notch.md`](../answer-in-notch.md) §9.4 said what should happen — *latching takes key status from the application underneath, and `⎋`, a send with nothing left waiting and a click outside all give it back to the same window* — and the code said it was already true, on the strength of one style-mask flag. It was not.

## What was believed

`OverlayPanel` is created with `.nonactivatingPanel`, whose documented promise is that a panel may receive keyboard input without activating the application that owns it. For an `LSUIElement` app hanging in the menu bar that is exactly the shape wanted: hold a key while the person's editor stays frontmost, and give it back when the row closes. `canBecomeKey` was gated on `latches` so the panel could never take a key it had no use for, and that was the whole of the mechanism.

## What was measured

2026-09-05, Release build, a staged answerable row, keys posted both through the HID tap and directly to the process:

| Question | Answer |
| --- | --- |
| Is the panel key while a row is open? | **Yes** — `NSApp.keyWindow` *is* the panel and its first responder *is* the field, and the accessibility tree agrees: the app's focused element is an `AXTextArea` |
| Do keystrokes reach it? | **No.** Every one went to whichever application was in front. `keyDown` on the panel logged nothing until the app itself was frontmost |
| Does a click on the panel's own field answer, then? | **No — it closed the row.** The global monitor watching for a click outside saw a click on the field, because an inactive app's window is not where that click was delivered |

**An application that is not active does not receive keys, whatever its windows believe.** The style mask governs whether *clicking* the panel activates the app, which is a different sentence than the one that was read into it.

Two smaller things were in the way and are worth recording, because each produced a symptom that looked like the one above:

- **`becomesKeyOnlyIfNeeded = true` makes AppKit refuse `makeKeyAndOrderFront` outright.** It was set when nothing on this surface could take a key, to keep `orderFront` from making a useless panel key. That job is now done exactly by `canBecomeKey`, which is `false` until a row opens, so the flag was redundant as well as wrong.
- **An `NSTextView` built through `init(frame:textContainer:)` with a `nil` container has no text system behind it.** It takes the caret, reports itself first responder, receives `keyDown` — and inserts nothing, so every keystroke fell through to the panel's own handler. Built through `NSTextView.init(frame:)` it has a container and behaves.

## The decision

**While a row is open, Notchline is the active application.** `setLatched(true)` remembers whichever application was frontmost and activates; `setLatched(false)` activates that application again. The three exits are the ones §9.4 already named — `⎋`, a send with nothing left waiting, and a click outside — plus the row closing for any other reason, because they all run through the same publish.

What this costs is one thing and it is visible: the menu bar becomes Notchline's for as long as a row is open, and the application underneath loses its focus ring. That is the honest drawing of what is happening — the keyboard really has moved — and it is bounded by the same gesture that started it. **Hover still takes nothing**, because hover never latches (§9.4); only a click on a mark does, and the chord will be the second one (§9.3).

If the application that was frontmost has gone by the time the row closes, nothing is activated and focus goes wherever the system would have sent it. The panel does not hold it open waiting, which §9.4 already required.

## What was rejected

- **Leaving it as it was and calling the field keyboard-less.** The field is §7's first object and §6.4's cheap refusal is a sentence and a return; a row that can only be answered with the pointer is a different feature.
- **Making the panel key without activating, by other means.** There is no other means: the window server routes keys to the active application, and every overlay that types — Spotlight and its imitators — activates.
- **Activating on hover, so the keyboard is ready before it is wanted.** That is exactly what §9.4 forbids: the panel sits over whatever the person is typing into, and a surface that took focus on proximity would eat a line of their code.
- **Restoring focus by hiding this app rather than activating the other.** `NSApp.hide()` would also order the panel out, which is a second thing happening for one reason.
