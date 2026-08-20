# 扩展支持 Claude Code（Desktop + CLI）技术探索

| 字段 | 内容 |
| --- | --- |
| 文档状态 | 可行性调研；不是实现决策，未改动任何生产代码 |
| 首次记录 | 2026-08-15 |
| 探索点 | 让当前只服务 Codex Desktop 的顶部监视器同时汇总 Claude Code 会话 |
| 目标读者 | 后续负责决策、spike 和实现的 Agent 与产品负责人 |
| 验证基线 | Claude Desktop `1.30096.5`（bundle `com.anthropic.claudefordesktop`），内置 Claude Code CLI `2.1.229`，macOS `Darwin 25.5.0`，验证日期 `2026-08-15` |
| 当前结论 | **可行，且 Phase 0 的存亡问题已闭合。** 用户级 hook 在 Desktop 托管会话中确实触发（2026-08-16 实测，§10）。`http` 通道可用，但 `SessionEnd` 必须排除在 http 之外。导航按产品决策降级 |
| 产品决策 | 已于 2026-08-15 确定：导航降级可接受；Apple Events 权限可接受（见 §8） |

> 目录约定沿用 [`shared-app-server/README.md`](../shared-app-server/README.md)：每个探索点独立二级目录，后续实验记录追加到本文第 10 节，不覆盖早期证据。

## 1. 文档目的

本文回答一个问题：把 Codex in Notch 扩展成同时监视 Claude Code（Desktop 与 CLI）的多智能体中心，技术上是否成立、代价在哪里、哪些能力现在还不存在。

它记录：

- 本机实测确认的 Claude Code 集成能力，以及每项能力是官方公开还是私有观察；
- 与当前 Codex 集成路径的逐项对照，指出哪些现有难题在 Claude Code 侧消失、哪些新难题出现；
- 现有架构需要的抽象改动范围；
- 分阶段验证计划与 NO-GO 条件；
- 必须由产品拍板的决策点。

本文不主张立即实现。除只读检查与一次 deep link 探测外，本次调研没有修改任何配置、代码或用户状态。

## 2. 结论摘要

| 维度 | 判定 | 依据 |
| --- | --- | --- |
| 会话发现 | **优于 Codex。** 官方公开命令直接枚举当前活动会话 | `claude agents --json` 返回 `pid / cwd / kind / startedAt / sessionId / name` |
| 启动现状同步 | **优于 Codex。** 当前的“启动不做现状同步”限制在 Claude Code 侧不存在 | 同上；启动即可知道有哪些会话在跑 |
| 生命周期状态 | **优于 Codex。** Hook 事件集更细、身份字段更全 | 官方 Hooks 提供 `PermissionRequest` / `PermissionDenied` / `Notification(permission_prompt)` / `Elicitation` 成对事件 |
| 子智能体过滤 | **优于 Codex。** 精确而非推断 | Hook payload 带 `agent_id` / `agent_type` |
| Desktop + CLI 统一 | **成立。** 一次集成覆盖两者 | Desktop 启动的就是同一个 CLI 二进制，且带 `--setting-sources=user,project,local` |
| 会话标题与元数据 | **成立。** 路径由官方 Hook payload 给出 | `transcript_path`、`cwd`；标题需解析 JSONL（格式非公开） |
| **精确导航** | **不可行，已决定降级。** 无任何受支持接口能聚焦已存在的会话 | 官方 deep link 只能新建会话；`claude://code/sessions/local_…` 实测被拒 |
| 原生实时状态源 | **不存在。** Hook 是唯一受支持的状态推送通道 | 五个候选源全部只描述身份或已发生的事实，见 §4.7 |
| 实现整洁度 | **可优于 Codex 侧。** 稳态零轮询、零落盘、无 helper 脚本 | `http` hook 直推 loopback listener + 事件驱动的会话发现，见 §6 |
| 已读自动移除 | 私有只读可行，风险等级与现有 Codex 未读适配器相同。**已于 2026-08-19 实现（CC-013）**，判定规则与本行的推测不同——见该日记录。**同日第二次修订覆盖了终端会话**，用的既不是私有只读也不是 Desktop：控制终端的访问时间 | Desktop 侧 `lastFocusedAt` / `lastActivityAt`；终端侧 `st_atime` |
| 额度圆环 | Desktop 用户可行；纯 CLI 用户无等价数据源 | `plan-usage-history.json` 属于 Claude Desktop 私有状态 |

**总判断：** 除导航外，Claude Code 的集成面比 Codex 更宽、更公开、更容易做对。产品价值主张里“快速跳回会话”这一半目前没有落点，这是决定要不要做的关键，而不是工程难度。

## 3. 与当前 Codex 路径的对照

```mermaid
flowchart LR
    subgraph codex ["Codex 现状"]
        cxDiscover["会话发现\n无受支持的当前态查询\n启动不做现状同步"]
        cxHooks["官方 Hooks\n六类事件\nPermissionRequest 无法表达仍在等待"]
        cxMeta["App Server 子进程\nthread/list thread/read"]
        cxNav["codex://threads/{id}\n精确导航可用"]
        cxUnread["私有 .codex-global-state.json\n未读集合"]
    end

    subgraph cc ["Claude Code 可用面"]
        ccDiscover["claude agents --json\n官方公开 当前活动会话"]
        ccHooks["官方 Hooks\n30 类事件\n审批与输入成对开闭"]
        ccMeta["transcript_path 由 Hook 给出\ncwd gitBranch title"]
        ccNav["无受支持的已存在会话导航\n只能新建会话"]
        ccUnread["Desktop 私有 local_*.json\nlastFocusedAt vs lastActivityAt"]
    end

    cxDiscover -.->|"能力提升"| ccDiscover
    cxHooks -.->|"能力提升"| ccHooks
    cxMeta -.->|"不再需要独立子进程"| ccMeta
    cxNav -.->|"能力倒退 阻塞点"| ccNav
    cxUnread -.->|"同风险等级"| ccUnread
```

值得注意的是三个当前架构里最贵的设计，在 Claude Code 侧都可以变简单：

1. **独立 App Server 子进程**（`CodexAppServerClient.swift` 全部 860 行、NDJSON 分帧、超时探活、传输重建）在 Claude Code 侧没有对应必需品。会话集合来自一条 0.2 秒返回的官方命令，标题与元数据来自 Hook 直接给出的 `transcript_path`。
2. **启动 cutoff 的能力边界**（见 [`system-architecture.md` §2.1](../../system-architecture.md)）在 Claude Code 侧不成立，因为存在受支持的“此刻有哪些会话”查询。
3. ~~**`PermissionRequest` 只证明管线跑过、不能表达仍在等待**在 Claude Code 侧有直接解法。~~ **这一条是错的**（2026-08-16 实测，见 §10）：`PermissionRequest` 不带 `tool_use_id`，所以 Codex 侧「借用仍打开的调用 id」的模型在这里原样保留，这个难题并没有消失。真正消失的是另一半——`PermissionDenied` **带** `tool_use_id`，拒绝因此能被精确关闭，不再有 Codex 侧那 67 秒的悬挂。

## 4. 已验证事实

以下每一条都在本机实测过。版本变化后必须重新验证。

### 4.1 会话发现（官方公开）

官方 CLI 文档公开 `claude agents --json`，实测输出：

```json
[
  {
    "pid": 91157,
    "cwd": "/Users/yinfenglu/Projects/codex-in-notch",
    "kind": "interactive",
    "startedAt": 1786832578142,
    "sessionId": "45510eae-d774-464e-bff9-972b2c28bae5",
    "name": "codex-in-notch-f6"
  }
]
```

要点：

- `claude agents --help` 明确写明 `--json` 的作用是 “Print active sessions (interactive and background) as a JSON array and exit (for scripting; does not require a TTY)”。**交互式会话可见是文档承诺，不是观察到的巧合**，包括由 Claude Desktop 托管的会话。这是本次调研最重要的单条发现。
- **该命令不返回任何状态字段。** 在本会话正处于处理中时执行，输出与空闲时完全一致。它是身份的权威来源，不是状态的来源（见 §4.7）。
- 支持 `--all`（含已完成的后台会话）与 `--cwd <path>`。
- 三次计时均为 0.19–0.26 秒。作为 1 秒轮询偏重，作为 5 秒轮询或事件触发后的权威读取合适。
- 同一信息也存在于 `~/.claude/sessions/<pid>.json`（额外含 `entrypoint`、`kind`、`version`、`messagingSocketPath`）。该文件由 `claude` 进程自己持有（`lsof` 确认 pid 91157 持有 `/tmp/cc-socks/91157.sock`），**因此终端启动的 CLI 会话与 Desktop 托管会话使用同一套注册机制**。该文件格式未公开，只应作为“何时该重新查询官方命令”的 watcher 输入，不应作为数据来源。

### 4.2 生命周期事件（官方公开）

官方 Hooks 文档公开 30 个事件、配置文件位置与 payload 字段。与本产品直接相关的映射：

| 产品状态 | Claude Code 证据 | 关闭条件 |
| --- | --- | --- |
| Running | `UserPromptSubmit`（实测字段为 `prompt`，`source` 可选且 `-p` 运行中缺席） | 后续状态事件 |
| Approval needed | `PermissionRequest`（**实测不带 `tool_use_id`**，见 §10 2026-08-16） | 借用仍打开的调用 id，由同 `tool_use_id` 的 `PostToolUse` 或 `PermissionDenied` 关闭 |
| Input needed | `Notification(notification_type: idle_prompt / agent_needs_input)`、`Elicitation` | `ElicitationResult`、`Notification(elicitation_complete)` |
| Completed | `Stop`（带 `last_assistant_message`、`background_tasks`）、`StopFailure`（字段名是 `error`，非 `error_type`） | 终态粘性 |
| 会话消失 | `SessionEnd`（字段名是 `reason`） | — |
| 行内容预览 | **`MessageDisplay`**（官方描述 "While assistant message text is displayed"；公开 payload `turn_id, message_id, index, final, delta`） | 新的 `message_id` 替换旧文本 |

> **更正（2026-08-18）。** `MessageDisplay` 这一行是后补的。上面那句「官方 Hooks 文档公开 30 个事件」在本次调研时逐个映射过，**唯独漏掉了它**，于是 `ClaudeCodeHookVocabulary.managedDefinitions` 也没有它，于是 [#34 / CC-015](https://github.com/soondubu137/codex-in-notch/issues/34) 得出了「Claude Code 侧取不到正文，要取就得再造一条等价于 `HookPreviewChannel` 的通道」这个结论。两半都是错的：正文取得到，而且不需要新通道——payload 本来就是 POST 进本进程的，正文抵达时已经在内存里。
>
> 本机实测（CLI 2.1.234，注册到一个临时 `--settings` 文件上的独立监听器，**全程未改动 `~/.claude/settings.json`**）：`-p` 非交互一次交付，`index: 0`、`final: true`，多行消息带着换行整份到达；交互式会话按增量交付，实测约每 0.3 秒一次。它也是唯一同时带 `prompt_id` 与 `turn_id` 的事件（两者不同值）；reducer 的身份仍用 `prompt_id`，此处只作记录。
>
> 已实现，见 [`tech-design.md` 第 11 节](../../tech-design.md)「正文如何到达本进程（Claude Code）」。

关键结构性优势：

- **`prompt_id`（v2.1.196+，当前 2.1.229 满足）是 `turn_id` 的直接对应物。** 现有 `HookTurnState` 的“精确 `threadID + turnID` 身份 + 退休 ID 不可复活”规则可以原样保留。
- **`agent_id` / `agent_type` 在子智能体上下文中存在。** 现有产品要求“子智能体不显示为独立行”，在 Codex 侧靠推断，在这里是精确过滤。
- **Hook 配置是热加载的。** 官方文档明确“对 settings 文件中 hooks 的直接编辑通常由 file watcher 自动生效”，不需要重启会话。
- **存在 `http` 类型 hook。** 意味着可以让 Claude Code 直接 POST 到应用内的 loopback listener，不需要 Codex 侧那套 “Python helper 写 0600 事件文件 + 应用轮询消费” 的落盘管线。这是一条值得单独评估的实现路线（见 §6.2）。（本条原写作 “`http` 类型 hook 与 `async: true`”，`async` 部分已于 2026-08-18 证伪，见该日更正。）

**待验证：** Hook 是否确实在 Desktop 托管的会话中触发。间接证据很强——Desktop 启动 CLI 时实测带 `--setting-sources=user,project,local`，即显式加载用户级 `~/.claude/settings.json`，且 `--settings {"fastMode":false}` 这一 inline override 不含 `disableAllHooks`。但本次调研**没有**写入任何 hook 配置去实证，因为那会修改用户配置。这是 Phase 0 的第一项。

### 4.3 会话身份与元数据

- 每个 Hook payload 都带 `session_id`、`transcript_path`、`cwd`、`permission_mode`。**路径由官方接口给出**，不需要猜测。
- transcript JSONL 中存在 `custom-title`、`ai-title`、`last-prompt` 记录，以及每条记录上的 `cwd`、`gitBranch`、`version`、`isSidechain`。标题、Project 归属与预览都可以从这里取。
- **但 JSONL 的记录结构本身不是公开契约。** 解析它属于私有依赖，需要按 [`AGENTS.md`](../../../AGENTS.md) 登记，并对缺失/损坏 fail closed。
- Project 概念在 Claude Code 侧没有 Codex 那样的用户创建实体。可用的等价物是 `cwd` + `gitBranch`，或 `claude agents --json` 返回的 `name`（实测为 `codex-in-notch-f6` 这类从目录派生的名字，`nameSource: derived`）。这与当前 PRD “禁止从 cwd、Git 根目录或路径最后一级推导 Project” 的规则直接冲突，需要产品决策（见 §8）。

### 4.4 导航（已决定降级，见 §8.1）

**结论：当前没有任何受支持的方式聚焦一个已经存在的 Claude Code 会话。**

官方证据：

- [Deep links 文档](https://code.claude.com/docs/en/deep-links) 定义的唯一路径是 `claude-cli://open`，参数只有 `q`（预填 prompt）、`cwd`、`repo`。它**总是新开一个终端窗口和新会话**，不接受会话 ID。
- Claude Desktop 侧公开的是 `claude://code/new`（可带 `?q=`、`?folder=`、`?file=`），同样只新建。

本机实测：

```text
open "claude://code/sessions/local_5ddb387b-66f4-4356-80f0-713248074c23"
→ main.log: [warn] claudeURLHandler: unrecognized code path { pathname: '/sessions/local_...' }
```

对安装包的只读检查显示 `/code/sessions/…` 路由在实现中确实存在，但它被 feature gate 保护，且其 ID 校验为 `/^(cse|session)_/`——即面向云端/远程会话 ID，本地会话的 `local_` 前缀不匹配。用 `cse_` 前缀的探测 ID 同样被拒，说明还有更严格的形状校验。**这是安装包实现细节，不是产品契约，不得据此实现。** 它唯一的价值是提示：本地会话 deep link 未来有可能出现，值得在每次 Desktop 更新后复查。

现有可行的替代路径，全部有代价：

| 路径 | 覆盖 | 代价 |
| --- | --- | --- |
| 只激活 Claude.app | Desktop 会话 | 用户仍需自己在侧边栏找会话；退化为“打开应用”而非“跳回会话” |
| pid → tty → Apple Events 聚焦终端标签页 | CLI 会话 | 需要 Automation（Apple Events）授权；需要逐个适配 iTerm2 / Terminal.app / Ghostty / kitty / WezTerm；PRD 现有约束只排除了辅助功能与屏幕录制权限，Apple Events 是否可接受需产品拍板 |
| Accessibility API 点击 Desktop 侧边栏 | Desktop 会话 | **与 PRD “不申请辅助功能权限” 直接冲突，本文不建议** |
| 等待官方提供本地会话 deep link | 两者 | 时间不可控 |

进程祖先链可以公开地区分两类宿主，实测：

```text
91157 (claude) → 91156 (Claude.app/Contents/Helpers/disclaimer) → 39127 (Claude.app)
```

即用 `ps -o ppid=` 向上走即可判定“Desktop 托管”还是“某个终端里的 CLI”，不需要读私有文件。

### 4.5 已读与自动移除

Claude Desktop 在 `~/Library/Application Support/Claude/claude-code-sessions/<org>/<account>/local_<uuid>.json` 中保存每个会话的：

```text
sessionId / cliSessionId / cwd / title / titleSource /
createdAt / lastFocusedAt / lastActivityAt / isArchived /
completedTurns / model / permissionMode
```

`lastActivityAt > lastFocusedAt` 是“未读”的自然等价物，`isArchived` 直接对应归档。`cliSessionId` 字段还提供了 Hook 的 `session_id` ↔ Desktop 会话 ID 的映射。

> **2026-08-19 更正：实现没有采用这个等价物。** `lastFocusedAt` 的真实语义已测实为“会话被显示到屏幕上的那一刻”，而本应用自己就知道轮次是什么时候结束的，所以判定用的是 `lastFocusedAt` 晚于**该轮次的终止时刻**，右边不再取自同一个文件。理由与代价见该日记录与 [ADR 0012](../../adr/0012-read-state-is-answered-per-product-or-not-at-all.md)。

风险等级与现有 Codex 未读适配器完全相同：私有只读 schema、高版本风险、必须 fail closed。纯 CLI 会话没有任何已读概念，其终态行只能靠手动 dismiss 或下一次 `UserPromptSubmit` 移除——`MonitorStore` 已有 dismissed-row 机制可复用。

### 4.6 额度

`~/Library/Application Support/Claude/plan-usage-history.json` 形如：

```json
{"version": 2, "samples": [{"t": 1786821640117, "org": "…", "u": {"fh": 3, "sd": 0}}]}
```

`fh` / `sd` 与官方 `/usage` 展示的滚动窗口对应（推测为 5 小时 / 7 天用量百分比，**未验证**）。这是 Claude Desktop 私有状态，纯 CLI 用户没有该文件。若 V1 要求额度圆环对 Claude Code 也成立，需要接受“仅 Desktop 用户可用，其余显示不可用”。

### 4.7 为什么不存在“原生实时状态源”

本次专门调查了“能不能不装 Hook、不轮询，直接监听一个原生真值源拿到所有会话的实时状态”。答案是**不能**。五个候选源全部实测评估如下：

| 候选源 | 是什么 | 为什么不够 |
| --- | --- | --- |
| `claude agents --json` | 官方公开命令，返回当前活动会话 | **只有身份，没有状态。** 返回字段固定为 `pid / cwd / kind / startedAt / sessionId / name`。在本会话正处于处理中时执行，输出与空闲时完全一致，没有任何 status 字段 |
| 会话间消息总线 `/tmp/cc-socks/<pid>.sock` | `[uds-messaging]`：NDJSON over Unix domain socket，1 MiB 单行上限，带 auth frame | **私有、需鉴权、且同样不含状态。** token 存放在 `~/.claude/sessions/<pid>.<sha256>.key`（0600），服务端校验 peer pid 与 token 匹配。CLI 自己的 peer 列表也只显示 name / kind / started，没有状态。连接它属于 §9 的 NO-GO |
| transcript JSONL（`transcript_path`） | 官方 Hook payload 给出路径，实时 append | **记录“发生过什么”，不记录“正在等什么”。** 实测 3.3 MB 真实 transcript 的全部记录类型只有 `assistant / user / system / attachment / custom-title / ai-title / last-prompt / queue-operation`：**没有轮次结束记录，也没有待审批记录**。等待审批与等待输入这两个状态在被解决之前不产生任何写入——而它们恰恰是本产品存在的理由 |
| Desktop `local_*.json` | Claude Desktop 私有会话状态 | `lastActivityAt` 实时更新，但 `isRunning` 只存在于 Desktop 进程的内存模型中（经其内部 MCP 暴露），未落盘。且纯 CLI 会话没有该文件 |
| `--output-format stream-json` | 会话真正的完整事件流，Desktop 消费的就是它 | 只有会话进程的**父进程**能读到这条管道。外部应用无法附着 |

结论：**Hook 是当前唯一受官方支持、能表达“此刻在等什么”的通道。** 这不是实现取舍，而是与 [`shared-app-server`](../shared-app-server/README.md) 中记录的 Codex 侧结论同源的能力边界——只不过 Claude Code 的 Hook 事件集足够细，不需要再叠加第二套证据来源。

但“必须用 Hook”不等于“必须做成 Codex 侧那样”。Hook 本身是**推送**语义，配合 `type: "http"` 后整条链路可以做成应用被动监听、稳态零轮询、零落盘，见 §6。

## 5. 对现有架构的影响

好消息是领域层几乎不需要动。`MonitorDomain.swift` 里的 `SessionStatus` 四态、`MonitorAvailability`、`MonitoredSession`、`MonitorAggregation` 都不含任何 Codex 语义；`HookEventRepository` 的事件 schema 与 Claude Code 的 payload 近乎逐字段对应：

| 现有 `HookEvent` 字段 | Claude Code 对应 |
| --- | --- |
| `session_id` | `session_id` |
| `turn_id` | `prompt_id` |
| `hook_event_name` | `hook_event_name` |
| `tool_use_id` | `tool_use_id` |
| `prompt` | `user_message` |
| `last_assistant_message` | `last_assistant_message` |

需要改动的边界：

```mermaid
flowchart LR
    subgraph unchanged ["基本不变"]
        domain["MonitorDomain\n四态 聚合 快照契约"]
        reducer["Turn reducer 规则\n精确身份 退休 ID 终态粘性"]
        ui["OverlayPanelController\nNotchOverlayView"]
    end

    subgraph newSeam ["需要新增的接缝"]
        provider["AgentProvider 协议\nsnapshot / navigate / setup"]
        codexProvider["CodexProvider\n现有实现整体下沉"]
        ccProvider["ClaudeCodeProvider\nagents --json + Hooks"]
        merge["多来源合并与排序\nMonitoredSession 增加 agent 标识"]
    end

    provider --> codexProvider
    provider --> ccProvider
    codexProvider --> merge
    ccProvider --> merge
    merge --> domain
    domain --> ui
    reducer -.->|"两侧共用"| ccProvider
    reducer -.->|"两侧共用"| codexProvider
```

具体改动清单：

1. **`CodexMonitoring` 升级为多提供者协议。** 现有 8 个方法（`fetchSnapshot` / `hookSetupStatus` / `installHooks` / `removeHooks` / `clearSessions` / `updateHookSettings` / `disconnect`）本身就是通用形状，需要的是允许多个实例并存并合并快照。
2. **`MonitoredSession` 增加来源标识**，用于行内图标、聚合与导航分发。当前 `id` 为 `threadID:turnID`，跨来源需要加前缀避免碰撞。
3. **`CodexNavigating` 拆成按来源分发的导航器**，且必须允许“导航能力不可用”这一状态——这是 Codex 侧从未出现过的情况，UI 需要新的表达（例如行可点但只激活应用，或行明确标记不可跳转）。
4. **`MonitorStatus` 的展示字符串去 Codex 化**（`"Connecting to Codex"`、`"Update Codex"`、`"Codex disconnected"`），改为按来源渲染。
5. **`CodexAppServerClient` 保持 Codex 专属**，不进入通用层。Claude Code 侧不需要等价物。
6. **产品命名。** 仓库、App、bundle 与 UI 文案目前整体叫 Codex in Notch，扩展后需要重新命名决策。

## 6. 推荐实现：稳态零轮询

Codex 侧的形状是能力受限下的产物：1 秒轮询 + Python helper 写 0600 事件文件 + 应用消费 + 独立 App Server 子进程 + 30/60 秒多级刷新。Claude Code 侧这四样**一样都不需要**。

```mermaid
flowchart LR
    subgraph launch ["仅启动时一次"]
        cold["claude agents --json\n≈0.2s 建立已有会话集合"]
    end

    subgraph push ["稳态：全部由 Claude Code 推送"]
        hooks["http hook"]
        listener["应用内 loopback listener"]
        reducer["HookEventRepository\n现有 reducer 规则不变"]
    end

    subgraph watch ["仅在会话增删时触发"]
        watcher["~/.claude/sessions/ 目录 watcher\n250ms debounce"]
        recheck["claude agents --json 复核"]
    end

    cold --> reducer
    hooks -->|"POST 每个状态迁移"| listener
    listener --> reducer
    watcher --> recheck
    recheck --> reducer
    reducer --> snapshot["MonitorSnapshot"]
```

稳态下没有任何定时器：状态变化由 Hook 推送，会话增删由文件事件触发。`claude agents --json` 只在启动和目录变化时各执行一次。

### 6.1 传输：`http` hook 取代 helper 脚本与事件文件

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [{
          "type": "http",
          "url": "http://127.0.0.1:<port>/hook",
          "timeout": 5,
          "headers": { "Authorization": "Bearer <install-time-token>" }
      }]}
    ]
  }
}
```

相比 Codex 侧的落盘管线：

- **不需要安装任何 helper 脚本**，因此不需要脚本升级、权限校验与哈希校验逻辑。
- **不产生事件文件**，因此不需要 0600 原子写、cutoff 分类、消费后删除与隔离目录。
- **不阻塞用户会话靠的是监听器立刻应答**，不是任何配置项：`AgentHookListener` 回 `200` + 空 body，会话的等待就是一次 loopback 往返。**没有 `async` 这个配置键**（2026-08-18 读 schema 证实），写进去只会被 settings 解析器悄悄丢掉。
- **应用未运行时 hook 连接被拒**（按非阻塞错误处理，会话正常完成、不进模型上下文），不会像落盘方案那样在应用关闭期间堆积无人消费的事件文件，也天然实现了“启动前事件不进入 reducer”这条既有规则。**但交互式会话会为每个事件打印一行 `hook error`**，这是代价而不是优点，见 2026-08-18 更正与 CC-021。

代价与必须处理的点：

- 需要固定 loopback 端口（hook URL 写死在 settings.json 里，无法动态发现）。端口冲突需要在安装时探测并写入实际端口，冲突后重装。
- 鉴权：安装时生成随机 token 直接写进 `headers`。它保护的只是一个 127.0.0.1 listener，不是凭证。**不要**走 `allowedEnvVars` 路线——那要求环境变量存在于会话进程环境中，而应用无法控制用户如何启动 `claude`。
- listener 必须只绑定 `127.0.0.1`，只接受 POST，拒绝非法 token，并对请求体大小设上限。

### 6.2 事件数量：4 个注册，可能只要 3 个

Codex 侧安装六类定义。Claude Code 侧建议起点：

| 注册 | matcher | 承担的状态 |
| --- | --- | --- |
| `UserPromptSubmit` | 无 | Running（新 Turn 由 `prompt_id` 建立身份） |
| `Notification` | `*` | Approval needed（`permission_prompt`）、Input needed（`idle_prompt` / `agent_needs_input` / `elicitation_dialog`）、可能的 Completed（`agent_completed`） |
| `Stop` | 无 | Completed |
| `SessionEnd` | 无 | 移除行 |

要点：

- **`Notification` 一条注册覆盖所有通知类型。** matcher 按 `notification_type` 过滤，用 `*` 即可全收，在应用侧按 payload 的 `notification_type` 分派。这是把六类事件压缩成一条注册的关键。
- **`PermissionRequest` / `PermissionDenied` 暂不注册。** 只有当 Phase 0 证明 `Notification(permission_prompt)` 无法表达“审批已解决”时才加回来——它们带 `tool_use_id`，可以走现有 reducer 的成对开闭模型。
- **`Stop` 可能可以省掉。** 若 Phase 0 证明 `Notification(agent_completed)` 在普通交互会话中也触发，则注册数降到 3。文档未说明该类型是否只在后台 agent 中出现，必须实测。
- **`SessionStart` 不需要注册。** 会话创建由目录 watcher 感知，且 `SessionStart` 不带 `prompt_id`，对状态机没有贡献。

### 6.3 会话发现：事件驱动，不轮询

- 启动时执行一次 `claude agents --json`，建立已有会话集合。~~**这就直接解决了 Codex 侧的冷启动能力边界**——不需要等待下一个生命周期事件。~~ **这一条已被实现否决（2026-08-19）。** 会话列表只答「有哪些会话」，轮次状态要靠 transcript 补；而等待用户期间 transcript 不写入任何东西，重建出的轮次因此只可能是 *Running*，启动瞬间停在权限请求上的会话被画成正在干活。启动前一律不显示如今是两个产品共同的规则，见 [`PRD.md`](../../PRD.md) 第 3 节与 [`system-architecture.md` §2.1](../../system-architecture.md#21-启动边界不做现状同步)。
- 用 `DispatchSourceFileSystemObject` 监听 `~/.claude/sessions/` 目录 + 250 ms debounce（该模式在 [`CodexDesktopUnreadState.swift`](../../../CodexInNotch/CodexInNotch/CodexDesktopUnreadState.swift) 已有实现），变化时再执行一次 `claude agents --json` 复核。
- 目录内容格式**不解析**，只当作“该复核了”的信号。权威数据永远来自官方命令。这样即使私有文件 schema 变化，最坏结果是复核触发变迟钝，退化到启动时的一次快照，而不是错误状态。

启动时会话的状态未知，可以按 [`CONTEXT.md`](../../../CONTEXT.md) 已定义的**未知（Unknown）**发布，等第一个 Hook 事件收敛为四态之一。这比 Codex 侧“启动前会话一律不显示”严格更好。**——同样已被否决（2026-08-19）：一行状态未知的会话回答不了「谁在等我」，而这正是本产品存在的理由；两侧现在都是「启动前一律不显示」。**

### 6.4 被否决的路线

- **纯 transcript 监听（无 Hook）：** 见 §4.7。看不到等待状态，直接否决。
- **连接会话消息总线：** 需要读取私有 token 文件并逆向未公开帧格式，属于 §9 NO-GO。
- **沿用 Codex 的落盘 helper 管线：** 可行且与现有代码同构，但在 `http` hook 可用的前提下是纯粹的额外复杂度。仅在 Phase 0 证明 `http` hook 不可靠时作为退路。

## 7. 分阶段验证计划

每阶段完成后记录证据再决定是否继续。任何阶段观察到会话行为变化、审批阻塞或配置损坏，立即停止并回滚。

### Phase 0：确认 Hook 在两种宿主中都触发（必须最先做）

目标：证明写入 `~/.claude/settings.json` 的用户级 hook 对 Desktop 托管会话与终端 CLI 会话都生效。

执行前必须获得用户明确授权，因为这会修改用户的 Claude Code 配置。

1. 备份现有 `~/.claude/settings.json`（本机当前**不存在**该文件，需注意首次创建与后续合并的差异）。
2. 安装 §6.2 的四条注册，`type: "http"` 指向一个临时 loopback listener。
3. 在 Claude Desktop 中发起一轮对话，确认事件是否到达。
4. 在终端 `claude` 中重复同一验证。
5. **验证 `Notification` 的类型覆盖面**，这是能否压到 3–4 条注册的关键：
   - `permission_prompt` 是否在普通交互会话触发，以及**审批被批准/拒绝后是否有对应的关闭通知**；若没有，加回 `PermissionRequest` + `PermissionDenied` 走 `tool_use_id` 成对模型。
   - `agent_completed` 是否在普通交互会话触发；若是，可省掉 `Stop`。
   - `idle_prompt` 的实际触发条件（是否有空闲延迟，会不会把 Running 误报成 Input needed）。
6. **验证 `http` hook 的可靠性：** 应用未监听时会话是否完全无感（2026-08-18 已答：**交互式会话每个事件打印一行错误**，非阻塞但可见）；超时行为；高频事件下是否丢事件。
7. 确认热加载：不重启会话直接改 hook 定义，观察是否生效。
8. 确认 workspace trust 的实际影响：官方文档说明 settings 文件中的 hooks 需要接受 workspace trust 对话框，需实测新增 hook 是否触发新的信任提示。
9. 完整移除 hook，确认配置恢复原状。

**停止条件：** Desktop 会话收不到 hook；安装 hook 会让用户在每个项目重新走信任流程；或 `http` hook 在应用未运行时对用户会话产生任何可见影响。

### Phase 1：会话集合与身份

1. 多会话并发下验证 `claude agents --json` 的完整性（Desktop 两个 + 终端一个 + 后台 agent 一个）。
2. 验证 `sessionId` 与 Hook 的 `session_id` 一致。
3. 验证 `prompt_id` 在同一会话连续多轮中确实变化，且不复用。
4. 验证子智能体事件带 `agent_id` / `agent_type`，可被正确过滤。
5. 验证会话结束后从 `agents --json` 中消失的时机。

### Phase 2：四态状态矩阵

在 `HookEventRepository` 的现有规则下重放真实事件序列，覆盖：

| 场景 | 必须观察到 | 不允许发生 |
| --- | --- | --- |
| 正常完成 | `UserPromptSubmit → Stop` | 出现第五种可见状态 |
| 权限审批 | `PermissionRequest` 开、同 `tool_use_id` 关 | 无真实等待时显示 Approval needed |
| 审批被拒 | `PermissionDenied` 关闭等待 | 等待悬挂 |
| 需要输入 | `Elicitation → ElicitationResult` 成对 | 用无关事件清除等待 |
| 请求失败 | `StopFailure` 直接进 Completed | 展示 `error_type` 细节 |
| 同会话下一轮 | 新 `prompt_id` 原子替换 | 旧 `prompt_id` 复活 |
| 压缩 | `PreCompact` / `PostCompact` 不改变状态 | 被误判为终态 |
| 会话结束 | `SessionEnd` 移除行 | 行残留 |

建议最低重复次数与 `shared-app-server` 探索一致：正常完成 30 次，审批合计 30 次，输入 20 次，失败与并发各至少 10 次。

### Phase 3：降级导航

> **2026-08-19：已实现并合入**（[#31](https://github.com/soondubu137/codex-in-notch/issues/31)）。第 1–3 条按下面的形状落地，实现与实测结论见 [`tech-design.md`](../../tech-design.md) §14.2、[`ClaudeCodeNavigator.swift`](../../../CodexInNotch/CodexInNotch/ClaudeCodeNavigator.swift) 与[私有依赖清单](../../non-public-codex-integration-features.md)。两点与下面的设想不同：走祖先链用的是 `sysctl(KERN_PROC_PID)` 与 `proc_pidpath` 而不是 `ps` 子进程；Ghostty 有完整脚本字典但整份没有 tty，因此归入「只激活应用」而不是需要逐个适配的那一类。**第 4 条已做**：2026-08-19 在 Terminal.app 里的真实 Claude Code 会话上跑通了未决 / 允许 / 拒绝三条路径，弹窗原文与实测数字见 [`tech-design.md`](../../tech-design.md) §14.2。

> **验证这条路径时踩到的坑，留给下一个人。** TCC 认的客户端身份取决于**应用是怎么被启动的**。直接 exec `…/DerivedData/…/CodexInNotch.app/Contents/MacOS/CodexInNotch` 拿到的授权，与经 Launch Services（`open -n -a`）启动同一个 bundle 拿到的**不是同一条记录**：前者授权之后，后者仍然报 `undecided`。这也解释了另外两个现象——那条授权在「系统设置 › 隐私与安全性 › 自动化」里根本不出现，`tccutil reset AppleEvents com.yinfenglu.CodexInNotch` 也匹配不到它。**只有 Launch Services 那条路径才是发布后的真实身份**，验证必须走 `open -n -a … --env … --stderr …`，直接跑二进制测出来的结论不作数。

产品已决定采用降级导航（§8.1），本阶段只验证实现：

1. 用 `ps -o ppid=` 向上走进程祖先链判定宿主类型。实测形态：
   `91157 (claude) → 91156 (Claude.app/Contents/Helpers/disclaimer) → 39127 (Claude.app)`。
   祖先中出现 `Claude.app` 即为 Desktop 托管，否则找到的终端进程即为宿主。
2. Desktop 会话：`NSWorkspace` 按 bundle id `com.anthropic.claudefordesktop` 激活即可，无需 deep link。
3. CLI 会话：pid → `ps -o tty=` → Apple Events 聚焦对应标签页。至少覆盖 iTerm2 与 Terminal.app；Ghostty / kitty / WezTerm / Alacritty 逐个确认支持程度，不支持的降级为仅激活应用。
4. 记录 Automation 权限提示的实际形态与用户成本，并确认被拒绝后的降级路径不报错、不反复弹窗。
5. 每次 Claude Desktop 更新后复查 `/code/sessions/` 路由是否开始接受本地会话 ID；一旦官方支持出现，应迁移到 deep link 并移除 Apple Events 路径。

### Phase 4：已读、额度与降级

1. 验证 `lastFocusedAt` / `lastActivityAt` 的更新时机与节流延迟（Codex 侧观察到约 500 ms 持久化延迟，此处需重新测量）。
2. 验证 `plan-usage-history.json` 的 `fh` / `sd` 与官方 `/usage` 显示是否一致。
3. 验证 Claude Code 未安装、版本过低、hook 未信任三种情况下的降级表现。

## 8. 必须由产品决定的问题

### 8.1 已决定（2026-08-15）

1. **导航降级可接受，且只对 Claude Code 降级。**
   - Claude Code Desktop 会话：只激活 Claude Desktop，不要求定位到具体会话。
   - Claude Code CLI 会话：只聚焦其所在的终端标签页，不要求定位到具体会话。
   - **Codex Desktop 侧维持精确导航要求不变**，ADR-0004 的发布门槛继续适用于 Codex。
2. **接受申请 Automation（Apple Events）权限**，用于聚焦终端标签页。辅助功能与屏幕录制仍然排除。

这两条需要同步反映到 PRD 第 3 条目标与 ADR-0004 的适用范围——两者当前都是无条件表述，扩展后必须按来源区分。建议在实现改动中一并更新，而不是留在本探索文档里。

### 8.2 仍待决定

> 以下四条已全部有下文，逐条跟踪见 GitHub 看板 [soondubu137/projects/2](https://github.com/users/soondubu137/projects/2)：3 已由 ADR 0009 解决；4 已由 ADR 0007 解决（额度对所有用户可用，不限 Desktop）；5 见 #36；6 已决定保持四态，理由见 §10 与 [#26](https://github.com/soondubu137/codex-in-notch/issues/26)。


3. **Project 语义怎么定义？** Codex 侧有用户创建的 Project 实体且明令禁止从 cwd 推导。Claude Code 侧不存在该实体，只有 `cwd` / `gitBranch` / 派生 `name`。要么为 Claude Code 行放宽规则，要么该列显示为不适用。
4. **额度只对 Desktop 用户可用是否可接受？**
5. **产品命名与定位。** 从 “Codex in Notch” 变成多智能体中心，仓库名、App 名、bundle id、UI 文案与引导流程都要重做。
6. **两侧状态语义是否强行对齐？** Claude Code 能提供比四态更细的信息（如 `StopFailure` 的 `error_type`）。保持四态可以复用整条链路，但会丢弃真实可用的信息。

## 9. NO-GO 条件

出现任一条件即不应把该方案产品化：

- ~~Phase 0 证明用户级 hook 对 Desktop 托管会话不生效~~ —— **已于 2026-08-16 排除，见 §10**。
- 安装 hook 会导致用户在每个项目重新走 workspace trust 流程，形成不可接受的安装摩擦。
- `http` hook 在应用未运行或崩溃时会对用户会话产生可见影响（阻塞、报错、卡住审批）。
- 降级导航连“激活正确的应用/终端”都做不到，或只能靠辅助功能权限与 GUI 自动化实现。
- 需要修改 `Claude.app`、`app.asar`、注入 Electron IPC，或连接 `/tmp/cc-socks/*.sock` 这类未公开的会话间消息通道来获取状态或导航。
- 官方后续移除 `claude agents --json` 对交互式会话的可见性，退回到与 Codex 相同的“无法查询当前态”。

## 10. 探索记录

沿用 [`shared-app-server/README.md` §14](../shared-app-server/README.md) 的模板，后续追加，不覆盖早期证据。

### 2026-08-15 — 初次可行性调研（只读）

- 执行范围：本机只读检查 + 一次 `claude://` deep link 探测 + 两次 `claude agents --json`
- Claude Desktop：`1.30096.5`，bundle `com.anthropic.claudefordesktop`
- 内置 Claude Code CLI：`2.1.229`
- macOS：`Darwin 25.5.0`
- 未修改：任何配置、任何生产代码、任何用户状态
- 结果：状态汇总 PASS（证据见 §4.1–4.3）；精确导航 **FAIL**（§4.4）
- 未验证项：Hook 在 Desktop 托管会话中的实际触发（Phase 0）；`fh` / `sd` 的确切窗口语义；`lastFocusedAt` 更新时机
- 下一步建议：先做 §8 的产品决策 1 与 2，再决定是否投入 Phase 0

### 2026-08-15 — 原生真值源调查与产品决策（只读）

- 触发问题：能否不装 Hook、不轮询，直接监听原生真值源
- 新增只读检查：`claude agents --help`、`ListAgents` peer 列表、3.3 MB 真实 transcript 的全量记录类型统计、`claude` 二进制中 `[uds-messaging]` 实现片段
- 结果：**不能**。五个候选源全部只描述身份或已发生的事实，详见 §4.7
- 附带发现 1：`claude agents --help` 明确写明 `--json` 打印 “active sessions (interactive and background)”，交互式会话可见是**文档承诺**而非观察到的巧合，§4.1 据此升级
- 附带发现 2：`Notification` 单条注册即可按 `notification_type` 覆盖审批与输入两类等待，注册数有望从六条压到三到四条，§6.2 据此重写
- 附带发现 3：会话消息总线为带 token 鉴权的 NDJSON over UDS，token 位于 `~/.claude/sessions/<pid>.<sha256>.key`；已列入 §9 NO-GO
- 产品决策：导航降级可接受（仅 Claude Code）；Apple Events 权限可接受。已写入 §8.1
- 未修改：任何配置、任何生产代码、任何用户状态
- 下一步建议：直接进入 Phase 0，重点是 `Notification` 类型覆盖面与 `http` hook 可靠性两项

### 2026-08-16 — Phase 0 局部执行：`http` hook 实测（CLI，未覆盖 Desktop 托管）

- 执行范围：**未修改 `~/.claude/settings.json`**。全部通过 `claude -p --settings <临时文件>` 注入 15 条 `type: "http"`、`async: true` 的注册，指向一个只绑 `127.0.0.1`、要求 bearer token、只记录字段名与安全标量（从不记录 prompt / tool_input / tool_response 内容）的临时监听器。共 5 次 `-p` 运行，模型 `claude-haiku-4-5`。
- 基线：Claude Code CLI `2.1.233`，macOS `Darwin 25.5.0`

**结论：`http` hook 通道成立，且 NO-GO 条件仅差一步被触发。**

| # | 结果 | 影响 |
| --- | --- | --- |
| 1 | 15 条注册全部投递成功 | `http` hook 可用 |
| 2 | 监听器关闭时，hook **完全静默失败**，会话正常完成（`is_error: false`） | 应用未运行不影响用户。**⚠️ 已于 2026-08-18 部分更正：静默只成立于 `-p`；交互式会话每个事件都打印 `hook error`** |
| 3 | **`SessionEnd` 例外**：向 stderr 打印 `SessionEnd hook [...] failed: connect ECONNREFUSED`，每次会话一行 | 这是 §9 NO-GO 里「应用未运行时对用户会话产生可见影响」。**对策：不要用 http 注册 `SessionEnd`**——它在本产品里只负责移除行，而会话消失同样能由 `claude agents --json` 与 `~/.claude/sessions/` watcher 观察到。去掉它，**stderr 上的**可见影响归零。**⚠️ 已于 2026-08-18 更正：交互式会话里其余事件照样每条打印一行 `hook error`，所以“可见影响归零”只对 `-p` / 脚本场景成立**（该日复测：`Stop` 与 `PreToolUse` 同时注册，stderr 只有 `SessionEnd` 一行） |
| 4 | **`PermissionRequest` 不带 `tool_use_id`**（实测字段：`agent_id, agent_type, cwd, hook_event_name, permission_mode, permission_suggestions, prompt_id, session_id, tool_input, tool_name, transcript_path`） | 证实 §4.2 与 §3 第 3 条写错了。Codex 侧的「借用仍打开的调用 id」模型在 Claude Code 侧**仍然必需**，不会消失 |
| 5 | 非交互运行中 `PermissionRequest` 照样触发，无人被询问 | 与 Codex 同一教训：孤立的 `PermissionRequest` 不是「有人在等」的证据 |
| 6 | `prompt_id` 出现在**每一个**事件上，包括 `SessionEnd` | 它就是 `turn_id`，身份规则可原样保留 |
| 7 | **子智能体事件带父会话的 `session_id` 与 `prompt_id`**，另加 `agent_id` / `agent_type` | 子智能体活动天然折叠进父 Turn，不需要额外身份工作，也不会产生独立行 |
| 8 | **`UserPromptSubmit` 在 `-p` 运行中没有 `source` 字段** | 自噪声过滤**不能**依赖 `source == "user"`；把额度轮询钉在专用工作目录、按 `cwd` 过滤才是主防线 |
| 9 | **payload 里没有任何时间戳** | Codex 的 helper 自己写 `received_at`；http 监听器必须在到达时自己盖时间戳 |
| 10 | **投递无序。** 同一 `prompt_id` 下，父 `Stop` 先于子智能体的 `PermissionRequest` 与 `SubagentStop` 到达 | 投递不保证顺序（与 `async` 无关，该键不存在）。reducer 依赖 `lastEventAt` 单调，只能由监听器的到达时刻喂给它；而「另一个 `tool_use_id` 上的活动关闭借用审批」这条规则在乱序下可能误判，需要在设计里单独处理 |
| 11 | `Stop` 额外带 `session_crons`（此前未记录），`background_tasks` 本次为 0 | — |
| 12 | `PostToolUseFailure` 在普通工具错误（文件不存在）时触发，带 `error` / `is_interrupt` / `duration_ms` | 中断与错误可区分 |

**未回答，且必须用真实 `~/.claude/settings.json` 才能回答的一条：hook 是否在 Claude Desktop 托管的会话中触发。** 这是决定整个方案存亡的问题（§9 第一条），而 `--settings` 只作用于它启动的那个 CLI 进程。审批相关的 `Notification(permission_prompt)` 同样测不到——它按定义只在有人被真正询问时才出现，非交互运行不产生对话框。两者都需要一次交互式验证。

### 2026-08-16 — Phase 0 收尾：Desktop 托管会话确实触发 hook

- 执行范围：用户本人把七条 `type: "http"` 注册写入真实 `~/.claude/settings.json`（本 Agent 被权限分类器拦下，未自行写入），随后立即从备份还原。监听器同前，仍只记录字段名与安全标量。
- **`SessionEnd` 被刻意排除**，见上一条记录第 3 项。

**结论：§9 第一条 NO-GO 不成立。用户级 hook 在 Claude Desktop 托管的会话中正常触发，整个方案成立。**

证据是本次对话自身——`~/.claude/sessions/45912.json` 记录该进程 `"entrypoint":"claude-desktop"`，而监听器收到的每一个事件都带同一个 `session_id: ff1a9f95-…`：

| 事件 | 关键字段 |
| --- | --- |
| `UserPromptSubmit` | `prompt_id: 7d174256…`，`permission_mode: auto` |
| `PreToolUse` | 同 `prompt_id`，`tool_name: Bash`，`tool_use_id: toolu_01Qq4o…` |
| `PostToolUse` | 同 `prompt_id`、**同 `tool_use_id`**，`duration_ms: 3049` |

即成对开闭模型在 Desktop 托管会话里与 CLI 会话完全同构。

两项补充观察：

1. **`permission_mode` 出现了 `auto`**，此前 `-p` 运行中只见过 `default`。状态映射不得假设该字段的取值集合。
2. **`UserPromptSubmit` 在真人交互提交时同样没有 `source` 字段**（实测 keys：`cwd, hook_event_name, permission_mode, prompt, prompt_id, session_id, transcript_path`）。这比上一条记录第 8 项更强：`source` 不是「`-p` 才缺席」，而是**普遍缺席**，因此自噪声过滤只能靠把额度轮询钉在专用工作目录并按 `cwd` 过滤。
3. 交互会话的事件还多带一个 `effort` 字段。

**仍未验证：`Notification(notification_type: permission_prompt)`。** 它按定义只在真的向人弹出审批对话框时出现，本次会话处于 `permission_mode: auto`，没有产生对话框。这一项不阻塞设计——审批区间的开闭已由 `PermissionRequest` 借用 id、`PostToolUse` / `PermissionDenied` 关闭这条链路覆盖——但在实现审批状态前应补测一次。

## 11. 参考入口

- 官方 Claude Code Hooks：<https://code.claude.com/docs/en/hooks>
- 官方 CLI 参考（含 `claude agents --json`）：<https://code.claude.com/docs/en/cli-reference>
- 官方 Deep links：<https://code.claude.com/docs/en/deep-links>
- 官方 Desktop 应用：<https://code.claude.com/docs/en/desktop>
- 当前领域状态：[`MonitorDomain.swift`](../../../CodexInNotch/CodexInNotch/MonitorDomain.swift)
- 当前 Hook reducer 与安装器：[`HookIntegration.swift`](../../../CodexInNotch/CodexInNotch/HookIntegration.swift)
- 当前编排器：[`LiveCodexMonitorService.swift`](../../../CodexInNotch/CodexInNotch/LiveCodexMonitorService.swift)
- 当前导航：[`CodexDesktopNavigator.swift`](../../../CodexInNotch/CodexInNotch/CodexDesktopNavigator.swift)
- 当前架构：[`system-architecture.md`](../../system-architecture.md)
- 非公开依赖登记规则：[`AGENTS.md`](../../../AGENTS.md)

### 2026-08-18 — 更正：`async` 不是配置键，且“静默失败”只成立于 `-p`

基线：Claude Code CLI `2.1.235`（schema 同时在 `2.1.233` 上核对），macOS `Darwin 25.5.0`。起因是用户报告 CLI 会话刷出成百上千行 `connect ECONNREFUSED 127.0.0.1:51741`。

| # | 结果 | 依据 | 影响 |
| --- | --- | --- | --- |
| 1 | **`http` hook 的配置 schema 里没有 `async`。** 接受的键只有 `type` / `url` / `if` / `timeout` / `headers` / `allowedEnvVars` / `statusMessage` / `once` | 从 `2.1.233` 与 `2.1.235` 两个二进制中读出 `HttpHookSchema` | 本文档此前多处“`async` 保证不阻塞”的说法作废。`async` 现在是**响应体**字段：hook 回 `{"async": true, "asyncTimeout": n}` 表示自己会在后台继续 |
| 2 | **写进去的 `async` 会被悄悄删掉。** hooks 经 zod 解析（未知键直接丢弃、不告警），而任何一次设置写入（`/effort`、`/theme`、`/config`、权限、插件安装）都用解析后的模型整体重写 `~/.claude/settings.json` | `updateSettingsForSource`：`l = 校验后的设置` → 合并 → `write(JSON.stringify(merged, null, 2))` | 这就是用户“改了好几次又没了”的原因，不是别的程序在改文件。对本应用的后果更重：`isCurrentManagedHandler` 比的是整个 handler，键被删 → 报 `repairRequired` → 用户重贴 → 下次写入再删。已从 `loopbackPost` 去掉该键 |
| 3 | 带 `async` 与不带 `async` 的注册**行为完全一致**：同样的错误记录、同样的时长、同样接受响应注入 | 两次 `claude -p` 对照，各 4 轮工具调用 | 佐证 #1。去掉它不损失任何东西 |
| 4 | **交互式会话会为每个失败事件打印一行 `<hookName> hook error`。** 渲染处只对 `Stop` / `SubagentStop` 返回 `null`，其余一律打印，且**没有任何设置或环境变量可以关闭** | 二进制中 `case "hook_non_blocking_error"` 分支；另查 `suppressHook` / `hideHook` / `HOOK_SILENT` / `DISABLE_HOOK` 均无 | 2026-08-16 的“完全静默失败”只在 `-p` 下成立（`-p` 不把它写到 stderr，但仍写进 transcript）。§9 NO-GO 里“应用未运行时对用户会话产生可见影响”这一条，因此**对所有事件成立，而不只是 `SessionEnd`**。见 CC-021 |
| 5 | 失败**不进模型上下文、不花 token**：记录为 `{"type":"hook_non_blocking_error","exitCode":0}` 的 attachment | 8 个错误与 16 个错误的两次运行，前四条 assistant 消息 input token 完全相同（25258） | 噪声是 UI 层面的，不影响会话质量、时长或成本 |
| 6 | 连接被拒在 loopback 上是立即返回，`timeout: 5` 不会被等满 | 两次运行时长一致 | 只有当地址变成“不可达”而非“被拒”（例如过滤型防火墙）时才会真的卡住 |
| 7 | **端口无人占用时是可以被别的进程抢走的。** `51741` 落在 macOS ephemeral 区间（`net.inet.ip.portrange.first: 49152`） | 用一个 40 行的本地监听器冒充本应用，收到了完整 `prompt`、`cwd`、`transcript_path`、`session_id` 与 bearer token；回一段 `additionalContext` 后，下一次会话按注入的内容作答 | bearer token 只能证明 CLI 的身份、不能证明监听器的身份。这是本条通道的真实风险面，见 CC-021 |

### 2026-08-19 — 已读自动移除：`lastFocusedAt` 的语义已确认，并已实现（CC-013）

基线：Claude Desktop `1.32885.1`、内置 Claude Code CLI `2.1.234`、本机 CLI `2.1.235`，macOS `Darwin 25.5.0`。执行范围：只读——`local_*.json` 与两个二进制的字符串检索，未写入任何文件、未调用任何 IPC。

§2 表里那条“已读自动移除：`lastActivityAt` vs `lastFocusedAt`”当时是**推测**。这次把它测实了，并且**改了判定规则**：

| # | 结果 | 依据 | 影响 |
| --- | --- | --- | --- |
| 1 | `lastFocusedAt` 的语义是「**会话被显示到屏幕上**」，不是「最后一次活动」。写法是 `setSessionVisibility(id, isVisible, reason)` 在 `isVisible` 为真时 `lastFocusedAt = Date.now()` 并**立即** `saveSession` | 安装包 `app.asar` 只读检索 | 这正好就是「用户读了它」，比 `lastActivityAt > lastFocusedAt` 这个推测更直接 |
| 2 | **判定改为 `lastFocusedAt` 晚于该 Turn 自己的终止时刻**，不再与同文件的 `lastActivityAt` 相比 | 本应用已由 reducer 掌握终止时刻 | 桌面端的活动记账延迟、节流或停写都不能把一个轮次说成已读；陈旧快照也只会让行多留一会儿 |
| 3 | 记录写入是**同目录临时文件 `rename` 原子替换**（实测 inode 变化：`63502564 → 63503966`） | 250 ms 采样器观察真实写入 | 目录级 watcher 有效，与 `~/.claude/sessions/<pid>.json` 的原地重写相反 |
| 4 | 本机 31 份记录、约 2 MB。全部解析 **5 ms**，按 `(size, mtime, inode)` 缓存后重读 **1 ms** | 用生产 adapter 对真实目录跑一次 | 每次刷新都读得起；不需要单独的节流 |
| 5 | 真实数据里 20 份记录中 17 份 `lastFocusedAt > lastActivityAt` | 同上 | 用户读完会话后确实会再盖一次章，规则在真实使用轨迹上成立 |
| 6 | **纯终端会话在这棵树里没有文件**，Claude Code 自己也不落盘任何 focus / read / seen 字段（`~/.claude/sessions/<pid>.json` 只有 `status` / `waitingFor` / `updatedAt` / `statusUpdatedAt` / `entrypoint`；二进制里的 `isFocused` 全部是 Ink 组件入参） | `2.1.235` 字符串检索；本机四个会话的记录 | 已读只能覆盖 Desktop 托管的一半，这是能力边界不是实现缺口。产品语义见 [ADR 0012](../../adr/0012-read-state-is-answered-per-product-or-not-at-all.md) |
| 7 | 本机验证：两个 Desktop 托管会话（`0141019a…`、`84a0c44a…`）能按 `cliSessionId` 连接到记录并取到 focus 时刻；本文档所在的终端会话（`f5eb12c1…`）报告 `unknown` | 生产 adapter 对真实目录的一次探针运行 | 身份连接不需要任何推断 |

**同日晚间的实时观察（250 ms 采样器，跨 30 分钟）：** 用户在 Claude Desktop 里打开一个会话，采样器只捕到**一次**写入，内容正是这条规则要的东西——

| 观察 | 值 |
| --- | --- |
| `lastFocusedAt` | `1787114114311`（08-18 21:35:14.311）→ `1787126484364`（08-19 01:01:24.364） |
| 写入方式 | 新 inode（`63521014`），即临时文件 `rename` |
| 该会话此前的状态 | `lastFocusedAt` 21:35:14 < `lastActivityAt` 21:38:54，两种规则下都是未读 |
| 打开之后 | 已读 |
| 该会话的 CLI 进程 `startedAt` | `1787126485613`，比 focus 盖章**晚 1.249 秒** |

最后一行是这次唯一的意外收获：**盖章发生在恢复该会话的 CLI 进程之前**，所以「用户打开了一个会话」这件事，本应用在那个会话的进程存在之前就已经能看见了。同一形态在 8 月 18 日的另一份记录里也成立（focus 早于 `startedAt` 约 1.1 秒）。

**同日的第二次实机验证，答案是否定的，而且比预想的更彻底。** 用户在 notch 上跑了一次完整流程：Desktop 里开会话 → 提交 → 切到别的窗口 → 轮次跑完（notch 出现 Completed）→ 切回 Claude Desktop 读它。采样器记录：

| 时刻 | 变化 |
| --- | --- |
| 01:06:33.307 | `lastFocusedAt` ← now（在侧栏里选中该会话） |
| 01:06:43.458 | `lastActivityAt` ← now（提交） |
| 01:07:37.826 | `lastActivityAt` ← now，`completedTurns` 1→2（**轮次结束**） |
| 之后 | **无任何写入** |

随后对整个 `~/Library/Application Support/Claude` 做「最近 6 分钟内被修改过的文件」扫描：**0 个**。所以不只是 `lastFocusedAt` 不盖章——**那次阅读在磁盘上完全没有痕迹**。`reason === 'blur'` 分支的存在曾让人推断「获得焦点大概也会发 `true`」，实测证伪：渲染进程发的是 document 可见性的跃迁，而 macOS 上另一个应用抢走焦点并不改变 `document.hidden`。

结论：**只读文件的适配器不可能覆盖「停在同一个会话上、切走再切回」这个最常见的用法。** 由此加入第二条判定路径（应用回到前台 + Desktop 记录里最后被显示的就是这个会话），它推翻了两条只为 Codex 写的既有规则，理由与代价见 [ADR 0012](../../adr/0012-read-state-is-answered-per-product-or-not-at-all.md)。

### 2026-08-19（复查）— 文件侧到此为止，剩下的两条只能从人的动作来（CC-013）

基线同上（Claude Desktop `1.32885.1`）。执行范围：只读——`app.asar` 与 `~/Library/Logs/Claude/main.log` 的字符串检索、`local_*.json` 全字段转储、`claude agents --json` 一次，未写入任何文件、未调用任何 IPC。

上一节收尾时留了一句「用户全程盯着会话跑完那一种仍不覆盖」。这次去找那条路，先把还没查过的来源查干净：

| # | 结果 | 依据 | 影响 |
| --- | --- | --- | --- |
| 1 | **Claude Desktop 对 Claude Code 会话没有任何已读字段。** `lastReadAt` / `hasUnread` / `seenAt` / `viewedAt` 在安装包里 0 命中；`markAsRead`(8) 与 `isRead`(89) 的命中**全部**属于 Outlook MCP connector 的邮件规则 schema，与会话无关 | `app.asar` 全文检索 | 没有可以当蓝点用的集合。ADR 0012「按产品各自取源」的判断在这一版上再次成立 |
| 2 | **`main.log` 比文件只少不多。** `[CCD] LocalSessions.setFocusedSession: sessionId=…` 以 `[info]` 落盘（本机 4 天 531 行），但它只在**切换会话**时出现，是 `lastFocusedAt` 盖章时刻的子集 | 把 25 个会话的最后一条日志时刻与记录里的 `lastFocusedAt` 对齐 | 日志路线不能多覆盖任何东西，而且日志级别、行文本与轮转都不是契约。已拒绝 |
| 3 | **窗口重新获得焦点确实什么都不写。** 日志里 46 行 `[SkillsPlugin] Window focused`，其后 60 行内没有任何 visibility 写入的有 23:11:42、00:17:05 两处；其余每一处紧跟的都是用户自己的一次会话切换 | 同上 | 从另一个方向独立证实了上一节的「0 个文件变化」 |
| 4 | **`lastFocusedAt` 会在没有人的情况下被盖章。** 09:29:00 `system woke — reconnecting`、`main process blocked for 603508ms [likely sleep: power_event]`，09:29:06 `[WarmLifecycle] Warming up session local_e7cca89e…`，记录里的 `lastFocusedAt` 落在 09:29:09——全程没有 `setFocusedSession` | 日志时刻与记录值对齐（该会话上一条 `setFocusedSession` 在 8 小时前的 01:29:35） | 第一条判定有一个朝「提前移除」倒的方向。醒来时那个答案就在屏幕上，所以离谱有限，但它是既有规则里唯一一处不需要人也会成立的路径 |
| 5 | **Desktop 托管的行并不是「永远留着」。** 本地会话隐藏 900 秒后被 `teardownSession` 拆掉（`idle_timeout` 且 `shouldKillOnIdlePause()` 为真），进程消失、会话离开 `claude agents --json`，行随之退出 | 22:04:26 `Starting idle timeout … 900s` → 22:19:27 `Pausing session … (idle_timeout)`；`app.asar` 里的分支 | **修正 issue #32 的前提**：Desktop 会话切走之后最迟 15 分钟自己消失，CC-013 要修的是「读完还要再等最多十五分钟」。真正无限期留着的只有「停在那个会话上不动」（终端会话另计，它们不进这条规则） |
| 6 | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType:)` 可按事件类型分别取值，公开、无 entitlement、不弹授权 | 本机实测 `keyDown 82.9s` / `scrollWheel 574.1s` / `leftMouseDown 294.6s` / `mouseMoved 293.4s` | 支撑了第一版第三条判定（`c1052bb`，按键或滚动作为手势）。该版本随后被换成状态判定，这一行留作记录 |
| 7 | `com.apple.loginwindow` 的 `activationPolicy` 是 `.accessory`(1)，不是 `.regular`(0) | 本机 `NSWorkspace.runningApplications` 枚举 | 记录下来是因为它反过来支持了**拒绝**「别的常规应用从 Desktop 手里拿走前台即已读」：那条路要靠这个策略过滤锁屏，而抢焦点的常规应用它挡不住 |
| 8 | 「屏幕上有没有人可能在看」有三条公开、无 entitlement、不弹授权的读数：`CGDisplayIsAsleep`、`CGSessionCopyCurrentDictionary` 的 `CGSSessionScreenIsLocked`（未锁时该键**不存在**，不是 `false`）与 `kCGSSessionOnConsoleKey`，以及屏保的 `com.apple.screensaver.didstart` / `didstop` | 本机实测：`display asleep: false`、锁屏键缺席、`on console: 1` | 这三条是最终版第三条判定的守卫。前两条是**读得到的状态**，屏保那条是**可能收不到的通知**，因此后者被定位成补充而不是依赖 |

**结论：结束那一刻两种用户完全同形，这不是缺一个 API。** 坐着看它跑完的用户和提交完就走开的用户，最后做的都是提交那一下，等下去也不会长出区别。

先落地的一版（`c1052bb`）取「读的人接下来做的第一件事」——往 Desktop 里敲键或滚页。它安全，但答不了「坐着看完、什么都不做」，而那正是提问的人要的。**产品随后选择换掉它**：不再分辨两种用户，改问「那个答案此刻是不是摆在一块有人可能正在看的屏幕上」，并接受把窗口留在前台走开的人会丢掉一次通知。第四条（该会话带着已结束的 Turn 停在屏幕上之后被别的会话顶下去）两版都保留。规则、守卫、逐场景行为与代价见 [ADR 0012](../../adr/0012-read-state-is-answered-per-product-or-not-at-all.md)。

### 2026-08-19（第二次修订）— 终端会话也有了退出路径：问终端，不问 Claude Code

前一条记录的结论是「终端那一半没有真值源」。**那个结论错在问错了对象**，不在证据。Claude Code 至今没有任何已读概念（2.1.236 复查：`lastFocusedAt` / `hasUnread` / `seenAt` / `viewedAt` 全部 0 命中；进程里那个 `userPresence` 对象持有 `lastInteractionTime()` 与 `terminalFocus()`，但只活在内存里，不落盘、不发 hook）。会说话的是**那个会话的控制终端**。

本机实测（Ghostty，CLI `2.1.236`，2026-08-19）：

| 做了什么 | `/dev/ttys001` 访问时间 | `/dev/ttys004`（另一个窗口，隐藏） |
| --- | --- | --- |
| 起点 | `…652.114` | `…705.770` |
| Ghostty 已在前台，再激活一次 Ghostty | 不变 | 不变 |
| Ghostty → Chrome | **前进**（`…683.874`） | 不变 |
| Chrome → Ghostty | **前进**（`…685.954`） | 不变 |
| Ghostty → Chrome | **前进**（`…688.028`） | 不变 |
| 再走一整轮前台切换 | **两次都前进** | **0 次变化** |

同一段时间里，claude 正在渲染，**修改**时间每 0.5 秒动一次而访问时间纹丝不动——所以能用的是访问时间，修改时间会把每一帧都当成用户。

**轮次结束本身会不会产生输入**，是单独验的一条，因为它要是会，行就会在没人读的情况下自己撤掉。做法是自建一个 pty、把 `claude` 挂上去、从 master 喂一句提示，然后只看着：

```
slave=/dev/ttys004
…770.728  atime=…770.000  <-- MOVED   启动时的终端能力查询收到回复
…778.509  WROTE prompt
…778.509  atime=…778.509  <-- MOVED   我敲下的那句话
（此后 67 秒 0 次变化，其间屏幕上依次出现 Contemplating → OK → Ran 1 stop hook → Cooked for 2s）
```

轮次末尾那条 `OSC 777 notify;Claude Code;Claude is waiting for your input` 是纯输出，终端不回复，因此也不动它。

另起一个探针（`\x1b[?1004h` + raw 模式，读什么记什么）确认到达的字节就是焦点上报本身：`\x1b[O`（失去前台）与 `\x1b[I`（拿到前台）。焦点上报是 Claude Code 自己开的——`strings` 在发布二进制里查到 `?1004h` / `?1004l`，代码里每次离开 alternate screen 都写一次。

三件事因此同时成立，而它们合起来正好是 Desktop 那一半要费很大劲才凑出来的：

1. **按会话，不按应用。** 不在屏幕上的界面收不到任何东西，所以不存在「碰一下终端应用，所有行都消失」。
2. **是跃迁，不是状态。** 上面每一种都要有人在键盘前。因此终端这一半**不需要**第三条那种不要求用户做任何事的规则——ADR 0012 第三条是在没有按会话手势可用时的退让，这里不必退。
3. **全部公开接口。** `sysctl(KERN_PROC_PID)` → `e_tdev`，`devname_r`，`stat`。Swift 侧同样实测通过：pid 66115 → `/dev/ttys001`；自建 pty 上 `read` 让访问时间前进到读的那一刻。

没有覆盖的是「读完之后继续盯着那个 tab 一动不动」。终端上它比 Desktop 上便宜得多：接下来做的任何一件事都会撤掉那一行。产品因此选择**不救**这一种，而不是像第三条那样为了救它接受撤掉没人读过的行。

**这一条推翻的是本文件与 ADR 0012 里「终端会话不回答」的结论，不是它的任何一条论据。** 「哪个 tab 在用户眼前无从得知」至今成立，本实现一次也没有去回答它。规则、代价与被保留的禁令见 [ADR 0012](../../adr/0012-read-state-is-answered-per-product-or-not-at-all.md)。

### 2026-08-20 — hook 传输从端口换成 helper：`command` 有 `async`，`http` 没有（CC-021）

基线：Claude Code CLI `2.1.237`（schema 与 2.1.235 一致），macOS `Darwin 25.5.0`。执行范围：pty 驱动的交互式会话与 `-p`，注册一律通过临时 `--settings` 文件，**未改动 `~/.claude/settings.json`**；另有一个临时 launchd agent，用完即 `bootout`。结论已实施，见 [ADR 0013](../../adr/0013-claude-code-hooks-run-a-helper-not-a-port.md)。

先把 2026-08-18 那条记录留下的一个空白补上：`if` 不是通用条件，因此**没有**「应用没开就不跑这个 hook」这条便宜路。它的官方描述是 `Permission rule syntax to filter when this hook runs (e.g. "Bash(git *)")`，只匹配工具调用。

| # | 结果 | 依据 | 影响 |
| --- | --- | --- | --- |
| 1 | **`command` hook 的 schema 里有 `async`**（`If true, hook runs in background without blocking`），还有 `args`（exec form，直接 spawn 不过 shell）。`http` 的 schema 里两个都没有 | 从 2.1.237 读出五个 hook schema | 2026-08-18 第 1 条「`async` 不是配置键」只对 `http` 成立，对 `command` 不成立。这是换传输的入口 |
| 2 | **`command` hook 收到的 payload 与 `http` 逐字段相同**，含 `MessageDisplay` 的 `message_id` / `delta` / `final` / `index` / `turn_id` | 同一句提示、同一组 12 个事件，两种注册各跑一次 | reducer 的词表一个字都不用改 |
| 3 | **同一套 harness 的 A/B：`http` → 无人监听的端口打 9 行 `hook error`；`command` + always-`exit 0` 的 helper 打 0 行**，且 5 类事件全部送达 | pty 交互式会话，两次工具调用 | 这就是 CC-021 的修法。噪声不可能从注册里关掉，只能让 hook 不失败 |
| 4 | **`async: true` 会重排成对事件，并在 `-p` 下整个丢掉 `Stop`** | `-p` 实测：3 个 `PreToolUse`、3 个 `PostToolUse`、**0 个 `Stop`**；同一份注册改同步则 `Stop` 到达。交互式会话不丢（进程在后台 hook 跑完之后才退出） | 注册保持同步。保序与终态比每事件 6.3 ms 值钱 |
| 5 | **每事件 CPU**（15 次运行，注册数放大 10×/60× 后按事件数回归，基线为不注册任何 hook 的同一句提示）：`http` **1.2 ms**、`command` + 编译产物 **4.8 ms**、`command` + `sh`+`nc` **6.3 ms**；一个轮次约 17 个事件 | `getrusage(RUSAGE_CHILDREN)`，pty 交互式会话 | 一个轮次 21 ms → 107 ms。对照 `tech-design.md` 第 11 节记录的 Codex Python helper：**30 ms/事件**，一直如此 |
| 6 | helper 的四种状态都实测过：应用没开 **17 ms / rc 0 / 两条流为空**；socket 文件是陈留物 6.2 ms；应用在听 6.3 ms 且 30/30 送达；对端 accept 了却不读，`nc -w 1` 在 1 s 收口 | 直接跑脚本，30 次取平均 | `exit 0` 与 `-w` 各自扛一种失败 |

**否决掉的那条路，值得单独记下来，因为它前半段成立得很好。** 「一个常驻进程占住端口、应用启动时交接」：

| # | 结果 | 依据 |
| --- | --- | --- |
| 7 | launchd 的 socket activation **在没有任何进程运行时**占住端口；job 按需拉起并在 3 次/秒下复用（1 次拉起服务 31 个连接）；`SIGKILL` 之后端口仍被占住（t+0.0/0.2/0.4 s 三次 bind 全被拒），下一个 POST 照常 200 | 临时 LaunchAgent，`Sockets` + `launch_activate_socket` |
| 8 | **交接没有安全做法。** `SO_REUSEPORT` 下两个进程可同时持有同一端口，投递 6/6 给后 bind 的那个；但普通 bind 与 `SO_REUSEPORT` 互不兼容（两个方向都实测 `EADDRINUSE`），所以开启它等于允许任何本地进程后 bind 接管投递——**包括本应用正在运行时**。把「关着时有窗口」换成「一直开着」 | 本机 socket 实测 |
| 9 | **job 拉不起来时，失败形态比原病更重。** 程序不存在时 `connect()` **1 ms 成功**、`recv()` 永不返回（10 s 无响应，`last exit code = 78: EX_CONFIG`），于是每个事件都等满自己的 `timeout`；而本应用改不了用户文件里的 `timeout` | 同上 |
| 10 | **端口被占时 bootstrap 静默成功**：`rc 0`、job 注册上、`launchctl print` 与健康时**逐字节相同**（都报 `sockets = { 16 (no bytes to read) }`），抢占者照常收 POST。今天 `bind()` 失败是个干脆的信号，这个方案把它弄丢 | 同上 |

### 2026-08-20（同日续）— `SessionEnd` 重新考察后仍不注册：它比 watcher 晚

[ADR 0013](../../adr/0013-claude-code-hooks-run-a-helper-not-a-port.md) 让 `SessionEnd` 的排除理由作废（helper 不会往 stderr 写东西），于是按它自身的价值重测了一遍。基线 CLI `2.1.237`，pty 交互式会话，注册通过临时 `--settings`，**未改动 `~/.claude/settings.json`**。

| # | 结果 | 依据 | 影响 |
| --- | --- | --- | --- |
| 1 | **`SessionEnd` 比 sessions 目录 watcher 晚约 330 ms。** `~/.claude/sessions/<pid>.json` 在 **+15.09s / +15.08s** 被删除，`SessionEnd` 两次都在 **+15.41s** 到达 | 20 ms 采样文件是否存在，两次独立运行，退出动作为时间原点 | 支持注册它的唯一理由（「比 watcher 更早退休行」）不成立，方向还是反的 |
| 2 | **`/clear` 在同一个 pid 下换掉 session id**：`bf10d6dc…` → `cd9d3d18…`，进程与会话文件都不变；`SessionEnd(reason: "clear")` 带的是**旧** id，紧接着退出时还会再来一条 `reason: "other"` 带**新** id | 对照 `claude agents --json` 在 `/clear` 前后的输出 | 唯一看起来 watcher 够不着的场景其实够得着：旧 id 立刻离开列表，行照常消失。`resume` 同形 |
| 3 | `SessionEnd` 的 payload 是 `cwd, hook_event_name, prompt_id, reason, session_id, transcript_path`；**reason 词表为 `clear` / `resume` / `logout` / `prompt_input_exit` / `other`**，而 group 的 `matcher` 匹配的就是 reason | 从 2.1.237 读出事件构造与词表，并实测到 `clear` 与 `other` | 注册可以按 reason 挑，但只有一部分 reason 意味着「会话没了」——它不是名字暗示的那种简单信号 |
| 4 | 退出时 `SessionEnd` 的失败确实走 CLI 自己的 stderr（`SessionEnd hook [...] failed:` 直接 `process.stderr.write`），这一点与 2026-08-16 的记录一致 | 二进制里的 `executeSessionEndHooks` | 旧理由本身没有错，只是被 helper 消掉了 |

**结论：不注册。** 行消失靠的一直是「turn 的会话不在实时列表里就不画」，该机制现由 `aRowGoesWhenItsSessionLeavesTheListIncludingAfterClear` 钉住（含 `/clear` 一形）。

顺带查清一件本来担心的事：Claude Code 侧的 reducer 从不调用 `removeThreads`，`turnsByThreadID` 里死会话的条目会一直留到进程结束。**这不是泄漏，不必修**——turn 状态是纯内存的（`persist()` 只写 observation marker，`LegacyPersistedTurn` 是空结构，启动时 `turnsByThreadID = [:]` 从不恢复），正文早已按实时集合裁剪（`retainPreviews`），残留的只是每个见过的 session id 一条小结构。
