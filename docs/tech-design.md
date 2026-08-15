# Codex in Notch — Codex 集成技术设计

| 字段 | 内容 |
| --- | --- |
| 文档状态 | 第一实现切片、精确导航、Desktop Project 身份、Desktop 未读终态移除与 Expanded footer 已实现；真实版本矩阵仍待验证 |
| 版本 | 0.19 |
| 日期 | 2026-08-15 |
| 范围 | 将 SwiftUI 原型中的 Mock 状态、额度、今日 tokens、会话列表与点击导航替换为真实 Codex Desktop 数据；Running 计时延后评估 |

## 1. 结论

V1 把展开列表实现为 Codex Desktop 当前处理轮次的实时监视器，不实现历史列表。权威成员集合是：当前 Desktop 账户下所有 Project 与 `Chats` 中，存在活动 Turn 或未读终态 Turn，并且仍可通过同一 `threadId` 在 Desktop 精确导航的根会话。

集成采用“受支持的 Desktop 观察通道 + 事件 reducer + 集合校正”架构。Project、未读状态和精确导航都是发布门槛；不能从 cwd、时间或窗口焦点推断。Desktop Project 身份与未读成员关系是经产品明确批准、带 schema gate 的私有只读例外；所有依赖未公开或未承诺兼容的 Codex 实现细节必须登记在 [`non-public-codex-integration-features.md`](non-public-codex-integration-features.md)。官方 Hooks、App Server 和 deep link 均属于公开支持接口，不因技术通道不同而登记。

本文同时记录实现方案、已验证的协议能力和当前测试版边界。

### 1.1 第一实现切片（2026-08-12）

已经实现：

- 通过 Codex Desktop 随附的 `codex app-server --listen stdio://` 建立 JSON-RPC 连接，严格按 `initialize → initialized` 握手。
- 只调用 `thread/list`、`thread/read`、`thread/loaded/list`、`account/read`、`account/rateLimits/read`、`account/usage/read` 六个只读方法，且不响应或代替用户处理审批/输入请求。`thread/read` **必须始终带 `includeTurns: false`**：它只用于按 id 取单个 Thread 的元数据（标题、preview、根线程判定、`status`），绝不用于读取 Turn 历史；`thread/items/list`、`thread/turns/list` 等 Turn 明细接口一律不调用。这条约束由测试固定。
- 从当前账户 primary rate-limit window 读取真实 `usedPercent`，转换为剩余百分比；不可用时显示灰色圆环。
- 从 `account/usage/read.dailyUsageBuckets` 读取本地日历“今天”的 token bucket；Expanded footer 显示标准 Compact 数字、额度重置日期和 Settings 入口。今日 bucket 缺失但 bucket 数组有效时按 `0` 处理，接口不可用时只将今日用量显示为 `--`。
- 提供用户显式触发的 Hooks 安装器，增量合并 `~/.codex/hooks.json`，保留其他定义，并要求用户在 Codex `/hooks` 中审核信任。Settings 使用一个 `Codex integration` 总开关，把六种必需 lifecycle event 定义作为一个产品能力启停；关闭后留在 Settings，不重置首次引导。
- 使用 `UserPromptSubmit`、`PermissionRequest`、`PreToolUse(request_user_input|request_permissions)`、`PostToolUse` 和 `Stop` 建立 Turn 生命周期事件桥；所有状态事件必须携带精确 `session_id + turn_id`，输入请求与审批请求都必须用相同 `tool_use_id` 成对关闭。事件文件采用用户私有权限、消费后删除。
- 标题使用 Thread 元数据，按成本分两层获取：Hook reducer 当前跟踪的 Thread 用 `thread/read`（`includeTurns: false`，实测约 1.2 KB/线程）按 id 读取，全量分页 `thread/list` 只负责低频成员关系对账（实测 33 个线程约 45 KB，且随历史线性增长）。`thread/list` 按契约**永远返回空 `turns`**（schema：`turns` 仅在 `thread/resume`、`thread/rollback`、`thread/fork` 和 `includeTurns: true` 的 `thread/read` 上填充），因此任何 Turn 级事实都只能来自 Hook reducer。Project/`Chats` 使用 Desktop 私有全局状态中的精确 thread assignment，绝不把 `thread.section` 当成 Project。未读终态成员关系只读消费同一 Desktop 全局状态中的本地未读集合；活动会话始终显示，只有权威主文件确认终态已读后才隐藏。会话状态只包含 Running、Input needed、Approval needed、Completed；实时 `Stop` 以及 App Server 的 `completed`、`failed`、`interrupted` 都直接收敛为 Completed，不再读取 Thread 详情区分结束原因。
- Preview 设置默认开启；关闭后 hook 不再写入内容片段，列表完全移除预览行，缺少 Desktop 标题时只显示 `Untitled`。即使开启，prompt/回答片段也不写入持久状态。
- `MonitorStore` 替换生产 Mock，事件活跃时 1 秒校正、断开时 5 秒静默重试；首次收到合法 Hook 后只持久化不含会话身份与内容的布尔配置健康标记。应用重启时 reducer 从空集合开始，启动前积压的所有 Hook（包括 Stop 与 SessionEnd）一律不恢复或修改 Turn；只有本次进程启动后的 Hook 才是实时证据，也是四态状态的唯一来源。Running 直接显示状态名称，额度区域始终显示真实剩余比例；空列表与全局状态采用薄层展开 UI。
- 会话行通过官方 `codex://threads/<thread-id>` deep link 打开同一 Codex Desktop 会话；打开前强制刷新全部未归档根 Thread，目标不存在时拒绝导航。URL 只定向交给 bundle id `com.openai.codex`，Launch Services 接受后才收起面板。

已经通过本机当前 Codex 版本验证：App Server 握手、真实额度响应、Thread/Turn schema、Desktop Project 与未读私有状态解析、Hooks 配置合并、事件 reducer 与精确导航 adapter。未读适配器的主/备份/last-known-good、私有 schema 失败、原子替换目录事件、settling window 与端到端已读移除均有单元测试。应用构建与单元测试已通过。

尚未满足、因此仍阻塞 V1 发布：

- 独立 App Server 不共享 Codex Desktop 的进程内事件流，且实测无法回答 Turn 级问题（见下），因此启动不做现状同步：只要 App Server 完成握手并成功返回一次 `thread/list`，即发布 Ready 并以空集合聚合为 Idle。只有 App Server 没有响应或连接失败才显示 `Codex disconnected`；校验请求尚未完成时保持 Connecting。跨 Codex in Notch 重启持久化的 Hook 标记只用于配置健康判断，不得恢复任何会话状态。
- **实测边界（Codex CLI `0.148.0-alpha.9`，在一个真实运行中的 Turn 上采样）**：独立 App Server 的 `thread/loaded/list` 返回空；所有 Thread 的 `status.type` 恒为 `notLoaded`；`thread/list` 契约上永不返回 `turns`；`thread/read` 即使带 `includeTurns: true` 也从不出现 `inProgress`——正在运行的 Turn 被记为 `interrupted` 且 `completedAt` 为 null。直接后果：依赖 `status.type == "active"` 的 `activeFlags` 校正在当前拓扑下**永远不成立**。该机制（`activeEvidence`、`terminalStatus`、`reconcileActiveStatus`、`markCompleted` 与 `hasLiveBoundary`）已整体删除，因为保留空转代码会让后续设计误以为存在这条能力。若将来出现共享运行时拓扑，应基于当时验证过的字段重新设计，而不是复活这段代码。
- 当前公开协议仍没有 Desktop 蓝点对应的已读字段；生产实现依赖第 1.3 节登记的 Desktop 私有只读 schema。Desktop 升级后的真实 read/unread 版本矩阵仍是发布验证项，任何不兼容都必须保守保留终态行。
- Hooks 可以可靠覆盖开始、权限管线触发、`request_user_input` 和终态边界；`PermissionRequest` 本身不证明仍需人工批准，Approval needed 必须由新鲜 App Server `waitingOnApproval` active flag 确认。App Server 的 `completed`、`failed`、`interrupted` 都映射为 Completed，仍需真实 Desktop 样本矩阵验证端到端覆盖。
- `threadSource/sourceKinds` 仍不足以单独证明 Desktop 与独立 IDE 来源边界，必须继续以真实样本验证。

### 1.2 已读移除与精确导航能力边界

- 官方 [Codex Desktop deep links](https://learn.chatgpt.com/docs/reference/commands#deep-links) 已定义 `codex://threads/<thread-id>`。导航 adapter 已按本节约束实现；Codex 当前仍不提供页面完成渲染的公开回执。
- 官方 [Codex App Server](https://learn.chatgpt.com/docs/app-server) 当前没有 unread/read/open/current-view 字段或通知。`thread/read` 是读取 Thread 记录，不是标记已读；`thread/loaded/list` 与 `thread/closed` 也不表达蓝点语义。
- 当前 Desktop 安装包内部把蓝点集合持久化在 `$CODEX_HOME/.codex-global-state.json` 的 `electron-persisted-atom-state.unread-thread-ids-by-host-v1.local`。经产品批准，本字段已作为独立、已登记的私有只读适配器进入生产；它不扩展到其他 Electron 状态或 IPC。
- 实现必须处理原子替换与短暂主/备份代际差异；活动 Turn 无论蓝点如何都继续显示，只有终态 Turn 在主文件权威快照中从 unread 集合消失后才移除。不得注入 IPC、修改 `app.asar`、使用 Accessibility/AppleScript，或把 Stop/SessionEnd 当作已读。
- Developer ID 直接分发在关闭 App Sandbox 时技术上可读取该路径；Mac App Store sandbox 需要用户选择目录与 security-scoped bookmark。无论分发方式如何，文件可读都不等于接口受支持。
- 长期方向仍是迁移到 Codex 未来公开的 `hasUnreadTurn` 快照与变化通知；出现等价公开能力时必须在同一改动中移除私有适配器与清单行。

### 1.3 Desktop 未读私有只读适配器（已实现）

对当前 Desktop `26.810.50856` build `6644`、CLI `0.148.0-alpha.9` 的只读核验表明：

- 状态根目录是 `process.env.CODEX_HOME ?? ~/.codex`；默认文件为 `.codex-global-state.json`。
- 未读集合位于 `electron-persisted-atom-state.unread-thread-ids-by-host-v1.<hostID>`；本地 V1 只能消费 `local`，不能合并其他 host。
- Desktop 自身在状态变化后等待约 `500 ms` 再持久化；写入通过同目录临时文件 `rename` 原子替换主文件，随后独立替换 `.bak`。因此目标 inode 会变化，主文件与 backup 也可能短暂属于不同 generation。
- 这是真实的 Thread 级蓝点集合，没有 Turn id。它只能与“每个 Thread 展示最新活动或未读终态 Turn”的领域模型组合。

生产实现采用以下架构：

1. `CodexDesktopUnreadStateRepository` 默认只读 `$CODEX_HOME/.codex-global-state.json`，并支持测试/隔离环境用 `CODEX_IN_NOTCH_CODEX_HOME` 覆盖 Codex Home。
2. 目录级 `DispatchSourceFileSystemObject` + `O_EVTONLY` 监听 Codex Home，而不是长期监听目标文件 inode；目录事件采用 `250 ms` trailing debounce 并触发刷新。现有 Hook 活跃期 1 秒轮询是 watcher 无法建立或事件被合并时的兜底。
3. 只解析 `local` host 的字符串集合，同时校验所有 host 名称、空 id 与重复 id。读取器拒绝 symlink、非当前用户普通文件、超过 4 MiB 的文件、异常 JSON 与不兼容 schema；不记录原始 JSON 或 Thread id。
4. 主文件失败时读取 `.bak`，两者失败时保留进程内 last-known-good。但 backup 和 last-known-good 只用于保留数据与诊断，只有 `source == current` 的主文件快照可以做新的隐藏决定；解析失败绝不能解释为空集合。
5. 活动、Input、Approval 始终显示并清除该 Turn 的终态 gate。终态首次出现且主文件暂未包含 unread 时保留 2 秒，覆盖 Desktop 约 500 ms 的持久化延迟；已经观察过 unread 后再从权威主快照消失则立即隐藏。隐藏 gate 在临时解析失败时保持隐藏，避免 UI 闪回；新终态在失败期间继续显示。
6. `MonitorStore` 同时消费目录变化流和原有轮询；统一的 in-flight gate 合并并发刷新。停止监视、关闭集成或清空列表时清除终态 gate。

适配器已经覆盖成功、缺失、损坏、backup、last-known-good、schema 不兼容、原子替换和终态竞态 fixture；Desktop 更新后仍必须执行真实 read/unread 与完成/阅读竞态矩阵。目标是 p95 同步不超过 1.5 秒、p99 不超过 2 秒，且任意错误都不提前移除终态行。当前 Developer ID 非沙箱构建可读取该路径；Mac App Store sandbox 仍需要用户选择目录与 security-scoped bookmark，未经实现不得声称支持。

其他路径的独立研究没有找到公开且准确的替代方案：

- App Server、Hooks、通知、JSONL、SQLite、窗口焦点与 deep-link 回调都不表达“用户已阅读”。
- 当前 Desktop 私有 Unix socket `~/.codex/ipc/ipc.sock` 会广播 `thread-read-state-changed` delta，但没有初始完整快照；连接者必须注册为内部 IPC client、参与 discovery，可能影响路由与超时。它的风险和版本耦合均高于纯只读文件，因此不采用。
- Accessibility、AppleScript、标题匹配、定时移除或“Desktop 获得焦点即已读”均不准确并违反安全约束。
- 唯一公开且诚实的产品折中是把 Notch 点击定义为本应用自己的“已确认”，但它无法覆盖用户直接在 Desktop 阅读，不得称为 Desktop 已读同步；当前产品语义不采用。

可替代本私有实现的最小公开能力仍是启动/重连可获取的 `hasUnreadTurn` 快照，以及携带 `threadId`、`hostId` 和新布尔值的 `thread/readState/changed` 通知，并具备 capability/version negotiation。

### 1.4 Desktop Project 私有只读适配器（已实现）

当前公开 Thread schema 没有 Desktop `projectId/projectName`；`thread.section` 是独立的 Thread Section，不能作为 Project。经产品批准，Project 身份使用一个严格受限的私有只读适配器：

- 默认读取 `$CODEX_HOME/.codex-global-state.json`；可用 `CODEX_IN_NOTCH_CODEX_HOME` 显式指定 Codex Home。
- `thread-project-assignments[threadId]` 的 `local` assignment 连接 `local-projects[projectId].name`，`remote` assignment 连接 `remote-projects[id].label`。
- 只有 `projectless-thread-ids` 明确包含 thread ID 时显示 `Chats`。映射缺失、未知 `projectKind` 或无法解析时显示 `Project unavailable`，不得回退到 `cwd`、Git root、Section 或 `Chats`。
- 主文件读取或解析失败时尝试 `.bak`；两者都失败时保留进程内 last-known-good 并发出诊断。文件未变化时按 size、mtime 与 inode revision 复用解析结果。
- 读取器拒绝 symlink、非当前用户普通文件、超过 4 MiB 的文件、空 Project 名称、重复 remote id 与 Project/Chats 冲突成员关系；不记录原始 JSON、root path 或 thread id。

该适配器已在 Desktop `26.810.50856` build `6644`、CLI `0.148.0-alpha.9` 验证。它仍是高版本风险的私有 schema，更新与失效排查必须遵守 [`non-public-codex-integration-features.md`](non-public-codex-integration-features.md)。

## 2. 设计约束

### 2.1 产品约束

- 一行是一个根 Thread；一轮处理是 Thread 中一个 Turn。
- 监视当前 Desktop 账户的全部 Project 与 `Chats`，不跟随侧边栏选择。
- 活动 Turn 始终显示；终态 Turn 只在 Desktop 未读时显示。
- 已读、归档、删除或失去可导航性立即退出列表。
- 子智能体、exec、独立 CLI/IDE 会话不显示为顶级行。
- 点击必须进入完全相同的 Desktop Thread；只打开首页不算成功。
- 启动时不展示缓存行，也不重建启动前的会话；列表从空开始，只累积启动后产生 lifecycle 事件的 Turn。
- 当前内容预览可全局关闭，默认开启且不持久化。

### 2.2 安全约束

- 默认只使用官方公开、受支持、可做版本能力判断的接口；生产中的例外必须是产品明确批准、只读、fail closed 且登记在 [`non-public-codex-integration-features.md`](non-public-codex-integration-features.md) 的能力。
- 不连接未经支持的 Desktop 私有 socket，不写私有数据库，不使用辅助功能或 GUI 自动化。
- 不读取认证文件或复制 Desktop 凭据。
- 不发起 Turn、resume Turn、批准、输入、取消、归档或删除。
- 集成配置只在用户确认后修改，并能从设置中移除。

### 2.3 UI 约束

- 共享展开基准宽度 `520`；`46` 高菜单栏、三行会话时参考总高度 `326`。
- 顶部汇总区参考高 `46`，始终等于目标菜单栏高度；展开只横向扩张。
- 下方内容区由列表视口和 footer 组成：列表视口最多 `472 × 240`，三行可见并垂直滚动；footer 固定 `472 × 40`。
- 健康空列表与全局可用性状态使用 `520 × 134` 薄层，其中状态正文 `48`、footer `40`。
- footer 在有会话与无会话时必须同为 `40` 高，不能在其下方追加 padding。顶部用与 header/list 相同的 hairline 分隔；左侧是今日 token 总量与 reset 文案，右侧是 `32 × 32` Settings 点击目标和 `16 × 16` 齿轮。
- Figma 与产品 UI 字体统一使用 SF Pro。

## 3. 关键发布门槛

Phase 0 必须分别证明以下能力，而不是从现有字段猜测：

| 能力 | 必须取得的真实值 | 缺失时行为 |
| --- | --- | --- |
| Thread 身份 | 稳定 root `threadId` 与可导航性 | 阻止 V1 发布 |
| Turn 实时状态 | 开始、Input、Approval、Running、Completed | 阻止实时监视器发布 |
| Desktop 未读 | 与蓝色未读点一致的成员变化 | 阻止终态生命周期发布 |
| Desktop Project | Project id/name 与 `Chats` | 阻止 Project 展示发布，不得用 cwd 替代 |
| 精确导航 | 官方 `codex://threads/<thread-id>` → 同一 Desktop 页面 | adapter 与单元测试已完成；保留版本化端到端兼容测试 |
| 额度 | 当前账户 primary rate-limit window | 只降级为灰色不可用圆环 |
| 今日 token 总量 | `account/usage/read.dailyUsageBuckets` 中本地今天的 bucket | 只降级为 `--`，不得使用 lifetime 或额度百分比推算 |
| 当前内容 | 用户可见 prompt/progress/final | 只隐藏预览 |

官方 App Server 的 Thread/Turn/状态/额度协议是主要基础，但当前公开字段不包含 Desktop Project 与未读成员关系。独立启动的 App Server 也不能假定与 Desktop 共享运行时。未读与 Project 分别使用第 1.3、1.4 节已批准并登记的私有只读适配器；其他内部 Desktop 资源只能用于理解问题，未经单独批准、fail-closed 设计和依赖登记不得成为生产依赖。

处理时长不是 V1 发布门槛。V1 不发布时长字段，也不根据开始/结束时间在 UI 中推算 Running 计时；该能力保留为未来评估项。

## 4. 领域数据模型

```swift
struct MonitoredThreadSnapshot: Identifiable, Equatable {
    let id: String                 // Desktop threadId
    let turnId: String
    let title: String
    let project: ProjectIdentity   // Desktop Project or Chats
    let status: SessionStatus
    let isUnread: Bool
    let isArchived: Bool
    let isDeleted: Bool
    let isNavigable: Bool
    let preview: String?           // memory only
    let observedAtMs: Int64
    let revision: UInt64
}

enum SessionStatus {
    case inputNeeded
    case approvalNeeded
    case running
    case completed
}

enum IntegrationAvailability {
    case setupRequired
    case connecting(deadlineMs: Int64)
    case ready
    case updateCodex
    case unsupportedVersion
    case disconnected
}

struct QuotaSnapshot: Equatable {
    let remainingPercent: Int? // primary usedPercent 的反值
    let resetsAt: Date?
    let todayTokens: Int64?    // account/usage/read 的本地今日 bucket
}

struct PrivacySettings {
    var showCurrentContentPreviews: Bool // default true
}

struct TurnKey: Hashable {
    let threadId: String
    let turnId: String
}

enum PendingInputEvidence: Equatable {
    case hook(toolUseId: String)
    case appServerSnapshot
}

struct TurnEvidence: Equatable {
    let key: TurnKey
    var status: SessionStatus
    var pendingInput: PendingInputEvidence?
    var isApprovalPending: Bool
    var hasLiveBoundary: Bool       // observed after this repository launch
    var retiredTurnIds: Set<String> // memory-only generation guard
}
```

`SessionStatus` 不包含 Idle 或 Disconnected。Idle 从“集成 ready 且成员集合为空”推导；Disconnected 属于 `IntegrationAvailability`。

`TurnEvidence` 是内存中的 reducer 真值，不直接持久化。当前 Turn 从 Running 开始；Input needed 与 Approval needed 都只是在同一活动 Turn 上暂时覆盖 Running，等待恢复信号回到 Running；任何可信执行结束信号进入不可逆的 Completed。缺失、超时或未知信号不创建第五种状态，只保留最后可信值。

## 5. 数据真值与禁止回退

| UI 字段 | 权威来源 | 允许回退 | 禁止回退 |
| --- | --- | --- | --- |
| Thread id | Desktop 支持接口 | 无 | 标题、session id、路径、时间接近度 |
| Turn id | 当前活动或未读终态 Turn | 无 | Thread updatedAt |
| 标题 | Desktop 当前显示标题 | 预览开启时使用本轮 prompt 安全截断；否则 `Untitled` | cwd、仓库名、Mock 标题 |
| Project | Desktop 私有全局状态中的精确 thread assignment + Project id/name | `projectless-thread-ids` 明确命中时 `Chats`；否则失败显示 `Project unavailable` | `thread.section`、cwd basename、Git root |
| 未读 | Desktop 未读真值 | 无 | 窗口焦点、Notch 点击、固定保留时间 |
| 状态 | 受支持的 Turn/请求事件与校正快照 | 保留最后可信四态值 | 计时器或 UI 猜测 |
| 处理时长（未来） | V1 不发布该 UI 字段 | 无 | `startedAt` 推算、Thread 时间、文件修改时间 |
| 预览 | Codex 已向用户公开的内容 | 隐藏 | raw reasoning、工具参数、输出、diff |
| 额度 | 当前账户 primary rate-limit window | 灰色 unavailable | stale 值、daily/lifetime usage 推算 |
| 今日 tokens | `account/usage/read` 当日本地日历 bucket | 有效 bucket 数组中缺少今天时为 `0`；接口失败显示 `--` | lifetime、peakDailyTokens、额度百分比、会话行求和 |

## 6. 系统架构

当前实现的详细组件图、刷新时序、状态收敛、App Server 恢复边界与源码映射统一维护在 [`system-architecture.md`](system-architecture.md)。本节不再维护第二份抽象图，避免概念组件名与真实 Swift 类型分别演进。

组件职责与源码位置也以 [`system-architecture.md` 的组件表](system-architecture.md#5-组件职责与代码位置) 为准；其中使用当前实现中的真实类型名，并明确区分官方协议边界、私有只读适配器、应用核心和展示层。

## 7. 集成生命周期

### 7.1 首次安装

1. 检测 Codex Desktop 是否存在并读取版本。
2. 展示 Welcome，不改变系统状态。
3. 展示将读取的本地元数据、不会持久化的内容与可逆性。
4. 用户点击 `Set Up Integration` 后才执行安装/注册。
5. 尊重 Codex 对本地 Hook/集成的信任与审核机制，不绕过。
6. 完成能力探测；只有必需能力全部通过才显示 Ready。
7. `Start Monitoring` 后进入 connecting，并从空集合重建。

安装器必须记录自己管理的最小配置片段，不能覆盖用户其他配置。移除时只移除本应用管理的片段。安装健康度要求 `UserPromptSubmit`、`PermissionRequest`、`PreToolUse(^(request_user_input|request_permissions)$)`、`PostToolUse`、`Stop`、`SessionEnd` 六种定义各有且只有一个当前 handler，且 command、matcher 与 `timeout = 3` 精确匹配；只存在任意子集、重复定义或字段被改变时必须 fail closed 为 `repairRequired`，不能显示 Ready。用户重新开启总开关后，安装器先移除所有本应用 command 的残缺/重复注册，再写回完整集合，同时保留其他 command。

### 7.2 启动与重连

```text
launch
→ load Hook trust marker only; initialize an empty in-memory reducer
→ detect installation/version
→ atomically upgrade the app-managed Hook helper whenever this app recorded installing it
→ Connecting to Codex (≤ 5s)
→ capability handshake
→ reconcile active + unread terminal membership
→ subscribe events
→ ready
```

五秒内连接成功则不显示中间错误；超时后根据原因进入 Update Codex、unsupported 或 disconnected。Codex 未运行时不自动启动。

Hook helper 的源码发生版本变化不等于集成未安装。安装器直接把磁盘上的 helper 与本版本内置的定义做内容比较：相同即 `current`；不同且本应用的 settings 文件存在（该文件只由 `install()` 写入，等于本应用确实安装过）时，只原子升级本应用管理的 helper 文件并保留预览设置，不改写 `hooks.json`、不重新要求信任。

这里**不再记录内容 hash**。曾经存在的 `managedHookSHA256` 与 helper 位于同一目录、同一属主与权限，能改写 helper 的主体同样能改写该 hash，因此它不提供任何防篡改能力；而 `repairRequired` 并不会把 helper 从 `hooks.json` 注销，Codex 仍会继续执行它。也就是说，遇到被替换的 helper 时，自动升级回内置版本比标记 `repairRequired` 更快地消除外来代码。缺少任一定义、定义结构不精确，或 helper 存在但 settings 文件缺失（本应用没有安装记录、来源不明）时仍 fail closed 为 `repairRequired`；Settings 总开关显示 Off，用户显式重新开启后才修复。这样应用升级后无需重新接受未改变的受信 helper；但完整注册集合和历史信任本身不能让运行时进入 Ready。只有当前态来源确认集合确实为空时，才能由空集合推导 Idle。

### 7.3 集合校正时机

- 首次连接成功。
- observer 重连。
- Mac 睡眠唤醒。
- 账户切换。
- 收到可能影响成员集合的未读、归档、删除或 Project 事件。
- 每 30 秒进行一次低频安全校正，用于覆盖漏失事件；Hook 发现尚未列出的新 Thread 时立即调度一次后台校正，但不得等待它再发布 Hook 状态，也不得秒级扫描完整历史。后台请求合并为单个 in-flight task；失败后至少 60 秒再重试。
- 点击导航前进行目标级轻量校正。

## 8. 成员集合算法

对每个 root Thread，选择当前活动 Turn；不存在活动 Turn 时选择 Desktop 标记未读的最近终态 Turn。只有满足以下全部条件才进入集合：

```text
isRoot
AND isNavigableInDesktop
AND !isArchived
AND !isDeleted
AND (turn.isActive OR (turn.isTerminal AND thread.isUnread))
```

集合差分规则：

- `added`：读取最小 Thread/Turn/Project 快照并生成行。
- `updated`：先按精确 `threadId + turnId` 定位，再按 `revision` 或稳定事件序号合并；旧 Turn 事件和无法关联的结果都不能覆盖当前 Turn。
- `removed`：立即从 repository 删除。
- `thread/closed`：只表示运行时关闭，不直接映射 removed。

重启时不读取本应用旧列表或旧 reducer Turn；从空集合执行同一校正。启动前已写入事件目录的历史事件只可建立 Hook 配置健康信任，任何事件类型都不得恢复终态边界、创建 Turn 或修改当前状态。

## 9. 状态 reducer

### 9.1 映射

| 信号 | 产品状态 |
| --- | --- |
| 等待用户输入 active flag / request | Input needed |
| 新鲜 `waitingOnApproval` active flag | Approval needed |
| Turn active 且无等待请求 | Running |
| `Stop` 或 terminal `completed` / `failed` / `interrupted` | Completed |

状态机只有以下合法流转：`Running ↔ Input needed`、`Running ↔ Approval needed`、`Running → Completed`。Running 是起点，Completed 是不可逆终点；没有合法新信号时保持当前状态。终态到达后清空该 Turn 的 pending request，旧 Turn 的晚到事件不能改变新 Turn。

### 9.2 身份准入与请求配对

- 所有会改变 Turn 状态的 Hook 必须包含非空 `session_id` 和 `turn_id`。不得回退到当前 Turn、`"unknown"`、时间邻近或 Thread 更新时间；缺少身份的事件只写脱敏诊断并消费隔离。
- repository 没有该 Thread 时，受支持事件可以用自身的精确身份建立 Turn。已有当前 Turn 时，顺序更新且从未被该 Thread 淘汰过的 `UserPromptSubmit` 可以建立下一 Turn；Desktop 中断后继续执行时可能不再发送 `UserPromptSubmit`，因此更晚到达的实时 `PermissionRequest`、`PreToolUse`、`PostToolUse` 或 `Stop` 也可以用新的、未退休的精确 `turn_id` 接管同一 Thread。接管时旧 Turn id 立即进入 `retiredTurnIDs`，保留原始开始时间与 prompt preview，清空旧等待证据；事件本身再决定 Running、Input needed 或 Completed。任何退休 Turn 的迟到事件都不能复活旧身份。
- `PreToolUse(request_user_input)` 只有在包含非空 `tool_use_id` 时才建立 Input pending；`PostToolUse` 只有 `turn_id` 和 `tool_use_id` 都与该 pending 完全相同时才能清除它。未匹配结果保持原状态。
- 当前公开 `PermissionRequest` Hook 没有稳定 request/tool id，也不区分人工等待与自动审查后立即继续，因此它只建立该 Turn 的新鲜刷新边界，不建立 Approval evidence。Approval needed 的唯一肯定依据是同一精确 Turn 的新鲜 App Server `waitingOnApproval` active flag；任意 `PostToolUse` 也不得用来猜测审批状态。
- 只有本次启动后收到的实时 `Stop` 才清空 pending input/approval，并让同一精确 Turn 直接进入 Completed。产品不区分 completed/failed/interrupted 的结束原因，也不存在终态待解析窗口。历史回放的 Stop 完全不进入 Turn reducer。

### 9.3 App Server 当前快照纠偏

Hook 是四态状态的唯一来源；App Server 只提供展示用元数据。Hook reducer 先用缓存的 Thread 标题与 Desktop Project 私有状态发布状态，再异步刷新元数据；任何 App Server 请求都不得位于 Hook → UI 的关键路径。Thread payload 只贡献根线程判定、标题与 preview，不参与状态推导——它没有任何字段能在当前拓扑下表达 Turn 级运行时真值（见第 1.1 节实测边界）。

独立 App Server 不共享 Desktop 当前运行时，因此它不是 Hooks 的替代品，也不参与状态纠偏。元数据读取遇到缺失字段、超时或协议错误时保留最后可信内存状态，绝不因此改变四态值。

### 9.4 历史回放与事件去重

repository 启动时记录 live cutoff。`received_at` 早于该 cutoff 的积压事件属于历史回放：文件可用于确认 Hook helper 曾经成功执行，随后删除，但事件业务语义不进入 reducer。UserPrompt、Permission、Input、PostTool、Stop 与 SessionEnd 使用同一条规则，没有终态例外。这样应用崩溃或退出期间遗留的任何 lifecycle 信号都不会在下次启动时伪装成当前状态。

优先使用服务端 event/revision 标识；否则构造稳定去重键：

```text
source + method + threadId + turnId + requestOrItemId + revision
```

所有未知字段与枚举写入脱敏诊断，不让应用崩溃。诊断只保留方法名、版本和枚举标识，不包含正文、路径或凭据。

## 10. 汇总与排序

汇总优先级：

```text
Input needed
> Approval needed
> Running
> Completed
```

ready 且集合为空时为 Idle。availability 非 ready 时，汇总改由全局可用性状态驱动并清空列表。

列表按同一优先级排序，同级按 `observedAtMs` 降序。repository 立即提交顺序，但 UI 在用户滚动或悬停时保留当前可见锚点；变化发生在视口外时显示轻量更新指示。

## 11. 当前内容预览

`PreviewExtractor` 只接收已经面向用户公开的 item：

1. Input needed：当前问题文本。
2. Approval needed：固定 `Approval requested`，不读取命令、路径或理由。
3. Running：最新公开 commentary/progress；否则本轮 prompt。
4. Completed：final answer 开头；没有时保留最后公开进度。

处理步骤：去控制字符 → 合并空白 → 取第一可见行 → 内存限制 → 交给 UI Alpha mask。禁止写日志、数据库、UserDefaults 或诊断包。

`showCurrentContentPreviews == false` 时，extractor 不产生正文，并禁止标题生成器访问 prompt fallback。

## 12. 处理时间（未来考虑）

V1 不实现处理时长：

- `MonitorStore` 不维护 1 Hz UI 时钟，也不派生、格式化或聚合 Running 时长。
- 收起态、展开汇总和会话行统一使用 `MonitorStatus.running.displayName`，即 `Running`。
- 额度区域始终显示 primary rate-limit window 的真实剩余比例；Running 不替换该值。
- `startedAt` 等生命周期元数据只可服务于事件排序或校正，不能形成用户可见计时。

未来若重新引入，必须先验证 Desktop 的权威时长语义，明确 Input/Approval、睡眠和重连时间是否计入，并完成无障碍、功耗与刷新频率评审。在此之前不增加计时器、时长格式化器或秒级一致性测试。

## 13. 额度、今日用量与 Expanded footer

连接成功后在核心会话快照发布之后异步读取两份账户数据：

- `account/rateLimits/read` 的 primary window 提供 `usedPercent` 与 `resetsAt`；圆环继续显示 `100 - usedPercent`。
- `account/usage/read` 的 `dailyUsageBuckets` 提供日期字符串 `yyyy-MM-dd` 和 token 总量。使用目标 Mac 当前 Gregorian 日历与时区生成今天的 key，按 `startDate` 精确匹配；有效数组没有今天时表示今日为 `0`，数组缺失或请求失败表示 unavailable。

账户 fingerprint 每 30 秒校正一次，额度与今日用量最多每 60 秒刷新一次；两份用量请求并发执行，但解析与降级相互独立：今日用量失败不得清空可用圆环，额度读取失败也不得隐藏可用的今日 token 总量。账户标识变化时先同时清空，再读取新账户。不得从 `lifetimeTokens`、`peakDailyTokens`、会话行 token、剩余百分比或旧 snapshot 推算今天的值。

### 13.1 Footer 格式

Expanded footer 固定 `40 pt` 高，位于会话/空状态正文之后且无额外 bottom padding；其顶部 hairline 与 header/正文分隔线使用同一视觉 token。外层跟随面板 `24 pt` 水平 inset，因此 `520 pt` 面板中的 footer 内容宽 `472 pt`。

左侧文案为：

```text
<today token compact value> • <reset text>
```

token 总量使用固定 `en_US` Compact notation 与 `1 ... 3` 位有效数字，保留必要小数并移除尾随零，例如 `13.4K`、`323K`、`2.8M`、`1.03B`；`0 ... 999` 直接显示整数。数据 unavailable 时显示 `--`。

reset 按本地日历日而不是 24 小时浮点时长计算：同一天为 `Resets today`，明天为 `Resets in 1 day`，超过一天为 `Resets in x days`；日期不可用时为 `Reset unavailable`。已经落在今天以前的 stale 时间也钳制为 `Resets today`，等待下一轮账户刷新纠正。

左侧生产字体为 SF Pro Regular `11/14`、secondary text；Figma 中的 Inter 只是 MCP 字体不可用时的渲染替代。右侧使用 `32 × 32` 原生 `Button` 点击目标与 `16 pt` `gearshape`，VoiceOver 名称为 `Open Settings`，调用 SwiftUI `openSettings` 打开现有 `Settings` scene，不在 overlay 内复制设置界面。

失败策略：

1. 单次请求沿用 App Server client 的 15 秒超时；读取失败后保持 UI 可用，并在 60 秒冷却后静默重试。
2. primary 仍失败则额度 unavailable，立即显示灰色圆环；today bucket 仍失败则 footer 使用 `--`。
3. 不保留旧值，不以 lifetime、peak 或其他字段估算。
4. 账户标识变化时先清空额度与今日用量，再读取新账户。
5. 任一账户用量字段失败都不改变 availability、会话状态或导航。

## 14. 精确导航

`CodexDesktopNavigator.open(threadId:)`：

1. 通过 repository 和目标级校正确认 Thread 仍存在、未归档、未删除、可导航。
2. 对 `threadId` 做 URL path-component 编码，构造官方 `codex://threads/<thread-id>`。
3. 使用 `NSWorkspace` 将 URL 定向交给 bundle id `com.openai.codex`；不得退回浏览器或 Codex 首页。
4. 当前没有公开的页面完成回执。运行时成功只表示 Launch Services 接受请求；“打开同一 Thread 且不创建/resume Turn”由版本化端到端兼容测试保证。
5. 请求被接受后收起面板；不主动标记已读。
6. 预检或打开失败时保持面板和行，显示非破坏性反馈并触发集合校正。

禁止：首页 fallback 作为成功、使用未文档化 URL、私有 IPC、Accessibility 点击、标题匹配。

## 15. 可用性与局部降级

| 故障 | UI |
| --- | --- |
| 无活动或未读终态 | 薄层 `No active turns` |
| App Server 已开始连接、会话快照尚未返回 | 薄层 `Connecting to Codex`，≤ 5s |
| 版本过旧 | 清空列表，薄层 `Update Codex` |
| 版本未知/未经验证 | 清空列表，薄层 `Codex version unsupported` |
| App Server 无响应、启动失败或连接断开 | 清空列表，薄层 `Codex disconnected` |
| Desktop 未读主状态缺失、损坏或不兼容 | 保留尚未隐藏的终态行并显示诊断；不得把 backup/LKG 的空集合作为已读证据 |
| 额度失败 | 灰色圆环；列表不变 |
| 某行预览失败 | 隐藏该预览；其他字段不变 |

上述 Notch 薄层不提供按钮。修复/移除集成只在首次引导或 Settings 中执行。

单次 App Server 查询超时不等于连接断开。传输层保留现有连接，UI 继续展示最后一次可信内存快照，并在同一连接上启动至多一个独立探活流程：先等待 3 秒宽限期；其间任意带 `id` 的响应（包括晚到响应）都证明 RPC event loop 仍活跃并取消探活。宽限期内没有响应时，调用官方只读且只访问内存集合的 `thread/loaded/list`，单次最多等待 5 秒；只有该探活也超时且期间仍无任何响应，才重建只读 App Server 传输。并行业务请求超时共享同一个探活，不累计为多次连接失败；远端方法错误和协议错误本身已经收到响应，也不得触发进程重启。该恢复动作不清空 Hook reducer 或最近可信 UI。已有 Ready 等可信状态时，只有 `disconnected` 连续超过 3 秒才发布全局断开状态并清空列表；启动仍为 Connecting 且初始化已确认无响应时直接发布 Disconnected。

尚未建立本次启动后的 Hook 观察时，启动与常规轮询只用最多 5 秒的 `thread/list` 做一次**只读连通性校验**，其结果不得产生任何会话行。请求完成前保持 Connecting；成功返回后发布 Ready 并以空集合聚合为 Idle；App Server 未响应或连接失败才发布 Disconnected。该分支不重建启动前的任何会话（cold-start sync 已明确列为非目标，理由见 PRD 第 3 节），因此也不需要 `thread/loaded/list` 或逐 Thread 详情读取。建立启动后 Hook 观察后，Hook 状态立即发布；后台校正按成本分成两条独立的单飞路径。Hook 跟踪的 Thread 用 `thread/read`（`includeTurns: false`，最多 5 秒，单条元数据陈旧超过 10 秒才重取）刷新标题、preview 与 `status`；全量分页 `thread/list` 只在 Hook 出现从未列出过的 Thread、或 30 秒成员关系到期时运行，最多 15 秒。两条路径各自同一时间只允许一个请求，失败后至少 60 秒再重试，且都不得位于 Hook → UI 关键路径上。服务端不支持 `thread/read`（`-32601`）时只探测一次，之后永久回退为由 `thread/list` 提供元数据，行为退化为旧路径而不丢标题。旧列表仍可提供标题，但其请求开始时间早于最新 Hook 时不得移除该 Turn；Project 与未读元数据分别从第 1.4、1.3 节的 Desktop 状态快照解析。实时 Stop 直接把同一 Turn 标记为 Completed，不发起终态详情读取。额度与今日用量读取也必须在核心会话快照之后异步执行；两个只读请求可并发，失败按第 13 节分别降级。

## 16. 设置与持久化

### 16.1 持久化内容

允许持久化：

- `showCurrentContentPreviews`。
- 用户选择的目标显示器稳定标识；显示器临时断开时不覆盖该偏好。
- 集成安装状态与兼容性结果。
- 已成功接收过合法 Hook 的布尔信任标记；不得包含 Thread、Turn 或内容。
- 非敏感应用版本/迁移标记。

禁止持久化：

- 会话列表快照、thread 标题缓存、Project 缓存、未读状态。
- Hook reducer 的 Turn 身份、lifecycle、pending input/approval evidence；旧版本持久化的 `turns` 只用于迁移信任标记，解码后立即丢弃。
- prompt、progress、final answer、raw reasoning。
- 完整路径、命令、diff、工具参数、凭据、额度旧值。

### 16.2 Settings 行为

- Expanded footer 齿轮：调用系统 `openSettings` 打开现有 Settings scene；不安装集成、不修改偏好，也不在 panel 中创建第二份设置 UI。
- `Display`：立即将组件移动到所选显示器；目标临时不可用时回退，并在重新连接后恢复用户偏好。
- `Recheck`：重新运行只读能力检查，不静默改配置。
- `Codex integration` 总开关：On 安装或修复六种必需事件定义，Off 只移除本应用管理的配置片段并清空 repository；关闭后 Settings 保持可达。切换期间控件 disabled；失败恢复切换前显示状态并给出非破坏性错误。首次安装或定义变化后仍由用户在 Codex `/hooks` 中审核，应用不得改写信任状态。
- `Show current content previews`：立即影响所有行；关闭时清空内存预览并重新生成安全标题。

## 17. SwiftUI 接入边界

当前产品 UI 层只依赖稳定 view model：

```swift
@MainActor
protocol MonitorViewModelProtocol: ObservableObject {
    var availability: IntegrationAvailability { get }
    var aggregate: AggregateState { get }
    var quota: QuotaSnapshot { get }
    var sessions: [MonitoredThreadSnapshot] { get }
    var privacy: PrivacySettings { get }
    func open(threadId: String) async
}
```

Mock 与真实实现共享协议，Preview/测试继续使用 Mock；生产入口注入真实 repository。SwiftUI 不直接解析协议事件、不读取本地文件、不构造导航 URL。

几何继续由现有 AppKit overlay 负责：使用完整 `NSScreen.frame`，所有中间帧保持相同 `midX` 与 `maxY`；顶部高度来自目标菜单栏。三行会话展开总高为 `menuBarHeight + 280`（`240` viewport + `40` footer），空/全局状态为 `menuBarHeight + 88`（`48` body + `40` footer）。因此 `46 pt` 参考分别是 `326` 与 `134`，无刘海 `24 pt` 三行参考是 `304`。

## 18. Phase 0 验证计划

1. **版本与 schema**：记录 Desktop/内嵌 CLI 版本，生成/读取官方 schema，构建未知字段兼容 fixture。
2. **同 runtime 可见性**：证明观察器能被动看到 Desktop 当前活动 Turn，不需要 resume 或接管请求。
3. **请求状态**：分别验证 Input、由 `waitingOnApproval` 确认的 Approval 出现/解决及 Running 恢复；验证单独 `PermissionRequest` 和自动审查不会误报 Approval。
4. **终态与未读**：验证实时 Stop 与 App Server 三种结束结果都使 Running 直接进入 Completed；验证终态未读保留，Desktop 阅读后即时移除。
5. **Project/Chats**：覆盖单仓库、多仓库 Project 与无 Project Chat。
6. **删除/归档**：验证事件与集合校正都能自动移除；确认 closed 不等于 deleted。
7. **Running 展示**：验证收起态、展开汇总和会话行均显示 `Running`，且不存在逐秒变化的计时文本。
8. **额度与今日用量**：验证 primary、多窗口字段、`account/usage/read` 当天 bucket、账户切换、15 秒请求超时、60 秒重试与相互独立的 unavailable。
9. **导航**：adapter 与单元测试已完成；仍需在版本矩阵中端到端验证进入相同 Desktop 页面且不创建/恢复 Turn。
10. **多客户端安全**：证明 observer 不响应 Desktop 的 server request、不改变运行状态。

产物为能力矩阵、脱敏事件时序、版本兼容表和 go/no-go 结论。

## 19. 实施阶段

### Phase 1：集成骨架

- 安装检测、版本 gate、首次引导与 Settings 存储。
- observer/reconciler/reducer 协议与 fixture。
- 生产 ViewModel 注入，但 UI 仍可切换 Mock。

### Phase 2：真实监视器

- 活动 + 未读终态集合。
- Project/Chats、真实标题、状态与预览。
- 主额度窗口、今日 token footer、局部降级；Running 只显示状态名称。
- 三行滚动、排序锚点与空/断开薄层。

### Phase 3：导航与发布

- 维护官方 `codex://threads/<thread-id>` 精确导航的版本兼容表与端到端样本。
- 安装修复/移除、账户切换、睡眠/重连校正。
- 签名、公证、性能、无障碍和隐私审计。

## 20. 测试策略

### 20.1 单元测试

- reducer 合法/非法转移、乱序与重复事件。
- 缺失 `session_id/turn_id` 失败关闭；旧 Turn 的 Permission/Stop 不能改变新 Turn。
- `request_user_input` 只被相同 `tool_use_id` 的 Post 清除；无关 Post 不清除 Input 或 Approval。
- 启动前积压的 UserPrompt/Permission/Input/PostTool/Stop/SessionEnd 都不进入 Turn reducer；持久化文件只保留布尔配置健康标记，迁移旧 `turns` 后内存仍为空。
- 监视成员集合的 active/unread/archive/delete 规则。
- 四态合法流转、Completed 粘性与汇总优先级。
- Project 无近似回退、标题隐私回退。
- Desktop Project 私有状态的 local/remote/Chats 精确解析、`thread.section` 隔离、主文件/backup/last-known-good 降级，以及缺失 assignment 显示 `Project unavailable`。
- Running 状态名称与额度读数不受时间推进影响。
- Compact token 数字边界、今天/明天/多日 reset 文案与本地时区日界线。
- 额度/今日用量账户切换、15 秒请求超时、60 秒重试和独立 unavailable。
- 并行业务超时只启动一个 `thread/loaded/list` 探活；探活成功或宽限期内收到晚到响应时不重启，探活也超时时才重建传输。
- 有会话与无会话 footer 都为 `40 pt`，展开高度分别包含 `280`/`88 pt` 内容区。
- Settings gear 的无障碍名称与现有 Settings scene 打开行为。
- Settings 关闭预览后内存清空。

### 20.2 集成测试

- 三个并发 Thread：Input、Running、未读 Completed。
- 同名 Thread、同名 Project 不合并。
- 多仓库 Project 与 `Chats` 显示一致。
- Desktop 阅读、归档、删除自动移除。
- Codex in Notch 重启无缓存闪现并正确重建。
- Desktop 未运行、低版本、未知新版本与重连。
- 点击每一行进入相同 Thread；不存在目标保持面板。

### 20.3 隐私与安全测试

- 扫描数据库、UserDefaults、日志、诊断包，确认无正文、路径、命令、diff、凭据和旧额度。
- 确认不申请 Accessibility/Screen Recording。
- 确认 observer 不发送会改变 Thread/Turn 的方法。
- 确认移除集成不会删除用户其他配置。
- 确认总开关 On/Off 分别安装与移除完整六项集合；缺少、重复或 matcher/handler/timeout 被改写时进入 `repairRequired`，重新开启可修复且不删除用户其他 Hooks。

## 21. Figma 对应

| 页面/节点 | 技术契约 |
| --- | --- |
| `Notch Core` / `118:120` | `520 × 326` 共享展开、顶部 `46`、底部 `40` footer |
| `05 — Panel` / `327:305` | `472 × 40` Expanded footer、今日 tokens、reset 文案与 Settings gear |
| `06 — Integration States` / `227:3` | 隐私关闭、额度局部降级、成员生命周期和 `520 × 134` 薄层状态 |
| `07 — Onboarding` / `232:95` | 显式授权的三步首次安装 |
| `08 — Settings` / `233:3` | 集成管理与预览开关的 On/Off 状态 |

## 22. 参考

- [Codex App Server](https://developers.openai.com/codex/app-server)
- [Codex Hooks](https://learn.chatgpt.com/docs/hooks)
- [`CONTEXT.md`](../CONTEXT.md)
- [`docs/adr`](adr/)
