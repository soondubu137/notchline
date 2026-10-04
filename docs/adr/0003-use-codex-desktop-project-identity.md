# Use Codex Desktop's Project identity

> **The label changed in 0.4.3 (2026-09-13); the decision did not. Recorded 2026-10-04.** A Thread belonging to no Project now draws `Untitled Project`, the words every product uses for a row with no Project, instead of `Chats`. `Chats` still names that set of Threads ([`CONTEXT.md`](../../CONTEXT.md)), and the ban on inferring a Project from a path is unchanged.

A Codex row's Project must correspond to a Project entity the user created in Codex Desktop's sidebar. One Project may span several repositories, and a Thread belonging to none shows `Chats`. V1 must not infer the Project from `cwd`, the Git root or a path name: those objects do not map one-to-one onto a user-managed Desktop Project. If the supported integration interfaces cannot yield Desktop Project identity and name, the capability ships not at all rather than degraded to an approximation.
