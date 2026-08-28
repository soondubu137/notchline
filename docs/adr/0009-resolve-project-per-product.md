# Resolve Project per product: a Desktop entity for Codex, the working directory for Claude Code

A row's Project has no single definition; it is resolved per product.

Codex rows keep [ADR 0003](0003-use-codex-desktop-project-identity.md): the Project must be an entity the user created in the Codex Desktop sidebar, an unattached Thread shows `Chats`, and inference from `cwd`, the Git root or a path name stays forbidden. That ban now binds only the Codex side, because its reason was that paths do not map one-to-one onto user-managed Desktop Projects.

A Claude Code row's Project is simply the Thread's working directory (`cwd`). Claude Code has no user-created grouping entity; the hook payload states `cwd` directly and transcripts are filed by it (`~/.claude/projects/<encoded cwd>/`), so it is a grouping that genuinely exists in that product rather than an approximation read off a path, and the inference ban does not apply. The row shows the last path component, with the full `cwd` as the accessibility name. `gitBranch` is equally available but the row's first line has width for one thing, so it is not shown.

Two alternatives were rejected: leaving a Claude Code row's attribution empty makes a mixed list ragged and discards the only clue distinguishing Threads with identical titles, and inventing a second term alongside Project would make the UI, the accessibility copy and the data model each carry two synonyms that differ only in origin. Known failure mode: two checkouts of identically named directories show the same attribution. Codex's user-named Projects cannot collide this way, and no disambiguation rule has been decided.
