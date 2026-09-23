# Make exact Desktop navigation a release gate (Codex only)

Every Codex Desktop row promises a return to the same Codex Desktop Thread that produced its state, so V1 accepts only a supported `threadId → the same Desktop page` contract. Opening the Codex home page, searching by title, guessing a URL, calling private IPC, or clicking through Accessibility are all rejected. A Codex Desktop version with no verifiable exact navigation cannot be marked as supported by V1.

**The gate binds the Codex Desktop surface.** Claude Code has no supported way to focus a Thread that already exists — the official deep link can only create a new one — so applying this unconditionally to the second product would block it on a capability that does not exist. Success for a Claude Code row is therefore reduced to raising its host: a Desktop-hosted Thread activates Claude Desktop, a terminal Thread focuses its tab. The reduction carries **no marker**: a row carries one marker and that marker is its timer. The sentence shown after the click is the only place the difference can be stated, so it must report what was actually done rather than copy Codex's wording (see `NavigationOutcome`).

Once an official deep link to a local Thread exists, Claude Code migrates to it and this reduction lapses.

## Local Codex CLI amendment (documented 2026-09-22)

The local CLI implemented on 2026-09-15 uses verified host return. Its Hooks establish execution ownership but do not establish the displayed Thread: `/new` delays `SessionStart` until the next submission. Exact terminal selection is therefore disabled even where a host can select by TTY. Notchline never launches `resume`, another CLI or a Desktop deep link for a CLI-only Thread. A Thread owned on both surfaces prefers Desktop while that owner is live. This narrows the original blanket Codex wording; the exact Desktop navigation gate is unchanged. [Current scope](../product-support.md#51-local-codex-cli), [implementation](../../Notchline/Notchline/Products/Codex/CodexNavigator.swift).
