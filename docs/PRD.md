# Codex in Notch — 产品需求文档

| 字段 | 内容 |
| --- | --- |
| 文档状态 | Desktop Project 身份与未读终态自动移除已实现；真实版本矩阵仍待 Phase 0 验证 |
| 版本 | 0.11 |
| 日期 | 2026-08-15 |
| 目标版本 | V1 MVP |
| 目标平台 | macOS；带物理刘海与无刘海显示器 |

## 1. 产品定义

Codex in Notch 是 Codex Desktop 当前处理轮次的实时汇总中心。它把正在运行、正在等待人工处理，以及已经结束但用户尚未在 Codex Desktop 中阅读的轮次集中显示在屏幕顶部。

产品不是历史会话浏览器，也不管理 Codex 任务。每一行代表一个可以通过同一 `threadId` 返回 Codex Desktop 的根会话；行的状态由该会话当前或最近一个仍在监视生命周期内的处理轮次驱动。

带刘海屏幕的收起态与物理刘海融合；无刘海屏幕使用内容驱动宽度的纯黑紧凑组件。两种形态悬停后共享同一个展开组件。

## 2. 目标

V1 必须做到：

1. 实时呈现当前 Codex Desktop 账户下所有 Project 与 `Chats` 中需要监视的处理轮次。**监视范围严格限定为本次 Codex in Notch 启动之后开始的 Turn**：应用启动前已在运行、已完成未读或正在等待审批的会话一律不纳入，直到它们产生下一个 lifecycle 事件为止（见第 3 节非目标）。
2. 会话状态只使用 Running、Input needed、Approval needed 和 Completed 四类。
3. 让用户点击任意会话行后进入 Codex Desktop 中完全相同的会话。
4. Running 与其他状态使用同一状态名称机制显示 `Running`；同时为每个未完成轮次显示处理时间，并在收起态右端显示全局最长运行时间（见 8.2）。
5. 显示当前 Desktop 账户的主额度窗口剩余比例；无法可靠读取时明确显示不可用。
6. 在应用重启、Codex 重启、账户切换和漏失事件后不展示任何缓存会话；列表从空开始重新累积。
7. 默认提供有用的当前内容预览，同时允许用户全局隐藏所有预览。
8. 保持本地优先、低干扰、低资源占用，不申请辅助功能或屏幕录制权限。

## 3. 非目标

V1 不包含：

- 发送新输入、批准权限、回答 Codex 提问、取消、归档或删除会话。
- 把 CLI、IDE 或子智能体作为独立列表来源。只有已经成为可在 Desktop 中精确导航的同一根会话时，才可能被纳入。
- 历史会话搜索、最近 N 条或固定时间窗列表。
- **启动时与 Codex Desktop 做任何形式的现状同步（cold-start sync）。** 应用启动前的所有会话状态——正在运行、已完成未读、正在等待审批——一律无视。理由是能力边界而非取舍：针对 Codex CLI `0.148.0-alpha.9` 在真实运行中的 Turn 上实测，独立 App Server 的 `thread/loaded/list` 为空、所有 Thread 恒为 `notLoaded`、从不出现 `inProgress` Turn，正在运行的 Turn 在持久化数据中甚至被记为 `interrupted`。没有任何受支持的读取能回答“Codex Desktop 此刻在做什么”，因此任何启动列表都只能是猜测。相关取舍与实测记录见 [`system-architecture.md` §2.1](system-architecture.md#21-启动边界不做现状同步)。
- 通过窗口焦点、路径、标题、时间接近度或 GUI 自动化猜测会话身份、Project、已读状态或导航目标。
- 展示原始推理、工具参数、命令输出、文件差异、敏感路径或批准理由。
- 将正文预览、会话列表快照或旧账户额度持久化。
- 在 Notch 的被动状态中提供修复、更新或启动 Codex 的按钮。
- 用模型计算时间、活跃执行时间或会话年龄替代 8.2 定义的墙钟处理时间；也不为无法确定开始时间的轮次推算时长。

## 4. 核心对象与监视范围

### 4.1 会话与处理轮次

- 一行永远代表一个可导航根会话（Thread）。
- 一个处理轮次（Turn）从用户提交输入时开始，在 Codex 报告任意执行结束信号时统一进入 Completed。
- 同一 Thread 的多个 Turn 不产生多行；新 Turn 替换该行的驱动轮次。
- 子智能体不显示为独立行。

### 4.2 监视生命周期

一个处理轮次在产品中的可见期为：

1. 用户提交输入后立即进入列表。
2. 尚未进入终态时始终保留。
3. 进入终态后，只要 Codex Desktop 仍将对应会话标记为未读，且会话未归档、未删除、仍可导航，就继续保留。
4. Desktop 标记已读、会话被归档、删除或失去可导航性时，立即从列表移除。

Codex in Notch 不主动修改已读状态。点击会话成功后，组件收起并等待 Codex Desktop 发出真实已读变化；Notch 点击本身不等于已读。

当前公开接口不提供 Desktop 未读成员关系。经产品批准，实现可使用 [`non-public-codex-integration-features.md`](non-public-codex-integration-features.md) 登记的严格只读适配器；只有当前 Desktop 主状态文件成功解析出的未读集合可以成为移除依据。主文件缺失、损坏、权限异常或 schema 不兼容时必须保守保留尚未隐藏的终态会话，不得把解析失败解释为已读。

### 4.3 范围与 Project

- 监视当前 Codex Desktop 账户下所有 Project 与 `Chats`，不跟随侧边栏当前选择。
- Project 必须是 Codex Desktop 左侧边栏中用户创建的 Project 实体；它可以对应一个或多个仓库。
- 无 Project 归属的会话显示 `Chats`。
- 禁止从 `cwd`、Git 根目录或路径最后一级推导 Project。
- 当前官方公开支持接口不提供 Desktop Project 身份；经产品批准，可使用 [`non-public-codex-integration-features.md`](non-public-codex-integration-features.md) 登记的严格只读私有适配器。只有 Desktop 的 `projectless-thread-ids` 明确命中时才显示 `Chats`；缺失或损坏必须显示 `Project unavailable` 并 fail closed。

## 5. 首次安装引导

首次安装使用独立 macOS 窗口完成三步引导：

1. **Welcome**：说明产品监视实时轮次、突出人工处理请求并返回相同 Codex 会话的价值。
2. **Connect to Codex**：准确列出需要读取的本地元数据，并在安装或注册任何用户级集成前取得用户确认。
3. **Ready**：确认实时状态、Project、未读成员关系、精确导航与主额度窗口能力可用，并说明当前内容预览默认开启。

设置必须是显式、可逆、由用户确认的流程。应用不得静默修改 Codex 配置、绕过 Codex 的信任机制或自动启动 Codex Desktop。

首次引导中的 `Set Up Integration` 与 Settings 中的 `Codex integration` 总开关都把本应用需要的六种 lifecycle event 定义作为一个不可拆分的产品能力管理。开启时安装或修复完整集合；关闭时只移除 Codex in Notch 管理的定义并留在 Settings，不重新进入首次引导。Codex 底层仍按事件类型显示六个定义，首次安装或定义变化后仍必须由用户在 `/hooks` 中审核信任。

## 6. 状态模型

### 6.1 行级状态

| 状态 | 含义 | 行尾显示 |
| --- | --- | --- |
| `Input needed` | Codex 等待用户回答 | 橙色状态；悬停时显示名称胶囊 |
| `Approval needed` | Codex 等待权限决定 | 橙色状态；悬停时显示名称胶囊 |
| `Running` | 当前轮次正在自动处理 | 蓝色 `Running` 状态名称胶囊，始终显示 |
| `Completed` | 当前轮次已经结束但仍未读 | 绿色状态 |

不存在行级 `Idle` 或行级 `Disconnected`。

`Approval needed` 只在当前精确 Turn 存在一个仍未关闭的审批区间时成立，且必须能被同一 `tool_use_id` 的结束事件关闭：专用审批工具自己构成该区间；普通工具（如 Bash 命令）由 `PermissionRequest` 指名、借用该工具仍打开的调用 id 构成。孤立的 `PermissionRequest` 仍不足以证明用户需要操作，因为自动审查可能立即放行。`Stop` 或 App Server 的 `completed`、`failed`、`interrupted` 都是同一种产品信号：当前 Turn 已经结束，因此统一进入 Completed。

### 6.2 顶部汇总优先级

汇总顺序为：

1. Input needed
2. Approval needed
3. Running
4. Completed

健康且列表为空时，收起态显示 Idle。

列表使用同一优先级排序；同优先级按最近可信更新时间降序。状态变化立即重排，但用户正在滚动或悬停列表时不得强制跳动当前视口，应显示轻量的顺序更新提示。

### 6.3 全局可用性状态

| 场景 | 列表 | 展开文案 | 是否提供操作 |
| --- | --- | --- | --- |
| 健康但无监视轮次 | 空 | `No active turns` | 否 |
| 首次尚未集成 | 空 | `Set up integration` | 引导流程中处理 |
| App Server 已开始连接、会话快照尚未返回 | 空 | `Connecting to Codex`，最长 5 秒 | 否 |
| Codex 版本过旧 | 空 | `Update Codex` | 否 |
| Codex 版本未经验证 | 空 | `Codex version unsupported` | 否 |
| App Server 无响应、启动失败或连接断开 | 清空 | `Codex disconnected` | 否 |

Disconnected 是全局集成健康问题，不能用于单会话。进入 Disconnected 时必须清空列表，不显示最后一次可信快照。应用不自动启动 Codex；用户在 Codex 或系统中自行完成相应操作。

## 7. 当前内容预览与隐私

预览只使用 Codex 已向用户公开的内容：

| 状态 | 预览来源 |
| --- | --- |
| Input needed | 当前向用户提出的问题 |
| Approval needed | 固定通用文案 `Approval requested`；不显示命令、路径或理由 |
| Running | 最新公开进度；没有时回退到本轮用户输入 |
| Completed | 最终回答开头 |

所有预览仅在内存中存在，规范化为单行并在 UI 中 Alpha 渐隐，不显示省略号。

设置提供全局开关 `Show current content previews`，默认开启。关闭后：

- 保留 Project、Desktop 标题与状态。
- 完全移除预览正文，但保持会话行高度与列表几何不变。
- 若 Desktop 尚无标题，禁止再用用户输入作为标题回退，显示 `Untitled`。

单独的预览读取失败只隐藏对应预览，不把会话或全局状态改为 Disconnected。

## 8. 标题、额度与未来功能

### 8.1 标题

优先使用 Codex Desktop 显示的会话标题。Desktop 尚无标题时，在预览开启的前提下使用本轮用户输入的安全单行截断；仍不可用或预览已关闭时显示 `Untitled`。

### 8.2 处理时间

处理时间已经从"未来考虑"进入产品范围。本节回答此前列为前置条件的五个问题：权威时间语义、等待与睡眠是否计入、可靠数据来源、无障碍文案和持续刷新的资源成本。

**计时对象与起点**：每个处理轮次一个计时器，起点是该轮次的用户提交时刻。同一 Thread 的下一个 Turn 重新从零开始计时，Turn 内部的继续执行不重置。

**终点**：只有 Completed 停止计时。Input needed 和 Approval needed 继续计时——用户等待审批的这段时间正是最需要被看见的部分，因此不暂停。

**墙钟语义**：显示值始终按 `当前时间 - 开始时间` 重新计算，不做累加。等待人工处理、设备睡眠和应用未刷新的时间因此自然计入，与 CONTEXT.md 中"处理时间"的定义一致。

**展示位置**：展开列表中每一行显示自己的处理时间；未完成行以计时文本本身作为状态标记（等待人工的行为琥珀色 Medium，Running 为暗色 Light），Completed 行不显示计时，只保留绿色状态点。收起态在刘海右侧显示全局最长运行时间，即所有未完成轮次中开始最早的那个；没有未完成轮次时该区域整体消失，不留空白翼。展开态不重复显示该汇总值。

**未知起点**：无法确定开始时间的轮次不显示任何推测数值，退回状态点。

**无障碍**：朗读文案使用时长读法而非时钟读法（`5 分 12 秒`，不是 `5:12`）。会话行朗读为"项目，标题，状态，已运行 X"；面板整体朗读补充"最长已运行 X"。

**刷新成本**：只有存在未完成轮次时才存在每秒刷新；全部完成或列表为空时计时任务完全停止，不做空转唤醒。

**已知限制**：应用重启不恢复启动前的轮次（见 ADR 0006），因此重启后重新观察到的轮次从其第一个重新观察到的事件开始计时，而不是真实提交时刻。此处宁可少算也不伪造起点。

### 8.3 主额度窗口

- 单一额度圆环代表当前 Codex Desktop 账户标记为 primary 的 rate-limit window，不把它称作通用 token 余额。
- 账户切换后旧值立即失效。
- 初次读取失败后静默重试 5 秒；仍失败则立即显示灰色不可用圆环，不保留陈旧值。
- 额度失败只降级圆环，不清空会话，也不影响真实状态与导航。

## 9. Notch 与展开列表

### 9.1 收起态

- 带刘海屏幕与真实菜单栏/刘海等高，只在左侧显示 `8 × 8` 汇总圆点、右侧显示 `18 × 18` 额度圆环。
- 无刘海屏幕使用内容驱动宽度：圆点、条件文本、额度圆环和固定边距；不得为不存在的刘海预留空白。
- 无刘海 Running 与其他状态一样显示完整英文状态名，即 `Running`。

### 9.2 展开态

- 基准宽度为 `520`；若物理中央不可显示区更宽，继续增宽以保证所有状态名完整可见。
- 顶部汇总区始终等于目标显示器菜单栏高度；参考设计为 `46`。展开时顶部只横向扩张，不增加高度。
- 会话内容区固定高 `256`；参考总高度为 `302`。
- 内边距后列表可见宽度为 `472`，最多同时显示三个 `80` 高会话行；更多会话通过垂直滚动查看。
- 健康空列表和所有全局可用性状态使用 `520 × 94` 的薄展开层。
- 面板始终贴住屏幕上沿并锁定水平中心；不得变成独立悬浮卡片。

### 9.3 会话行

- 左侧依次为 Project、标题、当前内容预览。
- Running 右侧始终显示状态圆点和 `Running` 状态名称胶囊。
- 非 Running 默认显示状态圆点，悬停时扩展为状态名称胶囊。
- 内容接近尾部控件时连续 Alpha 渐隐；不换行、不增加行高、不显示可见省略号。
- 行可点击，但不提供批准、输入、取消或其他 Codex 操作。

## 10. 导航

点击成功的定义是：激活 Codex Desktop，并让其显示传入 `threadId` 对应的完全相同会话。

- 直接导航是 V1 发布门槛，不允许以“只打开 Codex 首页”作为成功 fallback。
- 成功后面板收起；等待 Desktop 真实已读事件再移除该行。
- 失败时面板保持展开、行保持可见并提供非破坏性反馈。
- 点击前重新确认会话仍存在、未归档且可导航；竞态失败后触发集合校正。
- 不猜测 URL，不写私有 IPC，不使用辅助功能或 GUI 自动化。

## 11. 设置

V1 设置窗口只包含已经确认的三组能力：

1. **Display**：选择组件显示在哪个已连接显示器；选择跨启动保留，显示器临时断开时回退到可用屏幕。
2. **Codex integration**：显示连接与兼容状态，提供一个总开关同时启停全部六种必需 lifecycle event 定义；提供重新检测。关闭只移除本应用管理的定义并保留用户其他 Hooks；重新开启会安装或修复完整集合。
3. **Privacy**：`Show current content previews` 全局开关。

设置只影响 Codex in Notch。Notch 中的 `No active turns`、`Update Codex`、`Codex version unsupported` 和 `Codex disconnected` 不提供操作。

## 12. 可靠性与降级

- 应用启动时列表为空，先显示 Connecting；App Server 成功返回一次只读校验后进入 Ready 并显示 Idle。该校验只用于区分 Ready 与 Disconnected，**不得据此产出任何会话行**。只有 App Server 无响应、启动失败或连接断开才显示 Disconnected。
- 启动 cutoff 之前的 Hook、Stop、SessionEnd 或其他 lifecycle 信号不得创建、恢复、终止或修改当前 Turn；当前状态只能来自启动后的实时事件。App Server 数据只能为已由实时事件建立身份的会话补充元数据，永远不能独立创建会话。
- 用户在 Desktop 中中断后继续同一响应时，即使恢复后的执行使用新的 Turn ID 且没有新的 UserPromptSubmit，启动后携带该新身份的实时 Hook 也必须让同一会话继续保持 Running，并让最终 Stop 正确进入 Completed；旧 Turn 的迟到事件不得覆盖恢复后的 Turn。
- 首次验证过 Hook 后，应用自身重启不得要求再次产生事件才能恢复连接；恢复必须同时确认当前 Codex Desktop 正在运行。
- 六种必需定义缺少、重复或 matcher/handler/timeout 被改变时不得显示为已连接；总开关显示 Off，并明确进入可由用户重新开启修复的状态。
- 实时事件负责即时变化；`thread/list` 等集合校正必须在后台合并，不能阻塞 Idle、Running、Input 或 Approval 的发布。重连、唤醒和低频集合校正负责移除已读、归档、删除或漏失对象。
- 启动和常规刷新不得逐会话读取详情；状态快照失败时保留该 Turn 的最后一个可信四态值，不能据此制造新的会话状态。
- 单次 App Server 请求超时保留连接与最近可信状态；若其间没有任何有效响应且连续请求都超时，应重建只读 App Server 传输，再在后续轮询恢复校正。
- `thread/closed` 不等于删除，不可据此移除。
- 无法识别的新枚举不触发状态流转，并写入脱敏诊断；不能造成崩溃。
- 只有实时会话状态整体不可靠时才进入 Disconnected。
- Project、未读成员关系与精确导航不得使用近似值降级。
- Desktop 未读私有状态只允许只读消费；目录监听失败时由现有轮询校正，主文件解析失败时不得根据备份、空集合或 last-known-good 新增移除决定。

## 13. 发布门槛

Phase 0 必须证明受支持的集成路径能够可靠取得：

1. Desktop 可导航根会话及稳定 `threadId`。
2. 活动 Turn 与 Input/Approval/Running/终态事件。
3. Desktop 未读、归档、删除和 Project 身份。
4. 当前账户 primary rate-limit window 与账户切换。
5. `threadId → Desktop 同一会话` 的受支持导航动作。

Project、未读成员关系或精确导航任一无法满足时，V1 不得用 cwd、固定时间、焦点或首页 fallback 伪装完成。

## 14. 验收标准

1. 用户提交输入后一秒内出现对应会话行；同一 Thread 的后续 Turn 不产生重复行。
2. Input needed、Approval needed、Running、Completed 四态及优先级正确；专用审批工具与普通工具（如 Bash 命令）两种审批形态都必须进入 Approval needed，孤立的 PermissionRequest 不误报，任意执行结束信号都使当前 Turn 直接进入 Completed。
3. 活动轮次始终显示；终态轮次在 Desktop 已读、归档或删除后自动移除。
4. 列表覆盖当前账户所有 Project 与 `Chats`，Project 名称与 Desktop 完全一致。
5. 应用重启时不显示缓存行，也不恢复任何启动前的会话；列表从空开始，只累积启动后产生 lifecycle 事件的 Turn。
6. 处理时间按 8.2 计时：未完成行逐秒推进，转入 Approval needed 或 Input needed 后继续计时不暂停，Completed 后停止并让位给状态点；收起态右端显示所有未完成轮次中的最长值，全部完成后该区域消失；朗读使用时长读法；无未完成轮次时不存在每秒刷新。
7. 点击任意行进入同一 `threadId` 会话；打开首页不算通过。
8. 主额度窗口切换和不可用行为正确；额度失败不影响会话列表。
9. 关闭预览后无正文泄露，缺失标题显示 `Untitled`，行高和面板几何不变。
10. Disconnected 清空列表；No active turns 与四类被动状态不含操作按钮。
11. 展开基准为 `520 × 302`，顶部参考高 `46` 且只横向扩张；状态名不被物理刘海遮挡。
12. 三行以上可以垂直滚动，重排不强制打断用户当前滚动位置。
13. 首次引导在更改集成前明确说明范围并取得用户确认；Settings 中一个总开关原子启停六种必需定义，部分安装失败关闭并可修复，关闭不影响用户其他 Hooks。
14. Figma 与实现中的所有产品字体统一使用 SF Pro。

## 15. 设计来源

- Figma 文件：[Codex in Notch — V1](https://www.figma.com/design/B9qIi46zhdjbQYbjZo3AnM/Codex-in-Notch-%E2%80%94-V1)
- `06 — Notch Core`：收起与共享展开核心几何。
- `07 — Integration States`：隐私、额度降级、空与集成状态。
- `08 — Onboarding`：首次安装三步流程。
- `09 — Settings`：预览开启/关闭与集成管理。

## 16. 术语与架构决策

- 统一术语见 [`CONTEXT.md`](../CONTEXT.md)。
- 范围、未读生命周期和 Project 身份见 [`docs/adr`](adr/)。
- 所有依赖未公开或未承诺兼容的 Codex 实现细节及其版本风险见 [`non-public-codex-integration-features.md`](non-public-codex-integration-features.md)。官方 Hooks、App Server 和 deep link 不因接口类型不同而进入该清单。
