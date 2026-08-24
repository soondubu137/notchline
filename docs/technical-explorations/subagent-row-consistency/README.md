# 子智能体在跑时，整个界面怎样说同一句话

| 字段 | 内容 |
| --- | --- |
| 文档状态 | **全文已采纳并实现（2026-08-23）**：第 4、5、8.1 节先落地，第 6 节（子智能体的审批）在两个产品的前置实测完成后于同日落地——实测见 6.1（Claude Code）与 6.3（Codex），方案与落地记录见 6.2。落地后的契约在 `PRD.md` §6.2／§8.2／§9.3、`CONTEXT.md`「派生状态」、`tech-design.md` §9.2 与 `figma-design.md` §4.6，本文此后只作为「为什么这样做」的记录，不是契约。外部 Figma 画布本身在同一天补了对应节点——`112:28` 新增两个 Completed 尾部变体，`115:82` 新增一个 no-notch 合成读数变体，见 `figma-design.md` §2／§3.1／§4.6 |
| 首次记录 | 2026-08-23 |
| 探索点 | Codex 一条 Thread 自己的 Turn 结束、但它派生的子智能体还在跑时，如何让收起态、排序、成员关系与行本身说同一句话 |
| 目标读者 | 决定是否采纳的人，以及采纳后实现它的人 |
| 范围 | 一期只谈 Codex 一侧；第 8 节记的 Claude Code 一侧已于 2026-08-23 实测并落地，见 8.1 |
| 依据 | 阅读 `65e63ab` 及其后的工作树（`d290f04`）：`HookIntegration.swift`、`MonitorDomain.swift`、`MonitorStore.swift`、`NotchOverlayView.swift`、`LiveCodexMonitorService.swift`、`CodexDesktopUnreadState.swift`，以及 `PRD.md` §6.1/§6.2/§9.3、`CONTEXT.md`「会话状态」「终态原因」、`docs/non-public-codex-integration-features.md` 子智能体那一行 |
| 实测 | **没有自己的实测。** 文中出现的每一个数字都来自已有文档或代码注释，并在使用处注明出处 |

> 目录约定沿用 [`shared-app-server/README.md`](../shared-app-server/README.md)：每个探索点一个二级目录，后续证据追加而不是覆盖既有证据。

## 1. 先纠正一个说法

现状**不是**「保持 Running 并把计数写在计时的位置」。`65e63ab` 之后的行为是：主智能体的 `Stop` 照常落地，Turn 进入 `Completed`，预览换成最终回答，计时停下，**计数写在计时腾出来的那个位置**——`runningSubagentSummary` 明确以 `!status.keepsTiming` 为前提（[`MonitorDomain.swift:453`](../../../Notchline/Notchline/MonitorDomain.swift)）。

本文全部基于代码的实际形状，而不是那句描述。这个区别很重要：真的把行按在 `Running` 上，就是把 `65e63ab` 修掉的缺陷放回来（第 7 节）。

## 2. 现状：四条规则把状态当成了「这条 thread 还在不在干活」

行本身是对的。问题在于**别处**有四条规则读 `SessionStatus`，并且默认「`.completed` == 这里什么都没发生」。对这一种行来说，这个默认是假的。

| # | 规则 | 位置 | 现在会发生什么 |
| --- | --- | --- | --- |
| 1 | 顶部汇总与产品标记 | [`MonitorDomain.swift:822`](../../../Notchline/Notchline/MonitorDomain.swift)、`:844` | 这一行只贡献 `.completed`。它是最后一行时，收起态写 `Completed`、矩阵画完态、计时消失（`longestRunningSessionStart` 按 `keepsTiming` 过滤，[`MonitorStore.swift:1230`](../../../Notchline/Notchline/MonitorStore.swift)），而展开后的那一行写着 `2 subagents`。**用户真正在看的那块表面，说的是反话。** |
| 2 | 未读成员关系门 | [`CodexDesktopUnreadState.swift:100`](../../../Notchline/Notchline/CodexDesktopUnreadState.swift)、调用点 [`LiveCodexMonitorService.swift:800`](../../../Notchline/Notchline/LiveCodexMonitorService.swift) | 终态行在 Desktop 报告「已读」后被隐藏，边界取 `state.lastEventAt`，而子智能体边界**故意不推进** `lastEventAt`（[`HookIntegration.swift:2485`](../../../Notchline/Notchline/HookIntegration.swift)）。于是这句话可能在主 `Stop` 之后一个 settling interval 就被抹掉——而正在 Desktop 里盯着这条 thread 的人，恰恰是最可能刚派生出子智能体的人。 |
| 3 | 排序与三行视口 | [`MonitorDomain.swift:887`](../../../Notchline/Notchline/MonitorDomain.swift)、`maximumVisibleSessionCount = 3`（[`MonitorStore.swift:138`](../../../Notchline/Notchline/MonitorStore.swift)） | `.completed` 排最后。另有三个活跃 Turn 时，**唯一携带「还有活在跑」证据的那一行第一个被挤出视口**。 |
| 4 | 手动移除 | [`NotchOverlayView.swift:570`](../../../Notchline/Notchline/NotchOverlayView.swift) | 一条正在报告「还有活在跑」的行可以被次级点击移除，且按 Turn id 记住，不再回来。 |

另有两处不属于「状态被当成代理」，但同样是这次改动带来的不一致：

- **子智能体的审批看不见。** 带 `agent_id` 的事件成对丢弃（[`HookIntegration.swift:2256`](../../../Notchline/Notchline/HookIntegration.swift)），所以子智能体自己的 `PermissionRequest` 不再到达行。行会稳稳地写着 `1 subagent`，而 Codex 其实卡在一个对话框上——**本产品存在的理由正是报告这一种状态**。`SubagentStop` 丢失时同样是这个形状：计数不动，行上没有任何东西能把「卡住」和「在忙」分开（这一点 `65e63ab` 已经明说，此处只是指出它在 UX 上的读法）。
- **尾部那个文字位的将来。** `CONTEXT.md`「终态原因」把同一个位置留给了失败原因的文字。今天它还没有实现，一旦实现，「一行只有一个标记，而且它是计时」这条规则并不能在两段文字之间做裁决。另外，计时停下的那一刻，尾部元素从一个短计时变成一段更长的文字（`.fixedSize()`，面板宽度固定在 `expandedBaselineWidth = 520`，[`MonitorStore.swift:136`](../../../Notchline/Notchline/MonitorStore.swift)），标题与预览会在完成的瞬间重新截断。属于观感问题，不影响正确性。

## 3. 设计原则

**行画出来的状态不变，改的是别人问的那个问题。**

Turn 确实结束了：预览确实是最终回答，计时确实该停，`Completed` 确实是终态——`CONTEXT.md`「会话状态」说的是**当前处理轮次**的状态，子智能体是 thread 的活，不是这一轮的活。所以不加第五态，也不改这一行的状态。

要修的是：上面那四条规则问的其实是「这条 thread 还在不在干活」，却拿 `SessionStatus` 当答案。给它们一个真正的答案即可。

## 4. 方案

### 4.1 一个派生判据

```swift
// MonitorAggregation
/// 「这条 thread 还在不在干活」——与行画出来的状态是两个问题。
/// 只有 `.completed` 且仍有子智能体在跑时两者才分叉。
nonisolated static func effectiveStatus(of session: MonitoredSession) -> SessionStatus {
    session.status == .completed && session.hasRunningSubagent ? .running : session.status
}
```

`hasRunningSubagent` 已经存在（[`MonitorDomain.swift:443`](../../../Notchline/Notchline/MonitorDomain.swift)），除 Codex 外的产品恒为零，所以这个判据对 Claude Code 是恒等变换。

> **这句话在写下的当天就不再成立了。** Claude Code 的计数恒为零，是因为那边还没有注册两条子智能体边界，不是因为它没有子智能体（8.1）。判据本身不用改一个字——它读的是计数，不是产品——但「对 Claude Code 是恒等变换」这半句只对**没有子智能体在跑的行**成立，对任何产品都是。

### 4.2 汇总与排序——一处改动，因为 PRD 本来就说它们是同一条规则

`PRD.md` §6.2：「列表使用同一优先级排序」。所以 `MonitorAggregation.status`（`:822`）与 `rowOrder`（`:887`）都改读 `effectiveStatus`，第 2 节的第 1 条和第 3 条一起解决，不需要两套理由。

改完之后收起态写 `Running`，Codex 的标记按 Running 的图案动，**而且没有计时读数**——`longestRunningSessionStart` 按 `keepsTiming` 过滤后什么也找不到，这是对的：收起态计的是 Turn 的时间，此刻没有任何 Turn 在计时。

> **落地时这一段被第 5 节的拍板改写了一半。** 尾翼不再随计时一起消失：计数被提升到收起态，占的正是计时那一格（第 5 节）。「有标签、无计时」的形状仍然成立，只是那一格里写的是一个数字而不是空的。

`marks(agents:sessions:)` 内部转调 `status(agents:sessions:)`，所以产品标记自动跟上，不必单独改。

### 4.3 未读门——不许它把唯一的证据删掉

两半，缺一不可：

1. **门要认这个判据。** `shouldDisplay` 收下 `effectiveStatus` 的结果，于是这一行走非终态那条路：不隐藏、丢弃 entry、不再每秒预约一次复检——与一条 Running 行完全一样。
2. **清零那一刻要有自己的边界。** 只做第 1 点的话，最后一个子智能体收尾时 entry 用的还是早就过去的 `lastEventAt`，settling 早已耗尽，行会**立刻**消失。所以给 `HookTurnState` 加一个 `lastSubagentBoundaryAt: Date?`，在 `reduceSubagentBoundary`（`:2485`）里盖章，**只被这个门读**，取 `max(lastEventAt, lastSubagentBoundaryAt)` 作为 `terminalBoundaryAt`。

`lastEventAt` 本身一个字节都不动，`65e63ab` 为它写下的理由（不让子智能体的动静挡住成员关系校正——reducer 唯一的边界）原样成立。调用点只有 `LiveCodexMonitorService.swift:800` 一处。

### 4.4 手动移除：保持原样

`isDismissable == (status == .completed)` 看上去是第 2 节里最刺眼的一条，但它应当不动：移除的含义是「这一行我看完了」，用户的判断压过本应用知道的一切；而且在计数卡死时，它是唯一的人工出口。这一条要写进文档，而不是悄悄留着。

### 4.5 行本身：一个字不改

`SessionStatusControl`（[`NotchOverlayView.swift:701`](../../../Notchline/Notchline/NotchOverlayView.swift)）仍按 `session.status` 决定画计时还是画计数，预览仍是最终回答，无障碍标签仍照旧读出 `N subagents still running`。`effectiveStatus` **不得**进入行的渲染路径——一旦进入，行就会重新开始计时，那正是被否决的做法。

## 5. 唯一的判断题：要不要把计数提升到收起态

把它接进汇总，就把一个已知的失败模式的代价抬高了：`SubagentStart` 而 `SubagentStop` 永不到达时，今天只是一行文字发呆，改完之后是**整个收起态长期停在 `Running` 并且矩阵一直在动**，直到该 thread 离开列表。

没有安全的兜底可用，两条都查过：

- 计时器推断被 `AGENTS.md` §6.2 禁止；
- App Server 答不了——`docs/non-public-codex-integration-features.md` 已记录：子智能体 thread 带 `parentThreadId`／`agentRole`，从来不成行，而「正在跑的子智能体数量」不在任何 Thread payload 里。列出并不等于在跑，所以拿 `thread/list` 做自愈也不成立。

**仍然建议接。** 收起态说 `Completed` 而活还在跑，是每一次都错；计数卡死是偶发，而且已经有人工出口（4.4）。

**退路**（若判断「卡死的 Running 收起态」比「安静的收起态」更糟）：只做 4.2 的排序那一半和 4.3，汇总不动。那样面板里仍然握着真相，代价是把收起态与面板的分歧作为**明写的设计**留在 PRD §6.2 里，而不是像今天这样隐含在代码里。

### 5.1 拍板（2026-08-23）：接，而且把计数本身画出来

采纳建议，并且比建议多一步——收起态不只是**按** Running 画，它还说出**几个**。尾翼那一格由计时与计数共用：

| 列表状态 | 尾翼 |
| --- | --- |
| 没有子智能体，有轮次在计时 | `1:23` |
| 有子智能体，有轮次在计时 | `2 │ 1:23` |
| 有子智能体，所有轮次都结束 | `2` |
| 没有子智能体，所有轮次都结束 | 整条尾翼消失（与今天一致） |

理由：计数是这一形态里唯一能说明「Running 从何而来」的东西。只画 Running 而不画数字，收起态就成了一个没有读数的状态词，用户唯一的核对方式是展开面板——而展开面板本来就一直是对的，这次改的正是不必展开也能看对。行尾那条「一行只有一个标记，两者不并存」的规矩在这里不适用：行尾的一格属于一行，收起态那一格属于整张列表，所以计时说的是最长的那个轮次，计数说的是列表里还有几个子智能体在跑，两者不是同一句话说两遍。

分隔符取 `U+2502`（BOX DRAWINGS LIGHT VERTICAL），两侧各一个普通空格。SF Pro 里它与 ASCII 竖线同宽、几乎同形，取它是因为它是一条分隔规则而不是一个字符。整串画在同一个 raster 上（`ElapsedReadout` 的 `prefix`），因为一秒一变的只是它的计时那一半，而面板宽度必须由**一次**测量得出。

代价照第 5 节记着，并且已经明写进 PRD §6.2 与非公开集成登记表，另有 [#102](https://github.com/soondubu137/notchline/issues/102)（CR-033）单独跟踪：`SubagentStop` 永久丢失时，收起态会长期停在 `Running` 并写着一个不会归零的数字，直到该 Thread 离开列表或用户右键移除该行。

## 6. 子智能体的审批（两个产品共同的未决项——Claude Code 侧的形状见 8.2，实测与建议方案见 6.1～6.3）

零件其实都在：子智能体的 `PermissionRequest` 确实会到达父 thread 的 hook——当初的接管缺陷正是这批事件造成的——而它今天在 `:2256` 被成对丢弃。

提案：把它**消费成一个 thread 级标志** `subagentsAwaitingApproval`，而不是直接扔掉（配对仍然成对丢，失信探测不受影响）；同一个尾部位置在标志置位时改用**亮色**绘制。仍然是一个位置、一段文字，而亮度本来就是本应用的注意力通道（`NotchOverlayView` 里 `tint` 的注释）。`figma-design.md:170` 现在写的是「用 Running 的暗色，因为没有人被问任何事」——这一句要相应改成两档。

**前置实测**（原本没有做，2026-08-23 补上了 Claude Code 那一半，见 6.1）：子智能体那次审批的关闭事件是否携带同一个 `tool_use_id` 与它自己的 `agent_id`，否则标志清不掉，会退化成一个永远亮着的行。**答案是一半一半**：批准那一路带，两者都带；人拒绝那一路**什么事件都不发**，所以标志不能只靠配对来清——6.2 因此把关闭规则写成三条加一条封顶，而不是原提案那一条。Codex 那一半随后也测了，见 6.3：形状与 Claude Code 逐条相同，探测法就是既有的那一套——隔离 `CODEX_HOME` + `hooks/list` 确认信任，绝不改用户的 `hooks.json`。

### 6.1 前置实测（2026-08-23，Claude Code CLI `2.1.241`）

探测法沿用 8.1 那一套一次性 `--settings` + `--setting-sources project`，但这一次必须走 pty 交互式会话：`-p` 模式下工具直接跑，永远不产生 `PermissionRequest`。同一句提示词（「用 `Agent` 起一个 general-purpose 子智能体去跑 `sw_vers -productVersion`，别等它」）跑四次，区别只在对话框弹出来之后做什么——批准、按 `Esc` 拒绝、不作答；另有一次主线程自己被拒绝作为对照。

批准那一次的到达顺序：

```text
+ 0.00  UserPromptSubmit   prompt=808f…
+ 2.78  PreToolUse         prompt=808f…                  tool=Agent  tool_use_id=toolu_0182…
+ 2.80  SubagentStart      prompt=808f…  agent_id=a28a…  agent_type=general-purpose
+ 4.21  Stop               prompt=808f…  background_tasks=[{id: a28a…, type: subagent, status: running}]
+ 4.73  PreToolUse         prompt=808f…  agent_id=a28a…  tool=Bash   tool_use_id=toolu_015Z…
+ 4.75  PermissionRequest  prompt=808f…  agent_id=a28a…  tool=Bash   （没有 tool_use_id）
+11.72  PostToolUse        prompt=808f…  agent_id=a28a…  tool=Bash   tool_use_id=toolu_015Z…
+14.97  SubagentStop       prompt=808f…  agent_id=a28a…
```

六条结论，前四条决定方案：

1. **子智能体的审批就是主线程那个形状。** `PreToolUse` 带 `tool_use_id`，20–30 ms 之后 `PermissionRequest` 带 `tool_name` 而**不**带 `tool_use_id`——官方 schema 也是这样写的（`PermissionRequest` 的自有字段只有 `tool_name`／`tool_input`／`permission_suggestions?`；Codex 的 `permission-request.command.input` 同样没有 `tool_use_id`，但有可选的 `agent_id`）。所以那次等待只能借一个已经开着的调用，而且必须是**这个子智能体自己**开着的那一个。第 8.2 节推断出来的「得给 Turn 按 agent 分格」，到这里成了要求而不是选项。
2. **对话框不一定开在轮次结束之后。** 批准那次 `Stop` 在 `+4.21`、对话框在 `+4.73`；另一次运行反过来，对话框在 `+4.02`、`Stop` 在 `+4.17`。两种都测到，所以这不是终态行特有的形状：一条正在 Running 的行同样会有子智能体卡在对话框上，而那一行今天连计数都不写（`runningSubagentSummary` 以 `!status.keepsTiming` 为前提）。
3. **批准精确关闭，拒绝什么也不发。** 批准那次的 `PostToolUse` 带着同一个 `agent_id` 与同一个 `tool_use_id` 到达。按 `Esc` 拒绝那次（TUI 事后自己写着 "It was denied permission to run the Bash command"）**没有 `PermissionDenied`，也没有 `PostToolUse`**；此后唯一到达的事件是那个子智能体自己的 `SubagentStop`，+6.9 s。
4. **`PermissionDenied` 的意思不是「人拒绝了」。** 二进制里这个事件只有一个产生点，而它唯一的调用点被 `decisionReason?.type === "classifier" && decisionReason.classifier === "auto-mode"` 挡着——它报的是**自动模式的分类器**拒了一次，人按 `No` 不产生它。主线程单独试了一次（方向键选中 `No`，TUI 上看得见 `❯No`）：此后 90 秒内没有 `PermissionDenied`、没有 `PostToolUse`，连 `Stop` 都没有（人的拒绝把那一轮**中断**掉了，而官方 hook 里没有任何中断事件——见登记表「会话工作状态」那一行）。**这条同时解释了一个既有缺陷**，见 6.2 末尾。
5. **TUI 自己的内部 agent 也带 `agent_id`。** 四次运行里观察到三条没有配对 `SubagentStart` 的 `SubagentStop`（`agent_type` 为空字符串），以及一条 `agent_type` 缺席的 `PreToolUse`（`agent_id=a1ba…`，tool=Bash）。所以**任何按 `agent_id` 开出来的格子都不许自己成为「这条 thread 有子智能体在跑」的证据**——那个证据只有 `runningSubagentIDs` 能给，而它只由两条边界事件加减。
6. **另有一份绝对读数，只属于 Claude Code。** 子智能体的对话框开着、父轮次已经 `Stop` 的那一刻，`claude agents --json` 把该会话报成 `status: "waiting"`、`waitingFor: "permission prompt"`。本应用已经在读这条命令的这个字段（[ADR 0011](../../adr/0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md) 与登记表「会话工作状态」那一行）。它当不了主来源——没有轮次身份也没有 agent 身份，30 秒一拍，桌面端托管的会话永远没有它——但它是一份绝对读数，见 6.2 末尾「测到了但不采用」。

### 6.2 方案（已实现）：按 agent 分格，而不是一道闸门

**闸门换成分流。** `HookIntegration.swift:2358` 那句 `if stableIdentifier(event.agentID) != nil { return true }` 不再是「成对消费掉」，而是转给一个 `reduceSubagentToolEvent`，纪律与 `reduceSubagentBoundary` 完全相同：不走 `mutateExactTurn`，不读也不写 `turn_id`，不推进 `lastEventAt`。带 `agent_id` 的 `turnStarted`／`turnEnded` 仍然照丢——Codex 的 `stop.command.input` 里压根没有 `agent_id`，这一条只是防御。

**Turn 上多一张按 agent 索引的表。**

```swift
/// 一个 agent 手里开着的东西。主智能体用 Turn 上原有的那三格，
/// 每个子智能体自己一格，按 `agent_id` 索引。
nonisolated struct AgentWaitSlots: Sendable {
    var pendingInputToolUseID: String?
    var pendingApproval: PendingApproval?
    var openToolUse: OpenToolUse?
}

var subagentSlots: [String: AgentWaitSlots] = [:]
```

与 `runningSubagentIDs` 同级的 thread 级事实，跨 Turn 边界照抄（实测 2：对话框可以开在 `Stop` 之后，那一格必须活得比轮次长）。主智能体那三格一个字不动，于是主线程的每一条既有行为——借用 id、`request_permissions`、`Elicitation`、终态清空——都不受这次改动影响。

**关闭规则三条，外加一条封顶**，顺序就是它们各自负责的那种结局：

1. **同一个 `(agent_id, tool_use_id)` 上的任何关闭事件**——`PostToolUse`／`PostToolUseFailure`／`PermissionDenied`／`ElicitationResult`——清掉那一格的等待。这是**批准**那条路，也是 Claude Code 自动模式分类器拒绝那条路（6.1 第 4 条）。
2. **同一个 agent 的别的调用上出现活动**，清掉借来的那次等待——`resolveInferredApproval` 原样搬过来，作用域从整个 Turn 缩到一格。这是**人拒绝**那条路：实测两个产品都不发任何事件（Codex 是 2026-08-15 那 67 秒静默，Claude Code 是 6.1 的第 3、4 条）。也就是说「这个产品报不报告拒绝」在**子智能体这一格上两边都是「不报」**，`reportsApprovalDenials` 不参与这一格的判断。
   > Claude Code 当初关掉这条推断的理由是「`Stop` 被测到早于它自己子智能体的 `PermissionRequest`」。6.1 第 2 条说明那不是乱序投递，那就是异步子智能体本来的形状——`Agent` 调用立刻返回，轮次先结束，子智能体后来才要人。**按 agent 分格之后这条理由自己没有了**：那个 `Stop` 与那个 `PermissionRequest` 落在两格里，一条流的活动再也够不着另一条流的等待。
3. **那个 agent 的 `SubagentStop` 直接删掉整格。** 实测里人拒绝之后唯一到达的事件就是它，所以这是**兜底而不是补充**。
4. **封顶：画出来的标志只认 `runningSubagentIDs` 里的 agent。**

```swift
/// 这条 thread 有没有子智能体正卡在一个对话框上。
nonisolated var subagentsAwaitingApproval: Bool {
    subagentSlots.contains {
        runningSubagentIDs.contains($0.key) && $0.value.pendingApproval != nil
    }
}
```

这一条把 6.1 第 5 条（TUI 内部 agent 也带 `agent_id`）挡在外面，同时保证**这个标志永远不可能比计数活得久**：计数怎么清零——`SubagentStop`、用户右键移除、行离开列表——标志就跟着没了。于是 5.1 那笔已经明写接受的代价（[#102](https://github.com/soondubu137/notchline/issues/102)）仍然是唯一一处可能卡死的地方，本次不新增第二处。

**派生状态多一条子句。** `MonitorAggregation.effectiveStatus` 现在读两个事实而不是一个：

```swift
// 有人正被问，压过「还在不在干活」：一条 thread 可以同时两者都是。
if session.subagentsAwaitingApproval, session.status != .inputNeeded {
    return .approvalNeeded
}
return session.status == .completed && session.hasRunningSubagent
    ? .running
    : session.status
```

`inputNeeded` 仍然压过 approval（`PRD.md` §6.2 的优先级，也是状态机里「审批让位给输入」那一条）。注意这一条**对 Running 的行也会分叉**——实测 2 说那是真的会发生的形状——而第 3 节那条原则一个字没变：行画的是它自己那一轮，派生状态答的是「这条 thread 现在要不要人」。收起态汇总、产品标记、排序与终态未读门四处一起跟上，不必各写一遍，因为 §4.2 已经把它们并到同一个判据上了。

**行只多一档亮度，画什么一个字不改。** §4.5 真正禁止的是让派生状态决定行**画什么**——那会让计时重新跑起来、预览永远换不到最终回答。它没有禁止决定画得**多亮**。所以 `SessionStatusControl.wantsAttention` 从只看 `session.status` 变成两项之一成立即可，尾翼那一格（此刻多半写着 `1 subagent`）于是用亮色 Medium 画，正是第 6 节原提案说的那一处，只是现在它有来源了。计数文本今天硬编码 `NotchPalette.label`，改成与计时同一套 `tint`／`weight`。无障碍文案必须把它说成词（`1 subagent still running, waiting for approval`）——亮度读不出来。

`PRD.md` §9.3 那句「它用的是 Running 的暗色……没有人被问任何事」与 `figma-design.md:170` 的同一句，要相应改成两档。

**Codex 的 `auto_review` 减法：做。** 这一段原先写的是「不做，而且是故意的」——理由是登记表那一行记着 `heartbeat-thread-permissions-by-id` 里**缺席的恰好是 subagent 线程**，于是「子智能体的审批会不会也交给自动审查者」没有接口能问；两个方向的代价又不对称，做错了就是**把一个真的对话框藏起来**，所以当时按「宁可闪一下也不藏」选了不做。**6.3 第二条把它测出来了：72/72 继承父 thread 当时的 `approvals_reviewer`，零例外。** 所以 `approvalsReachTheUser(threadID)` 用行自己的（父 thread 的）threadID 去问，答案对它派生的子智能体同样成立，减法照做——被证明为 `auto_review` 的 thread 上，那次 `PermissionRequest` 本来就没有人被问。

**代价与失效方向**

| 方向 | 后果 | 有没有出口 |
| --- | --- | --- |
| `SubagentStop` 永久丢失，且那一格还留着等待 | 收起态长期写 `Approval needed` 并且亮着，比 #102 今天那个「停在 Running」更响 | 有，且是同一个：右键移除该行。标志被封顶在计数里，两者一起走 |
| 权限管线跑过但没人被问（Codex `auto_review`、Claude Code 自动模式） | 约 2.5 秒的假亮 | 自愈——分类器一决定就有关闭事件（规则 1） |
| `agent_id` 改名或消失 | 那些事件重新落不到任何一格，退回今天的样子：行写着 `N subagents`，审批看不见 | 不需要出口，这是安全方向 |
| 子智能体的 `PreToolUse` 被计进失信探测 | `observedPreToolUseCount` 只在 `== 0` 时被读，多计不会误报；**只计关闭不计打开才会**，所以两条一起计或一条都不计，不许只计一半 | — |

**影响面**

| 文件 | 改什么 |
| --- | --- |
| `HookIntegration.swift` | `AgentWaitSlots`；`HookTurnState.subagentSlots` 与 `subagentsAwaitingApproval`；`:2358` 的闸门改为 `reduceSubagentToolEvent`；跨 Turn 边界的两处复制一并带上 |
| `MonitorDomain.swift` | `MonitoredSession` 增一个 `Bool`；`effectiveStatus` 增前置子句 |
| `LiveCodexMonitorService.swift`、`ClaudeCodeMonitorService.swift` | 建行时传那个 `Bool`（Codex 侧**不**经 `approvalsReachTheUser` 减法，理由见上） |
| `NotchOverlayView.swift` | `wantsAttention` 两项；计数文本收 `tint`／`weight`；行的无障碍文案补一句 |
| `docs/PRD.md` | §9.3 尾翼那一句改成两档；§6.2 补一句派生状态也读审批；§14 补一条验收 |
| `docs/figma-design.md` | 170 行那段同上 |
| `docs/tech-design.md` §9.2 | 按 agent 分格的等待，与「拒绝在两个产品上都是静默的」 |
| `docs/non-public-codex-integration-features.md` | 两张表的子智能体那一行：把「本次没修的既有缺陷」换成新的显示后果与失效方向 |

**验收**（沿用既有命名风格）

1. `aSubagentsApprovalReachesTheRowItBelongsTo`——重放 6.1 那串事件，行仍是 Completed、计时仍停着、预览仍是最终回答，而派生状态是 `approvalNeeded`；
2. `aSubagentsApprovalOutranksTheRunningItAlsoIs`——同一行同时有别的子智能体在跑，汇总取 approval 而不是 running；`inputNeeded` 在场时反过来；
3. `aSubagentsApprovalNeverTouchesTheTurnsOwnSlots`——主智能体的 `pendingApproval`／`openToolUse`／`lastEventAt` 全程不动（`65e63ab` 那条同类断言的延伸）；
4. `aRefusedSubagentCallStopsSayingApprovalNeeded`——同一 agent 的下一个 `PreToolUse` 清掉借来的等待（人拒绝那条路，两个产品都要过）；
5. `aSubagentStopClearsWhateverThatAgentWasWaitingOn`——只到 `SubagentStop`，等待与计数一起清零；
6. `anInternalAgentsCallIsNotASubagent`——带 `agent_id` 但从没 `SubagentStart` 过的调用不产生任何标志（6.1 第 5 条）；
7. `aRowWithASubagentAwaitingApprovalIsStillDismissable`——§4.4 的人工出口在新状态下仍在。

#### 落地记录（2026-08-23）

按本节实现，四处与写下时不同，都记在这里而不是悄悄改掉：

1. **`auto_review` 那一段整个反过来了**，因为 6.3 把继承测出来了。本节原先写「不做减法」，落地做了减法。
2. **`ClaudeCodeHookVocabulary.reportsApprovalDenials` 由 `true` 改为 `false`**，即本节末尾那条既有缺陷同批修掉。它不是附赠：子智能体那一格无论如何都要推断，而让同一个 reducer 在主线程上继续假装这个产品会报告拒绝，等于把两条互相矛盾的规则并排放着。`aProductThatReportsRefusalsDoesNotInferThemFromUnrelatedActivity` 这条既有测试正是钉住旧行为的，它被改写成 `neitherProductReportsAHumanRefusalSoBothInferIt`——三个断言里只有 Claude Code 那一条翻了面，另两条原样成立。
3. **`pendingInputToolUseID` 也按 agent 分了格，但不画出来。** 分格是为了配对正确（一格里的 `AskUserQuestion` 不能被另一格的 `PostToolUse` 关掉）；不画是因为「子智能体的提问会不会真的问到人」没有实测，而一个本应用担保不了的提示比没有提示更糟。
4. **`renderedProjection` 多带一个字段。** 那是 reducer 决定「要不要唤醒面板」的投影；标志变化不写进去，收起态就要等下一次别的事件才跟上。

**测到了但不采用：`claude agents --json` 的 `waiting` 读数。** 它能干两件本方案干不了的事——证实（对话框确实开着）与**清除**（没有 `waiting` 就是没人被问，而这是一份绝对读数，因此天生不会卡死）。不作为本次方案的一部分，理由有三条：30 秒一拍，对本产品要报的这个状态太慢；桌面端托管的会话永远没有它（[#41](https://github.com/soondubu137/notchline/issues/41)）；而且它只属于 Claude Code，Codex 没有对等物，接进来就是同一件事两个产品两套画法。若将来 #102 决定给 Claude Code 一条自愈，它与 `background_tasks` 那条出路应当一起考虑——两者都是绝对读数，都只该用来减。

**顺带测出的一个既有缺陷，写在这里而不是藏着。** `ClaudeCodeHookVocabulary.reportsApprovalDenials = true` 只对**分类器**的拒绝成立（6.1 第 4 条）。人按 `No` 时 Claude Code 什么也不发，而 `infersDenials` 因为这个 `true` 是关着的，于是主线程的行会一直写着 `Approval needed`——直到 `claude agents --json` 报出 `idle` 让那一轮进入 Completed（ADR 0011，最多一拍 30 秒），桌面端托管的会话则要等 transcript 的中断记录。这与本节是同一条规则的两侧：**拒绝在两个产品上都是静默的**，所以那条「别的调用上有活动就算人答过了」的推断两边都需要。建议在同一次改动里把它一起修掉，并单独写一条 `aRefusedMainThreadCallStopsSayingApprovalNeeded`。

#### 后续（2026-08-23）：上面那条「测到了但不采用」被推翻了一半

方案落地当天用户就撞上了它没盖住的洞：*「子智能体弹出审批，行进入 Approval needed，**批准之后它不消失**，一直卡到十秒的 sleep 跑完为止。」*

这不是实现漏了什么，是 6.2 的模型缺一条出路。**Claude Code 在人按下批准时不发出任何 hook。** 那一格的等待因此只能等那次调用自己的 `PostToolUse`——而它落在**工具跑完**的时刻，不是对话框关闭的时刻。命令跑 200 ms 时两者看不出差别，命令跑十几秒时行就在整段执行期间请用户去回答一个他已经回答过的问题。6.2 的落地记录里那条「拒绝在两个产品上都是静默的」说的是**拒绝**；这里是**批准**，而批准同样是静默的，只是它后面还跟着一个迟到的关闭事件，所以一直看起来像是被盖住了。

实测（2026-08-23，CLI `2.1.241`，父轮次 `Stop` 在 +4.90 s，子智能体被要求 sleep 12 秒）：

```text
+6.18  PreToolUse         agent_id=a1f0…  tool=Bash  tool_use_id=toolu_01UX…
+6.22  PermissionRequest  agent_id=a1f0…  tool=Bash  （没有 tool_use_id）
       claude agents --json: status=waiting, waitingFor="permission prompt"   [+6.37 … +8.37]
+9.35  人按下批准
       claude agents --json: status=busy                                      [+9.07 起，整段执行期间]
+22.72 PostToolUse        agent_id=a1f0…  tool=Bash  tool_use_id=toolu_01UX…
```

**批准之后 13.4 秒的错报，而同一段时间会话自己一直在说 `busy`。** 于是上面那三条拒绝理由逐条重看：

1. 「30 秒一拍太慢」——**不成立**。那是没有边沿时的数字。`waiting → busy` 会重写 `~/.claude/sessions/<pid>.json`，而 `ClaudeCodeSessionRecordWatcher` 早已盯着**每一个列出的会话**（不只是有轮次在跑的），registry 的 `edgeFloor` 把一串翻转压到两秒一次读取。等待的关闭因此落在一次去抖 + 一次 `claude agents --json` 之内，而不是一拍。
2. 「桌面端托管的会话永远没有它」——**成立，但这是一次刻意的部分修复**，与 ADR 0011 本体当初的形状一样。那些会话保持今天的行为。
3. 「只属于 Claude Code，Codex 没有对等物」——**不适用**。这条规则不画任何新东西，它只**关掉**一个等待；Codex 侧一个字不改，两个产品画出来的仍然是同一套。

采用的是三件事里最小的那一件：不用它证实（对话框确实开着仍然只由 `PermissionRequest` 说），不用它当自愈兜底，只用它回答「人已经答过了」。并且**只认 `busy`，不认「不是 `waiting`」**——`idle` 证明不了对话框不在（CC-019 实测：对话框仍开着时按 `Esc`，160 ms 内即到 `idle`），从一个缺席里读出结束会关掉用户正在看的那一个。

落地：`PendingApproval` 记下自己开启的时刻（顺序护栏因此钉在每个等待自己身上，而不是钉在轮次的 `lastEventAt` 上——子智能体的事件本来就不许移动那个戳），新规则写在 `HookEventRepository.endApprovalWaitsForWorkingSessions(_:)`，由 `ClaudeCodeMonitorService` 用它已经在取的那份读数调用。主线程那一格一并修好，因为那是同一个缺陷的另一半。写进 ADR 0011 的 2026-08-23 补充、`tech-design.md` 第 4 节、`PRD.md` 与非公开集成登记表。

#### 更正（2026-08-23，同日）：上面那节只修好了终端里的会话

上面写完之后用户复现，**问题照旧**：批准之后仍然停在 *Approval needed*，一直到 20 秒的 `sleep` 跑完。修的方向没错，覆盖面错了——那节整节只在 pty 里的 TUI 上量过，而用户测的是 **Claude Code 桌面端托管的会话**，那种会话从头到尾不报告 `status`（实测其 `~/.claude/sessions/<pid>.json` 带 `entrypoint: "claude-desktop"`，没有 `status`／`updatedAt`／`statusUpdatedAt`，且会话启动后再不重写）。于是 `busy` 那条规则对它一个字都用不上。**教训写在这里：宿主是这个产品的一条真实分界线，任何「非事件证据」的方案都必须两种宿主各量一次，只量一种等于没量。**

顺手把一件更基本的事测掉，因为整套方案都压在它上面：**批准到底有没有 hook。** 把二进制里 `strings -a` 挖出的**全部 31 个**事件一次性注册，跑一个 sleep 25 秒的子智能体——批准（+9.96 s）与 `PostToolUse`（+36.23 s）之间 26 秒，唯一到达的是另一个无关 agent 的 `SubagentStop`。**没有漏注册的事件，这条路上就是没有事件。**

桌面端把证据写在自己的日志里（`~/Library/Logs/Claude/main.log`，用户那次复现的原文）：

```text
18:10:40 Emitted tool permission request c930390d-… for Bash in session local_6c63f909-…
18:10:45 LocalSessions.respondToToolPermission: requestId=c930390d-…, decision=once, …
18:10:45 Received permission response for c930390d-…: once (tool: Bash)
```

只有第一行带会话，只有第三行证明人答过，request id 把它们配起来——与 6.2 让 `PermissionRequest` 借用仍打开的调用 id 是同一个形状。落地：`ClaudeDesktopPermissionLogReader`，经 Desktop 记录的 `sessionId ↔ cliSessionId` 连回 thread，答案交给**与终端那条同一个入口** `HookEventRepository.endAnsweredApprovalWaits(_:)`。**决定本身不读**，所以桌面端的**拒绝**也一并修好了——那一半此前只能等 `SubagentStop`。日志与 Desktop 记录树都只在真的有审批开着时才读，边沿（`permissionLogWatcher`）也只在那时才建。详见 ADR 0011 的两条 2026-08-23 补充。

### 6.3 Codex 侧实测（2026-08-23，Codex CLI `0.149.0-alpha.4.1`）

两件事：一件跑出来的，一件从既有 rollout 里读出来的。用户的 `~/.codex` 全程只读——`hooks.json` 一个字节没动。

**一、子智能体的审批确实落在父 thread 的 hook 上，形状与 Claude Code 逐条对得上。** 隔离 `CODEX_HOME`（`auth.json` 软链、自己的 `config.toml` 与 `hooks.json`，九条定义靠 `codex app-server` 的 `hooks/list` 取 `currentHash` 写进 `[hooks.state."<key>"]` 完成信任），`codex exec --approve-for-me`，提示词让主智能体 `spawn_agent` 一个子智能体去跑一条被沙箱挡住的联网命令：

```text
+ 3.50  PreToolUse         tool=collaboration…spawn_agent  tool_use_id=call_sx15…  turn_id=01a03064…（父）
+ 4.59  SubagentStart      agent_id=01a03065-0ff5…  agent_type=default
+ 8.15  PreToolUse         agent_id=01a03065-0ff5…  tool=Bash  tool_use_id=exec-b66c8f31…   ← 沙箱里那次尝试
+ 8.34  PostToolUse        agent_id=01a03065-0ff5…  tool=Bash  tool_use_id=exec-b66c8f31…
+12.78  PreToolUse         agent_id=01a03065-0ff5…  tool=Bash  tool_use_id=exec-5aaefacb…
+12.81  PermissionRequest  agent_id=01a03065-0ff5…  tool=Bash  （没有 tool_use_id）
+18.51  PostToolUse        agent_id=01a03065-0ff5…  tool=Bash  tool_use_id=exec-5aaefacb…   ← 自动审查者答完
+20.79  SubagentStop       agent_id=01a03065-0ff5…
```

四条结论：

- `PermissionRequest` **到达了**，带 `agent_id`，不带 `tool_use_id`——与 6.1 第 1 条逐字相同。借用规则两个产品共用一条，不需要各写一遍。
- **三个身份各归各的**：`session_id` 是**父 thread**（`01a03064-fd1b…`），`agent_id` 是**子智能体自己的 thread id**（`01a03065-0ff5…`，等于它自己那份 rollout 的 `id`），`turn_id` 是**子智能体自己的轮次**（`01a03065-100a…`，不是父的）。这正是这些事件绝不许走 `mutateExactTurn` 的原因，也是当初接管缺陷的成因。Claude Code 那边盖的是父轮次的 `prompt_id`——**两个产品只在这一处不同**，而「按 agent 分格」对两种盖法都成立，因为那一格从来不问 `turn_id`。
- `PostToolUse` 带同一个 `(agent_id, tool_use_id)` **精确关闭**（这里隔了 5.7 s，是自动审查者的决定时间）。
- 同一个子智能体在同一格里先后开了**两个**调用（`exec-b66c8f31` 与 `exec-5aaefacb`），所以 6.2 规则 2 要的那种「同一个 agent 的**别的**调用上出现活动」在真实事件流里确实存在，不是纸上的形状。

另有一条负面观察，正好压住 `PRD.md` §14.2 那句「孤立的 `PermissionRequest` 不误报」：把同一个提示词换成非交互的 `approval_policy="on-request"`（现场没有人可问，实际解析成 `never`）再跑一遍，`PermissionRequest` **根本不触发**，子智能体照常跑完它的两条命令。

**二、子智能体继承父 thread 的审批归属，72/72。** 这是 6.2 里唯一一处「没测所以选保守」的地方，现在测了，而且答案让保守的那一边不必要了。方法是只读地扫 `~/.codex/sessions` 的 119 份 rollout：其中 77 份带 `parent_thread_id`（即子智能体），72 份的父 rollout 也在盘上。把每份子智能体 rollout 的第一条 `turn_context.approvals_reviewer`，与**它被派生那一刻**父 rollout 最近一条 `turn_context` 的取值对齐比较：

| 结果 | 份数 |
| --- | --- |
| 与父 thread 当时的 `approvals_reviewer` 相同 | **72** |
| 不同 | **0** |
| 父 rollout 不在盘上，无法比较 | 5 |

两种取值都出现过（子智能体的 `turn_context` 里 `auto_review` 1996 条、`user` 21 条），所以这不是「盘上只有一种值」的假一致。本次探测自己那两份 rollout 也是同一个形状：`--approve-for-me` 的父 thread 与它派生的子智能体都写着 `auto_review`。

**于是 6.2 里那条「不做减法」的建议作废，改成做减法**：`approvalsReachTheUser(threadID)` 用行自己的（也就是父 thread 的）threadID 去问，答案对子智能体成立。原先担心的「减错了会把一个真的对话框藏起来」不成立——被证明为 `auto_review` 的 thread，它派生的子智能体也在同一个审查者手里，那次 `PermissionRequest` 本来就没有人被问。

**三、顺带看见一件事，正好为 6.2 那条封顶作证。** `--approve-for-me` 的自动审查者**自己也是一个嵌套 agent**：探测目录里多出第三份 rollout，`parent_thread_id` 是那个子智能体、`session_id` 仍是根会话，而它**没有** `SubagentStart`。也就是说「带 `agent_id` 却从没宣告过自己」的 agent 两个产品都有（Claude Code 是 TUI 的内部 agent，见 6.1 第 5 条；Codex 是这个审查者），所以 6.2 那条「标志只认 `runningSubagentIDs` 里的 agent」不是为某一个产品打的补丁，是两边都需要的形状。

**四、还有一件没测，而它不改变任何设计。** 人在交互式 TUI 里**拒绝**一次子智能体的审批时，Codex 发什么，没有单独测。理由：主线程那一路 2026-08-15 已经测过（67 秒静默，什么都不发），Codex 的 `infersDenials` 本来就是开着的，6.2 规则 2 在这个产品上只是把作用域从整轮缩到一格，而兜底的规则 3（`SubagentStop`）不依赖它。真要测出来它会发点什么，那也只是多一个关闭点，推翻不了任何一条规则。

## 7. 明确否决：把行按在 Running 上

- 把 `SubagentStop` 丢失从「一段发呆的文字」升级成「一行永远停在 Running 且**没有任何东西能结束它**」——这就是 `65e63ab` 那段提交信息里逐条论证过的旧缺陷；
- 预览永远换不到最终回答（`status == .completed` 才取 `assistantPreview`，[`LiveCodexMonitorService.swift:1304`](../../../Notchline/Notchline/LiveCodexMonitorService.swift)）；
- 行不再可移除（4.4 那个唯一的人工出口也一起没了）；
- 未读门永远不评估它，Desktop 读没读都留在列表里。

## 8. 与 Claude Code 的关系

一期把这一节写成「本次不做，只登记」，并且建立在两个当时没有实测的假设上。**两个都是错的**，实测见 8.1。

- ~~Claude Code 侧从不设置 `runningSubagentCount`，`ClaudeCodeHookVocabulary.managedDefinitions` 十一条里也没有子智能体边界。**同一件事在两个产品上画法不同**，这是已知且当前接受的差异。~~ 那个差异不是「画法不同」，是那边根本没有画——而它需要画。
- Codex 那个**接管**缺陷在 Claude Code 上确实不复现：那边的 Turn 身份是 `prompt_id`，子智能体事件实测落在**父轮次同一个** `prompt_id` 上（2026-08-16，见 [`HookIntegration.swift:334`](../../../Notchline/Notchline/HookIntegration.swift) 与 `:1013` 的注释），永远不像新轮次。**但这句话只否掉了接管，没有否掉「子智能体活得比轮次长」**——一期把这两件事当成了一件，那是这一节最大的错。
- 一期还写着「何况还有 `claude agents --json` 活动读数与 transcript 中断记录两道兜底」。那两道兜底结束的是**轮次**，不是子智能体：轮次本来就正常结束了，它们无话可说。

### 8.1 实测（2026-08-23，CLI `2.1.241`）与落地

探测法沿用既有的「一次性 `--settings` + `--setting-sources project`」（`-p` 模式够用，因为要看的不是审批），提示词明说不要等待那次 `Agent` 调用。事件到达顺序：

```text
UserPromptSubmit  prompt_id=5fd7…
PreToolUse        prompt_id=5fd7…  tool=Agent   tool_use_id=toolu_01Un…
PostToolUse       prompt_id=5fd7…  tool=Agent   tool_use_id=toolu_01Un…
SubagentStart     prompt_id=5fd7…  agent_id=ae14…  agent_type=general-purpose
Stop              prompt_id=5fd7…  background_tasks=[{id: ae14…, type: subagent, status: running}]
PreToolUse        prompt_id=5fd7…  agent_id=ae14…  tool=Bash
PostToolUse       prompt_id=5fd7…  agent_id=ae14…  tool=Bash
SubagentStop      prompt_id=5fd7…  agent_id=ae14…
```

三条结论：

1. **`Agent` 调用在子智能体启动的那一刻就返回**，所以轮次可以带着自己派生的活到达 `Stop`——正是 Codex 那个形状，只是成因不同（那边是子智能体本来就异步，这边是工具调用本身不等）。主智能体的 `Stop` 自己就带着 `background_tasks` 指名那个子智能体还在跑。
2. **`agent_id` 确实存在**，而且在每一条 hook input 都继承的 base schema 上，不是四条 input 各自的可选字段；官方描述是「只在 hook 从子智能体内部触发时出现……用这个字段而不是 `agent_type` 来区分子智能体调用与主线程调用」。所以第三条那个担心成立。
3. **子智能体的事件盖的是父会话的 `session_id` 加父轮次的 `prompt_id`**，两者都是父的。这是让它们落在正确那一行的原因，也是接管缺陷在这里不成立的原因。

落地的就是第 4 节与第 5 节那一套，一个字不改地搬过来：`ClaudeCodeHookVocabulary` 注册 `SubagentStart` / `SubagentStop`（11 → 13 条），建行时传 `turn.runningSubagentIDs.count`，`ClaudeCodeMonitorService` 那道已读门收 `effectiveStatus` 与 `terminalBoundaryAt`。多做的一件小事：`MessageDisplay` 的折叠在 `deliver` 里就转向，绕过了 reducer 那道 `agent_id` 闸门，而它写的是用户看得见的正文，所以那里补了同一条判据（据 schema 写的，`-p` 观察不到——`-p` 本来就不显示子智能体的正文）。

### 8.2 没有做的那一件，和它现在的形状

那道 `agent_id` 丢弃闸门在**共享** reducer 里，所以 Claude Code 的子智能体 `PermissionRequest` 同样被吞掉。第三条担心的「行会停在 Running 且不报 Approval needed」成立，而且现在多了一种读法：行可能写着 `1 subagent`，而 Claude Code 停在对话框上。

这次没有修它，理由是它不是一条闸门的事：`HookTurnState` 只有一格 `openToolUse` 和一格 `pendingApproval`，放子智能体的事件进来就是让第二股流穿过同两格。要修得给 Turn 按 agent 分格，那是它自己的一次改动，和第 6 节是同一件事的两个产品版本。

**一个当时没想到、现在测出来的可能出路，只属于 Claude Code**：它的 `Stop` 与 `SubagentStop` 都带 `background_tasks`，其中 `type` 为 `subagent` 的条目的 `id` 就是 `agent_id`。那是一份**绝对**读数而不是累计值，落在 `Stop` 上——也就是计数开始被画出来的那一刻——因此天生不会像 5.1 那个代价那样卡死，是 [#102](https://github.com/soondubu137/notchline/issues/102) 在这个产品上的现成解。没有本次采用是因为它需要自己的实测：`SubagentStop` 自己那一条里**仍然列着正在停止的那个子智能体**（上面的实测里看得见），而 `pending` 状态的子智能体被取消时会不会补一条 `SubagentStop` 完全没测。

## 9. 影响面

| 文件 | 改什么 |
| --- | --- |
| `MonitorDomain.swift` | 新增 `effectiveStatus`；`status`、`rowOrder` 改读它 |
| `CodexDesktopUnreadState.swift` | `shouldDisplay` 接收「是否仍在干活」（或直接接收 `effectiveStatus`） |
| `LiveCodexMonitorService.swift` | 唯一调用点：传 `effectiveStatus` 与 `max(lastEventAt, lastSubagentBoundaryAt)` |
| `HookIntegration.swift` | `HookTurnState` 新增 `lastSubagentBoundaryAt`；`reduceSubagentBoundary` 盖章（调用点已有 `delivered.receivedAt`）；跨 Turn 边界的复制处一并带上 |
| `docs/PRD.md` | §6.2 说明汇总优先级读的是「派生状态」；§9.3 补一句行本身不变 |
| `docs/figma-design.md` | 170 行那段补上「计数在跑时收起态按 Running 画」 |
| `docs/non-public-codex-integration-features.md` | 子智能体那一行补上新的显示后果与失效方向 |
| `docs/tech-design.md` | §515 补 `lastSubagentBoundaryAt` 与 `lastEventAt` 的分工 |

5.1 拍板之后另外动的（本表原先没有列）：

| 文件 | 改什么 |
| --- | --- |
| `MonitorStore.swift` | `compactRunningSubagentCount`／`compactTrailingText`／`compactTimerPrefix`／`spokenRunningSubagentText`；`PanelMetrics` 的 `timerText:` 改名为 `trailingText:`，尾翼槽位在计数装不下时按内容变宽 |
| `NotchOverlayView.swift` | 尾翼分两种画法：有计时用带 prefix 的 `ElapsedReadout`，没有计时用静态 `CompactCountReadout`；面板无障碍文案补一句 |
| `NotchStatusMatrix.swift` | `ElapsedReadout` 收一个 `prefix`，与计时画在同一个 raster 上 |
| `CONTEXT.md` | 新增术语「派生状态」 |
| `docs/system-architecture.md` | 归并读派生状态，以及「写着 Running、尾翼没有计时」是正确形态 |

## 10. 验收

**落地时实际写下的七条单测**（编号对应下表，均在 `NotchlineTests.swift` 末尾一个 extension 里）：`aFinishedTurnWithASubagentStillRunningSummarisesAsRunning`（1 与 5.1 的三种尾翼形态）、`theCollapsedCountTotalsEveryRowAndObeysTheHiddenWings`、`aFinishedRowWithASubagentSortsWithTheRunningOnes`（2）、`aReadThreadWithASubagentStillRunningKeepsItsRow`（3 与 4，经真实 `LiveCodexMonitorService`）、`aSubagentBoundaryStampsItsOwnInstantAndNotTheTurns`（4 与 5）、`aFinishedRowWithASubagentIsStillDismissable`（6）、`aClaudeCodeRowIsUnchangedByTheDerivedStatus`（7），另有 `theCollapsedCountGrowsTheSlotItSharesWithTheTimer` 锁定 5.1 带来的宽度问题。第 3、4 两条经过反向验证：把 `LiveCodexMonitorService` 那处改回旧写法（任一半），`aReadThreadWithASubagentStillRunningKeepsItsRow` 都会失败。

原提案列的验收项（沿用既有三条的命名风格：`aSubagentOutlivingItsTurnLeavesTheRowFinishedAndStillWorking` 等）：

1. 一条 Completed 且有子智能体在跑的行，使收起态汇总为 `Running`，但 `compactTimerText` 为 `nil`；
2. 同一行在 `rowOrder` 里与 Running 同档，不被三行视口挤出；
3. Desktop 报告已读时该行**不**被未读门隐藏；
4. 最后一个 `SubagentStop` 之后，settling 从**那一刻**起算，而不是从主 `Stop` 起算；
5. `lastEventAt` 在整个子智能体生命周期内不被推进（回归保护，`65e63ab` 已有一条同类断言）；
6. 该行仍然可以被手动移除；
7. Claude Code 的行在同一批断言下一切照旧（`effectiveStatus` 对它是恒等变换）。

**第 6 节落地时写下的八条**（同一个 extension，接在上面那批之后；编号对应 6.2 的验收表）：`aSubagentsApprovalReachesTheRowItBelongsTo`（1，重放 6.1 那串事件，含行自己四样都不变）、`aSubagentsApprovalOutranksTheRunningItAlsoIs`（2，含 Running 的行也会分叉、`inputNeeded` 压过它、排序进 approval 那一档）、`aSubagentsApprovalNeverTouchesTheTurnsOwnSlots`（3，Codex 事件，两股流互不相干且子智能体的 `turn_id` 不被接管）、`aRefusedSubagentCallStopsSayingApprovalNeeded`（4，两个产品各跑一遍同一串事件）、`aSubagentStopClearsWhateverThatAgentWasWaitingOn`（5）、`anInternalAgentsCallIsNotASubagent`（6）、`aRowWithASubagentAwaitingApprovalIsStillDismissable`（7），另有 `aRefusedMainThreadCallStopsSayingApprovalNeeded` 钉住落地记录第 2 条那个既有缺陷；既有的 `aProductThatReportsRefusalsDoesNotInferThemFromUnrelatedActivity` 改写为 `neitherProductReportsAHumanRefusalSoBothInferIt`。六处做过反向验证——闸门的分流、`runningSubagentIDs` 那道封顶、`effectiveStatus` 的审批子句、子智能体那一格的推断、`SubagentStop` 清格、`reportsApprovalDenials`——任意一处改回旧写法，对应那条测试都会失败。

**8.1 落地时另外写下的三条**（同一个 extension 之后）：`aClaudeCodeSubagentOutlivingItsTurnLeavesTheRowFinishedAndStillWorking`（实测那串事件顺序照原样重放，并钉住轮次 id 不被接管、`lastEventAt` 不被子智能体推进、`SubagentStop` 的 `last_assistant_message` 不进预览）、`aReadClaudeCodeSessionWithASubagentStillRunningKeepsItsRow`（经真实 `ClaudeCodeMonitorService`，与 Codex 那条对称）、`aSubagentsDisplayedTextIsNotTheRowsPreview`（`MessageDisplay` 那道绕过 reducer 的路径）。原先那条 `aClaudeCodeRowIsUnchangedByTheDerivedStatus` 改写成 `theDerivedStatusReadsTheCountAndNotTheProduct`——它的注释本来就写着「以后某个 Claude Code 读数把它填上，就会同时改掉汇总、排序与已读门」，那个读数现在存在了，所以钉的东西从产品换成计数。四条都做过反向验证：注册、`effectiveStatus`、`terminalBoundaryAt`、`MessageDisplay` 判据，任意一处改回旧写法，整个套件都会失败。

## 11. 未决

- ~~第 5 节那个取舍需要拍板~~ 已拍板并实现，见 5.1；取舍本身写进了 `PRD.md` §6.2 与非公开集成登记表，不再只留在本文。
- ~~第 8 节最后一条（Claude Code 是否也盖 `agent_id`）没有实测~~ 已实测，见 8.1：盖，而且在 base schema 上。同一次实测还推翻了这一节自己的前提——那边的子智能体一样活得比轮次长——于是第 4、5 节整套搬了过去。
- ~~第 6 节的前置实测仍然没做~~ Claude Code 那一半已实测（6.1），方案见 6.2，**等拍板**。它仍然是本文里唯一可能产生**错误状态**而不是**缺失提示**的地方，优先级高于其余全部内容。剩下三件事没做：
  - ~~Codex 侧没有跑过真的子智能体审批~~ 已测（6.3 第一条）：`PermissionRequest` 带 `agent_id`、不带 `tool_use_id`，`PostToolUse` 精确关闭，与 Claude Code 唯一的不同是它盖的是子智能体自己的 `turn_id` 而不是父轮次的；
  - ~~自动审查的 thread 上，子智能体的审批到底交给谁~~ 已测（6.3 第二条）：继承父 thread，72/72，因此 6.2 改成照做减法；
  - 唯一还没测的是**人在交互式 TUI 里拒绝一次子智能体的审批时 Codex 发什么**，理由与它为什么不改变设计写在 6.3 第四条；
  - ~~6.2 末尾那条既有缺陷需要一并决定是不是同一次改动里修~~ 已在同一次改动里修掉，理由见 6.2 的落地记录第 2 条。
- ~~6.2 落地记录里「测到了但不采用 `claude agents --json` 的 `waiting` 读数」~~ 被推翻了一半，见 6.3 前那节后续：**批准与拒绝一样是静默的**，而那条会话读数是唯一能说「人已经答过了」的证据，三条拒绝理由里只有「桌面端托管的会话没有它」还成立。
- 8.2 末尾那条 `background_tasks` 出路**作为计数**仍然没有实测（`pending` 被取消时补不补 `SubagentStop`），一并记在 #102。**作为状态的那一半已经采纳并落地**，见第 12 节：它只问那一条 `Stop` 自己的列表是不是空的，不问里面是谁，因此不依赖上面那两条没测过的事实。

## 12. 子智能体收尾与父轮次被叫醒之间那一瞬（2026-08-23，Claude Code CLI `2.1.241`）

### 12.1 报告

> 「起一个子智能体然后立刻结束」这句提示词跑下来，行的读数是：Running → Approval needed（子智能体要 `sleep` 的权限）→ Running（子智能体在睡）→ **Completed（子智能体睡醒）** → Running（主智能体在总结）→ Completed。中间那次 Completed 能不能不要？状态变化太多，很分心。

### 12.2 实测

同一套探测法（一次性 `--settings` + `--setting-sources project`，全部 16 个事件都注册一个只写时间戳与 payload 的 helper），跑两遍：`-p` 一遍，pty 交互式一遍。两遍的形状完全相同，只有间隔不同。

pty 那一遍（时间以 `SessionStart` 为零点）：

```text
+26.25  UserPromptSubmit   prompt=1b21…
+29.21  PreToolUse         prompt=1b21…  tool=Agent
+29.25  SubagentStart      prompt=1b21…  agent=a489…
+29.25  PostToolUse        prompt=1b21…  tool=Agent
+31.18  Stop               prompt=1b21…  background_tasks=[{id: a489…, type: subagent, status: running}]
+31.61  PreToolUse         prompt=1b21…  agent=a489…  tool=Bash
+42.85  PostToolUse        prompt=1b21…  agent=a489…  tool=Bash
+44.30  SubagentStop       prompt=1b21…  agent=a489…  background_tasks=[{id: a489…, …, status: running}]
+44.35  UserPromptSubmit   prompt=0f4a…                ← 新的轮次，间隔 50 ms
+47.47  Stop               prompt=0f4a…  background_tasks=[]
```

四条结论：

1. **那次 Completed 只有 50 ms**（`-p` 下 130 ms），它是 `SubagentStop` 清空 `runningSubagentIDs` 到 Claude Code 用一个**新的 `prompt_id`** 把父轮次叫醒之间的空隙。行读的是计数，计数那一刻确实是零，所以行说的不是假话——它只是回答了一个没有人问的问题。
2. **父轮次是被一条 `UserPromptSubmit` 叫醒的，`prompt_id` 是新的**，不是原轮次的续。所以那一瞬之后是一个全新的 Turn，而不是同一个 Turn 复活。
3. **`Stop` 自己早就说清楚了它是哪一种终态。** `background_tasks` 在 `Stop` 与 `SubagentStop` 的官方 schema 上都有，描述一字不改地就是这件事：「In-flight background work (running/pending + backgrounded) registered in this session. Lets hooks distinguish "session is done" from "session is paused waiting for background work to wake it". Empty array when nothing is in flight.」最后那次 `Stop` 带的是 `[]`。
4. **`SubagentStop` 上的那份不能用**：它仍然列着正在停止的那个子智能体（两遍实测都是），所以它不是「还剩什么」的绝对读数。同一次实测还看到两条没有配对 `SubagentStart` 的 `SubagentStop`（TUI 自己的内部 agent，6.1 第 5 条），与本节无关但再次说明按 `agent_id` 开格子的东西不能自证是子智能体。

### 12.3 采纳：把「暂停」记成 Turn 自己的一个事实

`HookTurnState.pausedForBackgroundWork`，在 `turnEnded` 上由 `background_tasks` 非空写下，`MonitoredSession.isPausedForBackgroundWork` 带到行上，`MonitorAggregation.effectiveStatus` 与计数**并列**地读它：

```swift
return session.status == .completed
    && (session.hasRunningSubagent || session.isPausedForBackgroundWork)
    ? .running
    : session.status
```

三个决定，理由各自独立：

- **Turn 级而不是 Thread 级。** 与 `runningSubagentIDs`、`subagentSlots` 相反：那两个跨 Turn 边界继承，因为子智能体活得比轮次长；这一个由该轮次自己的终态写下，也就不许活得比它久。下一个轮次的终态自己答自己，而那一次带的是空列表。写的是赋值不是或，一个轮次停两次时以最后一次为准。
- **只读 `Stop` 上的那一份**（结论 4）。
- **没有计时器。** `AGENTS.md` §6.2 禁止用计时器推断 Running，而这里没有一个：一个事件写，另一个事件清。真正的替代方案——「最后一个 `SubagentStop` 之后宽限两秒」——正是那条禁令说的东西，也正是为什么它没有被选。

**行本身仍然一个字不改**（第 3 节、§4.5）。那 50 ms 里行尾什么都不画：它自己那一轮确实结束了，也确实没有子智能体可以点名。收起态与展开面板在这一瞬的分歧是明写的设计，不是疏漏。

### 12.4 代价，与它为什么比原来那一下轻

新增的失效方向只有一个：`SubagentStop` 之后父轮次永远没有被叫醒（用户正好在这 50 ms 里退出，或某次更新不再叫醒），那一行会停在 `Running` 而不是进入 `Completed`。它与 5.1 已经明写接受的那条（#102）是同一个方向、同一个出口（右键移除该行），而不是第二处新的卡死来源：两者都要求同一件事发生——该 Thread 再也不产生任何终态。反过来，字段消失或改名的方向是安全的：`pausedForBackgroundWork` 恒为 false，行退回今天的样子，闪一次，什么都不伪造。

登记表（`AGENTS.md` §8）**不新增行**：`background_tasks` 在随 CLI 分发的官方 hook input schema 上，并且带着官方描述，与 `agent_id` 同性质——那一半是公开的。本次没有依赖任何未公开的形状：不读条目里的 `id`、`type`、`status`，只读列表是不是空的。已有的「子智能体仍在跑时行尾说出来」那一行补记了新的显示后果。

### 12.5 验收

三条单测（`NotchlineTests.swift` 末尾）：`aTurnPausedForItsSubagentDoesNotSayFinishedBetweenTheTwo`（12.2 那串事件原样重放，逐帧钉住那 50 ms 里派生状态仍是 Running、计数确实是零、新轮次不继承这个标志、最后那次空列表让行进入 Completed）、`aTerminalThatNamesNoBackgroundWorkIsTheThreadFinishing`（空列表与字段缺席两种，两个产品各跑一遍）、`aListTooLongToCarryIsLeftOutRatherThanCutShort`（`HookPayloadDistiller` 的第三种取值：整段留下或整段不留，超上限时事件本身照常落地）。第一条做过反向验证：`effectiveStatus` 改回只读计数，它失败。

