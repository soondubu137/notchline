# Monitor only root Threads that Desktop can locate

V1 lists only root Threads that Codex Desktop can open directly under the same `threadId`. Threads from the CLI, an IDE, a subagent or any other origin qualify only once they are verified to satisfy that same navigation contract. The scope trades the breadth of "show all local activity" for the core promise that every row keeps: clicking it returns to the Codex Thread it describes.

## Local CLI amendment (documented 2026-09-22)

The original Desktop-only admission rule is superseded for ordinary local Codex CLI. A CLI row requires an App Server-confirmed root Thread and verified live execution ownership; its return route raises the owning host without claiming to select the displayed Thread. Desktop retains exact Thread navigation. This is an explicit mode boundary, not admission of every persisted local Thread. See [ADR 0004](0004-make-exact-desktop-navigation-a-release-gate.md), [ADR 0017](0017-a-row-requires-a-thread-the-app-server-vouches-for.md) and [current support](../product-support.md#51-local-codex-cli).
