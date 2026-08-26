# 点击问一条 Thread，不问整部历史

点击一个 Codex 行之前的重新确认，是对**那一条 thread** 的一次 `thread/read`，不是对全部未归档 Thread 的一次强制全量分页。判定不变，仍是 [ADR 0017](0017-a-row-requires-a-thread-the-app-server-vouches-for.md) 的那一条：App Server 交得出这条 Thread、并且它通过可导航根会话判定，才算数。

## 触发它的东西：可感知的导航延迟

用户报告在另一台 Mac 上点击 Codex 行要 1–2 秒才到达对应会话，本机较轻但同样能察觉。测下来那段时间几乎全在这道门里。

`thread/list` 由 App Server **扫描并解析 `~/.codex/sessions` 下的 rollout 文件**来回答——把 `state_5.sqlite` 换成空库、只留 sessions 目录，它照样列出全部 47 条——因此代价随用户历史增长，而且是分页的，页数也随历史增长。2026-08-26 在隔离的 `CODEX_HOME` 上对 Codex Desktop 内置 CLI `0.149.0-alpha.4.3` 实测一次完整分页：

| 未归档 Thread | 页数 | 一次完整分页 |
| --: | --: | --: |
| 50 | 1 | 51 ms |
| 100 | 1 | 108 ms |
| 199 | 2 | 335 ms |
| 400 | 4 | 754 ms |
| 799 | 8 | **2215 ms** |

（超线性：每多一页都要重付一次扫描。）本机真实历史 47 条、rollout 更大，一次完整分页 206 ms。

同一台机器上，一次 `thread/read`（`includeTurns: false`）中位 **1.4 ms**，20 条里最大 3 ms。点击路径上其余各项都可以忽略：`urlForApplication` <10 ms，`NSWorkspace.open` 的完成回调 94 ms，连接是空操作（app-server 子进程一直在）。所以**那道门就是点击延迟本身**——端到端 A/B 见下。

## 端到端 A/B（2026-08-26，本机）

同一台空闲机器、同一条 thread、同一个夹具，只换应用二进制——改动前后各起一次应用，用 hook socket 摆一行真的 Codex 行，用 `CGEvent` 真点，从点击那一刻量到 `NSWorkspace.didActivateApplicationNotification` 报出 ChatGPT 被激活：

| | 各次 | 中位 |
| --- | --- | --: |
| 改动前 | 208 / 215 / 220 / 252 / 317 ms | **220 ms** |
| 改动后 | 56 / 57 / 61 / 62 / 62 / 64 / 66 / 68 / 69 ms | **62 ms** |

差值 158 ms，与本机那次完整分页（206 ms）同量级——余下的 62 ms 是 `thread/read` 加 Launch Services 那一程。**本机只有 47 条未归档 thread**：被拿掉的这一项按上表随历史增长，400 条时是 0.75 秒，799 条时是 2.2 秒。落点也复验过：改动后点下去，Codex Desktop 打开的正是那一行指的 thread。

**怎么量的。** 这里没有一个数是 `ps` 量得出来的：代价既不是本应用的稳态 CPU，也不是它的一次突发，而是一个**子进程往返的时延**。分页那张表是直接对着 `codex app-server` 说 JSON-RPC——按本应用用的同一组参数（`archived: false`、`limit: 100`、`sortKey: updated_at`、四个 `sourceKinds`）逐页请求并记时，每个规模先预热一次再取 4–7 次的中位数；不同规模用隔离的 `CODEX_HOME`（真 rollout 文件的副本，thread id 逐份改写）。A/B 那两行是本应用的 **Debug** 构建，因为这条路径上本应用自己的 Swift 只有几个字典查找，配置差别落在测量噪声里；真正的代价全在子进程那一侧，而它两种配置下是同一个二进制。两次测量之间机器保持空闲——先前在一台同时跑着整套测试的机器上量到的改动前数字（217/253/347 ms）与上表一致，只是更吵。

## 为什么一条读就够

一行之所以存在，正是因为 App Server 交出过它的 Thread 并且它通过了判定（ADR 0017）。点击时把**同一个问题**对**同一个来源**再问一次，是这道门能有的最小形状；问得比成行更多，等于画出自己不肯打开的行——那恰好是 ADR 0017 要消灭的毛病。

`thread/read` 在这件事上还答得**更准**：实测同一条子智能体 thread，`thread/list` 的 `threadSource` 与 `parentThreadId` 都是 null，`thread/read` 两个都填。删除也照样接得住——不存在的 id 收到 remote error（`thread not loaded`），而 remote error 按 ADR 0017 就是「没有这条 thread」。

## 归档不在这道门里

**归档结束的是行的监视生命周期，不是 thread 的可达性。** 被归档的 thread 仍然在 Codex Desktop 里、deep link 仍然指着它；而「归档即退出列表」已经由 30 秒成员对账拥有：`removeThreads(notIn: listedThreadIDs)` 直接把那个 Turn 退休掉，行不再画。所以用户还能点到的行，就是上一次对账仍然列出的行——点击时再问一遍，买的是行本身已经带着的答案。

它也没法便宜地问，两条都是 2026-08-26 实测：

- **`thread/read` 交出已归档的 thread，且不带任何归档标记。** 在隔离的 `CODEX_HOME` 里真的调用 `thread/archive` 之后，`thread/list(archived: false)` 不再含它，`thread/read` 照常返回，payload 里没有任何 `archived` 字段。
- **`thread/archived` 通知只发给执行归档的那个客户端。** 同一个 `CODEX_HOME` 上起两个 app-server，B 归档，只有 B 收到 `{"method":"thread/archived","params":{"threadId":…}}`，A 一帧也没有。用户在 Codex Desktop 里归档走的是 Desktop 自己那个 app-server，本应用独立 fork 的那个永远不会被告知。（A 的下一次 `thread/list` 立刻反映了归档——共享的是磁盘状态，不是事件流。）

代价写清楚：从归档到下一次成员对账之间（最多 `threadListRefreshInterval`，30 秒），点一个还没消失的行会打开那条已归档的会话，而不是收到「已归档、删除或不再可用」。这是**同一个窗口**里画着那一行的同一份证据，只是不再自相矛盾。

## 旧 Codex

没有 `thread/read` 的构建（`-32601`）探测一次后永久回退到全量分页，与元数据那条路径同一处降级——它在这里付的还是原来的代价，别处一分不多付。

## 状态

已实施。测试：`openingAThreadAsksForThatThreadInsteadOfPaginatingTheHistory`、`openingAThreadTheAppServerRefusesIsNotNavigable`、`openingASubagentThreadIsNotNavigable`、`aThreadReadThatFailsInTransportDoesNotClaimTheSessionIsGone`、`aCodexWithoutThreadReadAnswersTheClickFromTheList`。
