# 子智能体在跑时，整个界面怎样说同一句话

| 字段 | 内容 |
| --- | --- |
| 文档状态 | **第 4 节、第 5 节与第 8.1 节已采纳并实现（2026-08-23）**；第 6 节（二期：子智能体的审批，两个产品都还没做）仍是开放研究。落地后的契约在 `PRD.md` §6.2／§8.2／§9.3、`CONTEXT.md`「派生状态」、`tech-design.md` §9.2 与 `figma-design.md` §4.6，本文此后只作为「为什么这样做」的记录，不是契约 |
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

## 6. 二期：子智能体的审批（本次不做，而且是两个产品共同的未决项——Claude Code 侧的形状见 8.2）

零件其实都在：子智能体的 `PermissionRequest` 确实会到达父 thread 的 hook——当初的接管缺陷正是这批事件造成的——而它今天在 `:2256` 被成对丢弃。

提案：把它**消费成一个 thread 级标志** `subagentsAwaitingApproval`，而不是直接扔掉（配对仍然成对丢，失信探测不受影响）；同一个尾部位置在标志置位时改用**亮色**绘制。仍然是一个位置、一段文字，而亮度本来就是本应用的注意力通道（`NotchOverlayView` 里 `tint` 的注释）。`figma-design.md:170` 现在写的是「用 Running 的暗色，因为没有人被问任何事」——这一句要相应改成两档。

**前置实测**（本文没有做）：子智能体那次审批的关闭事件是否携带同一个 `tool_use_id` 与它自己的 `agent_id`，否则标志清不掉，会退化成一个永远亮着的行。探测方法沿用 `codex-hooks-redesign` 与既有子智能体那一行的做法：隔离 `CODEX_HOME` + `hooks/list` 确认信任，绝不改用户的 `hooks.json`。

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

**8.1 落地时另外写下的三条**（同一个 extension 之后）：`aClaudeCodeSubagentOutlivingItsTurnLeavesTheRowFinishedAndStillWorking`（实测那串事件顺序照原样重放，并钉住轮次 id 不被接管、`lastEventAt` 不被子智能体推进、`SubagentStop` 的 `last_assistant_message` 不进预览）、`aReadClaudeCodeSessionWithASubagentStillRunningKeepsItsRow`（经真实 `ClaudeCodeMonitorService`，与 Codex 那条对称）、`aSubagentsDisplayedTextIsNotTheRowsPreview`（`MessageDisplay` 那道绕过 reducer 的路径）。原先那条 `aClaudeCodeRowIsUnchangedByTheDerivedStatus` 改写成 `theDerivedStatusReadsTheCountAndNotTheProduct`——它的注释本来就写着「以后某个 Claude Code 读数把它填上，就会同时改掉汇总、排序与已读门」，那个读数现在存在了，所以钉的东西从产品换成计数。四条都做过反向验证：注册、`effectiveStatus`、`terminalBoundaryAt`、`MessageDisplay` 判据，任意一处改回旧写法，整个套件都会失败。

## 11. 未决

- ~~第 5 节那个取舍需要拍板~~ 已拍板并实现，见 5.1；取舍本身写进了 `PRD.md` §6.2 与非公开集成登记表，不再只留在本文。
- ~~第 8 节最后一条（Claude Code 是否也盖 `agent_id`）没有实测~~ 已实测，见 8.1：盖，而且在 base schema 上。同一次实测还推翻了这一节自己的前提——那边的子智能体一样活得比轮次长——于是第 4、5 节整套搬了过去。
- 第 6 节的前置实测仍然没做，而它现在是**两个产品共同**的未决项，形状见 8.2：不是一条闸门，是 Turn 上那两格得按 agent 分开。它仍然是本文里唯一可能产生**错误状态**而不是**缺失提示**的地方，优先级高于其余全部内容。
- 8.2 末尾那条 `background_tasks` 出路没有实测（`pending` 被取消时补不补 `SubagentStop`），一并记在 #102。
