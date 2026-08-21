# Hook 事件不落盘，一条 socket 直接进 reducer

两个产品的 hook payload 现在都由 `hook.sh`（`sh` + `nc -U`）送进一条 0600 的 Unix domain socket，由 `AgentHookListener` 按到达顺序交给 `HookEventRepository`。**中间没有文件。**

## 为什么

事件队列存在的唯一理由，是 Codex 侧第一版的 helper 是一个 shell 脚本、它没有办法和一个正在运行的进程说话。有了 socket，下面这些全部失去存在理由：

- 原子 temp-and-rename 写入、每个事件文件的 `0600` 属性、按 `time_ns` 文件名排序；
- 损坏文件隔离到 `.invalid`、消费后删除、marker 落盘失败时回滚 reducer 状态；
- 队列目录上的 `DirectoryChangeWatcher` 和它每次刷新都要重试的 `attachIfNeeded`；
- `hookEventDebounceInterval`——**每一次 hook 驱动的重画都多加 100 ms**，而这正是用户盯着某一行等它变化的那条路径。

第二条 socket 也一起走。`HookPreviewChannel`、`event_id` 接合、`claimPreview`、未认领预览的保留上限，全部只因为「正文不许进事件文件」而存在。一条 socket 带整份 payload，就没有这个拆分。

**队列的删除还带走了一条跨产品的绕路。** `AgentHookListener` 从 socket 收到 Claude Code 的 payload，再把它写成事件文件，只为了让 `HookEventRepository`——一个目录读取器，因为 Codex——能把它读回来。这次改动删掉了那个读取器的最后一个客户。两个产品现在是同一个 store、同一个 reducer、各自一条 transport。这是本次改动里最大的一处简化，而它是把 Codex 这条路径设计对之后的副产物。

`.invalid` 的实际后果值得记一笔：本机 `agents/claudeCode/events/` 累计了 **155 个**隔离文件，没有任何东西会再读它们，也没有任何东西会清它们。现在无法解析的 payload 是「报一个诊断然后丢掉」，没有可以被留下的地方。**这句话曾有半年是假的**：6aeb6b9 删掉了队列时代那句 `Ignored a corrupted hook event file.`，却没有给它继任者，于是它只剩「丢掉」（CR-029）。现在 `deliver` 数下每一份读不懂的 payload——包括一个字节都没送到的连接——按本次运行累计报出来，并且到达 Settings 里该产品那一行。

## 三条守则变成架构性质

- **没有启动 cutoff。** 到达的事件按构造就是当前的：它顺着 socket 进到这个进程，来自片刻之前跑过的一个 helper。`AGENTS.md` §6.2 的「历史事件不携带业务语义」不再是一次对 `received_at` 的检查，而是一条性质——**没有 backlog，因为什么都没有被写下来**。`liveEventCutoff` 与 backlog 分类随之消失。
- **正文不需要承诺。** 它留在内存里，是因为它没有别的地方可去，而不是因为有一条规则禁止别的做法（PRD §7 已经删掉那条承诺）。
- **`retiredTurnIDs` 保留。** 提案里它随 cutoff 一起删除，理由是「串行读取队列上取的到达戳是单调的，所以退休轮次的迟到事件不可能存在」。这对 transport 成立，对 executor 不成立：ADR 0013 记录了 Claude Code 在同一个 `prompt_id` 下把 `Stop` 排在自己 subagent 的 `PermissionRequest` 前面交付，而 reducer 是两个产品共用的。Codex 那一半也没有实测。所以它留下，代价是每个被跟踪 thread 一个 `Set`。

## 只在画出来的东西变了时才发信号

store 现在**只在渲染投影变化时**发一次变更信号——状态、轮次身份、或者行上那句正文——而不是每来一个事件发一次。一个 17 事件的轮次是一次唤醒，不是十七次。这是 `AGENTS.md` §7 在源头上被满足：重画次数跟着画出来的东西走，而不是跟着内容变化走。

流式 delta 不在这个投影里，这不是疏漏。一行正文由该轮次自身生命周期事件引起的刷新顺带更新；把 delta 放进投影就是每秒 3.4 次重画一句用户正在读的话（`system-architecture.md` §6 的实测）。唯一需要自己一条边沿的是**行上什么都没有**那一种，它按原样保留：只报「从没有到有」，并且只为上一次刷新列出过的会话报。

## 保序：一个 GCD 队列交给一个 actor

listener 的串行读取队列保证 `deliver` 按 payload 落地的顺序被调用。这里不能用 `await` 把它交给 actor——按顺序 spawn 的两个 `Task` 不是按顺序运行的两个 `Task`。所以 payload 先按顺序进一个锁保护的 inbox，drain 一次把整个数组取走：无论哪个 drain 先跑，看到的都是一个前缀，每份 payload 恰好被 reduce 一次，顺序就是到达顺序（`AGENTS.md` §6.3）。

同样的理由让 `MessageDisplay` 的折叠留在读取队列上、由一个锁保护的 preview store 承接，而不是进 actor 的 mailbox：那条路径每秒 3.4 次，一次 actor hop 会把它放上产品的关键路径，换来的是零。

## 代价

- **没有崩溃缓冲。** 队列是「事件到达与被 reduce 之间」唯一能扛住崩溃的地方。这个窗口不值钱：内存里的轮次状态会在同一次崩溃里一起消失，而本设计本来就丢弃启动之前写下的一切。
- ~~**一份 payload 超过 1 MB 会被丢弃而不是截断。**~~ **这一条判断错了，已由 CR-030 改掉。** 原来的理由——「半份 payload 解不出有用的东西」——只对**整份解码**成立，而这条路径恰恰不该整份解码。reducer 要读的字段一共几百字节，大起来的全是它不读的那些：`PostToolUse` 带 `tool_response`（一次大文件 `Read`、一条长 stdout、一次宽 `Grep`），`UserPromptSubmit` 带 `prompt`（用户粘进去的东西）。拿「整份 payload 的大小」去决定「这个生命周期事件听不听得见」，等于把工具结果的大小当成了轮次的证据；丢掉的那一份里最难受的是 `PostToolUse`——它不关掉自己 `tool_use_id` 上的等待，而 Claude Code 这边 `reportsApprovalDenials = true` 特意拿掉了借用推断，于是那一行停在 *Approval needed* 直到本轮 `Stop`。

  现在字段选择发生在解码**之前**：`HookPayloadDistiller` 在字节上走一趟，只取 `HookPayload.CodingKeys` 认识的键，其余的值跳过——不拷贝、不解码、不测量——`JSONDecoder` 拿到的是一个几百字节的小对象。它仍然是「字段是什么意思」的唯一权威，这一趟只决定它能看见哪些字节。于是 transport 上的上限只约束**读队列的时间**，不再约束 reducer 能被告知什么。

  代价换了形状，没有消失：
  - **正文截断在 16 KiB，身份不截断。** 行上只画 240 字符，短一点的正文还是同一个答案；半个 `session_id` 却是另一个会话，所以过长的身份是整个字段不要，payload 随之丢掉——fail closed 的那一侧（`AGENTS.md` §6.2）。
  - **超过 16 MiB 的连接被切断，切断之前已经完整到达的字段照常生效。** 切在哪个字段之后由 payload 自己的字段顺序决定，而字段顺序不是任何一方的契约；同一条也覆盖「客户端连上之后不再写」的那种半份 payload。
  - **小 payload 每个事件贵 3 µs。** Release 实测：1.4 KB 的 `PostToolUse`，整份解码 5.0 µs、选择加解码 8.0–9.7 µs，对照这条路径本身的 2.06 ms/事件。**1 MB 上下反而快 4.7 倍**（976 KB：416 µs → 89 µs），因为 `JSONDecoder` 不再看那个工具结果；8.8 MB 时选择比整份解码慢 1.4 倍（3.6 ms → 5.2 ms），那是逐字节扫描在出了 L2 之后受内存带宽限制——而那个尺寸此前的结果是整份丢弃，所以那里没有回归，只有以前不存在的工作。
- **连接关闭在交接之后。** 早几微秒关会拿掉这条路径上唯一的背压：同一个会话的两份 payload 会同时在途，而读取队列存在的那个顺序会改由调度器决定。

## 状态

已实施。`AgentHookListener` 只做 transport（绑定、accept、读一份 payload、交出去），`HookEventRepository` 持有 reducer、正文与投递证据。`HookPreviewChannel.swift` 已删除。测试：`aPayloadTheStoreCannotReadIsReportedRatherThanDroppedInSilence`、`theReportOfADroppedPayloadStandsForTheRun`、`whatAProductReportedReachesTheCardThatReportsIt`、`anOversizedToolResultStillClosesTheWaitItBelongsTo`、`aPromptTooBigToForwardStillOpensItsTurnAndStillReadsAsItself`、`aConnectionPastTheCeilingIsCutAndKeepsWhatArrivedWhole`、`selectingFieldsReadsTheSameAsDecodingTheWholePayload`、`anIdentityTooLongToBeOneIsLeftOutRatherThanCutShort`、`aTextFieldIsCutOnlyWhereAJSONStringCanBeCut`、`aPayloadThatStopsPartWayThroughKeepsTheFieldsThatArrivedWhole`、`payloadsAreReducedInTheOrderTheyLanded`、`theStoreSignalsWhatIsDrawnAndNothingElse`、`nothingAThirdPartyCouldReplayIsEverWrittenDown`、`theListenerHandsOverOnePayloadPerConnection`、`aPayloadWrittenAfterTheConnectionIsAcceptedStillArrives`、`messageDisplayTextIsHeldInMemoryAndReducesNothing`、`aPreviewArrivingWhereThereWasNoneAsksToBeDrawn`。
