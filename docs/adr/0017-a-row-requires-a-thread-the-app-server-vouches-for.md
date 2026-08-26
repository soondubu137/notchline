# 一行需要 App Server 认领的 Thread

一个 Hook 轮次只有在 App Server 交出它的 Thread、并且那个 Thread 通过可导航根会话判定之后才成行。「还没问到」和「问过了，没有这条 thread」是两种不同的事实，但对成行是同一个答案：**不成行**。这是 [ADR 0001](0001-monitor-desktop-navigable-root-threads.md) 的 fail-closed 版本——原来的判定只在**拿到** Thread 时才可能否决，拿不到就默认放行。

## 触发它的东西：Codex 侧边会话

Codex Desktop 的 side chat 是一条会话内部的临时旁支，开在右侧标签页里，只在父会话的摘要面板下以「Side chats」列出，从不进侧边栏。Desktop 自己的文案说得很清楚：临时的、关掉应用就消失、关闭即删除且不可恢复、还会过期。它由父会话 fork 而来，`ephemeral: true`、`sideConversation: true`，注入的 developer instructions 第一句是「You are in a side conversation, not the main thread」——不接主线任务、不碰子智能体、非请求不改动工作区。

2026-08-25 实测（Desktop 内置 CLI `0.149.0-alpha.4.3`）：

- 它有自己的 thread id，照常触发 Turn hook——这就是它此前能画出一行的原因；
- 它**不落盘**：`~/.codex/sessions` 里没有 rollout，`state_5.sqlite` 里没有行，`.codex-global-state.json` 里也没有（`thread-tab-routes-v1:` 持久化的是别的标签页种类）；
- 独立的 App Server **够不着它**：`thread/list` 不含它，`thread/read` 答 `-32600 "thread not loaded"`。Desktop 自己那个 app-server 是 stdio 起的（`~/.codex/ipc/ipc.sock` 属于 Electron 主进程，不是 app-server），所以内存里那条 `forkedFromId` / `sessionId` 的父子关系没有任何外部接口读得到；
- **没有能打开它的 deep link**：整个 bundle 里只构造 `codex://threads/<id>`。

于是它既不能单独成行（没有 Project、没有标题、点下去无处可去），也不能并入父会话那一行（父是谁问不出来）。

## 修好之前那一行是什么样

Hook 到达 → 画一行 *Project unavailable* → 约 10 秒后成员对账把这个从未出现在任何列表里的 Turn 退休，行消失 → 侧边会话结束时最后一个 hook 又建一次 Turn，行以 Completed 回来 → 点它得到「会话已归档、删除或不再可用」。三个症状同一个根因：判定只能否决它看得见的东西。

顺带的代价也在同一处：一个 Hook 线程只要不在上次列表里，每次刷新都会再要一次**全量分页**的成员对账——而这条 thread 永远不会出现在里面。

## 代价

- **一行要等一次本地 `thread/read`。** 不再是 Hook 到达的同一拍出现。这个等待有实测支撑：`UserPromptSubmit` 触发时 rollout 文件与状态库行都已经写好，独立 App Server 立刻读得出来（2026-08-25，CLI `0.149.0-alpha.4.3`），所以正常路径上就是一个本地往返，而且**不等**那条昂贵的全量列表。老 Codex（没有 `thread/read`）退化成等一次列表。
- **侧边会话运行期间通知面是静的**，包括它要输入或要审批的时候。接受：它开在用户正看着的那个窗口里、设计上只读、而且本应用无论如何给不出「回到那里」的入口——那正是一行存在的一半理由。
- **App Server 从「装饰」变成了「门」。** 原来的分工是 Hook 负责低延迟、App Server 只做装饰。现在成行要它点头。实际影响比听起来小：连不上 App Server 时本来就一行新的都画不出来（那条路径直接保留上一份可信快照）。

## 不读措辞、不读错误码

拒绝的判定是「`thread/read` 收到了一个 remote error」，不看它的文本也不看具体 code：不管什么理由，一个 App Server 不肯交出来的 thread 就是本应用没法定位的 thread。这样也就不必把 Codex 的错误措辞登记进 [`non-public-codex-integration-features.md`](../non-public-codex-integration-features.md)。传输层失败（超时、连接重置）不是回答，不留记录，下次刷新照常再问。

## 状态

已实施。拒绝会被记下来，因此不会每次刷新重问，也不会再为一条产品自己都说不存在的 thread 去分页整部历史。测试：`aThreadTheAppServerRefusesDrawsNoRowAtAnyPointInItsTurn`、`aSessionThatStopsRenderingStopsSchedulingWakeUps`、`idleToRunningDoesNotWaitForSlowThreadList`。

子智能体不受影响：Codex 把子智能体的 hook 打上**父会话**的身份，它们本来就落在父会话那一行上，而父会话是一条正常的、交得出来的 Thread。
