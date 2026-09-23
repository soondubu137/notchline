# Notchline and Open Island: feature comparison

> **Historical comparison.** The snapshots below were reviewed on 13 September 2026. A documentation check on 22 September found that its standalone Codex CLI gap is now superseded on `feature/codex_cli_integration`: Notchline supports ordinary local CLI at L5, with reading-only requests, conditional terminal read removal and host return. See [current support](../product-support.md#51-local-codex-cli). The pinned Open Island snapshot and other comparison findings have not been re-reviewed.

Reviewed on **13 September 2026**. The repository named `open-vibe-island` now calls its application **Open Island**.

Notchline concentrates on identifying the Turns that still need attention across Codex Desktop, Claude Code, Antigravity and Trae Desktop, with explicit per-product coverage. Open Island covers more coding products and terminal workflows, with more controls for notifications, presentation and continuing work. Neither is a strict superset of the other.

## Scope and evidence

| Project | Snapshot inspected |
| --- | --- |
| Notchline | Local `master`, clean before this documentation change, commit `f1a9ee0bd009205cfea902e54aba90e855835d5c` |
| [Open Island][oi-repo] | Default branch, commit [`334c58073ec0ea8a1b34da0c71f969b1affd0959`][oi-snapshot], dated 3 September 2026; still upstream HEAD on 13 September |

This compares **implemented source at these snapshots**, not just released binaries or roadmap promises. Open Island links below are pinned to the inspected commit. Notchline links point into this repository; the commit above records the comparison baseline.

“Not provided” means no equivalent implementation or exposed control was found in the relevant source, settings and documentation. It is a scoped finding, not proof that a future version or an external script could never provide it. Open Island was inspected without running it, installing its hooks or testing its terminal and mobile combinations. This is not a performance benchmark or an end-to-end compatibility certification.

The upstream HEAD was checked again with `git ls-remote` on 13 September: it is unchanged from the 7 September comparison, so the pinned Open Island source findings below still describe the latest default branch. Notchline's side was refreshed against its current product contracts and implementation, including `ProductRegistry`, `TraeProvider`, `TraeReadEvidence`, the shared runtime and Settings. No new Open Island runtime testing was performed.

Notchline's **Thread** and **Turn** terminology follows [CONTEXT.md](../../CONTEXT.md). Open Island generally calls a tracked conversation a `session`; references to its session model do not imply that it has Notchline's monitoring lifecycle.

## Changes since the previous comparison

- **Four products with scoped levels:** Codex Desktop and Claude Code are L6, Antigravity Desktop/CLI is L3, and the verified Trae 3.5.91 local IDE/V2 mode is L5. These are cumulative coverage declarations, not a ranking of applications. [Support contract](../product-support.md).
- **Additional read and return paths:** Antigravity uses Desktop view records or conditional CLI gestures; Trae uses fresh window-specific visible-completion evidence and exact observed Thread navigation. Trae remains reading-only, and IDE-hosted SOLO is outside its L5 declaration. [Trae implementation](../../Notchline/Notchline/Products/Trae/TraeProvider.swift), [read evidence](../../Notchline/Notchline/Products/Trae/TraeReadEvidence.swift).
- **Shared evidence and request handling:** product-owned sources feed typed evidence to one Turn reducer; the runtime composes optional sources. Concurrent requests, occurrence-specific drafts, permitted answer operations and delivery outcomes are shared across products. This refactor adds no native answer capability by itself. [Architecture](../system-architecture.md), [implementation plan](../product-generalisation-plan.md).
- **Presentation:** Notchline now offers product grouping as well as one urgency-ordered list, and Privacy Mode covers text. It still has no arbitrary workspace grouping or last-update sort. [Settings][n-settings].

## Features both provide

These should **not** be counted as exclusive to either application:

| Shared capability | Relevant boundary |
| --- | --- |
| Native SwiftUI/AppKit overlay, physical-notch and notch-less display layouts | Their compact appearance and expansion behaviour differ. |
| Multiple conversations, working/waiting/completed states, attention ordering | The rules deciding which conversations remain visible differ substantially. |
| Codex Desktop and Claude Code, including Claude Code hosted by Claude Desktop | Open Island additionally supports standalone Codex CLI and many other products. |
| Content previews and expandable rows | Open Island also exposes more tool and work-item detail. |
| Ordinary Codex and Claude Code permission answers | Both have a hook reply path; this does not establish support for every kind of question or permission request. |
| Claude Code structured questions | Both contain option and typed-answer handling. |
| Codex conversation deep links | Both use `codex://threads/<id>`; exact Codex navigation is not exclusive to Notchline. |
| Claude host/terminal navigation | Both have targeted Terminal.app/iTerm2 paths; Open Island covers more terminal-specific targets. |
| Codex/Claude quota windows, hook installation controls and display preferences | Data sources, window coverage and available controls differ. |
| A Recent area and Claude Code subagent information | Neither the word “Recent” nor the existence of a subagent count is a differentiator by itself. |

Sources: [Notchline overview](../../README.md), [Notchline answers](../answer-in-notch.md), [Open Island overview][oi-readme], [Open Island bridge][oi-bridge], [Open Island panel][oi-panel] and [Open Island navigation][oi-jump].

## What Notchline provides that Open Island does not provide equivalently

| Capability | Notchline | Open Island at the inspected commit |
| --- | --- | --- |
| **1. Clearing completed rows using evidence that the Thread was read** | Uses Codex Desktop's unread membership, Claude Code's Desktop/terminal evidence, Antigravity's Desktop view records or conditional CLI gestures, and Trae's fresh per-window visible-completion evidence. A read completed Turn can leave the live list without dismissing its row manually. | Visibility is based on process/attachment state, activity, completion and presentation thresholds. No equivalent Codex unread-state or Claude Desktop/terminal read-state adapter was found. Suppressing a notification when a terminal is foreground is a separate feature. [N1][n-read] [O1][oi-presence] |
| **2. Real Codex Desktop Project names and the Chats distinction** | Resolves Desktop's actual Thread-to-Project assignments, including local/remote Project records and explicitly projectless Threads. An unavailable mapping is not silently replaced with a folder name. | Its project grouping uses the jump target's workspace name, with title fallbacks. Workspace names are useful, but do not reproduce Codex Desktop's user-managed Project membership. [N2][n-project] [O2][oi-workspace] [O3][oi-model] |
| **3. Avoiding false human-approval indicators for Codex “Approve for me” Turns** | Reads the reviewer assigned to the particular Turn, with a guarded Desktop-state fallback. Only evidence of `auto_review` suppresses the human-approval projection; changing a Thread's setting does not automatically rewrite a running Turn's interpretation. | `PermissionRequest` creates a permission card. No equivalent per-Turn reviewer filter was found. This is a distinction in deciding whether a person is being asked, not an extra approval method. [N3][n-reviewer] [O4][oi-bridge] |
| **4. Keeping parent completion separate from continuing subagent work** | Codex and Claude Code can retain subagent activity after the parent Turn completes. The parent row keeps its stopped timer and any supported final-answer preview, while aggregation, ordering and membership can still reflect work or subagent approvals. Claude Code's `background_tasks` pause is also represented. | Claude subagents are displayed, but the bridge clears them on the parent's `Stop` and also performs age-based cleanup. It suppresses other Claude hooks carrying `agentID`, including that path's subagent permission events. No equivalent Codex subagent aggregation was found. [N4][n-aggregation] [N5][n-hooks] [O4][oi-bridge] |
| **5. Claude quota without requiring an interactive terminal status line** | Invokes `claude -p "/usage" --output-format json` and parses the returned quota text. This can obtain quota while using Claude Desktop without first seeding a terminal status-line cache. It also recognises model-specific weekly windows when present. | Reads cached `five_hour` and `seven_day` windows written by its managed status-line bridge. Its README explicitly notes that Claude Desktop alone does not refresh that cache. No equivalent model-specific weekly window is represented by `ClaudeUsageSnapshot`. [N6][n-claude-usage] [O5][oi-claude-usage] [O6][oi-statusline] |
| **6. Today's token totals, per product and combined** | The footer shows daily token totals as well as quota. Codex comes from `account/usage/read`; Claude Code counts transcript usage, including cache reads, with incomplete readings reported as unavailable. | The inspected usage models and settings expose rate-limit percentages and resets, without an equivalent daily token counter or combined Today total. [N7][n-tokens] [N8][n-footer] [N9][n-usage-design] [O5][oi-claude-usage] [O7][oi-codex-usage] |
| **7. Processing time for the current Turn** | Shows a Turn's elapsed wall-clock time, including waiting and sleep, then its finished duration. The compact surface can show the longest running Turn. | Shows activity age and Claude subagent elapsed readings. No equivalent parent-Turn processing-time readout, including its stopped duration, was found. These readings answer different questions. [N8][n-footer] [N10][n-store] [O1][oi-presence] [O8][oi-panel] |
| **8. An editable explanation when refusing an ordinary permission request** | The answer field can carry a refusal reason or an instruction about what to do instead. Both Codex and Claude answer encoders preserve that message. | The ordinary approval card exposes Deny, Allow Once and a tool-level Always Allow action. The app supplies a fixed denial message; that card has no equivalent editable refusal field. This is separate from its typed answers to questions. [N11][n-answer-claude-code] [N11][n-answer-codex] [N8][n-footer] [O8][oi-panel] [O3][oi-model] |
| **9. Antigravity and Trae native activity** | Antigravity Desktop/CLI L3 observes lifecycle, context and event-updated progress. Trae local IDE/V2 L5 reads ordinary commands and structured questions through a pinned companion, with conditional read removal and exact observed Thread navigation. Neither has an answer channel here. | No dedicated Antigravity or native Trae activity adapter was found in the inspected product setup paths. Its Trae workspace navigation is a host return target for another coding product, not native Trae agent monitoring. [N17][n-support] [N18][n-trae] [O9][oi-setup] [O10][oi-jump] |

Important limits on these differences:

- **Read-aware clearance starts from live observation.** Notchline does not rebuild pre-launch working, waiting or unread Turns. Claude Desktop's foreground read rule also deliberately accepts that a user who leaves the answer visible and walks away can lose the notification. A Claude Thread with neither a Desktop record nor a controlling terminal has no automatic read answer. See [monitoring scope](../PRD.md) and [read-state decision](../adr/0012-read-state-is-answered-per-product-or-not-at-all.md).
- **Subagent accounting is not a promise that every subagent request is answerable from every row state.** The distinctive implementation is the separation of parent and accompanying work. A missing close event can leave work indicated until fresh evidence or manual dismissal. See [the shared state model](../dual-agent-design.md).
- **Quota support has a compatibility cost.** Claude's textual `/usage` format and transcript schema are private dependencies. The quota command also creates transcripts, whose size is shown in Settings. Codex and Claude's daily totals currently use their respective source day boundaries; Claude's counter buckets by UTC. See [quota reader][n-claude-usage], [token counter][n-tokens] and [file inventory](../artifacts.md).

## What Open Island provides that Notchline does not provide equivalently

| Capability | Open Island | Notchline at the inspected commit |
| --- | --- | --- |
| **1. More coding products and standalone Codex CLI** | Dedicated setup/runtime paths for Cursor, Gemini CLI, Grok Build, Kimi CLI, OpenCode, Pi, Oh My Pi, Qoder, Qwen Code, Factory and CodeBuddy, alongside Claude Code and Codex. Codex CLI is a supported workflow. Observation and answer capabilities vary by product. | Four products: Codex Desktop and Claude Code (L6), Antigravity Desktop/CLI (L3), and verified Trae local IDE/V2 (L5). A standalone CLI or IDE is not an independent Codex list source; a Codex row must satisfy the Desktop-navigable root Thread contract. Claude Code CLI is already supported. [O9][oi-setup] [N12][n-prd] |
| **2. More precise terminal, pane and IDE return targets** | Dedicated targeting for Ghostty, cmux, Kaku, WezTerm, tmux, Zellij and Warp, as well as Terminal.app/iTerm2. IDE paths include VS Code, Cursor, Windsurf, Trae, Zed and JetBrains launchers, with workspace/app-level fallbacks. | Uses shared process ancestry and terminal-host navigation for Claude Code and Antigravity CLI, plus exact observed Trae Thread selection through its owning window. Exact terminal-tab selection is implemented for Terminal.app and iTerm2; other hosts can be raised without those additional pane/workspace adapters. Full-screen Claude hosts are an explicit limitation. [O10][oi-jump] [N13][n-claude-jump] |
| **3. Recovery of existing conversations after launch** | Discovers conversations from local transcripts and registries, restores persisted records and reconciles them with process/attachment evidence. | Starts from new live lifecycle evidence. Recent is an in-memory record of departures from this app run's own live list, not a persisted startup list. [O11][oi-discovery] [O12][oi-registry] [N12][n-prd] |
| **4. Proactive notification cards, configurable sounds and haptics** | Can present permission/question/completion surfaces automatically, choose notification sounds, mute them, use haptics, suppress foreground-terminal notifications and keep the notch open pending a decision. | Provides a compact attention display and a panel opened by hover. No equivalent notification/sound/haptic configuration is exposed. [O13][oi-overlay] [O14][oi-sound] [O15][oi-settings] [N14][n-settings] |
| **5. Sending a follow-up after completion** | An opt-in completion reply field can send text and Enter to a tmux pane or a supported Ghostty terminal. The capability is gated by the terminal target. | Can answer an existing request, but cannot compose a new prompt or start a Turn. [O16][oi-text] [N12][n-prd] |
| **6. Session-scoped “Always Allow” for a Claude tool** | The approval card can construct a session-scoped allow rule and send it through Claude's permission-update path. | Offers grant/refuse for the current request. Permission suggestions can be parsed, but no broader “always allow” control is presented. [O8][oi-panel] [O17][oi-session] [N15][n-request] |
| **7. More detail in expanded conversations** | Tracks Claude `TaskCreate`/`TaskUpdate` work items and renders their subjects/statuses, individual subagent descriptions/types and elapsed readings. Also exposes current tool/command detail, Markdown completion text and worktree branch labels when available. | Shows brief parent content, elapsed time, subagent counts/attention and the payload of a request awaiting an answer. It has no equivalent work-item checklist, named subagent list, formatted completion reader or branch badge. [O4][oi-bridge] [O8][oi-panel] [O1][oi-presence] [N12][n-prd] |
| **8. Broader grouping and sorting of the conversation list** | Group by state, coding product or workspace/project; choose attention or last-update sorting. Also offers selectable state indicators, compact-slot content and a configurable completed-to-idle threshold. | Offers product grouping or one urgency-ordered list. It has display, outline, wing, compact-name and Privacy Mode settings, but no workspace grouping or last-update sorting. [O18][oi-appearance] [N14][n-settings] |
| **9. A packaged SSH workflow for remote Claude Code** | Includes a remote Python hook helper and setup script, using SSH Unix-socket forwarding back to the Mac. This is a documented remote-Claude workflow, not automatic support for every product on every remote host. | No equivalent remote deployment helper or SSH monitoring setup. Raising a local host and reading Codex remote Project metadata do not establish remote hook transport. [O19][oi-ssh] [O20][oi-remote-script] [N16][n-artifacts] |
| **10. iPhone/Apple Watch companion paths — implemented, with unfinished parts** | Includes Bonjour/HTTP relay and pairing, iPhone and Watch source, notifications and callbacks for approval/question answers. This is more than a roadmap entry, but was not tested here; `watchConnectedDevices` still returns a placeholder `0`. | No companion application, pairing or mobile answer relay. This should be treated as an additional integration under development, not a verified complete mobile experience. [O21][oi-watch-relay] [O22][oi-mobile] [O23][oi-watch] [O3][oi-model] |
| **11. Launch-at-login and Dock visibility controls** | Exposes both preferences, with `SMAppService` used for launch-at-login registration. | No equivalent built-in settings. A user arranging launch externally would be a separate macOS configuration. [O15][oi-settings] [O24][oi-login] [N14][n-settings] |

## Platform, language and distribution

These affect adoption, but are separate from the monitoring feature set.

| Area | Notchline | Open Island |
| --- | --- | --- |
| Minimum macOS | 26.5 | 14 |
| Application language | British English; no language selector | English, Simplified Chinese and Traditional Chinese, plus system selection. The source includes Traditional Chinese even though the README's feature table only names Simplified Chinese. |
| Updating | Manual replacement; no updater in the inspected app | Sparkle integration with automatic checks and a manual check action. Automatic downloading is disabled in the current wrapper. |
| Installation/distribution | Local app/build workflow; README states it is not currently notarised | README offers GitHub DMGs and Homebrew, and describes signed/notarised distribution. Packaging/signing workflows exist; a downloaded release's signature was not independently checked here. |
| Source licence | GPL v3 or later | GPL v3 |

Sources: [Notchline README](../../README.md), [Notchline changelog](../../CHANGELOG.md), [Open Island package][oi-package], [language manager][oi-language], [update checker][oi-update], [release workflow][oi-releasing], [README][oi-readme] and [licence][oi-licence].

## Request answering: where a broad “supported” label is misleading

| Request/action | Notchline | Open Island |
| --- | --- | --- |
| Ordinary Claude Code `PermissionRequest` | Grant or refuse; can include a typed refusal reason | Allow once, deny, or send a session-scoped tool rule |
| Claude Code `AskUserQuestion` | Structured questions, selections and typed answers; requires the matching held reply connection | Structured question/answer model and a Claude hook reply path |
| Ordinary Codex `PermissionRequest` | Grant/refuse on the held hook connection | Implemented in the installer, bridge and Codex directive encoder |
| Codex questions / `request_permissions` | Synchronous questions and `request_permissions` are reading-only; asynchronous questions are preview-only. No question-answer operation is exposed by the Codex hook channel | Rollout parsing can recognise waiting states; no equivalent complete answer route for these tools was found. A manually configured `PreToolUse` allow/deny hook is not that route. |
| OpenCode permission/question requests | Product not supported | Plugin and bridge paths exist for both |
| Trae ordinary commands / structured questions | Reading-only in verified local IDE/V2; answer in Trae | No native Trae request path found |
| New prompt after completion | Not provided | Optional tmux/Ghostty terminal text submission |

Sources: [Notchline request forms][n-request], answer encoders ([Claude Code][n-answer-claude-code], [Codex][n-answer-codex]), [Open Island Codex installer][oi-codex-installer], [Codex hook schema][oi-codex-hooks], [rollout interpretation][oi-rollout], [bridge][oi-bridge], [OpenCode plugin][oi-opencode] and [terminal text sender][oi-text].

Two corrections matter when interpreting Open Island's documentation:

1. Its README describes the default Codex hooks as `SessionStart`, `UserPromptSubmit` and `Stop`. The inspected installer also includes **`PermissionRequest`**. Consequently, “Open Island cannot answer Codex approvals” would be an incorrect comparison.
2. Its Codex coordinator starts a **separate** `codex app-server` and handles lifecycle notifications from that process. The existence of that code does not demonstrate that it receives every live request owned by Codex Desktop's own process. Notchline's separate-server capability boundary is documented in [PRD §3](../PRD.md); Open Island's [coordinator][oi-codex-coordinator] was not exercised against Desktop in this review. Do not equate transcript restoration, notification-handling code and proven cross-client request control.

Likewise, a Shortcuts tab is not evidence of a shipped global-shortcut system: Open Island's [settings implementation][oi-settings] still routes it to a “coming soon” placeholder. Notchline's current answer keyboard handling should not be confused with such a global shortcut system either.

## Interpreting the trade-offs

For someone primarily using **Codex Desktop and Claude Code**, Notchline's distinct value is the meaning of the information: actual Desktop Projects, evidence-based clearing, per-Turn approval attribution, continuing subagent work, processing time and daily consumption.

For someone working across **many coding products, terminals or remote machines**, Open Island adds concrete workflow coverage: more adapters, more precise return targets, restored conversations, notifications, terminal follow-ups and remote/companion paths. Its platform and distribution coverage is also broader.

Neither restoration nor conservative live-only monitoring is a blanket correctness win. Open Island can show useful existing conversations immediately, while restored data does not by itself prove a pending reply connection is still usable. Notchline avoids reconstructing those waits, at the cost of an initially empty list. Similarly, preserving subagent work avoids declaring it finished prematurely, but missing close evidence can leave an indicator stuck.

No CPU, memory, latency or battery ranking is asserted here. Both projects contain Core Animation drawing; the presence of an animation API, test suite or architectural rule is insufficient to establish comparative runtime cost.

This review changes documentation only. It adds, modifies, migrates or removes **no non-public Codex integration**. Existing private dependencies were checked against the [integration registry](../non-public-codex-integration-features.md); the tables describe them without changing their contracts.

[n-read]: ../adr/0012-read-state-is-answered-per-product-or-not-at-all.md
[n-project]: ../../Notchline/Notchline/Products/Codex/CodexDesktopProjectMetadata.swift
[n-reviewer]: ../../Notchline/Notchline/Products/Codex/CodexDesktopApprovalRouting.swift
[n-aggregation]: ../../Notchline/Notchline/MonitorDomain.swift
[n-hooks]: ../../Notchline/Notchline/MonitoringRepository.swift
[n-claude-usage]: ../../Notchline/Notchline/Products/ClaudeCode/ClaudeCodeUsageReader.swift
[n-tokens]: ../../Notchline/Notchline/Products/ClaudeCode/ClaudeCodeTokenCounter.swift
[n-footer]: ../../Notchline/Notchline/NotchOverlayView.swift
[n-usage-design]: ../tech-design.md
[n-store]: ../../Notchline/Notchline/MonitorStore.swift
[n-answer-claude-code]: ../../Notchline/Notchline/Products/ClaudeCode/ClaudeCodeHookVocabulary.swift
[n-answer-codex]: ../../Notchline/Notchline/Products/Codex/CodexHookVocabulary.swift
[n-prd]: ../PRD.md
[n-claude-jump]: ../../Notchline/Notchline/ProcessHostNavigator.swift
[n-settings]: ../../Notchline/Notchline/SettingsWindow.swift
[n-request]: ../../Notchline/Notchline/AgentRequest.swift
[n-artifacts]: ../artifacts.md
[n-support]: ../product-support.md
[n-trae]: ../trae-integration.md
[oi-repo]: https://github.com/Octane0411/open-vibe-island
[oi-snapshot]: https://github.com/Octane0411/open-vibe-island/tree/334c58073ec0ea8a1b34da0c71f969b1affd0959
[oi-readme]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/README.md
[oi-bridge]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandCore/BridgeServer.swift
[oi-panel]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/Views/IslandPanelView.swift
[oi-jump]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/TerminalJumpService.swift
[oi-presence]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/AgentSession+Presentation.swift
[oi-workspace]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandCore/WorkspaceNameResolver.swift
[oi-model]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/AppModel.swift
[oi-claude-usage]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandCore/ClaudeUsage.swift
[oi-statusline]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandCore/ClaudeStatusLineInstallationManager.swift
[oi-codex-usage]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandCore/CodexUsage.swift
[oi-setup]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/HookInstallationCoordinator.swift
[oi-discovery]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/SessionDiscoveryCoordinator.swift
[oi-registry]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandCore/ClaudeSessionRegistry.swift
[oi-overlay]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/OverlayUICoordinator.swift
[oi-sound]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/NotificationSoundService.swift
[oi-settings]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/Views/SettingsView.swift
[oi-text]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/TerminalTextSender.swift
[oi-session]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandCore/AgentSession.swift
[oi-appearance]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift
[oi-ssh]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/docs/ssh-setup.md
[oi-remote-script]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/scripts/remote-setup.sh
[oi-watch-relay]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandCore/WatchNotificationRelay.swift
[oi-mobile]: https://github.com/Octane0411/open-vibe-island/tree/334c58073ec0ea8a1b34da0c71f969b1affd0959/ios/OpenIslandMobile
[oi-watch]: https://github.com/Octane0411/open-vibe-island/tree/334c58073ec0ea8a1b34da0c71f969b1affd0959/ios/OpenIslandWatch
[oi-login]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/LaunchAtLoginService.swift
[oi-package]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Package.swift
[oi-language]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/Localization/LanguageManager.swift
[oi-update]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/UpdateChecker.swift
[oi-releasing]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/docs/releasing.md
[oi-licence]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/LICENSE
[oi-codex-installer]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandCore/CodexHookInstaller.swift
[oi-codex-hooks]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandCore/CodexHooks.swift
[oi-rollout]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandCore/CodexSessionTracking.swift
[oi-opencode]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/Resources/open-island-opencode.js
[oi-codex-coordinator]: https://github.com/Octane0411/open-vibe-island/blob/334c58073ec0ea8a1b34da0c71f969b1affd0959/Sources/OpenIslandApp/CodexAppServerCoordinator.swift
