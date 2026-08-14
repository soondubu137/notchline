# 非公开 App Server Feature 依赖清单

本文记录 Codex in Notch 中没有完全通过公开 Codex App Server JSON-RPC 实现的生产 feature。目的不是把所有本地实现细节都列出来，而是在 Codex Desktop 更新后出现兼容性问题时，能够按依赖边界快速定位。

当前验证基线：Codex Desktop `26.803.61601`（build `6396`），内置 Codex CLI `0.147.0-alpha.6.5`，验证日期 `2026-08-14`。

“公开 App Server”指官方 [Codex App Server](https://developers.openai.com/codex/app-server/) 文档及当前 CLI 生成 schema 中公开的 JSON-RPC 方法、字段和通知。官方 [Projects and chats](https://learn.chatgpt.com/codex/projects) 文档明确说明 CLI 不暴露 Desktop 的 Projects 视图。

## Feature 清单

| Feature | 这个 feature 是什么 | 为什么公开 App Server 无法实现 | 实现方法 | 依赖级别与失效信号 | 代码定位 |
| --- | --- | --- | --- | --- | --- |
| Desktop Project / `Chats` 身份 | 展开列表为每个 thread 显示 Codex Desktop 侧边栏中的真实 Project 名称；只有 Desktop 明确标记为无 Project 的 thread 才显示 `Chats`。 | 当前 `thread/list` / `thread/read` 的 Thread schema 没有 Desktop `projectId` 或 `projectName`。`thread.section` 是独立持久化的 Thread Section，不是 Desktop Project；独立 App Server 的 `section` 也不能提供这份映射。 | 只读 `$CODEX_HOME/.codex-global-state.json`；可用 `CODEX_IN_NOTCH_CODEX_HOME` 显式覆盖状态根目录。用 `thread-project-assignments[threadId]` 取得 assignment；`local` assignment 连接 `local-projects[projectId].name`，`remote` assignment 连接 `remote-projects[id].label`；只有 `projectless-thread-ids` 明确包含 thread ID 时返回 `Chats`。主文件失败时读取 `.bak`，两者失败时保留 last-known-good。拒绝 symlink、非当前用户普通文件、超过 4 MiB 的文件、冲突成员关系及不兼容 schema。 | **Desktop 私有只读 schema。** 高版本风险。典型信号：Project 全部显示 `Project unavailable`；诊断包含“Project 状态 schema 不兼容”或“无法读取 Codex Desktop Project 映射”；对应单测失败。Desktop 更新后首先检查四个顶层 key、assignment 的 `projectKind/projectId` 以及本地 `name`、远程 `label`。 | [`CodexDesktopProjectMetadata.swift`](../CodexInNotch/CodexInNotch/CodexDesktopProjectMetadata.swift)、[`LiveCodexMonitorService.swift`](../CodexInNotch/CodexInNotch/LiveCodexMonitorService.swift)、[`CodexInNotchTests.swift`](../CodexInNotch/CodexInNotchTests/CodexInNotchTests.swift) |
| 实时 Turn 生命周期桥 | 用户提交后低延迟进入 Running，并跟踪 `request_user_input`、权限请求、工具完成、Stop 与 SessionEnd；App Server 快照只对已建立的精确 Turn 身份做校正。 | 独立启动的 App Server 可以读取持久化历史，但不保证共享 Codex Desktop 当前已加载运行时；本机验证中可出现 `thread/loaded/list` 为空。因此仅靠该进程的公开通知或轮询会漏掉 Desktop 正在发生的实时边界，并导致 Idle → Running 延迟。 | 用户显式安装 Codex Hooks。受管理 helper 把 `UserPromptSubmit`、`PermissionRequest`、`PreToolUse`、`PostToolUse`、`Stop`、`SessionEnd` 写为用户私有 JSON 事件；`HookEventRepository` 消费后删除，通过 `session_id + turn_id + tool_use_id` reducer 建立身份。随后用公开 App Server `activeFlags`、Turn 状态与 `thread/read` 做新鲜度受控校正。 | **官方 Hook 接口 + 本地文件桥，不是 App Server。** 中版本风险。典型信号：Desktop 正在处理但 Notch 仍为 Idle、Hook 事件目录无新文件、诊断提示 helper 更新或事件解析失败。Desktop/CLI 更新后检查 Hook 名称、payload 字段与 `/hooks` 信任状态。 | [`HookIntegration.swift`](../CodexInNotch/CodexInNotch/HookIntegration.swift)、[`LiveCodexMonitorService.swift`](../CodexInNotch/CodexInNotch/LiveCodexMonitorService.swift) |
| Hook 安装、升级与移除 | 在首次连接或 Settings 中安装、升级、校验和移除本应用管理的 Hook，同时保留用户其他 Hooks。 | 公开 App Server 没有安装、信任或管理 Codex Hooks 的方法，也不能替用户完成 CLI 的 `/hooks` 审核。 | 显式用户操作后增量合并 `~/.codex/hooks.json`，写入受管理 helper 和设置文件，记录受管理脚本 SHA-256；已知旧版 helper 可安全迁移，未知编辑 fail closed；用户仍在 Codex `/hooks` 中审核信任。移除时只删除本应用管理的定义和文件。 | **官方 Hook 配置工作流 + 本地配置文件。** 中版本风险。典型信号：Setup Required 无法转为 Ready、`hooks.json` 合并测试失败、helper hash/version 诊断出现。更新后检查 Hooks 配置 schema、事件名称、信任流程和 helper payload。 | [`HookIntegration.swift`](../CodexInNotch/CodexInNotch/HookIntegration.swift)、[`ProductRootView.swift`](../CodexInNotch/CodexInNotch/ProductRootView.swift) |
| Codex Desktop 进程身份门槛 | 区分“独立 App Server 可连接”和“当前 Codex Desktop 确实正在运行”；只让同一 Desktop PID 生命周期中的可信 Hook 观察恢复 Ready。 | App Server 是可独立运行的进程。握手或额度读取成功只证明 App Server 可用，不能证明 Desktop 正在运行，也不能证明 Hook 事件属于当前 Desktop 生命周期。 | 用 `NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")` 获取当前 Desktop PID，并把它与首次/最新可信 Hook 观察绑定；Desktop PID 变化后重新建立观察门槛。 | **macOS 公共进程 API + Desktop bundle identifier，不是 App Server。** 低到中版本风险。典型信号：Desktop 已打开但 Notch 持续 Disconnected，或应用改名/换 bundle id 后检测不到进程。 | [`LiveCodexMonitorService.swift`](../CodexInNotch/CodexInNotch/LiveCodexMonitorService.swift) |
| 精确打开同一 Desktop thread | 用户点击列表行后，在 Codex Desktop 中打开完全相同的 `threadId`，而不是只打开首页或创建新会话。 | App Server 可以用 `thread/list` 验证 thread 仍存在，但公开 JSON-RPC 没有“让 Desktop 前台导航到该 thread”的方法，也没有 Desktop 页面渲染完成回执。 | 先用公开 `thread/list` 完整分页验证未归档根 thread；再生成官方 `codex://threads/<percent-encoded-thread-id>` deep link，通过 `NSWorkspace` 定向交给 bundle id `com.openai.codex`。Launch Services 接受后才收起面板。 | **官方 Desktop deep link + macOS Launch Services，不是 App Server。** 中版本风险。典型信号：点击后 Desktop 打开错误页面、URL scheme 被拒绝、bundle id 找不到；对应 navigator 单测或版本矩阵端到端测试失败。 | [`CodexDesktopNavigator.swift`](../CodexInNotch/CodexInNotch/CodexDesktopNavigator.swift)、[`MonitorStore.swift`](../CodexInNotch/CodexInNotch/MonitorStore.swift) |
| App Server 可执行文件发现与启动 | 找到与 Desktop/CLI 匹配的 `codex` 可执行文件，并启动只读 `app-server --listen stdio://` 连接。 | App Server 协议定义连接后的 JSON-RPC 行为，但不能启动自身，也不提供 Desktop 安装位置发现接口。 | 优先使用 `CODEX_IN_NOTCH_CODEX_PATH`；否则检查 `/Applications/ChatGPT.app/Contents/Resources/codex`、旧 `/Applications/Codex.app/...`，最后搜索 `PATH`。找到可执行文件后用 `Process` 启动 `app-server --listen stdio://` 并完成 initialize/initialized 握手。 | **官方 CLI 子命令 + Desktop 私有打包路径。** 中版本风险。典型信号：`executableNotFound`、Desktop 更新后 bundle 内资源位置变化、进程启动失败。 | [`CodexAppServerClient.swift`](../CodexInNotch/CodexInNotch/CodexAppServerClient.swift) |

## 不在本表中的能力

额度、今日 token、Thread 列表、标题、Turn 详情和当前 App Server 可见的状态校正，均直接通过公开 App Server 方法实现，不在本表重复记录。

Desktop 蓝点对应的未读成员关系目前仍未进入生产实现；`docs/tech-design.md` 中的私有文件/socket 内容只是探索与候选方案，不能登记成已实现 feature。

## Desktop 更新后的排查顺序

1. 记录新的 Desktop short version、build 与内置 `codex --version`，更新本文验证基线。
2. 先运行 `CodexInNotchTests`，根据失败测试定位到上表对应 feature。
3. 对私有依赖只做只读检查：确认文件/可执行路径仍存在，再确认最小 schema；不得修改 `app.asar`、注入 Desktop IPC 或把缺失值伪装成成功。
4. 如果公开 App Server 新增了等价能力，优先迁移到公开方法，并从本表移除对应私有实现说明。
5. 如果 feature 暂时失效，必须 fail closed：Project 使用 `Project unavailable`，状态使用单会话 `Unknown` 或全局 Disconnected，导航拒绝打开；不得改用 cwd、标题、时间或窗口焦点猜测。

## 维护规则

- 新增任何不完全依赖公开 App Server 的生产 feature 时，必须在同一个改动中新增或更新本表行。
- 每行至少保留 feature 定义、公开 App Server 的能力缺口、真实实现方法和代码定位。
- 私有 schema 必须有 fixture 测试、缺失/损坏测试和明确的保守降级；不得把解析失败解释为空集合或 `Chats`。
