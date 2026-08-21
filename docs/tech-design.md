# Codex in Notch — Codex 集成技术设计

| 字段 | 内容 |
| --- | --- |
| 文档状态 | 第一实现切片、精确导航、Desktop Project 身份、两侧的未读终态移除与 Expanded footer 已实现；真实版本矩阵仍待验证 |
| 版本 | 0.19 |
| 日期 | 2026-08-15 |
| 范围 | 将 SwiftUI 原型中的 Mock 状态、额度、今日 tokens、会话列表与点击导航替换为真实 Codex Desktop 数据；处理时间按第 12 节实现 |

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
- 使用 `UserPromptSubmit`、`PermissionRequest`、`PreToolUse`（catch-all，reducer 内按 tool 名过滤）、`PostToolUse` 和 `Stop` 建立 Turn 生命周期事件桥；所有状态事件必须携带精确 `session_id + turn_id`，输入请求与两种审批形态都必须用相同 `tool_use_id` 成对关闭。事件文件采用用户私有权限、消费后删除，目前只含身份与生命周期。
- 标题使用 Thread 元数据，按成本分两层获取：Hook reducer 当前跟踪的 Thread 用 `thread/read`（`includeTurns: false`，实测约 1.2 KB/线程）按 id 读取，全量分页 `thread/list` 只负责低频成员关系对账（实测 33 个线程约 45 KB，且随历史线性增长）。`thread/list` 按契约**永远返回空 `turns`**（schema：`turns` 仅在 `thread/resume`、`thread/rollback`、`thread/fork` 和 `includeTurns: true` 的 `thread/read` 上填充），因此任何 Turn 级事实都只能来自 Hook reducer。Project/`Chats` 使用 Desktop 私有全局状态中的精确 thread assignment，绝不把 `thread.section` 当成 Project。未读终态成员关系只读消费同一 Desktop 全局状态中的本地未读集合；活动会话始终显示，只有权威主文件确认终态已读后才隐藏。会话状态只包含 Running、Input needed、Approval needed、Completed；实时 `Stop` 以及 App Server 的 `completed`、`failed`、`interrupted` 都直接收敛为 Completed，不再读取 Thread 详情区分结束原因。
- Preview 始终显示，没有开关；缺少 Desktop 标题时回退到本轮 prompt，仍取不到才显示 `Untitled`。Codex 侧的 prompt/回答片段经 Unix socket 从 helper 交到运行中的进程内存，见第 11 节。
- `MonitorStore` 替换生产 Mock，事件活跃时 1 秒校正、断开时 5 秒静默重试；首次收到合法 Hook 后只持久化不含会话身份与内容的布尔配置健康标记。应用重启时 reducer 从空集合开始，启动前积压的所有 Hook（包括 Stop 与 SessionEnd）一律不恢复或修改 Turn；只有本次进程启动后的 Hook 才是实时证据，也是四态状态的唯一来源。Running 直接显示状态名称，额度区域始终显示真实剩余比例；空列表与全局状态采用薄层展开 UI。
- 会话行通过官方 `codex://threads/<thread-id>` deep link 打开同一 Codex Desktop 会话；打开前强制刷新全部未归档根 Thread，目标不存在时拒绝导航。URL 只定向交给 bundle id `com.openai.codex`，Launch Services 接受后才收起面板。

已经通过本机当前 Codex 版本验证：App Server 握手、真实额度响应、Thread/Turn schema、Desktop Project 与未读私有状态解析、Hooks 配置合并、事件 reducer 与精确导航 adapter。未读适配器的主/备份/last-known-good、私有 schema 失败、原子替换目录事件、settling window 与端到端已读移除均有单元测试。应用构建与单元测试已通过。

尚未满足、因此仍阻塞 V1 发布：

- 独立 App Server 不共享 Codex Desktop 的进程内事件流，且实测无法回答 Turn 级问题（见下），因此启动不做现状同步：只要 App Server 完成握手并成功返回一次 `thread/list`，即发布 Ready 并以空集合发布。在场此时已经可知（Codex Desktop 是否在运行），所以收起态可以诚实地显示 `Connected` 而对轮次一无所知——这处不对称是刻意保留的：在场在本应用启动的瞬间就可知，轮次不可知。只有 App Server 没有响应或连接失败才显示 `Disconnected`；校验请求尚未完成时保持 Connecting。跨 Codex in Notch 重启持久化的 Hook 标记只用于配置健康判断，不得恢复任何会话状态。
- **实测边界（Codex CLI `0.148.0-alpha.9`，在一个真实运行中的 Turn 上采样）**：独立 App Server 的 `thread/loaded/list` 返回空；所有 Thread 的 `status.type` 恒为 `notLoaded`；`thread/list` 契约上永不返回 `turns`；`thread/read` 即使带 `includeTurns: true` 也从不出现 `inProgress`——正在运行的 Turn 被记为 `interrupted` 且 `completedAt` 为 null。直接后果：依赖 `status.type == "active"` 的 `activeFlags` 校正在当前拓扑下**永远不成立**。该机制（`activeEvidence`、`terminalStatus`、`reconcileActiveStatus`、`markCompleted` 与 `hasLiveBoundary`）已整体删除，因为保留空转代码会让后续设计误以为存在这条能力。若将来出现共享运行时拓扑，应基于当时验证过的字段重新设计，而不是复活这段代码。
- 当前公开协议仍没有 Desktop 蓝点对应的已读字段；生产实现依赖第 1.3 节登记的 Desktop 私有只读 schema。Desktop 升级后的真实 read/unread 版本矩阵仍是发布验证项，任何不兼容都必须保守保留终态行。
- Hooks 可以可靠覆盖开始、两种审批形态、`request_user_input` 和终态边界；Approval needed 一律由某个工具调用的开合区间证明（专用审批工具自成区间，普通工具由 `PermissionRequest` 指名并借用其仍打开的调用 id），孤立的 `PermissionRequest` 不证明仍需人工批准。App Server 的 `completed`、`failed`、`interrupted` 都映射为 Completed，仍需真实 Desktop 样本矩阵验证端到端覆盖。
- `threadSource/sourceKinds` 仍不足以单独证明 Desktop 与独立 IDE 来源边界，必须继续以真实样本验证。

### 1.2 已读移除与精确导航能力边界

- 官方 [Codex Desktop deep links](https://learn.chatgpt.com/docs/reference/commands#deep-links) 已定义 `codex://threads/<thread-id>`。导航 adapter 已按本节约束实现；Codex 当前仍不提供页面完成渲染的公开回执。
- 官方 [Codex App Server](https://learn.chatgpt.com/docs/app-server) 当前没有 unread/read/open/current-view 字段或通知。`thread/read` 是读取 Thread 记录，不是标记已读；`thread/loaded/list` 与 `thread/closed` 也不表达蓝点语义。
- 当前 Desktop 安装包内部把蓝点集合持久化在 `$CODEX_HOME/.codex-global-state.json` 的 `electron-persisted-atom-state.unread-thread-ids-by-host-v1.local`。经产品批准，本字段已作为独立、已登记的私有只读适配器进入生产；它不扩展到其他 Electron 状态或 IPC。
- 实现必须处理原子替换与短暂主/备份代际差异；活动 Turn 无论蓝点如何都继续显示，只有终态 Turn 在主文件权威快照中从 unread 集合消失后才移除。不得注入 IPC、修改 `app.asar`、使用 Accessibility/AppleScript，或把 Stop/SessionEnd 当作已读。
- Developer ID 直接分发在关闭 App Sandbox 时技术上可读取该路径；Mac App Store sandbox 需要用户选择目录与 security-scoped bookmark。无论分发方式如何，文件可读都不等于接口受支持。
- 长期方向仍是迁移到 Codex 未来公开的 `hasUnreadTurn` 快照与变化通知；出现等价公开能力时必须在同一改动中移除私有适配器与清单行。
- **Claude Code 一侧没有等价的 deep link。** `claude-cli://open` 与 `claude://code/new` 都只新建会话，实测 `claude://code/sessions/local_…` 被 Desktop 拒绝。因此那一侧实现为宿主唤起（§14.2），并按 [ADR 0004](adr/0004-make-exact-desktop-navigation-a-release-gate.md) 只对该产品降级。每次 Claude Desktop 更新后复查 `/code/sessions/` 路由是否开始接受本地会话 ID；一旦官方支持出现，应迁移到 deep link 并移除 Apple Events 路径。

### 1.3 Desktop 未读私有只读适配器（已实现）

对当前 Desktop `26.810.50856` build `6644`、CLI `0.148.0-alpha.9` 的只读核验表明：

- 状态根目录是 `process.env.CODEX_HOME ?? ~/.codex`；默认文件为 `.codex-global-state.json`。
- 未读集合位于 `electron-persisted-atom-state.unread-thread-ids-by-host-v1.<hostID>`；本地 V1 只能消费 `local`，不能合并其他 host。
- Desktop 自身在状态变化后等待约 `500 ms` 再持久化；写入通过同目录临时文件 `rename` 原子替换主文件，随后独立替换 `.bak`。因此目标 inode 会变化，主文件与 backup 也可能短暂属于不同 generation。
- 这是真实的 Thread 级蓝点集合，没有 Turn id。它只能与“每个 Thread 展示最新活动或未读终态 Turn”的领域模型组合。

生产实现采用以下架构：

1. `CodexDesktopUnreadStateRepository` 默认只读 `$CODEX_HOME/.codex-global-state.json`，并支持测试/隔离环境用 `CODEX_IN_NOTCH_CODEX_HOME` 覆盖 Codex Home。
2. 目录级 `DispatchSourceFileSystemObject` + `O_EVTONLY` 监听 Codex Home，而不是长期监听目标文件 inode；目录事件采用 `250 ms` trailing debounce 并触发刷新。watcher 挂不上时的兜底是 `nextRefreshDeadline()` 与 60 秒心跳，不是轮询。
   **挂载不是一次性的。** 目录不存在（首次运行时 Hook 事件目录要等安装器创建）或被删除／替换（卸载后重装、Codex 整体换掉状态目录）都必须能恢复：watcher 收到 `rename`／`delete` 就重开描述符，`HookEventRepository.consumeEvents` 与未读 repository 的 `snapshot` 也各自在本来就要做的那次刷新上顺手重试一次，安装成功后再显式催一次。**刻意不设自己的重试定时器**——挂不上的代价因此是每次刷新一个失败的 `open`，而不是一个额外的唤醒源。
3. 只解析 `local` host 的字符串集合，同时校验所有 host 名称、空 id 与重复 id。读取器拒绝 symlink、非当前用户普通文件、超过 4 MiB 的文件、异常 JSON 与不兼容 schema；不记录原始 JSON 或 Thread id。
4. 主文件失败时读取 `.bak`，两者失败时保留进程内 last-known-good。但 backup 和 last-known-good 只用于保留数据与诊断，只有 `source == current` 的主文件快照可以做新的隐藏决定；解析失败绝不能解释为空集合。
5. 活动、Input、Approval 始终显示并清除该 Turn 的终态 gate。终态首次出现且主文件暂未包含 unread 时保留 2 秒，覆盖 Desktop 约 500 ms 的持久化延迟；已经观察过 unread 后再从权威主快照消失则立即隐藏。隐藏 gate 在临时解析失败时保持隐藏，避免 UI 闪回；新终态在失败期间继续显示。
6. `MonitorStore` 同时消费目录变化流和原有轮询；统一的 in-flight gate 合并并发刷新。停止监视、关闭集成或清空列表时清除终态 gate。

适配器已经覆盖成功、缺失、损坏、backup、last-known-good、schema 不兼容、原子替换和终态竞态 fixture；Desktop 更新后仍必须执行真实 read/unread 与完成/阅读竞态矩阵。目标是 p95 同步不超过 1.5 秒、p99 不超过 2 秒，且任意错误都不提前移除终态行。当前 Developer ID 非沙箱构建可读取该路径；Mac App Store sandbox 仍需要用户选择目录与 security-scoped bookmark，未经实现不得声称支持。

其他路径的独立研究没有找到公开且准确的替代方案：

- App Server、Hooks、通知、JSONL、SQLite、窗口焦点与 deep-link 回调都不表达“用户已阅读”。
- 当前 Desktop 私有 Unix socket `~/.codex/ipc/ipc.sock` 会广播 `thread-read-state-changed` delta，但没有初始完整快照；连接者必须注册为内部 IPC client、参与 discovery，可能影响路由与超时。它的风险和版本耦合均高于纯只读文件，因此不采用。
- Accessibility、AppleScript、标题匹配、定时移除或“Desktop 获得焦点即已读”均不准确并违反安全约束。（本条为 Codex 而写。Claude Code 一侧的例外经产品批准，见 [ADR 0012](adr/0012-read-state-is-answered-per-product-or-not-at-all.md)：那里没有别的来源，而「哪个会话在屏幕上」有记录可查，所以焦点说的是**那一个**会话而不是「所有 thread 都已读」。Accessibility、AppleScript、标题匹配与窗口几何在两侧都仍然禁止。）
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

### 1.5 Claude Code 已读适配器（已实现）

Claude Code 一侧此前没有任何已读来源，终态行只能靠下一次提交、会话消失或手动清空退出（CC-013）。它现在分成两半，**证据来源完全不同**：Desktop 托管的会话读 Claude Desktop 的私有记录（下文 1–7），终端里的会话读内核记的控制终端访问时间（下文 §1.5.1，不涉及任何私有 schema）。产品语义与两半的分工见 [ADR 0012](adr/0012-read-state-is-answered-per-product-or-not-at-all.md)；这里只记实现。

对 Claude Desktop `1.32885.1`、CLI `2.1.235` 的只读核验（2026-08-19）表明：

- 每个 Desktop 托管会话在 `~/Library/Application Support/Claude/claude-code-sessions/<org>/<account>/local_<uuid>.json` 有一份记录，其中 `cliSessionId` 就是 hook 携带的 `session_id`，因此身份连接不需要推断。
- `lastFocusedAt` 由 `setSessionVisibility(id, isVisible, reason)` 在 `isVisible` 为真时写成 `Date.now()`，随即 `saveSession`。它的语义是"最后一次被显示到屏幕上"，不是"最后一次活动"。
- 写入是同目录临时文件 `rename` 原子替换（实测 inode 变化），因此**目录级** watcher 能看见它——这与 `~/.claude/sessions/<pid>.json` 的原地重写相反，那里只有文件级 watcher 有用（见 §15.1）。
- 纯终端会话在这棵树里没有任何文件，Claude Code 自己的会话记录也不写任何 focus 字段（2.1.235 与 2.1.236 二进制内检索：无 focus/read/seen 落盘键；进程内有一个 `userPresence` 对象持有 `lastInteractionTime` 与 `terminalFocus`，但它不落盘、不发 hook）。**那一半因此不问 Claude Code，改问它的终端——见 §1.5.1。**

生产实现：

1. `ClaudeCodeDesktopReadStateRepository` 默认读 `~/Library/Application Support/Claude/claude-code-sessions`，可用 `CODEX_IN_NOTCH_CLAUDE_DESKTOP_HOME` 覆盖 Claude Desktop 的 application-support 根目录。目录结构按 `<org>/<account>` 恰好两级枚举，不做递归搜索。
2. 每条记录只解码四个字段：`cliSessionId`、`sessionId`（Desktop 自己的 `local_<uuid>`，即它的日志在屏幕上点名的那个 id，用来把日志接回 hook 的身份）、`lastFocusedAt`、`isArchived`。同一文件里的标题、`cwd` 与 MCP 配置一律不解码。读取器拒绝 symlink、非当前用户普通文件与超过 4 MiB 的文件。
3. **按 `(size, mtime, inode)` 缓存解析结果**，每次读取只打开真正变化过的记录。本机 31 份记录（约 2 MB）实测首读 5 ms、全部命中缓存 1 ms。记录数超过 512 时按 mtime 取最新的 512 份——活着的会话必然是最近被显示或恢复过的那些，尾部答 unknown 并保留其行。
4. 判定分两层。文件这一层在 provider 里：`readState(forSession:terminalBoundaryAt:)` 用 Turn 自己的终止时刻做比较左边（`HookTurnState.lastEventAt`），`lastFocusedAt >= boundary` 即已读，`isArchived` 同样为已读，**记录不存在则是 unknown 而不是未读**。跨来源的那一层在编排器里（`AGENTS.md` §6.1「决策跨数据源就属于编排中心」），文件说未读时还有三条，各自补一个文件里没有的事实：
   - **`comingBackShowedIt`**：`isOnScreen(该会话)`，且 `DesktopActivationReporting.lastActivation()` 晚于 `boundary`。
   - **`isInFrontOfThem`**：`isOnScreen(该会话)`，且 `DesktopReadingReporting.isInFrontOfTheUser()` 为真。**全应用唯一一条不比较任何时刻、也不要求用户做任何事的判定**，因而也是唯一一条可能撤掉没人读过的行的判定；权衡见 ADR 0012 第三条。
   - **`movedOnFrom`**：本应用曾在某次刷新看见该会话带着 `.completed` 的行在 Claude Desktop 的屏幕上，而 Desktop 此后把**另一个会话**放了上去（`hasReplacedItOnScreen`）。这份成员关系记在 Turn 上不记在会话上——行一旦重新变成非 `.completed` 就清掉——并且随会话离开列表一起清掉。

   **三条问的是同一个问题——「屏幕上的是不是它」——而这个问题有两个来源，见 §1.5.2。** 记录只答得出一半：`setSessionVisibility` 只在会话**被放上屏幕**时盖章，会话被拿下来时什么都不写，所以用户切到一个**新会话的输入框**之后，最后被盖章的那个会话会继续冒充「在屏幕上」。`isOnScreen` 因此是记录与 Desktop 日志两个来源的**取交**，`hasReplacedItOnScreen` 还要求顶替它的是一个**会话**——输入框不是会话，为它腾地方不等于有人读完走开。

   **后两条都是实测逼出来的，不是补强。** 2026-08-19 实机：用户切走、等轮次跑完、切回同一个会话读完，整个 `~/Library/Application Support/Claude` 树在 6 分钟内 **0 个文件**被修改；同日复查确认安装包里根本没有已读字段（`lastReadAt`/`hasUnread`/`seenAt`/`viewedAt` 0 命中）。（同一次复查还写下过一句「`main.log` 里的 `setFocusedSession` 只是 `lastFocusedAt` 盖章时刻的子集」——**那句话是错的，2026-08-19 晚上被一条丢行的实测推翻**：它在**关键的那一个方向上是超集**，因为它还会写 `sessionId=null`，而那正是记录写不下来的一半。见 §1.5.2。）产品语义、被推翻的两条既有规则与代价见 [ADR 0012](adr/0012-read-state-is-answered-per-product-or-not-at-all.md)。
   激活信号来自公开的 `NSWorkspace.didActivateApplicationNotification`（`DesktopActivationWatcher`），按 bundle identifier 过滤，只记录**跃迁**的时刻、从不记录「此刻是否在前台」，且只知道本应用启动之后发生的激活。
   「在不在人眼前」来自 `DesktopReadingWatcher`：同一个公开通知维护「那个应用此刻是否持有前台」（构造时从 `NSWorkspace.frontmostApplication` 读一次种子，之后只由通知驱动），再减去三种持有前台但等于没有的状态——`CGDisplayIsAsleep` 显示器休眠、`CGSessionCopyCurrentDictionary` 报告锁屏或不在 console、公开的 `com.apple.screensaver.didstart` / `didstop` 报告屏保在跑。三者全部公开、无需 entitlement、实测不弹授权；会话字典读不出来时答 `false`，即朝保留的方向倒。隐藏应用不单列（隐藏会交出前台）；**最小化、另一块显示器、另一个 Space 无法分辨**，落在这三种状态里的行会被没人看见地撤掉，这是被接受的代价而不是缺口。
   曾经上线过一版用「一次按键或滚动」当证据的实现（`c1052bb`，`CGEventSource.secondsSinceLastEventType` 取 `.keyDown` 与 `.scrollWheel`），它更安全但答不了「坐着看完、什么都不做」，已被本条取代；细节与它的一处硬伤记在 ADR 0012 的拒绝清单里。
5. 复用 Codex 侧的 `TerminalUnreadMembershipGate`：每次刷新由服务把判定结果折成一个未读集合交给它，settling window、"观察过未读后立即隐藏"和 `retain` 规则完全一致。**问不出来的行根本不进 gate**（既无 Desktop 记录、也无控制终端），因此不会为一个没有答案的问题每秒复查一次；它们的退出条件仍是下一次提交、会话消失或手动移除（在该行上右键，或清空整张列表）。**gate 收到的未读快照按行分成两份**：Desktop 判出来的那些带 Desktop 读数的 source（`unavailable` 时不得隐藏任何行），终端判出来的那些带 `.current`。这一分不是修饰——从没开过 Claude Desktop 的用户整棵树都不存在，读数恒为 `unavailable`，让终端结论借用它就等于在最需要这条路径的机器上把它整个关掉。它同时是诚实的：Desktop 的 source 存在是因为读数可能落后一个 generation（解析失败后保留的快照带着旧的 focus 时刻），而设备访问时间不可能落后——它在用到它的那一次刷新里现读，读失败答 `nil` 并把该行**移出** gate，而不是带着陈旧结论进去。
6. 边沿有两个：Claude Desktop 写记录，以及它回到前台。后者直接来自激活通知，因此「切回去读」这个手势与行离开 notch 是同一件事，不需要等 gate 的 1 秒复查。**`isInFrontOfThem` 没有边沿**：它要三个状态同时成立（前台、显示器、锁屏），因此在 gate 已经为等待中的行预约的 1 秒复查上采样，那个 1 秒同时是它的上界；没有行在等的时候不产生任何采样。用户点亮屏幕或解锁之后行的消失也走这一秒。前者来自 `PathSetChangeWatcher`——一个可以随时替换被监听路径集合的 watcher，`ClaudeCodeSessionRecordWatcher` 与本适配器共用它。适配器监听状态根目录加每个发现到的账户目录；账户目录在第一次读取时才被发现，新账户由根目录的边沿或心跳发现。
7. 失败一律 fail closed：树不存在（纯终端用户的常态）是 `unavailable` 且**不产生诊断**；单份记录读不出只让那个会话答 unknown；**全部记录都读不出**才判定为 schema 不兼容，发出诊断并保留 last-known-good，此时不做任何新的隐藏。

#### 1.5.2 屏幕上是哪个会话：记录之外还要问 Desktop 的日志（已实现）

上面三条都建立在一句话上：**这个会话正是 Claude Desktop 摆在屏幕上的那个**。记录只能答一半，而缺的那一半会丢行。

实测（2026-08-19 晚，Claude Desktop `1.32885.1`，用户没有读过那一行）：

| 时刻 | 用户做了什么 | 记录里写了什么 |
| --- | --- | --- |
| 21:02:30 | 切到会话 A | `lastFocusedAt` ← now |
| 21:03:30 | 打开一个**新会话的输入框** | **什么都没有** |
| 21:03:58 | A 的 Turn 结束 | 行变成 Completed；本应用仍以为 A 在屏幕上，于是把「结束时在屏幕上」记给了它 |
| 21:04:18 | 发出新会话的第一条消息 | 新会话被显示 → `movedOnFrom(A)` 成立 → **行被当作读过而移除** |

同一份陈旧判断也会更早地经 `isInFrontOfThem` 丢行（Claude Desktop 在用户敲输入框时持有前台），以及经 `comingBackShowedIt` 丢行（用户回到窗口来发送）。

**Claude Desktop 自己把这件事说出来了**，在它自己的日志里，而且两个方向都说：

```js
setFocusedSession(e){ log.info(`[CCD] LocalSessions.setFocusedSession: sessionId=${e ?? `null`}`), … }
```

每次导航都调用一次，`info` 无条件写出，`null` 正是记录写不下来的那一半（输入框、Home、设置页）。实测每次导航写成 `null` 后紧跟着目的地（另一个会话则再写一行 id，仍是 `null` 则表示屏幕上不是会话）。

`ClaudeDesktopFocusLogReader` 因此读 `~/Library/Logs/Claude/main.log`（可用 `CODEX_IN_NOTCH_CLAUDE_DESKTOP_LOG` 覆盖），答 `.session(desktopSessionID:)` / `.nothing` / `.unknown` 三种：

1. **只认本应用看着被追加进来的那些行。** `AGENTS.md` §6.2：业务状态只能来自当前快照或本进程启动之后观察到的事件。启动时（以及日志被轮转、被截断之后）那份历史只读一次，并且**只允许它说一件事：`.nothing`**——那个方向只会让行多留一会儿，是产品本来就愿意付的代价；历史里点名的会话一律答 `.unknown`。
2. 每次读取 `stat` 一次，按 (inode, size) 决定是续读还是重来，单次最多读 256 KiB（本机日志约 800 KiB/天），**只解析到最后一个换行为止**——正在被写的半行会带着半截 id，而半截 id 恰好会被读成「屏幕上是别的会话」。
3. 只匹配上面那一种行、只取 `sessionId=` 后面那一段；其余每一行都不解析。拒绝非当前用户的普通文件之外的一切；不写入。
4. 文件消失或读不出来时**保留最后一次陈述**（Desktop 不再说话不等于它收回了上一句），只忘掉读到哪里。

**它在编排器里是一个否决权，不是第五个来源**（`ClaudeCodeMonitorService.isOnScreen` / `hasReplacedItOnScreen`）：只能拦下记录声称的那个会话，不能提名记录没声称的会话，`.unknown` 就是没有这份日志之前的原样行为。因此日志缺失、被轮转、或某个未来版本改了行的形状，最坏只是退回旧行为，不会提前撤掉任何一行。`local_<uuid>` 到 hook 身份的连接来自记录里的 `sessionId`（§1.5 第 2 条）；接不上的 id 一律读成「不是这个会话」。

**上面那句「否决权，不是来源」有一处例外，是实测逼出来的（CC-024）。** `hasReplacedItOnScreen` 曾经也按那条写：先要求**记录**已经点名了别的会话，再让日志否决。问题在于两个来源说的是同一件事、却不在同一时刻说。实测（2026-08-20 本机）：

| 时刻 | 发生了什么 |
| --- | --- |
| 11:14:41.910 | Desktop 盖下 `lastFocusedAt`，同一瞬间把导航写进日志 |
| 11:14:42.257 | 它为被打开的会话拉起的 CLI 写下 `~/.claude/sessions/<pid>.json`，这条目录边沿唤醒一次刷新 |
| 11:14:42.938 | Desktop 自己的记录才落盘（比盖章晚 1.03 秒） |

中间那一秒里，日志已经点名新会话，而最新的那枚 `lastFocusedAt` 仍是**刚被离开的那个会话自己的**。于是它既不在屏幕上（日志否决），也没有被顶替（`hasReplacedItOnScreen` 问的是记录，记录没动）——四条已读路径同时落空，行被重新报成未读。用户看到的就是：**在两个已结束的会话之间切换时，Claude Code 的点阵会像完成信号那样亮一下，随即熄灭**。

修法是让这一个问题由日志自己回答，记录只在日志答 `.unknown` 时顶上。这不是一个新判断，只是把记录一秒之后给出的同一个判断提前；而且它仍然只是「屏幕上是谁」的陈述，把它变成「读过了」的是 `movedOnFrom`，后者只对已经带着结束的 Turn 出现在屏幕上过的会话成立。

**接不上的 id 在这里必须分成两种，否则会赔掉 §1.5.2 最后一句。** 日志点名的 `local_<uuid>` 连不回任何 hook 身份时，既可能是**记录还没写**（正是本条要处理的那一秒），也可能是**记录不再携带自己的 `sessionId`**（§1.5 第 2 条的降级形态）。后者按「不是这个会话」读是对的，按「别的会话顶替了它」读却会凭一个谁也没核实过的名字撤行。分开它们不需要等任何东西：拿**这个会话自己记录里的** Desktop id 去比——记的是另一个 id，那屏幕上就不是它，无论那份待写的记录最后说什么；自己那份记录根本没有 id，就退回记录单独作答，即读日志之前的原样。

**第二处修改在 gate 里，与来源无关：隐藏一旦做出，对那一个已结束的 Turn 就是终局**（`TerminalUnreadMembershipGate`，两个产品共用）。它此前一读到「又变未读」就把行放回来，等于让行成为各来源当下说法的实时读数，而这些来源是另一个应用按自己的节奏写的文件——两边短暂不一致是常态而非异常，每一次都会把已经撤掉的行闪回通知栏。在同一个已结束的 Turn 内没有任何途径重新变成未读，所以拒绝它不损失什么；唯一能让行回来的是**更晚的一个 Turn 结束**（`terminalBoundaryAt` 前进），而新 Turn 通常先经过运行态、gate 在那一步就把条目整个丢掉了。

**它没有自己的边沿。** 只有它能看见的那个跃迁（会话让位给输入框）只会保留行，而列在通知栏里的终态行本来每秒复查一次；能撤掉行的跃迁都伴随 Desktop 写记录或 hook 到达，那些边沿已经存在。为它单独挂 watcher 等于为 Claude Desktop 记的每一行 oauth 与 git diff 计时买一次唤醒。

#### 1.5.1 终端会话：控制终端的访问时间，加上那个终端在不在人眼前（已实现）

Desktop 那棵树对终端会话什么都不说，而 Claude Code 自己没有已读概念。这一半因此换了个对象问：**该会话的控制终端**。

`ControllingTerminalGestureReader` 一次读出**两个事实**，全部是公开 BSD 接口加一条公开的 workspace 通知，不打开任何文件内容：

1. `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_PID, pid)` → `kp_eproc.e_tdev`，该进程的控制终端设备号（`-1` 即没有控制终端）。pid 来自公开命令 `claude agents --json`，与 `~/.claude/sessions/<pid>.json` 的命名用的是同一个。
2. `devname_r(dev, S_IFCHR, …)` → `ttysNNN`，拼成 `/dev/ttysNNN`。**回查一次**：`stat` 出来必须仍是字符设备且 `st_rdev` 等于第 1 步那个设备号——`devname_r` 答的是一份按设备号缓存的名字表，名字被复用会把别的终端的动作算到这个会话头上。
3. `stat` 的 `st_atimespec`——**手势**这一半。
4. 同一个 `sysctl` 的 `kp_eproc.e_ppid` 逐级向上，看**前台应用的 pid 是不是这个会话的某一级祖先**——**在不在人眼前**这一半。链路在本机实测是 `claude` → `-/bin/zsh` → `/usr/bin/login` → `Ghostty`，最多走 16 级。前台 pid 由 `NSWorkspace.didActivateApplicationNotification` 维护（与 `DesktopReadingWatcher` 同一条通知，理由也一样：这一问发生在刷新所在的 executor 上，AppKit 不保证在那里作答），并复用 `DesktopReadingWatcher.systemScreenIsAvailable`——显示器睡着、锁屏或切走了用户，持有前台不算在谁眼前，而**锁屏本身就是一种让界面收到 `ESC [ O` 的方式**。

第 4 步不需要任何终端名单、bundle id 或"哪一级才算应用"的判断：**能走到前台进程的链路就是它托管的链路**，是谁都一样。它和导航那条路径共用同一份 `systemParentProcessIdentifier`（`ProcessAncestryHostResolver.systemParent` 现在只是它的转发）。

判定在编排器里（`ClaudeCodeMonitorService.rowsStillWorthShowing`），是 Desktop 那四条之外的第五条：**访问时间 ≥ 该 Turn 的终止时刻，且该终端的应用此刻持有前台，才算已读**。比较左边与前四条同源（Turn 自己的终止时刻）。答 `nil`（没有控制终端 / 读不出）的会话完全不进 gate；**答"没人在它前面"的会话进 gate**——那是"未读"而不是"问不出来"，因此它继续按每秒复查，回到那个终端的下一刻就会清掉。

**它是前四条的平级，不是它们的兜底**，尽管写成兜底看上去更自然（Desktop 托管的会话有记录，终端起的没有，两边本该正好分完）。**远程控制**是不能那样写的原因：同一个会话同时摆在终端和 Claude Desktop 面前，而两边由不同的手势读，只有一边写进本应用看得见的地方——在终端里读它，Desktop 的记录一个字节都不动。写成兜底，这样一行会为一个永远不会前进的 `lastFocusedAt` 无限期等下去。

反方向安全，而且是结构性的而不是撞运气：这一条只可能对**真的有控制终端**的会话成立，而 Claude Desktop 托管的会话没有——Desktop 把 CLI 跑成 `--output-format stream-json`、走管道、没有终端界面，这也正是那些会话没有 `status` 的原因（[#41](https://github.com/soondubu137/codex-in-notch/issues/41)）。

（实测 2026-08-19：一个开着远程控制的 CLI 会话在 `claude-code-sessions` 树里**根本没有记录**——整棵 Claude Application Support 树里没有任何文件提到它的 `sessionId` 或它的 `bridgeSessionId`——所以今天它答 `unknown`，走不到「两边都有」这个分支。那是某一个 Desktop 版本的事实，不是产品该依赖的性质。）

实测（2026-08-19 起，2026-08-20 在 Ghostty + CLI `2.1.238` 上重测并补测）：

| 事情 | 访问时间 | 修改时间 |
| --- | --- | --- |
| 敲键 | 前进 | — |
| 那个界面拿到前台（`ESC [ I`） | 前进 | — |
| 那个界面失去前台（`ESC [ O`） | 前进 | — |
| **指针划过那个界面**（`ESC [ ? 1003 h` 全动作鼠标上报） | **前进，且不需要前台** | — |
| **隐藏的界面**经历两轮完整前台切换 | **0 次变化** | — |
| CLI 渲染输出 | 不变 | 每秒约 2 次 |
| **一整轮跑完**（提交 → 答案 → Stop hook → 通知与响铃） | **只在提交那一下前进**，此后 110 秒不变 | 全程在动 |
| 会话空转（无人碰终端） | 150 秒 0 次变化 | — |
| **一次返回 `EAGAIN`、一个字节都没读到的 `read`** | **前进** | — |
| 对同一设备 `write` / `open` / `close` / `tcgetattr` / `ioctl` / `select` | 不变 | `write` 前进 |

**倒数第二行推翻了这条路径原来的立论。** 访问时间记的不是"终端递给了会话什么"，而是"会话对这个设备发起过一次读"——空读和读到一个按键一样远。这个区别在"只有终端递东西才会让 CLI 去读"的时候看不出来，而下面这条让它看出来了。

**第四行是这次的 bug。** Claude Code 自己打开全动作鼠标上报——`ESC [ ? 1000 h`、`1002 h`、**`1003 h`**、`1006 h`，启动时写一次，会话中途再写一次（`2.1.238` 抓包）——于是终端为**指针在窗口上的每一次移动**都写字节进 pty，不需要按键、不需要按下、**也不需要前台**。macOS 把指针移动投递给指针底下的东西，与哪个应用是活跃应用无关（[ADR 0012](adr/0012-read-state-is-answered-per-product-or-not-at-all.md) 否掉 `CGEventSource` 鼠标移动那一段说的正是这件事）。双屏下指针**只是路过**另一块屏上那个没有焦点的终端窗口，访问时间就前进，一行没人看过的终态在一秒内消失。事后无从分辨：访问时间是一个标量，读到它的时候它为什么动已经没了。

因此判定改成手势与前台**同时成立**。这是把一个状态并进一个跃迁，方向与 `DesktopReadingReporting` 那次反转相同，但这里只做 `AND`，**只可能让这条路径更窄**：指针划过没有焦点的窗口不再算数；某个应用抢前台造成的 `ESC [ O` 不再算数（采样那一刻持有前台的是它，不是这个终端）；敲键与 `ESC [ I` 照旧算数，因为这两件事本来就要求那个终端在前台。**它仍然首先是一个跃迁**——终端摆在空椅子前面不产生任何手势，光有状态永远不够。

第五行是这条路径能按会话而不是按应用成立的全部理由，第六行是必须读访问时间而不是修改时间的全部理由。焦点上报也是 Claude Code 自己开的（`ESC [ ? 1004 h` 在发布二进制里，每次离开 alternate screen 写一次）。

**没有边沿，只有采样。** 设备访问时间由内核推进，不产生任何文件系统事件，因此它在 gate 已经为等待中的行预约的 `terminalUnreadRecheckInterval`（1 秒）上采样，那一秒同时是行离开的上界。代价是每个列出的终态终端行每秒一次 `sysctl` 加一次 `stat`，加上前台成立时最多 16 次 `sysctl` 的向上走链；没有行在等的时候一次也不问。

**退化方向。** 不实现焦点上报的终端（或没开 `focus-events` 的 multiplexer）只剩按键，行等的是下一次敲键而不是回到 tab；`tmux`、`screen`、`ssh` 里的会话向上走链只会走到 `launchd`，它的宿主永远不持有前台，于是那样一行改为等下一次提交——**这是这次修改新增的一处退化**，方向是保留而不是提前移除；没有控制终端的会话保持既有行为。**仍然朝提前移除倒的**有两处：指针在**确实持有前台**的终端窗口上移动算已读（与 `DesktopReadingReporting` 对"窗口摆在空椅子前"的取舍相同，而且更窄——它还要求有人动了指针）；以及前台是在手势之后约一秒才采样的，用户在 `ESC [ O` 与 workspace 通知之间那几毫秒离开终端，会被读成没有离开。

单测按两层：`aTerminalsAccessTimeRecordsBeingReadFromRatherThanBeingTypedInto` 直接开一个 pty 对着真内核验上表的第一、六、九、十行——**空读那一条是这次补上的，它才是这个读数真正的语义**；`aTerminalIsInFrontOnlyWhenItsOwnApplicationIs` 用注入的进程链验第 4 步的四种答法（走到前台进程、走到别的应用、走到 `launchd`、屏幕不可用）。行为层的五个用例走注入的替身，因此不依赖跑测试时开发者在哪个终端里，其中 `aGestureAtATerminalNobodyIsInFrontOfRetiresNothing` 钉的就是这次的 bug。

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
- 下方内容区由列表视口和 footer 组成：列表视口最多 `508 × 240`，三行可见并垂直滚动；footer 固定 `496 × 40`。视口比 footer 宽两个 `6`：行块只缩进 `6`，行自己补回 `6`，行内文字与 footer 同落在 `12`。
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

处理时间不引入新的数据源：`startedAt` 来自官方 Hooks 中 `UserPromptSubmit` 事件的 `received_at`，与状态判定使用同一条事件流，因此不新增任何非公开依赖（见第 12 节）。

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
    let preview: String?           // 不随 Turn 持久化
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

`SessionStatus` 不包含 Connected 或 Disconnected。收起态在成员集合为空时显示的两个系统状态由 `MonitorAggregation.status` 推导：**任一产品「已打开且 availability 为 ready」时是 `Connected`，否则是 `Disconnected`**。availability 本身仍是 `MonitorAvailability`，但它不再单独决定收起态取值——「打开了却够不着」和「没打开」都落到 `Disconnected`。

在场是 `AgentSnapshot.presence`（`AgentPresence`：已打开／未打开／未知），与 availability 并列的独立事实：

- **Codex**：`NSRunningApplication.runningApplications(withBundleIdentifier:)`，内核事实，因此永不为未知。
- **Claude Code**：`ClaudeCodeSessionListing.presence()`，由活跃会话列表是否非空回答。列表是缓存的，所以只有它能报告未知——见第 15 节的可信上限。

`ClaudeCodeSessionListing` 的两个方法回答两个不同的问题，不得合并：`liveSessions()` 回答「有哪些会话」，Turn reducer 回答「它们在做什么」。**在场画出矩阵，reducer 点亮它。** 一个没有轮次在跑的会话仍然是一个打开着的 Claude Code。

**一个例外，只有这一个：会话自己会说它还在不在工作。** `claude agents --json` 除身份之外还给出 `status`（`busy` / `waiting` / `idle` / `shell`）与 `waitingFor`——本文档与代码注释此前都写着那份输出「不管会话在做什么都一字不差」，2026-08-18 对 2.1.235 实测证明那是错的。该读数进入 `ClaudeCodeSession.activity`，并且**只能做一件事**：结束 reducer 手里已经开着的那个轮次。它不携带轮次身份，所以永远不许开启、命名或描述一个轮次。

这条路存在的唯一理由是用户中断。`Esc` 不触发任何 hook——CLI 的 hook 事件表里没有任何取消事件，所有中断路径都在跑 `Stop` hook 之前就返回了——而按 `AGENTS.md` §6.2 计时器不得用来推断业务状态，于是「会话不再说自己在忙」是唯一一份证据（CC-019 / #38）。实测同一台机器：提交提示后 150 ms 内到 `busy`，审批对话框打开后 150 ms 内到 `waiting`（`waitingFor: "permission prompt"`），**在对话框仍开着时按 `Esc`，160 ms 内到 `idle`**——最后一种正是行会永远停在 *Approval needed* 的那一种。

应用规则写在 `HookEventRepository.endTurnsForStoppedSessions(_:)`，三条：

- **只有肯定的停止才作数。** `busy` 与 `waiting` 是会话在工作（`waiting` 时轮次仍然活着，只是停在用户面前，那是 reducer 自己的状态）；**没有这个字段**则什么也不做——桌面端托管的会话永远没有这个字段（#41），旧版本 CLI 也没有，沉默不是「空闲」的另一种说法。
- **读数必须整段晚于该轮次最后一个事件**，比较用命令**开始**运行的时刻而不是它答复的时刻。列表最长可缓存 30 秒，手里那份答案通常比之后到达的事件旧；用答复时刻比较，则一次跨越提交瞬间的读取会把它没看见的那个轮次报成空闲。
- **结束就是 Completed。** 产品只有一个终态，被中断的轮次是已经结束的轮次。

**桌面端托管的会话不说这句话，它写在别处。** Claude Code 桌面端把 CLI 当作 `stream-json` 的子进程来跑，没有终端界面，而 `status` 正是终端界面写出来的——所以那种会话的记录里从头到尾没有这个字段，上面第一条按「沉默不是空闲」什么也不做，行就一直停在 *Running* 或 *Approval needed*（CC-022 / #41）。它留下的是另一样东西：Claude Code 中止一轮时会往 transcript 里写一条 `user` 记录，而那条记录**指名了它中止的那个轮次**。

规则写在 `ClaudeCodeTranscriptReader.interruption(forSession:workingDirectory:turnID:after:)`，应用写在 `HookEventRepository.endInterruptedTurns(_:)`：

- **规则是结构，不是正文。** 一条 `user` 记录，`message.content` 恰好是一个 `text` 块，没有 `promptSource`，没有 `isMeta`。2026-08-19 在本机全部 transcript 上实测——205 个文件、7,438 条 `user` 记录——命中 15 条中断记录中的 15 条，**其余一条不中**。CC-019 当时否决这条路，理由是「要么读正文，要么用一条分不开中断记录与斜杠命令记录的结构规则」；分得开的那条规则是多问一句 `content` 的形状：把两者分开的 202 条斜杠命令与 `<local-command-stdout>` 记录都把 content 写成**一个字符串**而不是块数组。这句话是必需的而不是保险——那 202 条里有 23 条后面还有模型在同一个 `promptId` 上继续工作，少问这一句就会把还在跑的轮次退休掉，而那正是唯一不允许错的方向。
- **它指名轮次，因此被钉在那个轮次上。** 记录里的 `promptId` 就是 hook 的 `prompt_id`，也就是 reducer 的轮次身份（2.1.237 实测：`UserPromptSubmit` 与中断记录带同一个 id）。指到一个 reducer 没在持有的轮次就什么也不做。这也让「中断记录与真正的提示只差一个 `promptSource`」变得安全：提示开启的是一个**新**的轮次 id，即使某个版本不再写 `promptSource`，它也结束不了它自己刚开启的那一轮。
- **顺序护栏与上面同源，而且更准。** 比较用的是这条记录被**写下**的时刻（记录自带 RFC 3339 时间戳），不是本应用读到它的时刻。
- **不读一个字正文。** 解码结构里没有 text 字段，与 `AgentHookListener` 的解码器同理；只读 transcript 末尾 64 KiB，按 `(size, mtime)` 缓存，会话消失即丢弃。
- **只问该问的会话。** 只有「不报告任何状态」且此刻还持有未结束轮次的会话会被问——会自己报告的会话由它自己的回答负责，而没人在等的文件读取不值得做。

那条边沿同样要自己建：中断不会改写 `~/.claude/sessions/<pid>.json`（那份记录里根本没有状态可翻），于是 `ClaudeCodeSessionRecordWatcher` 看不到它。`ClaudeCodeMonitorService.transcriptWatcher` 因此按文件监听这些会话的 transcript（`PathSetChangeWatcher`，与记录 watcher 同一套理由：追加写不会触发目录级事件）。它**不**把会话列表标记为过期——那是与记录边沿的唯一区别：这条边沿说的是「本应用自己读的一个文件变了」，答案来自一次 64 KiB 的尾部读取而不是一次 `claude` 启动。

`TurnEvidence` 是内存中的 reducer 真值，不直接持久化。当前 Turn 从 Running 开始；Input needed 与 Approval needed 都只是在同一活动 Turn 上暂时覆盖 Running，等待恢复信号回到 Running；任何可信执行结束信号进入不可逆的 Completed。缺失、超时或未知信号不创建第五种状态，只保留最后可信值。

## 5. 数据真值与禁止回退

| UI 字段 | 权威来源 | 允许回退 | 禁止回退 |
| --- | --- | --- | --- |
| Thread id | Desktop 支持接口 | 无 | 标题、session id、路径、时间接近度 |
| Turn id | 当前活动或未读终态 Turn | 无 | Thread updatedAt |
| 标题 | Desktop 当前显示标题 | 预览开启时使用本轮 prompt 安全截断；否则 `Untitled` | cwd、仓库名、Mock 标题 |
| Project | Desktop 私有全局状态中的精确 thread assignment + Project id/name | `projectless-thread-ids` 明确命中时 `Chats`；否则失败显示 `Project unavailable` | `thread.section`、cwd basename、Git root |
| 未读 | Desktop 未读真值；Claude Code 另加 ADR 0012 的三条编排层规则 | 无 | 「此刻在前台」不带 ADR 0012 的三条读数与会话身份限定、Notch 点击、固定保留时间、窗口标题或几何 |
| 状态 | 受支持的 Turn/请求事件与校正快照 | 保留最后可信四态值 | 计时器或 UI 猜测 |
| 处理时间 | Hook `UserPromptSubmit` 的 `received_at` | 起点未知时退回状态点，不显示数值 | Thread 时间、文件修改时间、累加计数器 |
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

安装器必须记录自己管理的最小配置片段，不能覆盖用户其他配置。

**改写任何一条定义都会使它失去信任，因此定义写下之后不再改写**（[ADR 0014](adr/0014-the-codex-hook-definition-is-never-rewritten.md)）。Codex 在 `config.toml` 的 `[hooks.state."<hooks.json 路径>:<event>:<group>:<handler>"]` 下按定义内容哈希记录信任；定义内容一变，Codex 就**静默停止执行该定义**，直到用户重新 `/hooks` 信任。其余未改动的定义哈希不变，继续正常触发，因此应用侧看不出任何异常——投递证据会被它们满足，UI 照常显示已连接。2026-08-15 实测中 `PreToolUse` 因此连续两轮完全不触发而无任何提示。

据此，版本化整个搬进**脚本**（不参与哈希），定义只写一个稳定路径：

```json
{"type": "command", "command": "/bin/sh '<support>/agents/codex/hook.sh'", "timeout": 3}
```

注册的是 `UserPromptSubmit`、`PermissionRequest`、`PreToolUse`、`PostToolUse`、`Stop` **五**条，全部不带 matcher。`SessionEnd` 不再注册：它 reduce 之后什么也不做，代价是每次会话结束一次进程启动和一条要用户信任的定义；会话没了的行由 App Server 成员关系校正退休。`PreToolUse`/`PostToolUse` 保持 catch-all——把它们收窄到 `^(request_user_input|request_permissions)$` 会砍掉约 90% 的事件量，但普通工具的审批是一条带 `tool_name` 而不带 `tool_use_id` 的 `PermissionRequest`，只能挂到 catch-all `PreToolUse` 刚刚宣告的那个 id 上，而拒绝推断还需要看见**其他**调用上的活动。事件量的答案是更便宜的 helper，不是 matcher。

安装健康度要求这五条定义各有且只有一个当前 handler，且 command 与 `timeout = 3` 精确匹配、group 不带 matcher；只存在任意子集、重复定义或字段被改变时必须 fail closed 为 `mismatched`（卡片显示 `repairRequired`），不能显示 Ready。

两条合并规则，理由都在实测的信任 key 形状上——2026-08-20 本机读到 `[hooks.state."…/hooks.json:pre_tool_use:0:0"]`，第三段是 group 在数组里的**下标**：

1. **只在尾部追加，只从尾部移除。** 从中间移除一个 group 会让它后面所有 group 重新编号，于是**用户自己的**定义静默失去信任。
2. **已经正确的安装不写文件。** `install()` 在 `complete` 时直接返回，不重写、也不重排一份本来就正确的文件。

reducer 另外用「只见 `PostToolUse` 不见 `PreToolUse`」作为失信状态的运行时探测并输出诊断。定义冻结之后本应用自己已经到不了那个状态，探测留给它造不出的情况：用户手改 `config.toml`，或 Codex 更新重新哈希。移除时只移除本应用管理的片段。

### 7.2 启动与重连

```text
launch
→ bind hook.sock; write hook.sh if its bytes differ from the bundled one
→ read install.json (lastEventAt only); initialize an empty in-memory reducer
→ compute registration once from ~/.codex/hooks.json
→ Connecting (≤ 5s)
→ capability handshake
→ reconcile active + unread terminal membership
→ subscribe events
→ ready
```

五秒内连接成功则不显示中间错误；超时后根据原因进入 Update required、Version unsupported 或 Disconnected。Codex 未运行时不自动启动。

**helper 的升级只发生在启动与安装两处，不在刷新路径上。** 安装器把磁盘上的 helper 与本版本内置的字符串直接比较，不同就覆写；`hooks.json` 一个字节都不动，用户不需要重新信任（[ADR 0014](adr/0014-the-codex-hook-definition-is-never-rewritten.md)）。**没有安装标记**：它当初只用来区分「本应用装的旧 helper，该升级」与「本应用从没装过的文件，不该悄悄替换」，而这个区分不值一个文件——两边的处置是同一个，写下当前脚本。它也从来没有提供防篡改能力，旧代码自己的注释已经承认：能改脚本的东西也能改它旁边的标记。

这条此前挂在**每一次刷新**上（`upgradeManagedHookIfNeeded()` 读约 4 KB 脚本做字符串比较），去回答一个只有本应用自己升级时才会变的问题。

**注册完整度也不按节拍重算。** 它只在三个时刻改变：本应用写了 `hooks.json`、用户主动要求重新检查、或该文件在我们脚下被改动（FSEvents 边沿）。前两者直接失效缓存，第三者由 `CodexHookRegistrar` 自己订阅。`installationRevalidationInterval`、缓存扫描与 `hasManagedSupportFootprint` 随之删除。

安装与移除都对用户的 `hooks.json` **fail closed**，由 [`ManagedHooksConfiguration`](../CodexInNotch/CodexInNotch/ManagedHooksConfiguration.swift) 执行，规则只有三条：

1. **只改本应用管理的五个 event key**，其余 key、未知字段、分组内的自定义键一律原样保留。
2. **看不懂的结构不改**。只有当「必须写入的那个 key 已经是看不懂的结构」时才整体拒绝并返回可见错误——因为写进去就等于覆盖用户的内容。不相关的 event 即使结构奇怪也只是跳过，不构成错误，否则用户将永远无法干净卸载。
3. **移除侧额外做一次全文深扫**，确认本应用的命令没有残留在任何改不动的形状里。有残留就拒绝，并且**不删除 helper**——删了就是在用户配置里留下悬空引用。

写入前后各有一道保护：写入前比对文件字节是否仍是读取时那份（避免与 Codex `/hooks` 的并发写互相覆盖），写入后重新读回校验六个定义确实存在／确实已清除。无改动时根本不写，避免无谓地重排用户的文件格式。

这里**不再记录内容 hash**。曾经存在的 `managedHookSHA256` 与 helper 位于同一目录、同一属主与权限，能改写 helper 的主体同样能改写该 hash，因此它不提供任何防篡改能力；而 `repairRequired` 并不会把 helper 从 `hooks.json` 注销，Codex 仍会继续执行它。也就是说，遇到被替换的 helper 时，自动升级回内置版本比标记 `repairRequired` 更快地消除外来代码。缺少任一定义、定义结构不精确，或 helper 存在但安装标记缺失（本应用没有安装记录、来源不明）时仍 fail closed 为 `repairRequired`；Settings 总开关显示 Off，用户显式重新开启后才修复。这样应用升级后无需重新接受未改变的受信 helper；但完整注册集合和历史信任本身不能让运行时进入 Ready。只有当前态来源确认集合确实为空时，才能由空集合推导「没有东西在工作」。同一条规则对称地约束在场：只有确实读到了一个空的会话列表才算「未打开」，读不到时是**未知**，未知落到 `Disconnected`。

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

重启时不读取本应用旧列表或旧 reducer Turn；从空集合执行同一校正。这条不再需要靠一次检查守住：Hook 事件不落盘，所以下一次启动没有任何东西可以恢复终态边界、创建 Turn 或修改当前状态（[ADR 0015](adr/0015-hook-events-go-straight-into-the-reducer.md)）。磁盘上只剩 `install.json` 的 `lastEventAt`，它只建立 Hook 配置健康信任。

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

- 所有会改变 Turn 状态的 Hook 必须包含非空 `session_id` 和 `turn_id`（Claude Code 把后者拼作 `prompt_id`，字段选择在 `HookPayload` 里合流）。不得回退到当前 Turn、`"unknown"`、时间邻近或 Thread 更新时间；缺少身份的 payload 只写诊断并丢弃——没有可以被隔离到的地方，这也是 `.invalid` 文件不再堆积的原因（本机曾累计 155 个）。**「写诊断」这一半必须真的有人看得见**：读不懂的 payload（连一个字节都没送到的连接也算）与读得懂但放不下的事件分别计数，按本次运行累计，与「注册了却不触发」的探测拼成一句话，经 `AgentSnapshot.diagnostic` 到 Settings 里该产品那一行。报一次就清的写法等于没写——用户是因为看着不对才去开那个窗口的（CR-029）。**过长的身份等同于缺少身份**：正文可以截短，身份不能——半个 `session_id` 是另一个会话——所以超过 `HookPayloadDistiller.maximumIdentityBytes`（1 KiB）的身份字段整个不要，payload 随之丢掉（CR-030）。
- repository 没有该 Thread 时，受支持事件可以用自身的精确身份建立 Turn。已有当前 Turn 时，顺序更新且从未被该 Thread 淘汰过的 `UserPromptSubmit` 可以建立下一 Turn；Desktop 中断后继续执行时可能不再发送 `UserPromptSubmit`，因此更晚到达的实时 `PermissionRequest`、`PreToolUse`、`PostToolUse` 或 `Stop` 也可以用新的、未退休的精确 `turn_id` 接管同一 Thread。接管时旧 Turn id 立即进入 `retiredTurnIDs`，保留原始开始时间与 prompt preview，清空旧等待证据；事件本身再决定 Running、Input needed 或 Completed。任何退休 Turn 的迟到事件都不能复活旧身份。
- `PreToolUse(request_user_input)` 只有在包含非空 `tool_use_id` 时才建立 Input pending；`PostToolUse` 只有 `turn_id` 和 `tool_use_id` 都与该 pending 完全相同时才能清除它。未匹配结果保持原状态。
- `PermissionRequest` 没有自己的 `tool_use_id`，因此不能独立成为 Approval evidence；但它携带 `tool_name`，而被审批的调用已经由紧邻的 `PreToolUse` announce 过。reducer 因此为每个 Turn 记录"当前仍打开的工具调用"（`openToolUse`：`PreToolUse` 写入，同 `tool_use_id` 的 `PostToolUse` 清除），`PermissionRequest` 借用该 id 建立 Approval pending。没有打开的调用可配对，或 `tool_name` 与打开的调用不一致时，保持原状态——绝不建立无法关闭的等待。自动放行的请求在同一批事件内开合，不会滞留成假等待。`PostToolUse` 自身仍不得用来猜测审批状态。
- Approval pending 因此分两类（`PendingApproval.isInferred`）。`request_permissions` 自带 id，必然收到配对 `PostToolUse`，只由该事件关闭。借用 id 的等待在**拒绝**时永远收不到关闭事件（实测：拒绝后该 `tool_use_id` 再无任何事件，67 秒后直接 `Stop`），因此额外由"任意其他 `tool_use_id` 的 `PreToolUse`／`PostToolUse`"关闭——Codex 在阻塞于审批期间不发送任何事件，所以其他调用的活动就是人工已回答的证据。两类都由 `Stop` 兜底进入 Completed。该规则严格限定在借用 id 的等待上，不得放宽到 `request_permissions` 或 Input pending。
- 只有本次启动后收到的实时 `Stop` 才清空 pending input/approval，并让同一精确 Turn 直接进入 Completed。产品不区分 completed/failed/interrupted 的结束原因，也不存在终态待解析窗口。历史回放的 Stop 完全不进入 Turn reducer。

### 9.3 App Server 当前快照纠偏

Hook 是四态状态的唯一来源；App Server 只提供展示用元数据。Hook reducer 先用缓存的 Thread 标题与 Desktop Project 私有状态发布状态，再异步刷新元数据；任何 App Server 请求都不得位于 Hook → UI 的关键路径。Thread payload 只贡献根线程判定、标题与 preview，不参与状态推导——它没有任何字段能在当前拓扑下表达 Turn 级运行时真值（见第 1.1 节实测边界）。

独立 App Server 不共享 Desktop 当前运行时，因此它不是 Hooks 的替代品，也不参与状态纠偏。元数据读取遇到缺失字段、超时或协议错误时保留最后可信内存状态，绝不因此改变四态值。

### 9.4 到达顺序与迟到事件

**没有历史回放，因此没有 live cutoff。** 一份 payload 顺着 socket 进到这个进程，来自片刻之前跑过的 helper，所以到达的事件按构造就是当前的；应用崩溃或退出期间的 lifecycle 信号根本没有被写在任何地方，下次启动无从伪装（[ADR 0015](adr/0015-hook-events-go-straight-into-the-reducer.md)）。

**到达顺序由 transport 的串行读取队列保证，不由注册保证。** 连接按到达顺序 accept、交给同一条串行队列，`deliver` 因此按 payload 落地的顺序被调用。交给 actor 时不能用 `await`——按顺序 spawn 的两个 `Task` 不是按顺序运行的两个 `Task`——所以 payload 先按顺序进一个锁保护的 inbox，drain 一次把整个数组取走。

**`retiredTurnIDs` 保留。** 提案曾主张删掉它，理由是「串行队列上的到达戳单调，所以退休轮次的迟到事件不可能存在」。这对 transport 成立，对 executor 不成立：ADR 0013 记录了 Claude Code 在同一个 `prompt_id` 下把 `Stop` 排在自己 subagent 的 `PermissionRequest` 前面交付，而 reducer 是两个产品共用的；Codex 那一半也没有实测。迟到与乱序仍然只靠 `mutateExactTurn` 的时刻比较与 `retiredTurnIDs` 两条挡下。

所有未知字段与枚举写入诊断，不让应用崩溃。诊断只保留方法名、版本和枚举标识。

## 10. 汇总与排序

汇总优先级：

```text
Input needed
> Approval needed
> Running
> Completed
```

集合为空时，收起态取 `Connected` 或 `Disconnected`：至少一个产品已打开且 ready 时为前者，否则为后者。availability 非 ready 时清空该产品的列表；具体原因（尚未集成、版本过旧、连接断开）不进入收起态，只在展开面板与 Settings 中说明。

列表按同一优先级排序，同级按 `observedAtMs` 降序。repository 立即提交顺序，但 UI 在用户滚动或悬停时保留当前可见锚点；变化发生在视口外时显示轻量更新指示。

## 11. 当前内容预览

`PreviewExtractor` 只接收已经面向用户公开的 item：

1. Input needed：当前问题文本。
2. Approval needed：固定 `Approval requested`，不读取命令、路径或理由。
3. Running：最新公开 commentary/progress；否则本轮 prompt。
4. Completed：final answer 开头；没有时保留最后公开进度。

处理步骤：去控制字符 → 合并空白 → 取第一可见行 → 内存限制 → 交给 UI Alpha mask。禁止写日志、数据库、UserDefaults 或诊断包。

### 正文如何到达本进程（Codex）

**正文和它所属的那个事件一起到达，走同一条连接。** helper 把 stdin 原样转发进 `hook.sock`，不做任何过滤；字段选择、截断和事件命名都在 Swift 里（`HookPayloadDistiller`、`HookPayload` 与 `HookSessionPreviewStore.normalized`），而不是一个只有一条集成测试跑得到的 Python 字符串字面量。**选择发生在解码之前**：大起来的全是本 app 不读的字段（`tool_response`、粘进来的 `prompt`），所以扫一趟只把认识的键挑出来，`JSONDecoder` 拿到的是一个几百字节的小对象，工具结果的大小不再决定这个生命周期事件听不听得见（CR-030、[ADR 0015](adr/0015-hook-events-go-straight-into-the-reducer.md)）。`UserPromptSubmit` 带 `prompt`，`Stop` 带 `last_assistant_message`，两者都是 reducer 已经要处理的那个事件。

**没有第二条 socket，也没有 `event_id` 接合。** `preview.sock`、`claimPreview` 与未认领预览的保留上限全部只因为「正文不许进事件文件」而存在；一条 socket 带整份 payload 就没有这个拆分（[ADR 0015](adr/0015-hook-events-go-straight-into-the-reducer.md)）。

正文仍然不落盘，但这现在是构造使然而不是一条要守的规则：整条路径上没有文件。没有监听者时 helper 直接丢掉，结果是「没有预览」而不是「过时的预览」。

**connect 与 write 之间，应用可能已经 accept。** 监听 socket 是非阻塞的，好让 accept handler 一次排空 backlog 而不是停在下一个连接上；Darwin 的 `accept` 会把这个标志一并交给它返回的连接。接收循环于是从「已连接、但写还没落地」的客户端读到 `EAGAIN`，而它无法把 `EAGAIN` 与消息结束区分开——payload 被永久丢弃，而不是等一下再读。250 ms 接收超时本来正是为这一步设的，但它在非阻塞描述符上不约束任何东西，所以「从未触发」并不是余量充足的证据。`receivePayload` 先清掉该标志，超时才真正生效（CC-023/CC-024）。同一个读循环里还有一个更小的同形问题：`read` 因信号返回 `EINTR` 与 payload 结束也长得一样，所以它单独重试，剩下的答案（写方关闭的 0、以及超时的 `EAGAIN`）才结束这一次读——读到多少就是多少，由字段选择决定剩下什么（CR-030）。这个坑最初是在 `preview.sock` 上发现的；它是 accept 的性质，所以跟着搬进了两个产品现在共用的那条 transport。

不能改用 `thread.preview` 代替：实测它是**线程的首条用户消息**，不随轮次前进（17 轮的线程仍返回第 1 轮的文本），因此它满足不了 PRD 2.7 的「当前内容预览」。

### 正文如何到达本进程（Claude Code）

**两个产品现在是同一条形状：一个 helper、一条 socket、一个 store。** 这边和 Codex 的差别只剩正文的来源——那边一轮两次、跟着生命周期事件到；这边是 `MessageDisplay`，一个正在说话的轮次每秒 3.4 次。所以这边多一条规则：`MessageDisplay` 在 `HookEventRepository.deliver` 里就停下，折进一个锁保护的 preview store，**不进 reducer 的 mailbox**。折叠留在 listener 的串行读取队列上，而不是走一次 actor hop——那条路径每秒 3.4 次，一次 hop 会把它放上产品的关键路径（`AGENTS.md` §6.3）。

**这条通道此前是 `type: "http"`，指向 `127.0.0.1:51741`；换成 helper 的理由与正文无关，见 [ADR 0013](adr/0013-claude-code-hooks-run-a-helper-not-a-port.md)。** 一句话：端口在本应用没开时不属于任何人，于是 CLI 每个事件都往用户会话里打一行 `connect ECONNREFUSED`，而且关不掉；这两件事都不是注册能修的。

来源是官方 Hook `MessageDisplay`（官方描述 "While assistant message text is displayed"，公开 payload 为 `turn_id, message_id, index, final, delta`）。它此前从未进入本仓库的事件表，Phase 0 的 30 事件清单里没有它——这正是「取不到正文」这个结论的由来。

**先量再写。** 用 pty 驱动一个交互式会话，注册指向临时 `--settings` 文件里的独立监听器（**未改动 `~/.claude/settings.json`**），CLI 2.1.234 实测：一条 1561 字符的消息拆成 **11 个 delta**，间隔 **0.20–0.44 秒、均值 0.29 秒**，单个 payload 728–865 字节。这就是下面每一条的由来——三次每秒是这条路径唯一需要设计的东西。

`AgentHookListener` 对它做四件事：

1. **在进 reducer 之前转向。** `deliver` 认出 `MessageDisplay` 后折进内存并直接返回：不排队、不 reduce、不唤醒面板。此前它还要避开一个文件目录——三次每秒写一个文件、再由 reducer 读一个删一个，是这条路径最贵的做法；那个目录已经不存在了。
2. **一条串行读取队列，保序而不是抢快。** 连接按到达顺序 accept，交给同一条串行队列，所以 `record(_:)` 看到的顺序就是 payload 落地的顺序。这一条现在要单独说，因为 `command` schema **有** `async` 这个键（`http` schema 没有，2026-08-18 读 schema 证实，此前本文档以为写得进去的 `async: true` 会被 settings 解析器直接丢掉）。实测 2.1.237：`async: true` 会让同一个 `tool_use_id` 的 `PreToolUse` 与 `PostToolUse` 互相超车，并且在 `-p` 下**整个丢掉 `Stop`**——进程在后台 hook 跑完之前就退出了。所以注册是同步的，代价是每个事件 6.3 ms 落在会话上（对照：Codex 那边的 Python helper 一直是 30 ms）。
3. **只留每条消息的头部 240 字符。** 内存由常数决定，而不是由模型说了多少决定：头写满之后，后续 delta 在被扫描进任何保留结构之前就停下。
4. **一趟扫完，只扫新 delta。** 折叠函数以已规范化的头部为种子往下写，长度用 `Int` 随行。此前的写法是重建 `carried + delta` 再在每个字符后取 `.count`——`String.count` 要走一遍字素边界，于是相对截断长度是平方级，还额外整份拷贝了 delta（那时的上限是 `maximumBodyBytes`，1 MB；现在 delta 作为正文字段在选择这一步就被截在 `HookPayloadDistiller.maximumTextBytes`，16 KiB）。现在超长 delta 与普通 delta 同价。

`delta` 的官方措辞是「**newly completed lines**」，实测确实如此，而且**是增量、不是累计**：同一条消息的相邻 delta 依次以 `1. `、`2. `、`3. ` 开头，各自从上一个停下的地方开始——若是累计，逐块追加会把整条消息重复一遍。除最后一个之外，**每个 delta 都以换行结束**，规范化后塌成一个尾随空格，所以下一个 delta 直接接上去，分隔符不需要被发明；`pendingSpace` 的种子只为消息的最后一个 delta 而存在，那一个才停在行中间。`-p` 非交互是另一种形状：一次交付、`index: 0`、`final: true`，多行消息带着换行整份到达。

**它也不进 `changeEvents()`，只有一个例外。** 不写文件的第二个后果：一个正在说话的轮次不会每秒把面板重画三次。正文由该轮次自身生命周期事件引起的刷新顺带取走，也就是面板本来的节奏——这条约束见 [`AGENTS.md`](../AGENTS.md) §7。

例外是**从没有到有**这一个边沿，由 store 自己的 `changeEvents()` 报出——它不再需要一条自己的流，因为 store 本来就只在渲染投影变化时发信号。上一段的理由只覆盖「行上已经有一句、它变旧了」，不覆盖「行上什么都没有」——后者要等的不是一次更整齐的重画，而是那个会话下一次做点别的，而一个说上一分钟才调一次工具的轮次期间什么生命周期事件都不发，于是那一行会一直空着。只报这一个边沿，因此代价是每个会话每一段「无话可说」一次唤醒，而不是每个 delta 一次；并且只为**上一次刷新列出过**的会话报（`retainPreviews` 收下的那个集合）——列表不带的会话，它的正文会被它自己求来的那次刷新裁掉，于是下一个 delta 又是一次「从没有到有」，那不是一次唤醒而是一个按 delta 速率跑的循环，何况那一行本来也不在屏幕上。

预览按 live 会话集合裁剪（与标题缓存同一个集合），所以会话结束后它的正文不会比那一行活得更久。

## 12. 处理时间

产品语义见 PRD 8.2；本节只描述实现约束。

**时间来源**：`MonitoredSession.startedAt` 直接来自 `HookTurnState.startedAt`，即官方 Hooks `UserPromptSubmit` 事件的 `received_at`。同一 Turn 的继续执行沿用原 `startedAt`，同一 Thread 的新 Turn 重新取值。不读取 Desktop 私有时间字段，因此不进入非公开依赖清单。

**计算方式**：`SessionElapsedFormatter` 以 `now - startedAt` 重新计算，禁止累加计数器。这是等待与睡眠自动计入的原因，也使漏掉的刷新不会造成永久性偏差。起点缺失或时间倒流一律返回 `nil`，由调用方退回状态点，不得渲染 `0:00` 之类的猜测值。

**聚合**：`MonitorStore.longestRunningSessionStart` 取所有 `status.keepsTiming` 会话中最早的 `startedAt`。判定使用 `SessionStatus.keepsTiming`（仅 `completed` 为假），不得写成 `== .running`，否则轮次一进入 Approval needed 就会从收起态读数中消失。

**刷新**：`MonitorStore` 持有唯一的计时任务，经 `MonitorClock` 休眠，随会话列表变化启停——没有未完成轮次时任务被取消，不存在空转唤醒。每次休眠对齐到被计时轮次的下一个整秒，避免固定 1 秒休眠累积漂移后跳过一个数字。任务重新启动时先刷新 `timerNow`，否则空闲期间冻结的时间戳会让新轮次的第一秒读成负值。

**面板几何**：收起态宽度由计时文本测量得出，因此计时推进必须触发面板重新测量；`NotchTimerText` 使用等宽数字，避免每秒抖动。

**无障碍**：`SessionElapsedFormatter.spokenElapsed` 提供时长读法，与绘制文本分开；VoiceOver 会把 `12:34` 读成时刻。

## 13. 额度、今日用量与 Expanded footer

连接成功后在核心会话快照发布之后异步读取两份账户数据：

- `account/rateLimits/read` 的 primary window 提供 `usedPercent` 与 `resetsAt`；圆环继续显示 `100 - usedPercent`。
- `account/usage/read` 的 `dailyUsageBuckets` 提供日期字符串 `yyyy-MM-dd` 和 token 总量。使用目标 Mac 当前 Gregorian 日历与时区生成今天的 key，按 `startDate` 精确匹配；有效数组没有今天时表示今日为 `0`，数组缺失或请求失败表示 unavailable。

账户 fingerprint 每 30 秒校正一次，额度与今日用量最多每 60 秒刷新一次；两份用量请求并发执行，但解析与降级相互独立：今日用量失败不得清空可用圆环，额度读取失败也不得隐藏可用的今日 token 总量。账户标识变化时先同时清空，再读取新账户。不得从 `lifetimeTokens`、`peakDailyTokens`、会话行 token、剩余百分比或旧 snapshot 推算今天的值。

### 13.1 Footer 格式

Expanded footer 固定 `40 pt` 高，位于会话/空状态正文之后且无额外 bottom padding；其顶部 hairline 与 header/正文分隔线使用同一视觉 token。外层跟随面板 `12 pt` 水平 inset，因此 `520 pt` 面板中的 footer 内容宽 `496 pt`。

左侧文案为：

```text
<today token compact value> • <reset text>
```

token 总量使用固定 `en_US` Compact notation 与 `1 ... 3` 位有效数字，保留必要小数并移除尾随零，例如 `13.4K`、`323K`、`2.8M`、`1.03B`；`0 ... 999` 直接显示整数。数据 unavailable 时显示 `--`。

reset 按**剩余时长**而不是本地日历日计算——`Resets today` 在 00:30 与 23:30 同样成立，等于什么都没说：不足一小时为 `Resets in under an hour`，不足一天为 `Resets in x hours`，整天为 `Resets in x days`，两者都有为 `Resets in x days y hours`；已经落在当下以前的 stale 时间钳制为 `Resets now`，等待下一轮刷新纠正。

没有 reset 时间有两种含义，按窗口**已知的其余部分**区分：Claude Code 的 5 小时窗口在第一次请求时才起算，在那之前它那一行只有百分比、没有 `resets ...` 从句——这是一个还没开始的窗口，不是一次失败的读取，写作 `Not started`（未消耗，即 `100% left`）。其余情况仍为 `Reset unavailable`：**已消耗**却读不到 reset 的窗口正是输出措辞变化的信号，那一条必须继续说读数不可用。

左侧生产字体为 SF Pro Regular `11/14`、secondary text；Figma 中的 Inter 只是 MCP 字体不可用时的渲染替代。右侧使用 `32 × 32` 原生 `Button` 点击目标与 `16 pt` `gearshape`，VoiceOver 名称为 `Open Settings`，调用 SwiftUI `openSettings` 打开现有 `Settings` scene，不在 overlay 内复制设置界面。

失败策略：

1. 单次请求沿用 App Server client 的 15 秒超时；读取失败后保持 UI 可用，并在 60 秒冷却后静默重试。
2. primary 仍失败则额度 unavailable，立即显示灰色圆环；today bucket 仍失败则 footer 使用 `--`。
3. 不保留旧值，不以 lifetime、peak 或其他字段估算。
4. 账户标识变化时先清空额度与今日用量，再读取新账户。
5. 任一账户用量字段失败都不改变 availability、会话状态或导航。

## 14. 导航

点击成功的定义按产品成立，两个产品各有一个导航器，由 `AgentNavigationRouter` 按 `MonitoredSession.agent` 分发；没有注册导航器的产品报自己的名字失败，而不是被交给表里第一个。传过去的是整行而不是一个 thread id——Codex 行是一条 deep link，Claude Code 行是一个进程加一个工作目录，没有一个标识能同时装下两者。

### 14.1 精确导航（Codex）

`CodexDesktopNavigator.open(threadId:)`：

1. 通过 repository 和目标级校正确认 Thread 仍存在、未归档、未删除、可导航。
2. 对 `threadId` 做 URL path-component 编码，构造官方 `codex://threads/<thread-id>`。
3. 使用 `NSWorkspace` 将 URL 定向交给 bundle id `com.openai.codex`；不得退回浏览器或 Codex 首页。
4. 当前没有公开的页面完成回执。运行时成功只表示 Launch Services 接受请求；“打开同一 Thread 且不创建/resume Turn”由版本化端到端兼容测试保证。
5. 请求被接受后收起面板；不主动标记已读。
6. 预检或打开失败时保持面板和行，显示非破坏性反馈并触发集合校正。

禁止：首页 fallback 作为成功、使用未文档化 URL、私有 IPC、Accessibility 点击、标题匹配。

### 14.2 宿主唤起（Claude Code）

ADR 0004 的精确导航门槛只约束 Codex：目前没有任何受支持的接口能聚焦一个已经存在的 Claude Code 会话，官方 deep link 一律新建。`ClaudeCodeNavigator.open(_:)` 因此唤起宿主，这是**声明过的能力边界**，不是伪装成成功的 fallback。行上不加任何标记（一行只带一个标记，那个标记是计时），差别只由 `NavigationOutcome` 的那句反馈说出来。

1. 向 `ClaudeCodeMonitorService` 问该 `threadID` 此刻的 pid，答案来自同一份 `claude agents --json` 会话列表。**这就是点击前的重新确认**：已经结束的会话不在列表里，于是点击失败并触发集合校正。pid 不预先写在行上——过期的 pid 不是死链接，而是别人的进程。
2. 用 `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_PID)` 的 `e_ppid` 与 `proc_pidpath` 向上走进程祖先链，**从父进程开始**：桌面端托管的 `claude` 自己就跑在一个 bundle 里（`~/Library/Application Support/Claude/claude-code/<version>/claude.app`，`com.anthropic.claude-code`），把会话进程本身算进去会让每个桌面端会话都"自己托管自己"。每个祖先取它最外层的 `.app`，helper 因此归到发它的应用名下。
3. 祖先里出现 Claude Desktop（`com.anthropic.claudefordesktop`）即为桌面端托管，激活它。取该 bundle id 在链上**最高**的那个祖先，因为最近的那个是 `Claude.app/Contents/Helpers/disclaimer`，而 helper 不是窗口服务器认识的应用。
4. 否则最近的那个 `.app` 就是宿主终端。取该会话的控制终端设备（与终端已读同一条 `sysctl` + `devname_r` 路径），交给终端**自己的公开脚本字典**选中那个标签页：Terminal.app 的 `tab` 有 `tty`，iTerm2 的 `session` 有 `tty`。报不出 tty 的终端只激活应用——Ghostty 有完整字典却整份里没有 tty，只有标题和工作目录，按之匹配正是 PRD 禁止的猜测。
5. **Automation 授权不在点击里等人。** 未决时后台发出一次授权请求并当场降级为激活应用；被拒之后系统本身就不再弹窗，本应用也不再问，且不产生任何错误——用户看到的仍然是那句 `Raised X`。脚本执行有 5 秒上限，卡住的终端不会把「同一时刻只有一次导航」的名额一直占着。

   2026-08-19 在 Terminal.app 里的真实会话上实测（`claude` pid 69273，`/dev/ttys015`）：

   | 时刻 | 观察 |
   | --- | --- |
   | 未决，弹窗正在屏幕上 | 第一次点击 **0.02s** 返回 `raisedApplication(host: "Terminal")`——弹窗没有挡住导航，这条设计成立 |
   | 用户点 Allow | 之后每次点击 0.06–0.14s 返回 `focusedTerminal(host: "Terminal")`；Terminal 拿到前台，且 `/dev/ttys015` 的访问时间在那一刻前进——**被选中的是那一个标签页，不只是那个应用** |
   | 用户点 Don't Allow | 同一进程内后两次点击 0.03s / 0.09s 返回 `raisedApplication`；再起两个全新进程各点三次，六次全部 0.01–0.02s 返回 `raisedApplication`，**不弹第二次窗、不报错**，Terminal 仍被带到前台 |

   桌面端那一半单独验过（`claude` pid 94822）：祖先链答 `desktop(com.anthropic.claudefordesktop, pid 24014)`——拿到的是应用本身而不是 `disclaimer` helper，即上面第 3 条那个「取最高的那个祖先」在真机上成立。两次点击都在 0.00s 返回 `raisedApplication(host: "Claude Desktop")`，前台应用从 Chrome 变成 Claude Desktop，`NSRunningApplication.activate()` 这一步没有退到 Launch Services 兜底。

   系统弹窗的原文（模板取自 `TCC.framework` 的 `REQUEST_ACCESS_SERVICE_kTCCServiceAppleEvents`，两个 `%@` 填入两侧应用名，末尾接本应用的 `NSAppleEventsUsageDescription`）。**前半句是实测抄下来的原文；末尾那句按下面这版用途说明重排过**——实测当天用的还是中文那版，此后随全局英文化改写，模板部分一字未动：

   > “CodexInNotch.app” wants access to control “Terminal.app”. Allowing control will provide access to documents and data in “Terminal.app”, and to perform actions within that app. Codex in Notch uses this to bring the terminal tab running a Claude Code session to the front when you click its row.

   两点值得记下来。其一，**用途说明确实会显示**，所以那句话是用户看到的文案而不只是一个必填字段。其二，弹窗里的应用名是 **`CodexInNotch.app`**——带 `.app` 后缀、没有空格，因为它取自 bundle 的文件名而不是 `CFBundleName`；产品叫「Codex in Notch」，这句不好看。改它要动 `PRODUCT_NAME`，牵连 scheme、二进制名与 bundle 名，不在本次范围内。
6. 不读 `~/.claude/sessions/<pid>.json`：它确实带 `entrypoint`，但那是私有 schema，而祖先链是内核公开的事实。该文件只作为二者不一致时的旁证。

禁止：按窗口标题或工作目录匹配标签页、Accessibility 点击、GUI 自动化、连接 `/tmp/cc-socks/*.sock`。

## 15. 可用性与局部降级

下表的「薄层」全部指**展开面板**。收起态只有 `Connected` 与 `Disconnected` 两个系统状态，原因不在收起态出现（见第 4 节与 `figma-design.md` §6.6）。

| 故障 | 收起态 | 展开面板 |
| --- | --- | --- |
| 无活动或未读终态，且产品已打开 | `Connected` | 薄层 `No active turns` |
| App Server 已开始连接、会话快照尚未返回 | `Disconnected` | 薄层 `Connecting`，≤ 5s |
| 尚未注册集成（产品可能已打开） | `Disconnected` | 薄层 `Set up integration` |
| 版本过旧 | `Disconnected` | 清空列表，薄层 `Update required` |
| 版本未知/未经验证 | `Disconnected` | 清空列表，薄层 `Version unsupported` |
| App Server 无响应、启动失败或连接断开 | `Disconnected` | 清空列表，薄层 `Disconnected` |
| Desktop 未读主状态缺失、损坏或不兼容 | 不变 | 保留尚未隐藏的终态行并显示诊断；不得把 backup/LKG 的空集合作为已读证据 |
| 额度失败 | 不变 | 灰色圆环；列表不变 |
| 某行预览失败 | 不变 | 隐藏该预览；其他字段不变 |

上述 Notch 薄层不提供按钮。修复/移除集成只在首次引导或 Settings 中执行。

### 15.1 在场的可信上限

Codex 的在场是内核事实，没有缓存也没有过期。Claude Code 的在场来自 `claude agents --json` 的一次外部读取，因此需要三个独立的时间参数：

| 参数 | 值 | 含义 |
| --- | --- | --- |
| `freshness` | `30s` | 距**上一次尝试**多久之后重新读取 |
| `edgeFloor` | `2s` | 收到「列表已经不对了」的**边沿**后，距上一次尝试至少多久才允许提前读取 |
| `trustCeiling` | `90s` | 距**上一次答案**多久之后陈旧答案不再被相信（三次连续失败） |

读取失败时仍然返回上一次结果，且不更新「上次成功时间」。这对**行**是对的——一次失败不是所有会话都结束了的证据，不该据此退休所有行。但在场现在决定 `Connected` 与 `Disconnected`：`claude` 被卸载、改名或移出 `PATH` 后读取会永久失败，若两个参数合一，药丸会在该进程的余生里一直显示 `Connected`。超过 `trustCeiling` 后在场为**未知**，未知落到 `Disconnected`——按第 4 节的语义这不是妥协而是字面真相：我们确实没有任何可用的连接。

**失败的尝试也要按节拍占时间。** `freshness` 曾经从上一次**答案**起算，于是一次失败什么时间都不占：下一个调用者看到答案仍然过期，立刻又跑一次命令，再下一个也一样。这一侧的刷新由 Hook 事件驱动，一个繁忙轮次每秒问好几次，因此**一次失败的读取会变成按 Hook 频率启动 `claude` 的连锁**。实测（诱发故障、真机、Debug 构建）：110 秒内 71 次启动，节拍只允许 4 次；再实测 24 个并发 `claude agents --json` 各耗 1.6 秒，单跑 0.25 秒——风暴反过来让下一次读取更慢。改为从上一次**尝试**起算，并对读取做单飞（一次刷新按设计要问两次：一次给行、一次给标记，见下），同样条件下降到 76 秒 3 次。这同时把 `trustCeiling` 恢复成表里写的意思：「连续三次失败」只有在失败之间隔着一个 `freshness` 时才真的是三次。

**边沿要能把新鲜度窗口截断，否则「刚出生」的会话整轮不可见。** `freshness` 是对「列表还能算数多久」的猜测，`~/.claude/sessions` 的变更则是有人来报告它已经不算数了——一个会话文件出现或消失，正是让缓存从「旧」变成「错」的那件事。收到报告仍然把猜测等满，代价全落在一个产品上：CLI 会话是人先起进程、再在提示符前坐一会儿才输入，等到第一条提示时列表早就追上了；**Claude Code 桌面端的会话是被第一条提示创建出来的**——进程、`~/.claude/sessions/<pid>.json`、`UserPromptSubmit` 都在一秒内到达，于是整个轮次都跑在「列表说这个会话不存在」的窗口里，而 `ClaudeCodeMonitorService` 会丢弃会话不在列表中的轮次（这是对的，只是列表得被告知）。实测 2.1.234（2026-08-18，用桌面端同款参数与 entrypoint 驱动的会话）：行在该轮 `Stop` 之后 20 秒与 23 秒才出现，也就是 *Running* 从未画出来过，*Completed* 也远晚于它所描述的那一轮。

这里同时有两处故障，各自都足以吞掉一整轮。其一，那个 watcher 是**内联构造、只留下流**的：`AsyncStream` 不持有产出它的对象（订阅是存在 watcher 里的 continuation，终止回调对 watcher 是弱引用），实例在创建它的那个表达式结束时就析构，`deinit` 结束了所有 continuation 并取消了 dispatch source——所以这条边沿不是慢，而是从 `init` 返回前就已经结束了。全应用只有这一个 watcher 是这样写的，Hook 队列与 Codex 未读适配器的都一直是存储属性。其二，边沿即使存在也没有通知会话列表：它唤醒的那次刷新照样问一个最多 `freshness` 那么旧的缓存，答案来自这个会话存在之前。修法是让边沿在**唤醒任何人之前**先把列表标记为「已知过期」，于是它引起的那次刷新正好就是重新读取的那一次；`edgeFloor` 只用来限制一串边沿能让本应用多快地启动 `claude`——实测同一时段 `~/.claude/sessions` **45 秒内 0 次变化**（一个活跃的桌面端会话加两个空闲会话）。

那个 0 曾被解释成「这些文件只在会话起止时写」，只对了一半：CLI 会话每次 `busy` / `waiting` / `idle` 翻转都会重写自己那份记录，一轮好几次。但它是**原地重写、不改名**，而目录级的 vnode 事件不为「目录里某个文件被写」触发——2026-08-18 用本应用自己的事件掩码实测：原地重写 0 次事件，新建、删除、原子替换各 1 次。所以边沿确实像那个数字说的一样稀少，**状态翻转不会作为边沿到达**，只有下一次有人重新读列表时才看得到。被中断的那一行因此原本最快也要等到下一次刷新（心跳 60 秒、列表新鲜度 30 秒）。所以**记录文件本身也被监听**（`ClaudeCodeSessionRecordWatcher`，仍然只当信号、不解析内容）：只监听那些轮次还在跑的会话的 `<pid>.json`，边沿同样先 `invalidate()` 再唤醒刷新。范围是刻意收窄的——一个没有轮次在跑的会话不必监听，它开始下一轮时 hook 会自己报到，而那一刻记录也正好翻成 `busy`，监听它只会白买一次 `claude` 启动；剩下的正是没有别的东西会报的那次翻转（`busy` / `waiting` 转 `idle` 而没有 `Stop`），一串边沿仍由 `edgeFloor` 兜住。

`invalidate()` 故意**不给协议默认实现**（与同一协议上的 `presence()` 相反）。actor 用同步方法去满足 `async` 需求是合法的，但此时 `await source.invalidate()` 在具体类型上会解析到扩展里的空实现而不是 actor 自己的那一个——两者都能编译，只有一个真的做事。没有默认实现，忘记实现是编译错误，而不是一个静默的空转。

**在场与行必须出自同一份证据。** 上一段的「行不随在场一起退休」有个前提，写在同一处：由界面通过转入 `Disconnected` 来退役它们。界面此前没有履行这一半——`MonitorAggregation.status` 先看行、后看在场，于是一个标记已经从刘海上撤掉的产品（在场为未知，矩阵不画），行里仍然写着 `Running`。用户看到的正是 Claude Code「掉线并消失、但仍在跑」。`ClaudeCodeMonitorService` 因此在 `presence` 不为 `open` 时不上报任何行；列表本身没有被丢弃，只是被扣住，下一次成功读取立刻恢复，不必等任何 Hook。

**本应用自己的额度读取不算用户的会话。** `claude -p "/usage"` 在运行的那一两秒里是一个真实的 Claude Code 会话，`claude agents --json` 报的 `kind` 就是 `interactive`——和人开的会话一字不差（实测 2.1.234，2026-08-18），唯一能区分两者的是它运行在哪个目录。要紧的是它**回答在场**——一个根本没开 Claude Code 的用户，会因为本应用刚刚自己跑了一次 `claude`，每五分钟看到该产品在刘海里亮起来一次。（它曾经还多花一行：那份 transcript 里有两条 `user` 记录而**一条 `assistant` 记录都没有**（斜杠命令根本不到模型，`num_turns: 0`），因此永远不会出现结束一个轮次所需的 `stop_reason`，当时的启动前重建会把它读成一行以本应用自己的文件夹命名的 *Running*，且活满一整个新鲜度窗口。重建已移除，这条过滤如今只为在场服务。）

因此该目录由 `HookIntegrationPaths.quotaWorkingDirectory` 统一命名，交给三个协作者：额度读取钉在它上面、会话注册表把它排除、Hook listener 丢弃带着它的事件。排除放在注册表而不是界面，因为在场是在注册表里决定的：事后再丢掉那一行，产品仍然已经被报告为「打开」。listener 那一半今天是冗余——`-p` 的斜杠命令实测不触发任何 hook——但仍然接上：「不触发 hook」是别人那条命令的性质，不是对本应用的承诺。

**stdout 不保证只有那个数组。** `claude` 会启动用户的 MCP server，其中一个实测会往命令的 stdout 上多写一行（`Client.listTools() called but server does not advertise tools capability - returning empty list`，五次里两次）。`JSONDecoder` 会因为多出来的文本拒绝整个流，而在这个边界上「解不开的列表」与「命令没有回答」不可区分——别人的一行日志因此不只损失一次读取，还会把本产品推向信任上限、把标记从刘海上撤掉。额度读取早已按行逐条解码来绕开同一件事；这里的数组是跨行 pretty-print 的，那个办法不成立，改为在流里定位从第一个 `[` 到最后一个 `]` 的区间。

**幽灵会话不需要本应用处理。** 被 `SIGKILL` 的会话来不及删除 `~/.claude/sessions/<pid>.json`，但 `claude agents --json` 按 `pid` + `procStart` 成对校验后才输出，实测（2.1.229）会滤掉它，也滤掉指向被回收 PID 的条目。该命令不输出 `procStart`，自己重做这条校验必须改读私有 schema，反而会新增一项非公开依赖去复制一条已经正确的公开实现。详见 `figma-design.md` §6.5。

单次 App Server 查询超时不等于连接断开。传输层保留现有连接，UI 继续展示最后一次可信内存快照，并在同一连接上启动至多一个独立探活流程：先等待 3 秒宽限期；其间任意带 `id` 的响应（包括晚到响应）都证明 RPC event loop 仍活跃并取消探活。宽限期内没有响应时，调用官方只读且只访问内存集合的 `thread/loaded/list`，单次最多等待 5 秒；只有该探活也超时且期间仍无任何响应，才重建只读 App Server 传输。并行业务请求超时共享同一个探活，不累计为多次连接失败；远端方法错误和协议错误本身已经收到响应，也不得触发进程重启。该恢复动作不清空 Hook reducer 或最近可信 UI。已有 Ready 等可信状态时，只有 `disconnected` 连续超过 3 秒才发布全局断开状态并清空列表；启动仍为 Connecting 且初始化已确认无响应时直接发布 Disconnected。

尚未建立本次启动后的 Hook 观察时，启动与常规轮询只用最多 5 秒的 `thread/list` 做一次**只读连通性校验**，其结果不得产生任何会话行。请求完成前保持 Connecting（该 availability 不进入收起态，收起态在此期间为 `Disconnected`——观察契约尚未建立，就还没连上）；成功返回后发布 Ready，此时若 Codex Desktop 也在运行，收起态转为 `Connected`；App Server 未响应或连接失败才发布 availability 层面的 Disconnected。该分支不重建启动前的任何会话（cold-start sync 已明确列为非目标，理由见 PRD 第 3 节），因此也不需要 `thread/loaded/list` 或逐 Thread 详情读取。建立启动后 Hook 观察后，Hook 状态立即发布；后台校正按成本分成两条独立的单飞路径。Hook 跟踪的 Thread 用 `thread/read`（`includeTurns: false`，最多 5 秒，单条元数据陈旧超过 10 秒才重取）刷新标题、preview 与 `status`；全量分页 `thread/list` 只在 Hook 出现从未列出过的 Thread、或 30 秒成员关系到期时运行，最多 15 秒。两条路径各自同一时间只允许一个请求，失败后至少 60 秒再重试，且都不得位于 Hook → UI 关键路径上。服务端不支持 `thread/read`（`-32601`）时只探测一次，之后永久回退为由 `thread/list` 提供元数据，行为退化为旧路径而不丢标题。旧列表仍可提供标题，但其请求开始时间早于最新 Hook 时不得移除该 Turn；Project 与未读元数据分别从第 1.4、1.3 节的 Desktop 状态快照解析。实时 Stop 直接把同一 Turn 标记为 Completed，不发起终态详情读取。额度与今日用量读取也必须在核心会话快照之后异步执行；两个只读请求可并发，失败按第 13 节分别降级。

## 16. 设置与持久化

### 16.1 持久化内容

允许持久化：

- 用户选择的目标显示器稳定标识；显示器临时断开时不覆盖该偏好。
- 集成安装状态与兼容性结果。
- 已成功接收过合法 Hook 的证据；不得包含 Thread、Turn 或内容。它现在是 `install.json` 里的一行 `lastEventAt`，每次运行只写一次——卡片只问「有没有到达过」，为它每个事件写一次盘就是在买一个没人读的精度。
- 非敏感应用版本/迁移标记。

禁止持久化：

- 会话列表快照、thread 标题缓存、Project 缓存、未读状态。
- Hook reducer 的 Turn 身份、lifecycle、pending input/approval evidence。这条现在由架构保证而不是由规则守住：整条路径上没有文件。
- prompt、progress、final answer、raw reasoning。
- 完整路径、命令、diff、工具参数、凭据、额度旧值。

### 16.2 Settings 行为

- Expanded footer 齿轮：调用系统 `openSettings` 打开现有 Settings scene；不安装集成、不修改偏好，也不在 panel 中创建第二份设置 UI。
- `Display`：立即将组件移动到所选显示器；目标临时不可用时回退，并在重新连接后恢复用户偏好。
- `Recheck`：重新运行只读能力检查，不静默改配置。
- `Codex integration` 总开关：On 安装或修复五条必需事件定义，Off 只移除本应用管理的配置片段并清空 repository；关闭后 Settings 保持可达。切换期间控件 disabled；失败恢复切换前显示状态并给出非破坏性错误。首次安装或定义变化后仍由用户在 Codex `/hooks` 中审核，应用不得改写信任状态。窗口里它是 `Products` 卡片中 Codex 那一行的 switch；Claude Code 那一行按 ADR 0010 给的是 `Set Up…` 而不是开关（`figma-design.md` §8.1）。
- `Clear the session list`：只清空本应用的行，不删除任何 Codex 会话；列表为空时 disabled。单行的对应动作是在终态行上右键（§17），两者共用同一个 `dismissedSessionIDs`。
- `Quota reading transcripts`：报出本应用的额度读取在 Claude Code 自己的 project 目录里留下的 transcript 总大小，尾部 `Reveal in Finder` 打开那个目录（**只报大小**：个数那一半回答的是没人会问的问题，判断值不值得去清只看大小）；**只统计不删除**，理由见 `ClaudeCodeUsageTranscripts`。**这一行有三种读数，而不是「有数字」与「没有行」两种。** 目录靠一次已经发生的读取反查出来，因此第一次读取落地之前无从计数：那时写 `Calculating…` 并把按钮置灰；量到了写 `43.2 MB` 并恢复按钮；读取已经跑完却仍未找到目录时写 `Unavailable`。判据是「有没有跑完过一次读取」（`ClaudeCodeUsageReader.attemptedAt`）而不是失败次数——`session_id` 在 `read` 内部就已记下，所以一次跑完的读取找到的目录不会还被报成在路上；而机器上没有 `claude` 时那件「正在进行的工作」已经停了，再写 `Calculating…` 就是一句不再成立的进度声明。产品若根本不留文件（Codex）则整行不存在——把它和「还没量出来」用同一个 nil 表示，正是 CC-020 里卡片自己长出一行的成因。按钮的置灰由「有没有目录」这一个来源决定，不设第二个标志位，两者因此不可能互相矛盾。
- `Quit Codex in Notch`：窗口最后一行的胶囊按钮，调用 `NSApp.terminate`，收起态组件随之从菜单栏消失。它不属于任何分组——不是设置，而是这个窗口唯一能提供的应用级动作：叠层没有自己的窗口，关掉 Settings 也不会让它退出。

## 17. SwiftUI 接入边界

当前产品 UI 层只依赖稳定 view model：

```swift
@MainActor
protocol MonitorViewModelProtocol: ObservableObject {
    var availability: IntegrationAvailability { get }
    var aggregate: AggregateState { get }
    var quota: QuotaSnapshot { get }
    var sessions: [MonitoredThreadSnapshot] { get }
    func open(threadId: String) async
}
```

Mock 与真实实现共享协议，Preview/测试继续使用 Mock；生产入口注入真实 repository。SwiftUI 不直接解析协议事件、不读取本地文件、不构造导航 URL。

**终态行的右键移除也走这条边界**：视图只发出意图（`MonitorStore.dismiss(_:)`），由 store 把该行的 `MonitoredSession.id` 记进 `dismissedSessionIDs` 并**重新走一遍 merge 发布**——列表、顶部汇总和产品标记都是从「还在显示的行」推出来的，只改数组会留下一条看不见却仍在点亮产品标记的行。`dismiss` 自己拒绝非终态行，因此这条限制不依赖调用方。SwiftUI 没有次要点击手势，`contextMenu` 给的是一个只有一项的菜单，而这个面板在指针离开后就收起；因此行上盖一层 `SecondaryClickCatcher`（`NSViewRepresentable`），它的 `hitTest` 只在当前事件是 `rightMouseDown`/`rightMouseUp` 时认领，其余一律返回 `nil` 让左键、hover 和光标跟踪照常落到下面的按钮上——`SecondaryClickView.claims(_:)` 单独拿出来就是为了让这条能被断言。它只装在终态行上。

几何继续由现有 AppKit overlay 负责：使用完整 `NSScreen.frame`，所有中间帧保持相同 `maxY`；顶部高度来自目标菜单栏。水平方向上展开态锁定 `midX`，带刘海的收起态改为锚定缺口右缘，窗口另在本体左右各留一个圆角半径的肩（见 `figma-design.md` §3.4）。三行会话展开总高为 `menuBarHeight + 280`（`240` viewport + `40` footer），空/全局状态为 `menuBarHeight + 88`（`48` body + `40` footer）。因此 `46 pt` 参考分别是 `326` 与 `134`，无刘海 `24 pt` 三行参考是 `304`。

## 18. Phase 0 验证计划

1. **版本与 schema**：记录 Desktop/内嵌 CLI 版本，生成/读取官方 schema，构建未知字段兼容 fixture。
2. **同 runtime 可见性**：证明观察器能被动看到 Desktop 当前活动 Turn，不需要 resume 或接管请求。
3. **请求状态**：分别验证 Input、两种审批形态（专用审批工具与 Bash 等普通工具）的 Approval 出现/解决及 Running 恢复；批准与拒绝两条路径都要覆盖，拒绝后既要验证 Turn 继续调用其他工具时恢复 Running，也要验证不再调用工具时由 `Stop` 收敛为 Completed；验证孤立 `PermissionRequest`、指名其他 tool 的 `PermissionRequest` 和自动审查都不会误报 Approval。
4. **终态与未读**：验证实时 Stop 与 App Server 三种结束结果都使 Running 直接进入 Completed；验证终态未读保留，Desktop 阅读后即时移除。
5. **Project/Chats**：覆盖单仓库、多仓库 Project 与无 Project Chat。
6. **删除/归档**：验证事件与集合校正都能自动移除；确认 closed 不等于 deleted。
7. **处理时间**：验证会话行与收起态逐秒推进；验证轮次转入 Approval needed 后计时不暂停、Completed 后停止；验证收起态取所有未完成轮次中的最长值，全部完成后读数消失；验证列表为空或全部完成时计时任务不再唤醒。
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
- 签名、公证、性能与无障碍审计。

## 20. 测试策略

### 20.1 单元测试

- reducer 合法/非法转移、乱序与重复事件。
- 缺失 `session_id/turn_id` 失败关闭；旧 Turn 的 Permission/Stop 不能改变新 Turn。
- `request_user_input` 只被相同 `tool_use_id` 的 Post 清除；无关 Post 不清除 Input 或 Approval。
- 启动前积压的 UserPrompt/Permission/Input/PostTool/Stop/SessionEnd 都不进入 Turn reducer；持久化文件只保留布尔配置健康标记，迁移旧 `turns` 后内存仍为空。
- 监视成员集合的 active/unread/archive/delete 规则。
- 四态合法流转、Completed 粘性与汇总优先级。
- Project 无近似回退、标题回退。
- Desktop Project 私有状态的 local/remote/Chats 精确解析、`thread.section` 隔离、主文件/backup/last-known-good 降级，以及缺失 assignment 显示 `Project unavailable`。
- Running 状态名称与额度读数不受时间推进影响。
- Compact token 数字边界、今天/明天/多日 reset 文案与本地时区日界线。
- 额度/今日用量账户切换、15 秒请求超时、60 秒重试和独立 unavailable。
- 并行业务超时只启动一个 `thread/loaded/list` 探活；探活成功或宽限期内收到晚到响应时不重启，探活也超时时才重建传输。
- 有会话与无会话 footer 都为 `40 pt`，展开高度分别包含 `280`/`88 pt` 内容区。
- Settings gear 的无障碍名称与现有 Settings scene 打开行为。

### 20.2 集成测试

- 三个并发 Thread：Input、Running、未读 Completed。
- 同名 Thread、同名 Project 不合并。
- 多仓库 Project 与 `Chats` 显示一致。
- Desktop 阅读、归档、删除自动移除。
- Codex in Notch 重启无缓存闪现并正确重建。
- Desktop 未运行、低版本、未知新版本与重连。
- 点击每一行进入相同 Thread；不存在目标保持面板。

### 20.3 集成边界测试

- 确认诊断与日志不写入用户路径以外的凭据；Claude Code 这条通道已经没有 token 可写。
- 确认不申请 Accessibility/Screen Recording——这是一条安装摩擦的取舍，不是隐私承诺：这两项授权都要用户去系统设置里点，而本产品能做到的事不值这个价。
- 确认 observer 不发送会改变 Thread/Turn 的方法。
- 确认移除集成不会删除用户其他配置。
- 确认总开关 On/Off 分别安装与移除完整六项集合；缺少、重复或 matcher/handler/timeout 被改写时进入 `repairRequired`，重新开启可修复且不删除用户其他 Hooks。

## 21. Figma 对应

| 页面/节点 | 技术契约 |
| --- | --- |
| `06 — Notch Core` / `118:120` | `520 × 326` 共享展开、顶部 `46`、底部 `40` footer |
| `05 — Panel` / `327:305` | `496 × 40` Expanded footer、今日 tokens、reset 文案与 Settings gear |
| `07 — Integration States` / `227:3` | 额度局部降级、成员生命周期和 `520 × 134` 薄层状态 |
| `08 — Onboarding` / `232:95` | 显式授权的三步首次安装 |
| `09 — Settings` / `609:2` | macOS 26 单面板设置窗口：Products／Display／Session list 三组、两模式颜色；`233:3` 为 v1 参考 |

## 22. 参考

- [Codex App Server](https://developers.openai.com/codex/app-server)
- [Codex Hooks](https://learn.chatgpt.com/docs/hooks)
- [`CONTEXT.md`](../CONTEXT.md)
- [`docs/adr`](adr/)
