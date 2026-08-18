# Codex in Notch — Figma 设计规范

| 字段 | 内容 |
| --- | --- |
| 文档状态 | V1 SwiftUI 四态契约已同步；设置窗口已按 macOS 26 重做；系统状态收敛为 `Disconnected` / `Connected` 两个，在场与宽度已实现、画法待 [#35](https://github.com/soondubu137/codex-in-notch/issues/35)；外部 Figma 的旧状态变体待清理 |
| 版本 | 1.1 |
| 日期 | 2026-08-17 |
| 文件 | [Codex in Notch — V1](https://www.figma.com/design/B9qIi46zhdjbQYbjZo3AnM/Codex-in-Notch-%E2%80%94-V1) |

## 1. 设计原则

1. 顶部组件是当前处理轮次的实时汇总中心，不是历史入口。
2. 带刘海与无刘海的收起几何不同，但展开后共享同一内容结构。
3. 展开组件始终贴住屏幕上沿、锁定水平中心；顶部汇总区只横向扩张。
4. 状态、额度、Project、标题、当前内容和处理时间都来自真实 Codex Desktop 语义，不使用近似值。
5. 无法可靠取得的数据明确降级，不用 Mock、缓存或近似值填补。
6. 所有 Figma 文字统一使用 SF Pro；不得继续引入 Inter、SF Compact 或其他产品字体。

## 2. Figma 文件结构

| Page | 作用 | 关键节点 |
| --- | --- | --- |
| `00 — Cover & Notes` | 文件说明 | — |
| `01 — Getting Started` | 使用说明 | — |
| `02 — Foundations` | 颜色、布局、字体、Motion、响应式圆角 | `99:38`, `99:39`, `287:2` |
| `03 — Status Components` | Status Dot、Readout、Usage Ring、Badge | `108:18`, `153:202`, `154:24` |
| `04 — Session Row` | 会话行、列表和状态名称胶囊 | `112:28`, `140:201`, `198:72` |
| `05 — Panel` | 收起与展开 Panel 变体 | `115:82`, `300:253`, `300:263` |
| `06 — Notch Core` | 核心产品状态与不同菜单栏高度参考 | `118:73`, `185:292`, `304:630`, `304:641` |
| `07 — Integration States` | 隐私、局部降级；薄层状态已退休或并入两个系统状态，见 §6.6 | `227:3`, `307:30` |
| `08 — Onboarding` | 首次安装三步流程 | `232:95` |
| `09 — Settings` | macOS 26 设置窗口（浅色／深色）、集成管理、预览隐私与 `Session list` 分组 | `609:2`（现行）；`233:3`、`591:2`（v1 参考） |
| `10 — Double Apps` | 双产品（Codex + Claude Code）设计；`08 — Presence` 定义收起态的在场规则 | `540:2`、`624:1560` |

本文描述单产品契约。同时监视 Codex 与 Claude Code 时的设计见 [`dual-agent-design.md`](dual-agent-design.md)，其中两处已取代本文：设置齿轮的位置（见 4.5，现为展开态顶栏右上角，单产品同样生效）与双产品页脚的额度构成（见 4.3）。其余部分不受影响。

当前 SwiftUI 与本文只承认四个会话状态变体：Running、Input needed、Approval needed、Completed。外部 Figma 中超过这四类的历史会话状态变体不再属于产品契约，需在下一次 Figma 同步中删除；在完成前以本文和代码为准。`Usage Ring` 的 7 个合法变体、`Usage Indicator` 的 4 个合法变体及 `Panel` 的 7 个合法变体不受本次状态收敛影响。

## 3. Foundations

### 3.1 Typography

Figma 文件中的本地 Text Styles 与所有已有/新增文字层均使用 `SF Pro`：

| 用途 | 字重 | 基准字号 / 行高 |
| --- | --- | --- |
| 大标题 | Bold | `24–32 / 29–38` |
| Panel/窗口标题 | Semibold | `13–15 / 17–20` |
| 会话标题 | Medium | `13 / 17` |
| 正文与预览 | Regular | `12–14 / 16–20` |
| Project / 辅助信息 | Regular | `11 / 14–15` |
| 状态标签 | Semibold | `13 / 16` |

字体不存在时必须先安装 SF Pro，再编辑文件；不得以相似字体永久替代。当前设计环境已经提供所需 Regular、Medium、Semibold 和 Bold 字重。

**已知例外：`609:2` 上的 `closing note` 两条文字（浅色 `665:3`／`665:5`，深色 `667:3`／`667:5`）当前是 Inter Regular。** 通过 MCP 编辑时，`listAvailableFontsAsync()` 会列出 SF Pro 且 `loadFontAsync` 不报错，但字形度量取不到：`characters` 写进去了，节点宽度与渲染却停在旧值——同一个按钮实测 SF Pro 下仍是 `49 pt` 的 `Recheck`，换成 Inter 立刻重排为 `115 pt` 的 `Quit Codex in Notch`。两害相权：留在 SF Pro，板上会把一句**不存在的文案**画给每一个看它的人；换成 Inter，板读得对而字体错一处。选后者，并记在验证清单里，等在装有 SF Pro 的 Figma 桌面端重新键入。这条例外只覆盖这四个节点，不放宽 §1.6 的规则。

### 3.2 Color

- Panel 背景：纯黑或现有 `surface/notch` / `surface/panel` token。
- Primary text：白色（暗色 Panel）或近黑色（原生窗口）。
- Secondary text：中性灰。
- Running：蓝色。
- Input/Approval：橙色。
- Completed：绿色。
- Disconnected/版本不可用：紫色。

以上 token 服务于 Notch 组件。**原生窗口（设置、Onboarding）另有一套集合 `Color / macOS Window`**，它是本文件里唯一带 `Light` / `Dark` 两个 mode 的集合，承载 macOS 窗口自己的语义：`window/bg`、`window/titlebar`、`window/stroke`、`group/bg`、`group/stroke`、`separator`、`text/primary｜secondary｜tertiary`、`accent`、`control/bg`、`control/stroke`、`switch/off-track`、`knob`、`status/green`、`product/codex`、`product/claude`。原生窗口的浅色与深色必须由这一套集合的 mode 切换产生，不得复制成两批硬编码颜色。

### 3.3 Layout tokens

| 项目 | 值 |
| --- | --- |
| Notch compact | `348 × 46` 参考基线 |
| No-notch `Running` compact | `168 × 46` 参考基线；`24` 高菜单栏时为 `168 × 24` |
| No-notch Input needed compact | `200 × 46` 参考基线 |
| Shared expanded | `520 × 302` 参考基线 |
| No-notch expanded / `24` 高菜单栏 | `520 × 280` 参考基线 |
| Expanded header | 宽 `520`、高为真实 `menuBarHeight`；`46` 高时内容宽 `496` |
| Expanded content region | `256` 高 |
| Session viewport | `508 × 240` |
| Session row | `508 × 80` |
| Thin expanded state | `520 × 94` |
| Horizontal Panel padding | `12` |
| Session row gutter / padding | `6` + `6`；见下 |
| Status dot | `8 × 8` |
| Usage ring | `18 × 18`, stroke `2` |
| Row badge | `24` 高 |

**会话行比面板其余部分宽两个 `6`。** 行块从面板边缘缩进 `6` 而不是 `12`，好让 hover 的填充不撞到边；行自己再补回 `6`，于是行内文字仍然落在 `12`——与 header 里的状态矩阵、页脚里的额度规则同一条边距上。两个数因此是互相定义的（`PanelMetrics.sessionRowGutter` 与 `sessionRowPadding = expandedHorizontalPadding − sessionRowGutter`），不是两个各写死的 `6`；`aRowsTextLandsOnTheSameMarginAsTheRestOfThePanel` 锁定这条关系。行块 `520 − 6 − 6 = 508`，内容盒 `520 − 12 − 12 = 496`。

目标显示器菜单栏高度不是 `46` 时，顶部汇总区使用真实菜单栏高度，总高度为 `menuBarHeight + 256`。例如无刘海 `24` 高菜单栏的展开参考尺寸为 `520 × 280`。带物理刘海时，宽度还要根据中央不可显示区继续增加，确保 `Approval needed`、`Input needed`、`Codex version unsupported` 等最长状态名完整位于可显示区域。

Panel 外轮廓的基准圆角为 `10`。带物理刘海时始终使用该值；无刘海屏使用以下公式：

```text
cornerRadius = min(10, 10 × max(0, menuBarHeight) / 38)
```

因此菜单栏低于原生 MacBook Notch 基准 `38` 时，圆角约为菜单栏高度的 `26.32%`；达到或超过 `38` 时保持 `10`。Figma 的响应式示例为 `38 → 10`（`287:8`）、`24 → 6.316`（`287:12`）与 `19 → 5`（`287:16`），用于避免矮组件呈现过度胶囊化。

### 3.4 面板本体、窗口与刘海对齐

`PanelContour` 只有最上沿一条边铺满它拿到的矩形，随后向内收成竖直边：直边落在矩形内缩一个圆角半径的位置，两侧各留出一个「肩」，画回菜单栏的那道凹弧就在肩里。

因此本文件所有参考尺寸描述的都是**面板本体**——真正画出来的那块黑色——而承载它的 `NSPanel` 窗口左右各宽一个圆角半径（`OverlayPanelLayout.frame(on:panelSize:surfaceShoulder:trailingAnchor:)` 的 `surfaceShoulder`）。按本体尺寸开窗口就是错的：收起态的右缘会落进刘海里一个半径，底部圆角再吃掉一个半径，看上去像刘海右下角被咬掉一块。

带刘海的收起面板**以缺口的右缘为锚**：`NSScreen.auxiliaryTopRightArea.minX` 加尾翼宽度，不再由屏幕中心加位移推导。旧写法只有在缺口正好居中、且本体宽度不取整时才与之等价；取整的余量现在落在前导翼上——那里是留白，吃得下半个点，与硬件对齐的右缘吃不下。展开态与无刘海形态仍然锁定屏幕水平中心。

内容（含 `24` 水平内距）在本体内排布，所以内距是从黑色边缘量起的；指针响应区域同样只覆盖本体，肩部把点击让给它盖住的菜单栏项。

## 4. 核心组件

### 4.1 Status Dot

`Status Dot` 包含两类互不混用的状态：会话级 Running、Input Needed、Approval Needed、Completed，以及系统级 Idle、Connecting、Disconnected、Update Codex、Unsupported Version、Setup Required。

- Idle（旧名）只用于健康空集合的汇总，现已并入 `Connected`；变体保留见下一条。
- Disconnected 不用于会话行。
- **系统级取值收敛为两个**：`Disconnected` 与 `Connected`（§6.4）。`Idle` 并入 `Connected`，`Connecting`、`Update Codex`、`Unsupported Version`、`Setup Required` 退出收起态（§6.6），只在展开面板与设置中出现，组件变体因此保留。

### 4.2 Status Readout

Compact 与 Expanded 两个 Context 都提供完整状态文本。Expanded 组内圆点—名称间距为 `12`；状态名称不得被物理刘海遮挡。

### 4.3 Usage Ring 与 Indicator

- `100%` 时为全亮环；剩余量降低时，暗色弧从十二点方向逆时针增长，亮色弧同步逆时针缩短，非满环两端为圆头。
- 亮色整环与暗色弧共用 `9pt` 中心线半径和 `2pt` 居中描边；暗色弧不得向内缩小。
- `0%` 为全暗环；Unavailable 同样只显示完整轨道色，但其数值文案为 `--`，不得与真实 `0%` 混淆。
- `> 50%` 白色，`15%–50%` 橙色，`< 15%` 红色。
- Unavailable 为灰色圆环，不显示伪造百分比。
- Expanded leading value 始终为剩余百分比；Running 不替换额度文本。

Figma `Usage Ring` 组件集（`108:18`）包含 `100`、`72`、`50`、`32`、`10`、`0` 与 `Unavailable` 七个变体；`Usage Indicator`（`153:202`）包含 Healthy、Warning、Critical 与 Unavailable 四个变体。

### 4.4 Session Row

每行左侧依次显示 Project、标题、当前内容；右侧为状态控件。

- Running 始终显示蓝色 `Running` 状态名称 Badge。
- 非 Running 默认显示圆点，Hover 显示状态名称 Badge。
- 左侧文字接近尾部控件时 Alpha 渐隐，不换行、不显示省略号。
- 最多三行可见；更多行使用垂直滚动。
- 隐私关闭时移除预览文字，但保持 `80` 行高和 Panel 几何；标题与 Project 仍保留。

### 4.5 Panel

Panel 组件集保留 Notch Compact、No Notch Compact 和 Expanded。Expanded 的正式参考尺寸已经从 `444 × 310` 修正为 `520 × 302`：

- header 高度从 `54` 修正为 `46`。
- 展开时 header 只横向扩张。
- 内容区使用 `256`，三行视口使用 `240`，底部保留 `15`。
- 现有 `06 — Notch Core` Running Desktop 画板已按 `1512` 屏幕重新居中到 `x = 496`。

Figma `Panel` 组件集（`115:82`）使用 `Mode`、`Content` 与 `Menu Bar` 属性，共七个合法变体。除 `46` 高参考外，还包含无刘海 `24` 高菜单栏的 Compact Running（`300:253`，`168 × 24`，圆角 `6.316`）和 Expanded（`300:263`，`520 × 280`，圆角 `6.316`）。所有变体均使用与 SwiftUI `PanelContour` 相同的外轮廓，而不是普通 RoundedRectangle。

### 4.6 处理时间

PRD 8.2 与技术设计第 12 节已明确权威时间语义、等待/睡眠行为、无障碍文案与刷新成本，处理时间因此进入产品范围。它不是独立的 Runtime Badge：未完成会话行以计时文本本身作为状态标记，一行永远只有一个标记——等待人工的行为琥珀色 Medium，Running 为暗色 Light，Completed 行不显示计时，只保留绿色状态点。

收起态在刘海右侧显示全局最长运行时间，与左翼状态读数构成两翼；没有未完成轮次时右翼整体消失，避免渲染出第二个假刘海。展开态不重复该汇总值。计时文本使用等宽数字，因此右翼宽度只在进位时变化。

**前导翼的处置按形态分开**（§6.4）：没有任何智能体已连接时，有刘海形态连前导翼一起去掉、只剩 `200` 遮挡；无刘海形态保留前导翼，画一个灰色矩阵加 `Disconnected`——菜单栏里消失的控件会带走自己的位置，因此这里保住位置比省掉一条翼更重要。

收起态宽度不是设计常量：实现按真实渲染文本测量后向上取整，宽度是布局的结果而不是谁定下的数值。因此 **Figma 变体中的计时与状态文字层必须 hug contents，不得写死宽度**。写死是唯一需要记住的失败模式——上一次同步把计时 TEXT 固定为 `34`（自然宽约 `28.6`），刘海计时变体因此整体偏宽 `5.4`；无刘海一对同样因固定文本宽度偏出十余 pt。

可以直接对照的固定值只有一处：刘海形态左翼 = `24` padding + `16.6` 状态矩阵 + `8` clearance = `48.6`，加 `200` 遮挡后收起态总宽为 `249`。计时文本从 `x = 256.6` 开始（`48.6 + 200 + 8`），宽度随文本自身变化；无刘海形态在 `24` 高菜单栏上触及 `120` 宽度下限。这些关系由 `compactGeometryComposesTheNotchWings` 锁定，其余宽度不写入契约。

> 本段此前写的是 `18.4` / `50.4` / `251`，那是矩阵改用 `16.6`（`13 × 1.2778`，见 `PanelMetrics.statusMatrixSize`）之前的数字，代码一直画的是 `249`。§6.4 的宽度表用 `16.62` 记这同一个值；两者差 `0.02`，三个 ceil 之后的宽度完全相同，所以下表不受影响。

## 5. 实时监视列表

### 5.1 成员语义

一行代表一个可导航根 Thread。Running、Input needed、Approval needed 始终显示；Completed 只在 Desktop 仍为未读时显示。Desktop 已读、归档、删除或失去可导航性后自动移除。

列表覆盖当前 Desktop 账户所有 Project 与 `Chats`，不跟随侧边栏选择，不展示子智能体，也不承担历史浏览。

### 5.2 排序

```text
Input needed
> Approval needed
> Running
> Completed
```

同级按最近可信更新时间降序。排序实时变化，但不得在用户滚动或悬停时强制改变当前视口锚点。

### 5.3 当前内容

| 状态 | 内容 |
| --- | --- |
| Input needed | 当前问题 |
| Approval needed | 固定 `Approval requested` |
| Running | 最新公开进度，回退到本轮输入 |
| Completed | final answer 开头；没有时保留最后公开进度 |

禁止 raw reasoning、工具参数、命令输出、diff、敏感路径和批准理由。

## 6. Integration States

`07 — Integration States`（`227:3`）包含：

### 6.1 Content previews hidden

- 保留 Project、Desktop 标题与状态。
- 未生成 Desktop 标题的会话显示 `Untitled`。
- 不显示正文预览，不改变行高。

### 6.2 Quota unavailable

额度环为灰色 unavailable，但会话列表、状态和点击能力继续工作。该场景表达局部降级，不是 Disconnected。

### 6.3 Monitoring lifecycle

注释卡明确：提交输入后入列；活动 Turn 始终保留；终态只在 Desktop 未读时保留；已读、归档、删除或失去可导航性后自动移除；Notch 不主动标记已读。

### 6.4 在场：两个系统状态

设计见 `10 — Double Apps` 的 `08 — Presence`（`624:1560`）。

支持两个产品之后，应用不能再假设用户在用哪一个，因此为从不打开的产品长期变暗的矩阵必须去掉。但菜单栏里消失的控件会把自己的位置一起带走，而无刘海屏幕没有可以藏身的缺口——药丸必须留在原地。解法是让矩阵不再报告我们自己的连接健康，改为报告一件用户能自己核对的事：**是否有编码智能体处于打开状态**。

系统状态因此从六个收敛为两个：

| 状态 | 成立条件 | 收起态 |
| --- | --- | --- |
| `Disconnected` | 没有任何编码智能体处于已连接状态（§6.7） | 有刘海：什么都不画。无刘海：一个灰色矩阵加状态名，替药丸守住位置 |
| `Connected` | 至少一个智能体已连接，且没有任何一个在工作 | 该产品自己的矩阵，熄灭态；没有计时，因为没有未完成轮次 |
| 四个会话状态 | 有处理轮次在进行 | 不变：Running、Input needed、Approval needed、Completed |

`Idle` 并入 `Connected`，这次改名值得：`Idle` 描述的是我们自己看到的空列表，用户无从核对；`Connected` 描述的是用户瞄一眼自己的 Dock 就能核对的事实。

矩阵因此承载三个通道，而不是两个：

| 通道 | 含义 |
| --- | --- |
| **在场** | 该产品是否打开。新增——这正是旧设计没有的通道，此前靠「永远画一个熄灭矩阵」假装 |
| 色相 | 哪个产品。不变 |
| 亮度 | 是否需要用户处理。不变 |

灰色不是第四种颜色，而且它是整个界面上**最暗**的东西：`#151515` 是仍然处在两个产品熄灭色亮度之下（或持平）的最亮中性灰——相对亮度 `0.0075`，对 `#21120D` 的 `0.0079` 与 `#101B26` 的 `0.0104`。这样「有智能体已连接」永远不会看起来比「什么都没连接」更暗。产品内部的点亮／熄灭关系保留原有的 `15%` 规则不变。

静息与 hover：

| 形态 | 静息 | hover |
| --- | --- | --- |
| 有刘海 | 什么都不画，只占 `200` 遮挡 | 药丸横向展开为 `400 × 46`，绕过刘海：前导侧灰色矩阵与状态名，尾侧齿轮 |
| 无刘海 | `160 × 46`，灰色矩阵 + `Disconnected` | 横向展开为 `208 × 46`，尾部加齿轮 |

**hover 只横向展开药丸，不落下面板。** 没有智能体连接时面板里没有内容可放，展开的唯一目的是让齿轮可达；原因写在 Settings 里，齿轮离它只有一个动作。

> **实现记录：** 上表的 `400 × 46` / `208 × 46` 与本节 §6.8 清单里的 `400.6 × 46` / `224.6 × 46` 互相矛盾，两处都没有给出组成关系。实现按本文其余宽度一致的办法**按组成计算**（`PanelMetrics.restingExpandedWidth`）：前导内边距 `24` + 矩阵 `16.6` + 间距 `12` + `Disconnected` `82.96` + 间距 `12` + 齿轮 + 尾部内边距 `24`，有刘海形态在中间插入 `8 + 遮挡 + 8`。齿轮随菜单栏缩放（`46pt` 下 `32`，`24pt` 下 `20`，见 [`dual-agent-design.md`](dual-agent-design.md) §5.3），因此本机 `46pt` 菜单栏下得到无刘海 `204`、有刘海（`200` 遮挡）`420`。上屏后若与图不符，改的应是这条组成关系，而不是把数字写死。

**第一个打开的产品接管灰槽，而不是并排新增。** 灰色表示「没有产品」，一旦有产品在场，就没有「没有产品」可画；第二个产品才新增一槽。关闭时逐步反向。

#### 固定工作宽度

无刘海药丸在**单产品的整个工作集合内不改变宽度**：`Connected`、`Running`、`Approval`、`Input`，以及计时最长到 `00:00:00` 的情况，全部使用同一个宽度。只有第二个智能体连接时才加宽，且只加一个矩阵。`Disconnected` 是唯一允许更窄的状态——它后面不会来计时，撑开只会在短状态名旁留下可见的空药丸。

宽度用 `NSFont.systemFont(ofSize: 13)` 与 `monospacedDigitSystemFont` 在本机实测，即应用真正渲染的字体：

| 组成 | 值 |
| --- | --- |
| 前导内边距 | `12` |
| 状态矩阵 | `16.62` |
| 间距 | `12` |
| 最宽紧凑状态名 `Approval`（**最宽的可计时状态**，见下注） | `52.74` |
| clearance | `32` |
| 最宽计时 `00:00:00`（等宽数字，Medium） | `57.91` |
| 尾部内边距 | `12` |
| **固定工作宽度** | **`195.27` → `196`** |

其余全部落在它之内：`Completed 118.43`、`Connected 118.67`、`Input + 00:00:00 172.98`、`Running + 00:00:00 191.52`、`Approval + 00:00:00 195.27`。双产品为 `217.89 → 218`（一个矩阵加一个 `6` 间距）；`Disconnected` 为 `135.58 → 136`。

两侧内边距从 `24` 收到 `12` 之前，这三个宽度分别是 `220`、`242` 和 `160`；表里其余每一项都没有变，差额就是两个 `12`。

**`Approval` 是最宽的可计时状态，不是最宽的状态名。** `Connected`（`66.05`）与 `Completed`（`65.81`）都比 `Approval`（`52.74`）长，但两者都不会计时，所以都输给「`Approval` 再加计时槽」。把计时槽预留在最长的*名字*后面而不是最长的*可计时状态*后面，会多留约 `13pt`——对一个常驻菜单栏的药丸来说是看得见的。实现按状态各自计算（`PanelMetrics.compactContentWidth`），由 `theFixedWidthFitsEveryWorkingStatusWithItsLongestTimer` 指名锁定。

计时在预留空间内**右对齐**且使用等宽数字，因此轮次跨过一小时时数字只向左长进本来就空着的位置，药丸不动，菜单栏里它左边的图标也不动。

这同时了结了 [`dual-agent-design.md`](dual-agent-design.md) §8 里登记的那条：`Update Claude Code` 曾把双产品药丸从 `189` 顶到 `202`。它退出收起态后不再参与定宽；即便日后回来也仍然装得下——`12 + 16.62 + 12 + 124.77 + 12 = 177.4`，在 `196` 之内。（`Update Claude Code` 本机实测 `124.77`，与 §8 已记录的 `124.8` 一致，这是上表其余数字可信的依据。）

### 6.5 openness 如何判定

两个信号在代码里都已存在，且都不是为此新写的——一个用于退休会话已死的行（`SessionEnd` 被刻意不注册），另一个是冷启动得以成立的前提：

| 产品 | 「打开」的含义 | 来源 | 现有实现 |
| --- | --- | --- | --- |
| Codex Desktop | 应用正在运行 | `NSRunningApplication.runningApplications(withBundleIdentifier:)`；每次刷新取一次，本来就已经在取，用于把实时 Hook 绑定到同一个 Desktop 进程生命周期 | `LiveCodexMonitorService.swift:990` |
| Claude Code | 至少有一个活跃会话 | `claude agents --json`，经 `ClaudeCodeSessionListing.liveSessions()`。没有应用可问，会话列表就是在场信号 | `ClaudeCodeSessionRegistry.swift` |

`ClaudeCodeSessionRegistry` 自己的契约就是这里需要的那条界线：它的输出无论会话正在处理还是空闲都逐字节相同——它回答「有哪些会话」，Turn reducer 回答「它们在做什么」。**在场画出矩阵，reducer 点亮它**，两者不得重新合并。

`Connected` 继承 tech-design 已经为 `Idle` 写下的规则：只有当前态来源确认集合确实为空时，空集合才能被读成「没有东西在工作」，绝不能在看不见时这样读；否则 `Connected` 就成了新的谎言。

有一处不对称值得刻意保留：Codex 的在场在本应用启动的瞬间就可知，它的处理轮次不可知（产品刻意不显示启动前的任何东西）。因此刚启动的应用可以诚实地为 Codex 显示 `Connected`，而此时它对工作还一无所知——这比今天显示一片空白严格更好。

在场的可信度按产品不同，只有 Claude Code 一侧需要额外规则：`NSRunningApplication` 是内核事实，不存在缓存与过期；`claude agents --json` 背后是 `~/.claude/sessions/<pid>.json`，每个会话一个文件，**没有心跳字段，mtime 也不更新**，因此文件本身无法自行过期。两处后果：

1. **幽灵会话——已实测，官方命令自己做掉了，而且用的正是那条正确的判据。** 被 `SIGKILL` 的会话确实来不及删除自己的文件，所以这个担心是对的；但 `claude agents --json` 并不会列出它。实测 2.1.229：把一个活会话的文件逐字节复制、**只改 `procStart`**，它就从输出里消失；写一个指向活着但不相干进程（`pid 1`）的会话文件，同样消失。也就是说该命令按 `pid` + `procStart` 成对校验——正是这里需要的判据，也正是只查 `kill(pid, 0)` 会被 PID 回收骗过的那一条。

    因此本应用**不重做、也不应重做**这条校验：`--json` 根本不输出 `procStart`，要自己判断就必须改去直接读 `~/.claude/sessions/<pid>.json` 这套私有 schema，等于为了复制一条已经正确的公开实现而登记一项非公开依赖（`AGENTS.md` §8）。结论记在 [`ClaudeCodeSessionRegistry.swift`](../CodexInNotch/CodexInNotch/ClaudeCodeSessionRegistry.swift) 的 `runOfficialCommand` 注释里。
2. **我们自己的缓存没有上限。** `ClaudeCodeSessionRegistry.refresh()` 在读取失败时返回上一次结果且不更新 `readAt`。这对「行」是对的（一次失败不该退休所有行），但在场现在决定 `Connected` 与 `Disconnected`：只要 `claude` 被卸载或改名，读取会永久失败，而药丸会永远显示 `Connected`。因此「多久重读一次」（`freshness`，`30` 秒）与「陈旧答案还能被相信多久」必须分开，后者建议 `90` 秒（三次连续失败）。

超过上限时在场是**未知**，而未知落到 `Disconnected`。按 §6.7 的语义这不是妥协而是字面真相：我们确实没有任何可用的连接。这与 tech-design 为 `Idle` 写下的规则是同一条，只是对称地用在非空集合上。

### 6.6 已退休的薄层状态

| 已退休 | 去处 |
| --- | --- |
| 静息的熄灭产品矩阵 | 直接删除。灰槽不指认任何产品 |
| `Idle` / `No active turns` | 并入 `Connected`（§6.4） |
| `Connecting to Codex` | 删除。在场由系统 API 直接回答，没有需要向用户解释的等待 |
| `Update Codex` | 设置里的产品行，以及用户打开时的展开面板 |
| `Codex version unsupported` | 同上 |
| `Set up integration` | 引导流程，以及设置里的开关 |

`Codex disconnected` 不退休，而是被重新定义为 `Disconnected`，见 §6.7。薄层 `520 × 94` 只保留给展开面板。

### 6.7 `Disconnected` 的定义

在场与可观察性现在是两件独立的事实，因此可以互相矛盾。[ADR 0010](adr/0010-never-write-the-users-claude-code-settings.md) 把 Claude Code 的 hook 注册留给用户自己写，「打开了但监视不到」因此是普通的首次运行，而不是边缘情况。两个状态必须覆盖它，且不能变成三个。

**已定：`Disconnected` 的含义是「没有任何编码智能体处于已连接状态」，而不是「没有任何编码智能体打开」。** 这一行改动买到很多：智能体已打开却不可达时状态仍然为真；不需要第三个状态；而且这个词终于名副其实——你不会与一个从未打开的东西断开，但与一个打开了却够不着的东西确实是断开的。原因写在设置里，hover 展开距离它只有一个动作。

失去观察是**过渡而不是状态**：矩阵先落到各自的熄灭色（保留色相，因而看得出是哪个产品暗了），行随之排空，随后整体落到 `Disconnected`。

### 6.8 已知代价与未决

已定：`Disconnected` 的语义（§6.7）、灰色取最暗（§6.4）、单产品工作集合共用一个宽度（§6.4）。

**`Connecting` 算不算已连接：已定为不算。** §6.5 说刚启动的应用可以诚实地为 Codex 显示 `Connected`，§6.7 说「打开了但监视不到」读作 `Disconnected`；App Server 尚在连接的那几秒同时落在两句话之间。取「不算」，因为 §6.7 的定义是字面的——观察契约还没建立，就还没连上——而且反过来做等于在没有证据时报告一个业务状态，正是 `AGENTS.md` §6.2 禁止的猜测。代价接近于零：有刘海形态静息时本来就什么都不画，所以正在连接的产品是「还没有标记」而不是「一个错的标记」，标记随契约一起到达。§6.5 那段不对称仍然成立，它讲的是轮次不可知而非连接未建立。

剩下三条：

- **`Disconnected` 这个词本身。** 它现在指认的是一次真实的连接失败，反对意见因此弱了很多；但它仍然是新用户在「一切正常、只是还没打开任何东西」时读到的第一句话。备选 `No agents`、`Nothing running`，上屏后再判断。
- **有刘海形态在静息时没有任何绘制**，因此 `Disconnected` 是一个只在无刘海形态与 hover 时可见的状态名；两种形态第一次在「系统状态是否可见」上产生差异，而不只是画法不同。
- **已死会话会占住一个槽。** `SIGKILL` 不报告任何东西，因此在场必须校正而不只是订阅（§6.5）。

## 7. 首次安装引导

`08 — Onboarding`（`232:95`）由三个 `580 × 640` 的 macOS 窗口组成：

1. **Welcome**：Notch 预览、实时监视价值、人工请求优先级和精确会话返回。
2. **Connect to Codex**：列出受支持的本地元数据与额度读取，说明本地、最小、可逆；只有用户点击 `Set Up Integration` 后才改变配置。
3. **Ready**：确认实时状态与精确导航，提醒预览默认开启并可在设置中关闭。

引导窗口使用标准 macOS 视觉层级：交通灯、单列内容、底部主操作。它不请求用户允许辅助功能或屏幕录制，也不承诺静默绕过 Codex 信任。

## 8. 设置

现行设计是 `09 — Settings` 上的 `609:2`（`Settings — redesigned for macOS 26`），按 macOS 26 视觉语言重做，包含浅色与深色两个完整窗口，以及预览关闭状态的两个局部切片。`233:3` 与 `591:2` 保留为 v1 参考，不再是验收对象。

### 8.0 窗口结构

设置窗口是**单面板，没有侧边栏**。V1 只有三个已确认分组，用一个只有一项的 source list 承载它们，等于宣告一套并不存在的导航，还逼内容区重复一个 `General` 大标题。窗口标题因此按 HIG 写作 `Codex in Notch Settings`，内容区不再有第二个标题。

| 项目 | 值 |
| --- | --- |
| 窗口宽度 | `580`（与 Onboarding 窗口同宽） |
| 窗口圆角 | `26` |
| 标题栏 | 高 `52`，与窗口同色；内容滚动到其下方之前不画分隔线 |
| 交通灯 | 直径 `12`，间距 `20`，`x = 20` |
| 内容边距 | 左右 `24`，上 `20`，下 `22` |
| 分组间距 | `22`；组标题与卡片之间 `8` |
| 卡片 | 圆角 `12`，1px hairline 描边，极轻投影 |
| 行内边距 | 左右 `14`，上下 `11`；主标签与说明行间距 `2` |
| Switch | `38 × 22`，滑块 `18` |
| 按钮与弹出菜单 | 胶囊圆角；弹出菜单尾部是强调色 `18 × 18` 双箭头 chip |

三个分组自上而下是 `Products`、`Session list`、`Privacy`。每个分组的形状都是「小标题 + 一张圆角卡片 + 卡片下方的脚注文字」。脚注取代了 v1 的蓝色提示条——macOS 用脚注而不是色块陈述后果，色块在原生窗口里只会读作一个没人点得动的控件。

窗口最后一行是 `closing note`：左边是那句只读声明，右边是胶囊按钮 `Quit Codex in Notch`。它与 `Recheck` 同形不是巧合——两者都是「说明文字尾部挂一个它所说的那个动作」。退出不属于任何一个分组：它不是一项设置，而它要收走的那个组件也没有自己的窗口可关，Settings 是唯一能承载它的界面。这一行不加内缩（分组脚注的 `2 pt` 左内缩只属于分组），因此它与三个组标题落在同一条竖线上。

所有主标签共用同一左缩进：产品行的绿色状态点移到说明行行首，而不是站在产品名左边，因此三张卡片的标题列在同一条竖线上。

浅色与深色是**同一批节点**：颜色全部绑定到两模式集合 `Color / macOS Window`（`Light` / `Dark`），深色窗口是浅色窗口的 clone 加一次 mode override。改一次颜色两边同时生效，不存在两套值漂移的可能。实现侧对应 [`SettingsWindow.swift`](../CodexInNotch/CodexInNotch/SettingsWindow.swift) 的 `MacOSWindowColor`：每个 token 是一个 `NSColor(name:dynamicProvider:)`，一次声明同时回答两种外观，这是两模式集合在代码里的等价物。状态点例外，取系统色 —— `status/green` 的两个值本来就是 `systemGreen` 的两个值，用系统色还能跟随「增强对比度」。

**标题栏按 macOS 自己的样子渲染，不按本表这一行。** 板上的标题栏与窗口同色、高 `52`、不画分隔线；SwiftUI 持有 scene 窗口的标题栏并在每次布局重新应用自己的配置，`titlebarAppearsTransparent`、`backgroundColor`、`titlebarSeparatorStyle` 与 `.fullSizeContentView` 实测全部无效。剩下的做法是 `.hiddenTitleBar` 加自绘 `52` 色带与居中标题——那会让「用原生控件而不是它们的近似物」这个论点里最显眼的一块变成唯一的近似物。因此标题栏保持系统材质，`52` 是板上的排版约定而不是验收项。

### 8.1 Products

`Codex Desktop` 与 `Claude Code` 是同一张卡片里的两行，不是两个分组。加入第三个产品的代价是一行，而不是一个新面板。

- 每行左侧是产品名，说明行以状态点开头，写连接结论与能力信息（`Connected · compatible version`、`Connected · hooks installed`）。
- Codex 行右侧是一个原生 macOS switch，启停该产品所需的 lifecycle event 定义；切换进行中 disabled。
- **Claude Code 行没有 switch，这是实现与板上不一致的一处，且是刻意的。** [ADR 0010](adr/0010-never-write-the-users-claude-code-settings.md) 决定本应用永不写 `~/.claude/settings.json`，因此那一行给不出一个能兑现的开关。它的尾部是胶囊按钮 `Set Up…`，展开卡片内的一段：粘贴目标路径、可选中的 JSON 片段、`Copy` 与 `Reveal Settings File`。两行并排正是这个不对称唯一被看见的地方——把它藏进另一个流程，只会让它读起来像疏漏而不是决定。板上的双 switch 保留为「若日后恢复写入能力」的形态。
- 卡片下方脚注说明开关只安装 Codex in Notch 需要的六项定义，关闭时移除，用户其他 hooks 不受影响，并写明 Claude Code 由用户自己注册。
- **卡片里还多一行 `Quota reading transcripts`，板上没有，这是实现与板不一致的第二处。** 读取 Claude Code 额度的每一次调用都是一个真实会话，因而在 Claude Code 自己的 project 目录里留下一份约 `3 KB` 的 transcript，没有任何东西会清掉它们。这一行报出它们的总大小与个数（`43.2 MB · 1,284 files`），尾部是胶囊按钮 `Reveal in Finder`。
  **只报不删，这是决定而不是省事。** Claude Code 给 project 目录起名的规则未公开，且压平分隔符与空格后并非一一对应（实测 `…/a b` 与 `…/a-b` 同属一个目录），因此那个目录里可能同时躺着用户真实项目的会话记录。把数字摆在用户眼前、并把门打开，比替他们删要正确。这一行与 `Display` 分组同类：既有行为在新形状里的安置，不是往设置里塞新功能。
- `Recheck` 是脚注行尾部的胶囊按钮，重新检测能力。
- Off 后保持 Settings 可达；再次 On 安装或修复完整集合。首次安装或定义变化后的 `/hooks` 信任仍由 Codex 处理。

### 8.2 Session list

弹出菜单 `Distinguish products`，值为 `Name and colour`（默认）／`Name only`／`Badge`，语义见 [`dual-agent-design.md`](dual-agent-design.md) §6。脚注说明它只在两个产品同时运行时有效果；单产品时该项仍然可见但无效果，隐藏它会让用户恰好在准备接入第二个产品时找不到它。

卡片里还有第二行 `Clear the session list`，尾部胶囊按钮 `Clear`，列表为空时 disabled。它在 v1 是 Codex 卡片里的一枚破坏性按钮；产品分组现在只讲产品，而这个动作的对象是会话列表，它属于这里。板上没有这一行，因为板只画了三个已确认的**设置**，而这是一个动作。

### 8.3 Privacy

- `Show current content previews` 默认 On，说明行写明它覆盖哪些片段。
- On 的脚注写明预览不落盘。
- Off 的脚注写明 Project、标题与状态仍然显示，且 prompt fallback 被禁用、缺失标题为 `Untitled`。
- 只有开关本身改变：行高、行几何与说明行都不动，这一点由两个局部切片直接对照。

### 8.4 Display

板上没有这一组，实现里有，位置在 `Products` 与 `Session list` 之间。

`Show Codex in Notch on` 是一个已经存在的控件：组件只出现在一台显示器上，由用户选定，说明行报出该显示器的形态与真实菜单栏高度（`Notch display · 39 pt menu bar`）。删掉它会拿走一个真实功能，所以它按同一形状留下——小标题、一张卡片、一行脚注。

这不是「加入尚未确认的功能」的例外：下面那条禁止的是把没定过的功能塞进设置，而这一项是既有功能在新形状里的安置。板与窗口的差异记在这里，等板更新时一起消掉。

不在 V1 设置画板中加入登录启动、动画、通知、模型选择或其他尚未确认的功能。

## 9. 交互

### 9.1 展开/收起

- Hover intent 参考 `150 ms`。
- 展开参考 `180–220 ms`。
- 鼠标离开后参考 `250 ms` 收起。
- Escape 立即收起。
- 所有中间帧保持相同 `maxY`。水平方向上，展开态与无刘海形态保持相同 `midX`；带刘海的收起态锚定缺口右缘（§3.4）。
- Reduce Motion 下使用短淡入淡出，不使用明显弹簧或缩放。

### 9.2 会话点击

- 点击成功进入相同 Desktop Thread 并收起 Panel。
- Notch 点击本身不改变已读；等待 Desktop 蓝点消失事件。
- 导航失败时 Panel 与行保持，不把打开首页当作成功。
- 会话行不提供批准、回答、取消或归档操作。

## 10. 无障碍

- 所有状态必须有文字或可访问名称，不能只依赖颜色。
- 系统级状态与四个会话级状态使用不同文案与语义。
- 隐私关闭后旁白不读取已隐藏正文。
- 长状态名称在带刘海 Expanded 几何中必须完整可读。
- Reduce Motion 不影响状态可理解性。

旁白示例：

```text
Codex，三个当前轮次，状态需要输入，额度剩余百分之七十二
确认未读生命周期，Project Codex in Notch，需要输入
等待审批，Chats，需要批准
```

## 11. 验证清单

- [x] 展开宽度 `520`，参考高度 `302`。
- [x] header 固定参考 `46`，只横向扩张。
- [x] 三行 `508 × 80` 视口与滚动契约。
- [x] SF Pro 文件级字体统一。
- [x] 隐私关闭场景。
- [x] Quota unavailable 局部降级。
- [x] ~~No active turns、Connecting、Disconnected、Update、unsupported、setup 薄层。~~ 收敛为 `Disconnected` 与 `Connected` 两个系统状态，见 §6.4 与 §6.6。
- [x] 收起态在场规则与开合序列（§6.4，`624:1560`）：矩阵随智能体打开与关闭出现和离开，第一个产品接管灰槽。**画法已随 [#35](https://github.com/soondubu137/codex-in-notch/issues/35) 落地**：每个已连接产品一个矩阵，各自跑自己的曲线；无产品时一个灰色静息标记；有刘海形态静息时整条前导翼消失。
- [x] hover 只横向展开药丸、不落下面板；展开尾部为齿轮。**宽度改为按组成计算**，原因见 §6.4 的实现记录。
- [x] `Disconnected` 按 §6.7 重定义为「没有任何智能体已连接」；灰色取 `#151515`，为界面上最暗值（§6.4）。
- [x] 无刘海药丸在单产品工作集合内固定为 `196`，双产品 `218`，`Disconnected` 为 `136`；宽度用系统字体本机实测（§6.4）。
- [ ] 会话行里的 `alpha fade mask` 仍是 `273` 定宽。行从 `472` 一路走到 `508`、内边距又从 `16` 收到 `6` 之后，渐隐的收尾离右缘比原先远了 `56`；遮罩应该跟着行走，或改为距右缘定距。
- [x] 会话行的边距拆成 `6` 行块缩进 + `6` 行内边距，行内文字因此与状态矩阵、额度规则同落在 `12`（§3.3）；由 `aRowsTextLandsOnTheSameMarginAsTheRestOfThePanel` 锁定。
- [ ] 折叠额度块（[`dual-agent-design.md`](dual-agent-design.md) §5.4，Figma §09）：折叠后页脚 `28`、面板恒为 `520 × 314`；`quota fold` 控件 `16 × 16`，两个状态由同一枚 chevron 旋转 `180°` 得到。**设计已定稿，尚未实现。**
- [x] `Colour bar` 作为第四个 `Distinguish products` 选项（[`dual-agent-design.md`](dual-agent-design.md) §4，Figma §06）：`2 × 40` 竖条、圆角 `1`，行内 `x = 0`。**已实现**；`Distinguish products` 弹出菜单现在是四项。
- [ ] §3.3 的三条 compact 参考基线（`348 × 46`、`168 × 46`、`200 × 46`）在这次改动前就与文件里的组件不一致，本次未一并修正；组件当前是 `237`（刘海静息）、`285`（刘海计时）与 `165`（无刘海）。
- [ ] `Disconnected` 这个词是否保留（备选 `No agents`、`Nothing running`），上屏后判断。
- [x] ~~Claude Code 在场的第一条校正：按 `pid` + `procStart` 成对过滤幽灵会话。~~ **实测后撤销：`claude agents --json` 自己就是这么校验的**，而且它不输出 `procStart`，自己重做只能改读私有 schema。见 §6.5。
- [x] Claude Code 在场的第二条校正：为陈旧缓存设上限（`90` 秒 = 三次连续失败），超过后在场为未知并落到 `Disconnected`。`freshness` 与 `trustCeiling` 现在是两个参数。
- [x] 首次安装三步流程。
- [x] Settings 预览 On/Off 与集成管理。
- [x] Settings 已按 macOS 26 重做为单面板窗口，浅色与深色由 `Color / macOS Window` 的两个 mode 驱动。**实现已落地**（[`SettingsWindow.swift`](../CodexInNotch/CodexInNotch/SettingsWindow.swift)），四处与板不一致均已记录：标题栏保持系统材质（§8.0）、Claude Code 行是 `Set Up…` 而不是 switch（§8.1）、Products 卡片多一行 `Quota reading transcripts`（§8.1）、多一个 `Display` 分组与一行 `Clear the session list`（§8.4、§8.2）。
- [ ] 在装有 SF Pro 的 Figma 桌面端打开 `609:2`，确认字形正常渲染、多行脚注的换行落位与预期一致。
- [ ] 同一次打开时，把 `closing note` 的四条 Inter 文字（`665:3`、`665:5`、`667:3`、`667:5`）重新键入为 SF Pro Regular，原因见 §3.1。
- [x] 会话行已同步 Running／等待人工／Completed 三种计时表现，一行只有一个标记。
- [ ] 收起态计时变体的文字层改为 hug contents（见 4.6），消除固定文本宽度带来的整体偏宽。
- [ ] 刘海计时变体中的计时 TEXT 在渲染中不可见（节点数据正确、坐标与实现一致，`24` 高面板中同一文本正常）；需在 Figma 桌面端确认是渲染问题还是文件缺陷。
- [ ] 外部 Figma 文件中的历史 Runtime Badge 变体已删除；计时不是独立徽标，而是未完成行的唯一状态标记。
- [x] Usage Ring 已同步为从十二点逆时针增长的暗色消耗弧，并覆盖 `100`、`0` 与 Unavailable 边界。
- [x] 无刘海 Panel 已同步 `38`、`24`、`19` 菜单栏高度下的响应式圆角参考。
- [x] Figma 组件集结构合法，且同步范围内无 Inter、旧尺寸或旧计时文案残留。
- [ ] 从外部 Figma 删除不属于四态模型的历史会话状态变体。
- [ ] 不同真实菜单栏高度与至少两种物理刘海设备的原生几何验证。
- [ ] 真实 Codex 集成事件、Project、未读和精确导航的 Phase 0 能力验证。

## 12. 实现映射

产品与技术行为以 [`PRD.md`](PRD.md)、[`tech-design.md`](tech-design.md)、[`CONTEXT.md`](../CONTEXT.md) 和 [`docs/adr`](adr/) 为准。Figma 节点用于视觉与布局验收，不作为 Codex 协议事实来源。
