# Claude Code 的 hook 走 helper，不走端口

Claude Code 的生命周期事件此前由 `type: "http"` handler POST 到 `127.0.0.1:51741`，现在由 `type: "command"` handler 运行本应用写在自己 support 目录里的一个 helper，helper 把 payload 顺着 0600 的 Unix domain socket 交进来。

## 为什么换

端口有两个毛病，**都不是注册能修的**，因为本应用不写用户的 `settings.json`（[ADR 0010](0010-never-write-the-users-claude-code-settings.md)）。

**一、本应用没开的时候，端口不属于任何人，于是每个事件都在用户会话里打一行。** 实测 CLI 2.1.237，pty 驱动的交互式会话，同一句提示、两次工具调用：指向无人监听端口的 `http` 注册打出 **9 行** `<event> hook error / connect ECONNREFUSED`。渲染处只对 `Stop` 与 `SubagentStop` 返回 `null`，其余一律打印，且**没有任何设置或环境变量可以关掉**（查过 `suppressHook` / `hideHook` / `HOOK_SILENT` / `DISABLE_HOOK` / `quietHooks`，都不存在；`suppressOutput` 是 hook **回复**里的字段，连接被拒时根本够不着）。这条就是 §9 那条 NO-GO——「`http` hook 在应用未运行时对用户会话产生任何可见影响」——它对**所有**事件成立，不只是 `SessionEnd`。

**二、无人占用的端口可以被抢走，token 挡不住。** `51741` 落在 macOS ephemeral 区间（`net.inet.ip.portrange.first: 49152`），任何本地进程 bind 0 都可能拿到它。一个 40 行的冒充监听器收到了完整的 `prompt`、`cwd`、`transcript_path`、`session_id` 与 bearer token；回一段 `additionalContext` 之后，下一次会话按注入的内容作答；`PreToolUse` 上同样的形状可以回 `permissionDecision`。**bearer token 认证的是 CLI，不是监听器**，方向正好反了。

helper 两个毛病都没有：它无论本应用开没开都 `exit 0` 且两条流都不说话，所以任何注册的事件都不可能在任何地方留下一行；socket 在本应用自己的目录里，权限 0600，别的进程 bind 不了也读不了。

## 考虑过并否决的方案

**一个常驻进程占住端口，本应用启动时把端口交接过去。** 这是最先被提出的方案，端口部分成立得很好、交接部分不成立。实测：

- launchd 的 socket activation 确实**在没有任何进程运行时**占住端口（`state = not running`，别的进程 bind 报 `EADDRINUSE`），job 按需拉起、在 3 次/秒的连接率下复用同一个进程（1 次拉起服务 31 个连接），`SIGKILL` 之后端口仍被占住（t+0.0/0.2/0.4 s 三次 bind 全被拒），下一个 POST 照常 200。「永远有人占着」这一半是真的。
- 但**交接本身没有安全的做法**。`SO_REUSEPORT` 让两个进程同时持有 `127.0.0.1:P`（实测 6/6 连接投给后 bind 的那个），可是它要求**所有**参与者都设这个选项——实测普通 bind 无法加入一个已被普通 bind 占住的端口，反之亦然。也就是说今天本应用在运行时没人能挤进来，而一旦为了交接打开 `SO_REUSEPORT`，任何本地进程只要也设上并后 bind 就能接管投递，**包括本应用正在运行的时候**：把「关着的时候有个窗口」换成了「一直开着」。剩下的只有 `SCM_RIGHTS` 传 fd，那要把 `AgentHookListener` 从 `NWListener` 改写成裸 fd 的 accept 循环。
- 更要命的是**失败形态比它要修的病更重**。job 拉不起来的时候（应用被删、bundle 被移动、系统升级后二进制被隔离、launchd 限流），launchd 仍持有监听 socket：`connect()` **1 ms 就成功**，`recv()` 永远不返回（实测 10 s 无响应，`last exit code = 78: EX_CONFIG`）。于是每个事件都要等满自己的 `timeout`，而本应用**改不了用户文件里的 `timeout`**。今天连接被拒是立即返回的，`timeout: 5` 从来等不满——这个方案把「吵」换成了「卡死」。
- 而且**端口被占时 bootstrap 是静默成功的**：`rc 0`、job 注册上、`launchctl print` 的输出与健康时**逐字节相同**（两边都报 `sockets = { 16 (no bytes to read) }`），抢占者照常收到 POST。今天 `bind()` 失败是一个干脆的信号，这个方案把它弄丢了。

**换一个 ephemeral 区间之外的端口**（例如 `31741`）。便宜地关掉了抢占窗口，对噪声毫无作用，而且要用户重贴。

**每个 handler 加 `once: true`。** CLI 在第一次触发后把 hook 摘掉，于是每次会话最多十二行——安静的代价是监视本身结束。

**接受它并在设置卡片里说明。** 即注册这些 hook 就意味着应用关着时 CLI 会很吵。

## 代价

**每个事件一个进程。** 实测（2.1.237，pty 交互式会话，注册数放大 10× 与 60× 之后按事件数回归，基线是同一句提示不注册任何 hook）：

| 传输 | 每事件 CPU | 每轮次（17 个事件） |
| --- | --- | --- |
| `http` → 活着的监听器 | 1.2 ms | 21 ms |
| `command` → 编译出来的 helper | 4.8 ms | 81 ms |
| `command` → 本 ADR 的 `sh` + `nc` | 6.3 ms | 107 ms |
| `command` → Python（Codex 那边一直如此） | 30 ms | 510 ms |

也就是说比它替换掉的通道贵，但只贵几十毫秒每轮次，而且**比本应用另一半早就在付的价钱便宜五倍**。没有为此单独做一个编译产物：省下的 2.2 ms 不值一个新 target、一份签名和一条升级路径。

**注册是同步的。** `command` schema 有 `async` 键（`http` schema 没有），但实测 2.1.237 用它会让同一个 `tool_use_id` 的 `PreToolUse` 与 `PostToolUse` 互相超车，并且在 `-p` 下整个丢掉 `Stop`（进程在后台 hook 跑完之前就退出）。保序和终态比 6.3 ms 值钱。

**依赖 `/usr/bin/nc` 带 `-U`。** macOS 自带，不是私有依赖，但它是这条通道唯一的外部件。helper 的三层超时由内向外是 `SO_RCVTIMEO` 250 ms（本应用读一条 payload）、`nc -w 1`（对端 accept 了却不读的情况）、注册里的 `timeout: 3`。

**已经装过的用户要重贴。** 旧的 `http` handler 留在他们文件里，本应用删不掉（ADR 0010）。所以 `ManagedHooksConfiguration` 把旧的 URL path `/codex-in-notch/hook` 当作 legacy identity marker：认得出来，于是状态报 `repairRequired`（「这不是本版本要的注册，请重贴」）而不是 `notInstalled`（「你还没装」）——后者会让用户在旧的旁边再贴一份。

## 连带

**`SessionEnd` 排除的理由没有了。** 它当初被单独排除，是因为它是唯一一个失败会写进 CLI **自己的 stderr**、因而会跟着 `claude -p` 进入脚本、管道和 CI 的事件。helper 不会那样失败。是否注册它现在是一个纯粹的产品问题（要不要让一个死掉的会话的行直接退休，而不是等 sessions 目录 watcher 发现），单独处理。

**CC-014 一并消失。** 「固定端口冲突无法自愈」的前提是有个固定端口。

## 状态

已实施。`ClaudeCodeHookSetup` 写 helper 并渲染要粘贴的块，`AgentHookListener` 绑 socket，`ClaudeCodeMonitorService.prepareTransport()` 每次刷新确认两者都在。测试：`theHelperDeliversWhenTheAppIsUpAndIsSilentWhenItIsNot`（拿真脚本按 CLI 的 exec form 跑，两种状态都要 `exit 0` 且两条流为空）、`theSocketIsPrivateToThisUserAndDropsWhatItCannotRead`、`theHandlerThisBuildReplacedStaysRecognisableSoAnUpgradeReplacesIt`、`anHTTPEraRegistrationAsksToBeRepairedRatherThanReadingAsAbsent`、`theHelperQuotesASocketPathThatCarriesAQuote`。
