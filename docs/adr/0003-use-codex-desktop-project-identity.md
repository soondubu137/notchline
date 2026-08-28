# Use Codex Desktop's Project identity

A Codex row's Project must correspond to a Project entity the user created in Codex Desktop's sidebar. One Project may span several repositories, and a Thread belonging to none shows `Chats`. V1 must not infer the Project from `cwd`, the Git root or a path name: those objects do not map one-to-one onto a user-managed Desktop Project. If the supported integration interfaces cannot yield Desktop Project identity and name, the capability ships not at all rather than degraded to an approximation.
