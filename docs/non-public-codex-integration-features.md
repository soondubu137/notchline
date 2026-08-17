# 未受官方公开支持的集成依赖清单

本文只记录 Codex in Notch 中依赖未被官方公开文档或公开 schema 支持的实现细节的生产 feature，按产品分表。目的不是列出所有没有使用 App Server 的功能，而是在 Codex Desktop 更新后出现兼容性问题时，能够快速定位真正的私有依赖。

当前验证基线：Codex Desktop `26.810.50856`（build `6644`），内置 Codex CLI `0.148.0-alpha.9`，验证日期 `2026-08-14`；Claude Desktop `1.30096.5`，Claude Code CLI `2.1.233`，验证日期 `2026-08-16`。

“官方公开支持”包括官方文档和公开 schema 中定义的 App Server、Codex Hooks、CLI/SDK 接口、Desktop deep link，以及实现中使用的 macOS 公共 API。仅仅没有通过 App Server 实现，不构成登记理由。官方 [Codex Hooks](https://learn.chatgpt.com/docs/hooks) 明确公开 lifecycle 事件、`hooks.json` 配置位置和信任流程；官方 [Commands](https://learn.chatgpt.com/docs/reference/commands#deep-links) 公开 Desktop deep link，这些能力不列入本表。

## Codex Feature 清单

| Feature | 这个 feature 是什么 | 为什么官方公开支持的接口无法实现 | 实现方法 | 依赖级别与失效信号 | 代码定位 |
| --- | --- | --- | --- | --- | --- |
| Desktop Project / `Chats` 身份 | 展开列表为每个 thread 显示 Codex Desktop 侧边栏中的真实 Project 名称；只有 Desktop 明确标记为无 Project 的 thread 才显示 `Chats`。 | 当前公开 App Server Thread schema、Hooks 和 Desktop deep link 都不提供 Desktop `projectId`、`projectName` 或 thread 到 Project 的成员关系。`thread.section` 是独立的 Thread Section，不是 Desktop Project。 | 只读 `$CODEX_HOME/.codex-global-state.json`；可用 `CODEX_IN_NOTCH_CODEX_HOME` 显式覆盖状态根目录。用 `thread-project-assignments[threadId]` 取得 assignment；`local` assignment 连接 `local-projects[projectId].name`，`remote` assignment 连接 `remote-projects[id].label`；只有 `projectless-thread-ids` 明确包含 thread ID 时返回 `Chats`。主文件失败时读取 `.bak`，两者失败时保留 last-known-good。拒绝 symlink、非当前用户普通文件、超过 4 MiB 的文件、冲突成员关系及不兼容 schema。 | **Desktop 私有只读 schema。** 高版本风险。典型信号：Project 全部显示 `Project unavailable`；诊断包含“Project 状态 schema 不兼容”或“无法读取 Codex Desktop Project 映射”；对应单测失败。Desktop 更新后首先检查四个顶层 key、assignment 的 `projectKind/projectId` 以及本地 `name`、远程 `label`。 | [`CodexDesktopProjectMetadata.swift`](../CodexInNotch/CodexInNotch/CodexDesktopProjectMetadata.swift)、[`LiveCodexMonitorService.swift`](../CodexInNotch/CodexInNotch/LiveCodexMonitorService.swift)、[`CodexInNotchTests.swift`](../CodexInNotch/CodexInNotchTests/CodexInNotchTests.swift) |
| Desktop 已读后自动移除 Completed 会话 | Completed 会话保持在列表中，直到 Codex Desktop 的未读蓝点消失；用户直接在 Desktop 打开并读过会话后，Notch 自动隐藏该行。Running、Input 与 Approval 会话不受未读状态影响。 | 当前公开 App Server Thread schema、Hooks 和 deep link 都没有 Desktop `hasUnreadTurn` 快照或已读变化通知；`thread/read` 只是读取 Thread 内容，不能表达蓝点语义。 | 只读 `$CODEX_HOME/.codex-global-state.json` 中的 `electron-persisted-atom-state.unread-thread-ids-by-host-v1.local`。用 `O_EVTONLY` + 目录级 `DispatchSourceFileSystemObject` 监听原子替换，250 ms trailing debounce 后刷新；现有 1 秒监视轮询负责 watcher 失效兜底。主文件失败时读取 `.bak`，再退到 last-known-good，但**只有当前主文件成功解析的 generation 才能隐藏新会话**。Completed 首次出现时保留 2 秒以覆盖 Desktop 约 500 ms 的持久化延迟；一旦观察过未读后再确认消失则立即隐藏。拒绝 symlink、非当前用户普通文件、超过 4 MiB、空/重复 id 及不兼容 schema；不连接私有 IPC、不写 Desktop 状态。 | **Desktop 私有只读 schema。** 高版本风险。典型信号：用户在 Desktop 阅读后 Completed 行持续保留；诊断包含“Desktop 未读状态 schema 不兼容”或“无法读取 Codex Desktop 未读状态”；目录原子替换测试失败。解析、权限或版本错误时 fail closed：保留尚未隐藏的 Completed 行，且不把空集合当成有效已读证据。Desktop 更新后首先检查 `electron-persisted-atom-state` 与 `unread-thread-ids-by-host-v1.local`、500 ms 持久化节流和主文件/`.bak` 原子替换行为。 | [`CodexDesktopUnreadState.swift`](../CodexInNotch/CodexInNotch/CodexDesktopUnreadState.swift)、[`LiveCodexMonitorService.swift`](../CodexInNotch/CodexInNotch/LiveCodexMonitorService.swift)、[`MonitorStore.swift`](../CodexInNotch/CodexInNotch/MonitorStore.swift)、[`CodexInNotchTests.swift`](../CodexInNotch/CodexInNotchTests/CodexInNotchTests.swift) |
| Codex Desktop 进程身份门槛 | 确认本次 Codex in Notch 启动后收到的实时 Hook 仍属于同一个 Codex Desktop 进程生命周期；它不参与判断 App Server 快照是否已确认，也不允许持久化 Hook 信任恢复 Ready。 | 官方 App Server 与 Hooks 不提供 Desktop 应用进程生命周期查询。实现依赖观察到的 Desktop bundle identifier `com.openai.codex`，该标识未作为 Codex 集成兼容契约公开。 | 用 macOS 公共 API `NSRunningApplication.runningApplications(withBundleIdentifier:)` 获取当前 Desktop PID；只有本次启动 cutoff 后实际消费了合法 Hook，才把该观察绑定到当前 PID。PID 变化后旧的实时 Hook 观察失效，重新走 App Server 当前快照或等待新 Hook。App Server `initialize` 与 `thread/list` 的公开响应独立决定 Connecting、Ready/Idle 或 Disconnected，不受此私有门槛影响。 | **未公开的 Desktop bundle identifier。** 中版本风险。典型信号：Desktop 更新 bundle id 后，启动后的 Hook 无法保持低延迟实时分支，但 App Server 快照仍应正常进入 Ready/Idle；对应 PID 绑定测试失败。 | [`LiveCodexMonitorService.swift`](../CodexInNotch/CodexInNotch/LiveCodexMonitorService.swift)、[`CodexInNotchTests.swift`](../CodexInNotch/CodexInNotchTests/CodexInNotchTests.swift) |
| App Server 可执行文件发现与启动 | 找到与 Desktop/CLI 匹配的 `codex` 可执行文件，并启动只读 `app-server --listen stdio://` 连接。 | `app-server` CLI 子命令本身是官方公开能力，但官方契约不包含 Codex Desktop bundle 内的可执行文件安装位置。 | 优先使用 `CODEX_IN_NOTCH_CODEX_PATH`；否则检查 `/Applications/ChatGPT.app/Contents/Resources/codex`、旧 `/Applications/Codex.app/...`，最后搜索 `PATH`。找到可执行文件后用 `Process` 启动公开的 `app-server --listen stdio://` 并完成 initialize/initialized 握手。 | **Desktop 私有打包路径。** 中版本风险。典型信号：`executableNotFound`、Desktop 更新后 bundle 内资源位置变化、进程启动失败。 | [`CodexAppServerClient.swift`](../CodexInNotch/CodexInNotch/CodexAppServerClient.swift) |

## Claude Code Feature 清单

| Feature | 这个 feature 是什么 | 为什么官方公开支持的接口无法实现 | 实现方法 | 依赖级别与失效信号 | 代码定位 |
| --- | --- | --- | --- | --- | --- |
| 会话标题 | 展开列表为每个 Claude Code 会话显示 Claude Code 自己在用的标题：用户设置的标题优先于自动生成的标题。 | 官方 Hook payload 只给出 `transcript_path`，不给标题；`claude agents --json` 只返回从目录派生的 `name`，那是 Project 不是标题；没有任何公开接口报告会话标题。 | 只读 `~/.claude/projects/<目录>/<sessionId>.jsonl`，解析 `custom-title` / `ai-title` 两种记录，取最后出现的一条，用户标题优先。目录名按「工作目录路径中的 `/` 全部替换为 `-`」推断；**该推断失败时退回按 `<sessionId>.jsonl` 文件名在 projects 下逐目录查找**，所以目录命名规则单独变化不会导致标题丢失。只读文件两端各 64 KiB，不整文件扫描（本机已见 16 MB 的 transcript）；按 `(size, mtime)` 缓存，会话消失即丢弃。解析失败、记录类型不认识、文件不存在一律返回无标题，行显示 `Untitled`，**绝不退回目录名**。预览开关关闭时同样显示 `Untitled`——标题也是用户内容。 | **Claude Code 私有只读 schema。** 中高版本风险。典型信号：所有 Claude Code 行显示 `Untitled`；标题解析单测失败。CLI 更新后先检查 `custom-title` / `ai-title` 记录类型与其 `customTitle` / `aiTitle` 字段，再检查 projects 目录命名规则。 | [`ClaudeCodeTranscriptReader.swift`](../CodexInNotch/CodexInNotch/ClaudeCodeTranscriptReader.swift)、[`ClaudeCodeMonitorService.swift`](../CodexInNotch/CodexInNotch/ClaudeCodeMonitorService.swift)、[`CodexInNotchTests.swift`](../CodexInNotch/CodexInNotchTests/CodexInNotchTests.swift) |
| `~/.claude/sessions/` 作为「该复核了」的信号 | 会话增删时立刻重新查询官方会话列表，而不是等心跳。 | 官方没有提供会话增删的通知接口；`claude agents --json` 是查询而非推送。 | 用现有的 `DirectoryChangeWatcher` 监听该目录，**只当作变更信号，从不解析目录内容**。权威数据永远来自官方命令 `claude agents --json`。 | **私有目录位置，非 schema。** 低风险，退化温和：目录消失或改名只会让复核变迟钝，退回心跳节奏，不会产生错误状态。 | [`ClaudeCodeMonitorService.swift`](../CodexInNotch/CodexInNotch/ClaudeCodeMonitorService.swift) |

## 不在本表中的能力

- 实时 Turn 生命周期桥、Hook 安装/升级/总开关/移除使用官方 Codex Hooks、公开事件与 `hooks.json` 配置，不在本表记录。
- Claude Code 的会话发现使用官方公开命令 `claude agents --json`——其 `--help` 明确承诺 `--json` 打印包含交互式在内的活动会话且不需要 TTY——不在本表记录。
- Claude Code 的 Hook 事件、`type: "http"` handler 与 `~/.claude/settings.json` 中的 `hooks` 配置位置均为官方公开能力，不在本表记录。本应用**不写**该文件（见 [ADR 0010](adr/0010-never-write-the-users-claude-code-settings.md)），只读取它以判断注册是否完整。
- 精确打开 Desktop thread 使用官方 `codex://threads/<thread-id>` deep link 和 macOS 公共 Launch Services，不在本表记录。
- 额度、今日 token、Thread 列表、标题、Turn 详情和状态校正使用公开 App Server 方法，不在本表记录。

## Desktop 更新后的排查顺序

1. 记录新的 Desktop short version、build 与内置 `codex --version`；只有重新验证了表中的私有依赖后才更新本文验证基线。
2. 先运行 `CodexInNotchTests`，根据失败测试定位到上表对应 feature。
3. 对私有依赖只做只读检查：确认文件、标识或可执行路径仍存在，再确认最小 schema；不得修改 `app.asar`、注入 Desktop IPC 或把缺失值伪装成成功。
4. 如果官方文档或公开 schema 新增了等价能力，优先迁移到官方方法，并从本表移除对应私有实现说明。
5. 如果 feature 暂时失效，必须 fail closed：Project 使用 `Project unavailable`；会话状态保留最后可信四态值，只有 App Server 无响应才使用全局 Disconnected；不得改用 cwd、标题、时间或窗口焦点猜测。

## 维护规则

- 新增任何依赖未公开或未承诺兼容的 Codex 实现细节的生产 feature 时，必须在同一个改动中新增或更新本表行。
- 不得仅因为实现没有使用 App Server 而登记；官方 Hooks、官方 deep link、公开 CLI/SDK 接口和 macOS 公共 API 都是允许的实现方式。
- 每行至少保留 feature 定义、官方公开支持接口的能力缺口、真实实现方法、失效信号和代码定位。
- 私有 schema 必须有 fixture 测试、缺失/损坏测试和明确的保守降级；不得把解析失败解释为空集合或 `Chats`。
