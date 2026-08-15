# Current Issues

本文只保留当前工作树中仍可复现或可由代码直接证明的问题。已经解决的问题不继续留在本表；修复后应同时补齐测试与相关设计文档，再从本文件删除。

本轮审查基线：`2026-08-15`，代码基线为 `a9764f8` 加当前工作树。审查范围覆盖状态模型、Hook 安装与 reducer、App Server transport、会话聚合、Desktop 私有只读适配器、Store、导航、Notch/UI 和核心测试。另以当前 Desktop 内置 Codex CLI `0.148.0-alpha.9` 做了一次独立 App Server 只读探针。

CR-021（App Server stdio 分帧被并发投递打乱、响应被静默丢弃）已在当前工作树修复并移出本表：分帧改为在串行化的 readability queue 内同步完成，JSON 解码移出 actor，单帧超限 fail closed，解码失败改为有界且不含正文的诊断。

CR-002（每批 Hook 事件都触发全量分页 `thread/list`）也已修复并移出本表：Hook 跟踪的 Thread 改用 `thread/read`（`includeTurns: false`）按 id 读取元数据，全量列表只保留低频成员关系对账。残留的「刷新进行中丢失失效信号」仍记在 CR-003。

CR-010（冷启动无法重建 Desktop 当前会话状态）已**作为非目标关闭**，不再是缺陷：产品能力现已严格限定为「本次启动之后开始同步会话列表」，启动前的运行中／未读终态／等待审批会话一律无视。决策依据是下面的实测边界；对应实现移除了 `activeSession` 与冷启动会话构建，PRD 第 3 节已把 cold-start sync 列为非目标。

### 针对 App Server 能力边界的实测结论

用 `codex app-server generate-json-schema --experimental`（CLI `0.148.0-alpha.9`）导出的官方 schema，加两轮只读探针——**其中一轮在一个真实运行中的 Turn 上采样**——确认：

1. **`thread/list` 永远返回空 `turns`。** schema 原文：`turns` 仅在 `thread/resume`、`thread/rollback`、`thread/fork` 和 `includeTurns: true` 的 `thread/read` 响应上填充。实测 33 个线程全部为空，且 `minimal` / `useStateDbOnly=true|false` / 应用当前参数四种组合结果一致。
2. **`thread/loaded/list` 恒为空，即使有 Turn 正在运行。** 独立 App Server 进程看不到 Desktop 运行时。历史上那个 `guard !loadedIDs.isEmpty` 门槛因此从来不可能通过。
3. **`status.type` 恒为 `notLoaded`，即使有 Turn 正在运行。** 因此 `CodexSnapshotParser.activeEvidence` 依赖的 `status.type == "active"` **永不成立**，`activeFlags` 校正路径在当前拓扑下是空转——不只是启动分支，Hook 分支中的纠偏同样如此。该代码保留只为将来出现共享运行时拓扑时无需重写，**不得据此推导任何当前能力**。
4. **`inProgress` 从不出现。** 运行中的 Turn 在持久化数据里被记为 `status: "interrupted"` 且 `completedAt` 为 null；`thread.updatedAt` 会随真实时间前进（空闲线程则严格按墙钟变旧）。也就是说唯一可用的活跃信号是 `completedAt == null` + `updatedAt` 新鲜度，而非任何 status 字段。

第 3、4 条同时说明：即使将来要恢复某种启动同步，也不能建立在 `status`／`inProgress` 之上。

优先级定义：

- `P0`：会造成严重数据破坏、安全事故，或使核心产品在正常条件下完全不可用，必须阻断发布。
- `P1`：核心状态正确性、隐私承诺或用户配置安全存在明确缺口，应优先修复。
- `P2`：存在明确的可靠性、性能、协议完整性或回归保护风险，应纳入近期迭代。
- `P3`：低频降级、诊断能力、文案或维护性问题，可排在核心问题之后处理。

## P0

本轮未发现 P0 问题。

## P1

| ID | 问题 | 代码证据与触发条件 | 导致的后果 | 建议修改方式 |
| --- | --- | --- | --- | --- |
| CR-003 | `thread/list` 刷新进行中收到新的失效信号时会直接丢弃，没有 dirty revision 和补跑。 | [`scheduleThreadListRefreshIfNeeded`](../CodexInNotch/CodexInNotch/LiveCodexMonitorService.swift) 在 `threadListRefreshTask != nil` 时直接返回；完成后只清空 task，并把读取开始时间写入 `threadListReadAt`。 | 旧结果即使因 Hook freshness boundary 被拒绝，也可能没有后续请求；等待审批、线程成员关系或元数据修正最多延迟到下一次 30 秒对账。 | 使用 single-flight + monotonically increasing dirty revision。刷新期间只累积失效；当前请求结束后若 revision 已变化，立即补跑一次。失败退避也应保留 dirty 状态。 |
| CR-011 | “预览内容不持久化”的产品承诺与实际 Hook 队列不一致。 | [`hookScript`](../CodexInNotch/CodexInNotch/HookIntegration.swift) 在预览开启时把 prompt 和 final-answer 片段写入权限 `0600` 的 JSON 事件文件；应用未运行或无法消费时文件会持续留在磁盘。Onboarding 和 Settings 却明确显示 “No prompt or answer is persisted” / “No preview text is persisted”。 | 用户可能在错误的隐私认知下开启功能；敏感正文会在本地事件目录形成无明确 TTL 的积压。 | 最干净的方向是让 Hook 只传身份与生命周期信号，正文只从受支持的当前快照读取并保留在内存。若短期仍需落盘，必须明确披露临时持久化、设置严格 TTL/数量上限、启动清理和失败清理，并修改 UI/PRD/技术设计中的绝对化承诺。 |
| CR-012 | 隐私开关对 Hook helper 的设置更新是无确认、可乱序的 best-effort 操作。 | [`showsContentPreviews.didSet`](../CodexInNotch/CodexInNotch/MonitorStore.swift) 每次创建一个未持有的 `Task`；[`updateHookSettings`](../CodexInNotch/CodexInNotch/LiveCodexMonitorService.swift) 用 `try?` 吞掉写入失败。快速切换、进程退出或写文件失败后，没有 revision、最终值校验或错误回滚。初始化时也不会主动把 UserDefaults 最终值与 Hook settings 对账。 | UI 可以显示预览已关闭，但 helper 仍按旧设置把内容写入事件文件；这是隐私开关的 fail-open。 | 由 Store 持有一个串行设置任务或 revision，旧写入可取消但最终值必须落盘并读回验证；失败时保持 UI 为安全关闭并显示诊断。启动时主动对账，helper 在设置缺失、损坏或过期时继续默认关闭。 |
| CR-013 | Hook 配置的安装/移除在结构异常时没有 fail-closed，可能覆盖用户配置或留下悬空命令。 | [`mergeHooksConfiguration`](../CodexInNotch/CodexInNotch/HookIntegration.swift) 会把“合法 JSON 但根不是 object”或 `hooks` 不是 object 的内容当成空字典；某个 event value 类型异常时也可能被新的 managed group 覆盖。相反，[`removeManagedHooksConfiguration`](../CodexInNotch/CodexInNotch/HookIntegration.swift) 遇到同类结构会静默返回，随后 `uninstall` 仍删除 helper 与 settings。 | 安装可能丢失非本应用管理的 Hook 内容；移除可能让 `hooks.json` 继续引用已删除脚本。两者都违背“只管理六个定义并保留用户 Hooks”的边界。 | 对根、`hooks`、每个将修改的 event/groups/handlers 做严格结构验证；任何不兼容都停止写入并返回可见错误。只有成功移除全部 managed definitions 后才能删除 helper。为合法 JSON 的错误根类型、错误 hooks 类型和混合 event 类型增加保留性测试。 |

## P2

| ID | 问题 | 代码证据与触发条件 | 导致的后果 | 建议修改方式 |
| --- | --- | --- | --- | --- |
| CR-005 | `thread/list` 只有单页超时，没有整个分页过程的总预算。 | [`readAllUnarchivedThreads`](../CodexInNotch/CodexInNotch/LiveCodexMonitorService.swift) 有重复 cursor 检查，但没有 wall-clock deadline、最大页数或最大条目数。触发频率已随 CR-002 的修复从「每秒」降到「30 秒成员关系对账或出现未列出 thread」，但单次调用本身仍无上限。 | 数据量大或服务端不断返回新 cursor 时，总耗时可达到“页数 × 单页超时”，长期占用后台任务。 | 增加整体 deadline、最大页数和最大条目数；只有完整分页成功才原子替换成员关系，超限时保留可信旧状态并记录诊断。 |
| CR-006 | 活跃状态下每个一秒周期会重复执行 Hook 安装完整性扫描。 | `fetchSnapshot` 先执行 upgrade 检查，再读取 status；Store 随后又调用 `hookSetupStatus`。每次都会读取脚本、`hooks.json`、settings 并计算哈希，event directory 也会被消费两次。 | 无状态变化时仍持续产生磁盘读取、哈希计算和系统唤醒，增加空闲 CPU 与能耗。 | 每轮构造一次 Hook health snapshot 并复用；完整性检查改为启动、手动 Recheck、文件变化通知或 30–60 秒低频校验。 |
| CR-007 | App Server 请求取消不会传播到 pending request，响应后 timeout task 也不会主动取消。 | [`performRequest`](../CodexInNotch/CodexInNotch/CodexAppServerClient.swift) 用 continuation 注册 pending 后创建未持有的 sleep task；没有 cancellation handler。连接 waiters 同样不响应调用方取消。 | 已取消刷新仍占用 RPC；大量快速响应留下休眠任务，并扩大 timeout/response/disconnect 竞态面。 | 用 cancellation handler 和显式 request token 管理生命周期；保存并取消 timeout task，保证 pending continuation 只完成一次，并覆盖响应、超时、取消、断连竞争测试。 |
| CR-008 | 手动刷新和 Desktop 文件变化发生在自动刷新中时会被直接丢弃。 | [`performRefresh`](../CodexInNotch/CodexInNotch/MonitorStore.swift) 在 `isRefreshInFlight` 时立即返回；`refreshNow`、Recheck 与 directory watcher 没有 pending 标记。 | 用户点 Recheck 可能立即结束但仍看到旧状态；Desktop unread 的低延迟通知也可能只能等待下一秒轮询。 | Store 同样采用 single-flight + dirty/pending；显式用户刷新至少保证当前任务后补跑一次，并等待补跑结果再返回。 |
| CR-014 | Hook 事件目录的消费没有文件大小、批次数量或总工作预算。 | [`consumeEvents`](../CodexInNotch/CodexInNotch/HookIntegration.swift) 每轮枚举、排序并完整读取所有 JSON；历史事件虽然不进入 reducer，仍逐个解码后才删除。删除失败也被忽略，文件可在后续轮次反复出现。 | 应用长时间未运行、高频工具调用或异常大文件都可能让启动/刷新长时间占用 actor；删除失败还会持续触发全量列表失效。 | Hook 写入和读取两端都设置单文件大小、队列数量、每批数量与 wall-clock 上限；启动先按 cutoff 快速清理历史文件，失败移入有界 quarantine，并把删除失败作为可诊断错误。 |
| CR-015 | Desktop Project 私有 schema 只要求四个顶层 key 中任意一个存在，部分或未知映射会被当成成功。 | [`GlobalState.init`](../CodexInNotch/CodexInNotch/CodexDesktopProjectMetadata.swift) 使用 `contains(where:)`，缺失 key 默认空集合；未知 `projectKind`、不存在的 `projectId` 和空 thread id 会被静默跳过。清单文档却声明不兼容 schema 应 fail closed。 | Desktop schema 漂移可能被错误标记为 `.current`，既没有兼容性诊断，也可能只丢失部分 Project/Chats 映射。 | 明确当前版本的最小必需 key 集；assignment 必须引用已知 project 且 kind 受支持，thread id 不得为空。任何不一致都拒绝整份 current snapshot，转 backup/last-known-good，并补齐 partial/unknown/dangling fixture。同步核对非公开 feature 清单中的契约描述。 |
| CR-016 | JSON-RPC envelope 分类只看整数 id，不能正确区分 response 与 server-initiated request。 | [`handleEnvelope`](../CodexInNotch/CodexInNotch/CodexAppServerClient.swift) 只要 `id` 可转 Int 就从 pending 中移除；公开 schema 的 request id 同时允许 string/integer，而带 `method + id` 的 server request 也可能使用整数。 | 若 server request id 与本地 pending id 碰撞，正常请求会被误判为缺少 result 的 response 并失败。当前只读路径触发概率较低，但 transport 本身并不满足双向协议边界。 | 先按 envelope shape 分类：response 必须有 `result` 或 `error` 且无 `method`；server request 单独走显式只读拒绝/unsupported response。增加 numeric id collision 测试。 |
| CR-017 | Integration 总开关的 install/remove 任务也没有串行意图或 revision。 | [`setIntegrationEnabled`](../CodexInNotch/CodexInNotch/MonitorStore.swift) 先改变 UI 值再创建未持有 Task，真正的 `isInstallingIntegration` / `isRemovingIntegration` 标记在任务开始后才设置。快速来回切换可在标记生效前排入相反操作。 | 安装和移除可能按非用户最终意图的顺序完成，UI 回滚也可能覆盖更新后的真实状态。 | 用单一持有任务和 desired-state reducer 串行收敛到最后一次选择；所有操作完成后重新读取 Hook health，再发布 switch 状态。 |
| CR-009 | 关键边界仍缺少确定性回归测试，live tests 未运行时表现为普通通过。 | 当前测试没有覆盖刷新中的 dirty invalidation、分页总预算、request cancellation、隐私设置乱序/写失败、Hook 错误结构、或 server-request id 碰撞。两个 live test 在未设置 `CODEX_IN_NOTCH_RUN_LIVE_TEST=1` 时直接 `return`。 | 测试全绿仍可能遗漏本表最关键的状态丢失、隐私 fail-open 和后台任务泄漏。 | 注入 Clock/调度器与可控文件写入器，补齐上述确定性测试；live test 应使用测试框架的显式 skip/disable 机制并输出原因，并在受控环境定期执行真实 Codex Desktop 的启动后四态场景。 |

## P3

| ID | 问题 | 代码证据与触发条件 | 导致的后果 | 建议修改方式 |
| --- | --- | --- | --- | --- |
| CR-018 | Desktop 状态目录 watcher 不会在初始化失败或目录被替换后重新挂载。 | [`CodexDesktopStateDirectoryWatcher`](../CodexInNotch/CodexInNotch/CodexDesktopUnreadState.swift) 只在 init 时 `open(O_EVTONLY)` 一次；失败便永久结束 stream，收到 rename/delete 也只 yield，不重建 descriptor。 | 一秒轮询仍能兜底，因此不会永久丢状态，但 unread 变化的 250 ms 低延迟路径会悄然失效。 | watcher 增加重新 attach 状态机与退避；目录 rename/delete 后关闭旧 source 并重新打开，暴露 watcher health 诊断。 |
| CR-019 | App Server 子进程 stderr 被直接丢弃，版本不兼容缺少可定位的诊断。 | [`connect`](../CodexInNotch/CodexInNotch/CodexAppServerClient.swift) 把 `standardError` 设为 `FileHandle.nullDevice`。分帧上限与 undecodable frame 诊断已随 CR-021 修复补齐，stderr 通道仍是空白。 | 协议或版本不兼容只能表现为超时或 `-32601`，无法区分「子进程启动后立刻报错退出」与「服务端沉默」，定位困难。 | 为 stderr 增加有界、脱敏的采集（固定行数上限、不记录正文 payload），并在 `launchFailed` / `disconnected` 诊断中带上最近若干行。 |
| CR-020 | Assets 中仍有未被代码引用的 failed 状态资源。 | `StatusFailedRing` 与 `StatusFailedX` 未被任何代码引用，但会话模型已只有四态。（Onboarding 关于 Completed 生命周期与启动范围的文案已随冷启动同步下线一并更新。） | 设计资产继续暗示 failed 是产品状态。 | 删除未引用 failed assets，并在设计文档/视觉资源检查中固定四态集合。 |

## 修复顺序建议

1. 先处理 CR-011、CR-012、CR-013，收紧隐私与用户 Hook 配置边界。
2. 用同一个 revision/single-flight 抽象收敛 CR-003、CR-008，避免继续叠加互相独立的布尔补丁；现在成员关系与元数据是两条独立的单飞路径，该抽象应同时覆盖两者。
3. 完成 P2 的有界队列、分页、取消和协议分类后，再清理 P3 与补齐完整回归矩阵。

传输层分帧（原 CR-021）已完成，是上述所有状态正确性工作的前提：在它修好之前，任何依赖 App Server 响应的结论都可能因为响应被静默丢弃而失真。
