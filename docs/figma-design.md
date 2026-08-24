# Codex in Notch — Figma 设计规范

| 字段 | 内容 |
| --- | --- |
| 文档状态 | V1 SwiftUI 四态契约已同步；设置窗口已按 macOS 26 重做；系统状态收敛为 `Disconnected` / `Connected` 两个，在场与宽度已实现、画法待 [#35](https://github.com/soondubu137/notchline/issues/35)；子智能体尾部状态（§4.6）已同步到 Session Row 与 Panel 两个组件集；外部 Figma 的旧状态变体待清理 |
| 版本 | 1.2 |
| 日期 | 2026-08-23 |
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
| `04 — Session Row` | 会话行、列表和状态名称胶囊；`807:91`／`807:102` 是 Completed 行的子智能体尾部变体（§4.6） | `112:28`, `140:201`, `198:72`, `807:91`, `807:102` |
| `05 — Panel` | 收起与展开 Panel 变体；`808:527` 是 no-notch 收起态计数+计时合成读数变体（§4.6） | `115:82`, `300:253`, `300:263`, `808:527` |
| `06 — Notch Core` | 核心产品状态与不同菜单栏高度参考 | `118:73`, `185:292`, `304:630`, `304:641` |
| `07 — Integration States` | 局部降级；预览隐藏与薄层状态已退休或并入两个系统状态，见 §6.6 | `227:3`, `307:30` |
| `08 — Onboarding` | 首次安装三步流程 | `232:95` |
| `09 — Settings` | macOS 26 设置窗口（浅色／深色）、集成管理与 `Session list` 分组 | `609:2`（现行）；`233:3`、`591:2`（v1 参考） |
| `10 — Double Apps` | 双产品（Codex + Claude Code）设计；`08 — Presence` 定义收起态的在场规则 | `540:2`、`624:1560` |

本文描述单产品契约。同时监视 Codex 与 Claude Code 时的设计见 [`dual-agent-design.md`](dual-agent-design.md)，其中两处已取代本文：设置齿轮的位置（见 4.5，现为展开态顶栏右上角，单产品同样生效）与双产品页脚的额度构成（见 4.3）。其余部分不受影响。

当前 SwiftUI 与本文只承认四个会话状态变体：Running、Input needed、Approval needed、Completed。外部 Figma 中超过这四类的历史会话状态变体不再属于产品契约，需在下一次 Figma 同步中删除；在完成前以本文和代码为准。`Usage Ring` 的 7 个合法变体、`Usage Indicator` 的 4 个合法变体及 `Panel` 的 8 个合法变体（2026-08-23 新增 `808:527`，见 §4.6）不受本次状态收敛影响。

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

**已知例外：`609:2` 上的 `closing note` 两条文字（浅色 `665:3`／`665:5`，深色 `667:3`／`667:5`）当前是 Inter Regular。** 通过 MCP 编辑时，`listAvailableFontsAsync()` 会列出 SF Pro 且 `loadFontAsync` 不报错，但字形度量取不到：`characters` 写进去了，节点宽度与渲染却停在旧值——同一个按钮实测 SF Pro 下仍是 `49 pt` 的 `Recheck`，换成 Inter 立刻重排为 `115 pt` 的 `Quit Codex in Notch`。两害相权：留在 SF Pro，板上会把一句**不存在的文案**画给每一个看它的人；换成 Inter，板读得对而字体错一处。选后者，并记在验证清单里，等在装有 SF Pro 的 Figma 桌面端重新键入。这条例外原先只覆盖这四个节点，不放宽 §1.6 的规则——2026-08-23 同步子智能体支持时，同一个渲染限制在新增节点上复现（见下一条），例外范围相应扩大，规则本身不变。

**例外扩大（2026-08-23，子智能体支持同步）：** `112:28`（Session Row）新增的两个尾部文字节点（`807:101`「2 subagents」、`807:112`「1 subagent」，见 §4.4／§4.6）与 `115:82`（Panel）新增的 `808:562`（no-notch 收起态尾翼「2 │ 1:23」的合成读数）同一个原因改用 Inter：这三处都是**全新文案**，不是编辑已有 SF Pro 节点——但用 `figma.createText()` 以 SF Pro 新建文字节点同样不渲染（空白、零宽度），不止已有节点编辑失效那一种情况，说明这个限制覆盖新建与编辑两条路径。`808:562` 另有第二处例外：分隔符实现应为 `U+2502`（BOX DRAWINGS LIGHT VERTICAL），但 Inter 在本文件中没有这个字形（渲染为空白），暂以 ASCII `|` 代替。三个节点的 `description` 字段各自记着同样的说明与待办。这条不是先例——不因为好用就继续拿 Inter 顶新文案，只在同一个渲染限制再次挡住 SF Pro 时才这样做，且必须现场记录。

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
| Session row gutter / padding | `6` + `6`；画 `Colour bar` 时 `12` + `8`，见下 |
| Status dot | `8 × 8` |
| Usage ring | `18 × 18`, stroke `2` |
| Row badge | `24` 高 |

> **上表前五行是 V1 的参考基线，已被组成关系取代。** 收起态宽度现在由 `PanelMetrics` 按实测文本组合后向上取整，不再有「参考基线」：无刘海单产品整个工作集合是一个定宽 `196`（`Running` 与 `Input needed` 因此同宽，不是 `168` 与 `200`），双产品 `218`，`Disconnected` `136`（§6.4「固定工作宽度」）；有刘海形态是两翼加遮挡，本机 `200` 遮挡下静息为 `237`（§5）。展开态高度是 `menuBarHeight + 视口 240 + 页脚`，`46` 高菜单栏下为 `326`（仅 Codex）、`340`（仅 Claude Code）、`370`（两个都在）、`314`（折叠额度块），不是 `302`。保留这几行只为对照历史文件，读数请以 §5、§6.4、§6.8 为准。

**会话行比面板其余部分宽两个 `6`。** 行块从面板边缘缩进 `6` 而不是 `12`，好让 hover 的填充不撞到边；行自己再补回 `6`，于是行内文字仍然落在 `12`——与 header 里的状态矩阵、页脚里的额度规则同一条边距上。两个数因此是互相定义的（`PanelMetrics.sessionRowGutter` 与 `sessionRowPadding = expandedHorizontalPadding − sessionRowGutter`），不是两个各写死的 `6`；`aRowsTextLandsOnTheSameMarginAsTheRestOfThePanel` 锁定这条关系。行块 `520 − 6 − 6 = 508`，内容盒 `520 − 12 − 12 = 496`。

**画 `Colour bar` 竖条时缩进改为 `12` + `6`。** 竖条就画在行块前缘，所以行块的缩进就是竖条的位置：留在 `6` 上，它比上方状态矩阵、下方额度规则都朝里半个 `12`，差一点对齐比不对齐更像做错。因此只在竖条**画出来的时候**（两个产品都在，见 [`dual-agent-design.md`](dual-agent-design.md) §4）行块让出整 `12`，行内边距同时由 `6` 改为 `8`——它此时不再是「离面板边多远」而是「离那条 `2pt` 线多远」，`6` 会让线和字读成一个东西——行内文字因此落在 `20`，站到竖条后面而不是骑在上面；行块此时 `520 − 12 − 12 = 496`，与内容盒同宽。单产品时没有竖条，行块回到 `6` + `6`，文字仍落在 `12`。这条几何由 `MonitorStore.sessionRowGutter` 与 `sessionRowPadding` 提供，`theAttributionRailLandsOnThePanelsOwnMargin` 与 `theRowBlockOnlyGivesUpItsGutterWhileTheRailIsDrawn` 锁定。

目标显示器菜单栏高度不是 `46` 时，顶部汇总区使用真实菜单栏高度，总高度为 `menuBarHeight + 256`。例如无刘海 `24` 高菜单栏的展开参考尺寸为 `520 × 280`。带物理刘海时，宽度还要根据中央不可显示区继续增加，确保 `Approval needed`、`Input needed`、`Version unsupported` 等最长状态名完整位于可显示区域。状态名不再指名产品（§6.6），因此这条加宽只取决于遮挡宽度，与用户装了哪些产品无关：单侧为 `12 + 16.6 + 12 + 124.88 + 8 = 173.48`，`520` 的基线要到遮挡超过 `173` 才被顶开。

Panel 外轮廓有**两个**圆角，因为刘海本身有两个：侧边与屏幕上沿相接处是一段向外的小凹弧，下面两角是它的两倍。两者都不是常数，而是菜单栏高度的固定比例：

```text
shoulderRadius   = max(0, menuBarHeight) / 8    // 上凹弧，也是窗口每侧多出的「肩」
bottomCornerRadius = max(0, menuBarHeight) / 4  // 下圆角
```

**比例而非常数**，是因为硬件就是这样：刘海是一块毫米数固定的缺口，带刘海屏的菜单栏正好与它等高，两者在缩放变粗时一起在点单位上缩小——*More Space* 下 `220 × 38`，默认 `185 × 32`，再到 *Larger Text* 的 `127 × 22`。写死一个半径只在某一档缩放上对，其余每一档都偏圆；旧写法在带刘海屏固定 `10`，在默认缩放下就比真实缺口圆 `25%`，在 `22` 档上圆到近乎胶囊。

比例取自 Iconfactory 的 Notchmeister——它把轮廓直接描在硬件缺口上，`notchUpperRadius = 4`、`notchLowerRadius = 8`，对应默认的 `185 × 32` 缺口。上凹弧与 Apple 自带机型图标（`com.apple.macbookpro-14-2021`）中量到的 `13.5%` 一致；图标把下圆角画得更圆（约 `40%`），但那是插画尺度上的夸张，以描线为准。两段都是**正圆弧**（`0.5523` 控制柄），与缺口边缘一致。

参考值：`38 → 4.75 / 9.5`、`32 → 4 / 8`、`28 → 3.5 / 7`、`24 → 3 / 6`、`22 → 2.75 / 5.5`、`19 → 2.375 / 4.75`。带刘海与无刘海用同一条规则——无刘海形态模仿的正是同一个缺口，且新的下圆角比例（`25%`）与旧公式的 `26.32%` 几乎重合，所以外接屏的观感不变，变的是上凹弧减半。Figma 的响应式示例（`287:8`、`287:12`、`287:16`）仍是旧的单圆角 `10 / 6.316 / 5`，**尚未同步**。

### 3.4 面板本体、窗口与刘海对齐

`PanelContour` 只有最上沿一条边铺满它拿到的矩形，随后向内收成竖直边：直边落在矩形内缩一个肩宽（即 `shoulderRadius`）的位置，两侧各留出一个「肩」，画回菜单栏的那道凹弧就在肩里。

因此本文件所有参考尺寸描述的都是**面板本体**——真正画出来的那块黑色——而承载它的 `NSPanel` 窗口左右各宽一个肩宽（`OverlayPanelLayout.frame(on:panelSize:surfaceShoulder:trailingAnchor:)` 的 `surfaceShoulder`）。按本体尺寸开窗口就是错的：收起态的右缘会落进刘海里一个肩宽，底部圆角再吃掉一个半径，看上去像刘海右下角被咬掉一块。

带刘海的收起面板**以缺口的右缘为锚**：`NSScreen.auxiliaryTopRightArea.minX` 加尾翼宽度，不再由屏幕中心加位移推导。旧写法只有在缺口正好居中、且本体宽度不取整时才与之等价；取整的余量现在落在前导翼上——那里是留白，吃得下半个点，与硬件对齐的右缘吃不下。展开态与无刘海形态仍然锁定屏幕水平中心。

内容（含 `12` 水平内距）在本体内排布，所以内距是从黑色边缘量起的；指针响应区域同样只覆盖本体，肩部把点击让给它盖住的菜单栏项。

## 4. 核心组件

### 4.1 Status Dot

`Status Dot` 包含两类互不混用的状态：会话级 Running、Input Needed、Approval Needed、Completed，以及系统级 Idle、Connecting、Disconnected、Update Required、Unsupported Version、Setup Required。

- Idle（旧名）只用于健康空集合的汇总，现已并入 `Connected`；变体保留见下一条。
- Disconnected 不用于会话行。
- **系统级取值收敛为两个**：`Disconnected` 与 `Connected`（§6.4）。`Idle` 并入 `Connected`，`Connecting`、`Update Required`、`Unsupported Version`、`Setup Required` 退出收起态（§6.6），只在展开面板与设置中出现，组件变体因此保留。

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

### 4.5 Panel

Panel 组件集保留 Notch Compact、No Notch Compact 和 Expanded。Expanded 的正式参考尺寸已经从 `444 × 310` 修正为 `520 × 302`：

- header 高度从 `54` 修正为 `46`。
- 展开时 header 只横向扩张。
- 内容区使用 `256`，三行视口使用 `240`，底部保留 `15`。
- 现有 `06 — Notch Core` Running Desktop 画板已按 `1512` 屏幕重新居中到 `x = 496`。

Figma `Panel` 组件集（`115:82`）使用 `Mode`、`Content` 与 `Menu Bar` 属性，共七个合法变体。除 `46` 高参考外，还包含无刘海 `24` 高菜单栏的 Compact Running（`300:253`，`168 × 24`，圆角 `6.316`）和 Expanded（`300:263`，`520 × 280`，圆角 `6.316`）。所有变体均使用与 SwiftUI `PanelContour` 相同的外轮廓，而不是普通 RoundedRectangle。

### 4.6 处理时间

PRD 8.2 与技术设计第 12 节已明确权威时间语义、等待/睡眠行为、无障碍文案与刷新成本，处理时间因此进入产品范围。它不是独立的 Runtime Badge：未完成会话行以计时文本本身作为状态标记，一行永远只有一个标记——等待人工的行为琥珀色 Medium，Running 为暗色 Light，Completed 行不显示计时，只保留绿色状态点。

**行尾那个位置在计时停下之后还有一句话可说，而且只有一句。** 这条 Thread 的 Turn 已经结束、但它派生的子智能体还在跑时（两个产品都会走到），同一个位置写 `1 subagent` / `N subagents`，用 Running 的暗色 Light（有活在跑，没有人被问任何事，不能用琥珀）。**这一格有两档亮度**：这条 Thread 的某个子智能体停在审批对话框上时改用 spotlight 亮色 Medium——与需要用户处理的行同一套处理，因为那正是它现在的意思，产品停下来在等人。同一条规则也作用在计时上：一条还在计时的行也可能有子智能体卡在对话框上，那一格照样转亮。两档之外不加记号、不加颜色。这**不违反「一行只有一个标记」**：位置只有一个，先给计时，计时没有了才轮到它，两者永不并存。正在跑的行不写这个数字——那一行已经在说这条 Thread 在工作了。Figma 侧因此是同一个文字层的又一个变体，同样必须 hug contents（下文）。产品理由与状态语义见 [`PRD.md`](PRD.md) §6.1 与 §9.3。这两档亮度现在也在 Figma 里：`112:28`（Session Row）新增 `Type=Completed - Subagent Running, Interaction=Default`（`807:91`，暗色 Light，「2 subagents」）与 `Type=Completed - Subagent Awaiting Approval, Interaction=Default`（`807:102`，spotlight 亮色 Medium，「1 subagent」），行内容与既有 `Completed` 变体不变，只有尾部这一格不同。两个节点的文字层是 Inter 而非 SF Pro，§3.1 记着原因与待办；仅有 `Default` interaction——`Hover`／`Pressed` 沿用既有 `Completed` 变体那一套背景处理，不单独复制。

**同一件事在收起态是另一种画法，规矩相反：那里两者并存。** 行尾的一个位置属于一行，收起态的尾翼属于整张列表，所以它说的是总数，也没有「同一句话说两遍」的问题——计时说的是最长的那个轮次，计数说的是列表里还有几个子智能体在跑。计数大于零时写在计时前面，`2 │ 1:23`；所有轮次都结束而子智能体还在跑时没有计时可读，尾翼只剩 `2`。分隔符是 `U+2502`（BOX DRAWINGS LIGHT VERTICAL）两侧各一个普通空格，不是 ASCII 竖线——SF Pro 里两者宽度相同，取前者是因为它是一条分隔规则而不是一个字符。整串与计时同色同字号（暗色 Light，等宽数字），画在同一个 layer 上：一秒一变的只是它的计时那一半，拆成两个视图会让面板宽度由两次可能互相矛盾的测量组成。收起态写 `Running` 而尾翼没有计时读数，是这一形态的正常样子而不是缺口（[`PRD.md`](PRD.md) §6.2）。**还有一种更短的形态：`Running` 而整条尾翼什么都没有。** 它出现在 Claude Code 的子智能体收尾到父轮次被叫醒之间——实测 50–130 ms——此刻既没有轮次在计时，也没有子智能体可数，而这条 Thread 确实还在工作（`PRD.md` §6.2 第 3 档）。它太短，不值得为它画一个变体：要点是尾翼**空**着不等于状态词错了，读到这个组合时不要去补一个占位读数。`115:82`（Panel）新增 `Mode=No Notch Compact, Content=Working With Subagents, Menu Bar=46 Reference`（`808:527`）示范这个合成读数，宽度仍是无刘海工作集合共用的那个定宽（§6.4）；文字层同样是 Inter，且分隔符暂以 ASCII `|` 代替 `U+2502`（Inter 在本文件里没有这个字形），两处都记在 §3.1 与该节点自己的 `description` 里。有刘海形态的等价变体未新增——它的宽度会随内容变化，直接改 `PanelContour` 矢量会破坏两个圆角比例（见 §3.3），留给下一次同步。

收起态在刘海右侧显示全局最长运行时间，与左翼状态读数构成两翼；没有未完成轮次、也没有子智能体在跑时右翼整体消失，避免渲染出第二个假刘海。展开态不重复该汇总值。计时文本使用等宽数字，因此右翼宽度只在进位时变化。

**前导翼的处置按形态分开**（§6.4）：没有任何智能体已连接时，有刘海形态连前导翼一起去掉、只剩 `200` 遮挡；无刘海形态保留前导翼，画一个灰色矩阵加 `Disconnected`——菜单栏里消失的控件会带走自己的位置，因此这里保住位置比省掉一条翼更重要。

收起态宽度不是设计常量：实现按真实渲染文本测量后向上取整，宽度是布局的结果而不是谁定下的数值。因此 **Figma 变体中的计时与状态文字层必须 hug contents，不得写死宽度**。写死是唯一需要记住的失败模式——上一次同步把计时 TEXT 固定为 `34`（自然宽约 `28.6`），刘海计时变体因此整体偏宽 `5.4`；无刘海一对同样因固定文本宽度偏出十余 pt。

可以直接对照的固定值只有一处：刘海形态左翼 = `12` padding + `16.6` 状态矩阵 + `8` clearance = `36.6`，加 `200` 遮挡后收起态总宽为 `237`。计时文本从 `x = 244.6` 开始（`36.6 + 200 + 8`），宽度随文本自身变化——尾翼里出现子智能体计数时同样只是这个文本变长，右翼跟着变宽。无刘海那个定宽为计时预留的槽位是 `00:00:00`（Medium，`57.9`），装得下 `2 │ 1:23`（Light，`45.7`）这样的组合；装不下的组合（`2 │ 1:23:45` 是 `65.5`）让胶囊自己变宽，而不是把计数裁掉——那是**唯一**一处内容能推动这个定宽的地方，为一个几乎不会出现的读数长期加宽每一个菜单栏里的胶囊才是更糟的那一边。由 `theCollapsedCountGrowsTheSlotItSharesWithTheTimer` 锁定。无刘海形态不再按内容组合：整个工作集合共用一个定宽（§6.4「固定工作宽度」），也不再有随菜单栏高度变化的宽度下限——`PanelMetrics` 中已没有任何一处拿菜单栏高度算宽度，它只决定面板高度与圆角。这些关系由 `compactGeometryComposesTheNotchWings` 锁定，其余宽度不写入契约。

> 本段此前写过两轮旧数字：`18.4` / `50.4` / `251` 是矩阵改用 `16.6`（`13 × 1.2778`，见 `PanelMetrics.statusMatrixSize`）之前的；`48.6` / `249` 是两侧内边距还是 `24` 时的。内边距收到 `12` 之后（`PanelMetrics.expandedHorizontalPadding`），左翼为 `36.6`、总宽为 `237`，`compactGeometryComposesTheNotchWings` 断言的正是 `237`。§6.4 的宽度表用 `16.62` 记 `16.6` 这同一个值；两者差 `0.02`，ceil 之后的宽度完全相同，所以下表不受影响。

## 5. 实时监视列表

### 5.1 成员语义

一行代表一个可导航根 Thread。Running、Input needed、Approval needed 始终显示；Completed 只在该产品的桌面端仍认为用户没看过时显示，桌面端已读、归档、删除或失去可导航性后自动移除。**终端里的 Claude Code 会话没有已读可读**，它的 Completed 行留到该会话的下一次提交、会话消失或用户手动移除（在该行上右键；~~清空列表~~ 全清已删除，见 §8.2）为止（见 [ADR 0012](adr/0012-read-state-is-answered-per-product-or-not-at-all.md)）——注释卡必须写出这条差异，否则设计稿看起来像是所有行都会自己消失。

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

这四行取的都是产品已经显示给用户的那一份。raw reasoning、工具参数、命令输出和 diff 不在其中，不是因为不许取，而是因为这条路径没有去取它们——要显示得先加一次读取，那是一个按价值判断的新功能（见 [`PRD.md`](PRD.md) 第 7 节）。

## 6. Integration States

`07 — Integration States`（`227:3`）包含：

### 6.1 Content previews hidden（已退休）

板上这一格画的是预览开关关闭后的行。该开关连同它兑现的隐私承诺已经删除（[`PRD.md`](PRD.md) 第 7 节），预览始终显示，因此这一格不再对应任何可达状态。板上保留，不再是验收项。

### 6.2 Quota unavailable

额度环为灰色 unavailable，但会话列表、状态和点击能力继续工作。该场景表达局部降级，不是 Disconnected。

### 6.3 Monitoring lifecycle

注释卡明确：提交输入后入列；活动 Turn 始终保留；终态只在桌面端仍未读时保留；已读、归档、删除或失去可导航性后自动移除；Notch 不主动标记已读；**已读无从回答的终态行（终端里的 Claude Code 会话）不参与自动移除**。

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

**「有刘海、静息」这一格也是 `Hide the wings` 打开后的收起态。** 该偏好（§8.4）把这一格从「没有任何产品连接时」推广到任何时候：矩阵与计时都不画，收起态宽度恒等于遮挡宽度。它只改收起态，hover 那一列一个字都不变。因此这一格的两条理由也原样继承——有刘海屏的缺口本来就是屏幕上的一个形状，旁边再放一个不携带信息；缺口量不出来的屏（无刘海，或报了刘海却量不出遮挡宽度）没有可以缩上去的形状，所以那一行在设置里是置灰的。

**hover 只横向展开药丸，不落下面板。** 没有智能体连接时面板里没有内容可放，展开的唯一目的是让齿轮可达；原因写在 Settings 里，齿轮离它只有一个动作。

> **实现记录：** 上表的 `400 × 46` / `208 × 46` 与本节 §6.8 清单里的 `400.6 × 46` / `224.6 × 46` 互相矛盾，两处都没有给出组成关系。实现按本文其余宽度一致的办法**按组成计算**（`PanelMetrics.restingExpandedWidth`）：前导内边距 `12` + 矩阵 `16.6` + 间距 `12` + `Disconnected` `82.96` + 间距 `12` + 齿轮 + 尾部内边距 `12`，有刘海形态在中间插入 `8 + 遮挡 + 8`。齿轮随菜单栏缩放（`46pt` 下 `32`，`24pt` 下 `20`，见 [`dual-agent-design.md`](dual-agent-design.md) §5.3），因此本机 `46pt` 菜单栏下得到无刘海 `179.56 → 180`、有刘海（`200` 遮挡）`395.56 → 396`。内边距还是 `24` 时这条关系给出的是 `204` / `420`，那两个数已经过期；`10 — Double Apps` 的 `08 — Presence` 已按 `396` / `180` 重画。上屏后若与图不符，改的应是这条组成关系，而不是把数字写死。

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

这同时了结了 [`dual-agent-design.md`](dual-agent-design.md) §8 里登记的那条：`Update Claude Code` 曾把双产品药丸从 `189` 顶到 `202`。它退出收起态后不再参与定宽；即便日后回来也仍然装得下——`12 + 16.62 + 12 + 124.77 + 12 = 177.4`，在 `196` 之内。（`Update Claude Code` 本机实测 `124.77`，与 §8 已记录的 `124.8` 一致，这是上表其余数字可信的依据。）这一整段现在只剩历史意义：`Update Claude Code` 这个标签本身已经不存在，`updateAgent` 无论收起还是展开都说不指名产品的 `Update` / `Update required`，见 §6.6。

### 6.5 openness 如何判定

两个信号在代码里都已存在，且都不是为此新写的——一个用于退休会话已死的行（`SessionEnd` 被刻意不注册），另一个本来就是每次刷新都要取的：

| 产品 | 「打开」的含义 | 来源 | 现有实现 |
| --- | --- | --- | --- |
| Codex Desktop | 应用正在运行 | `NSRunningApplication.runningApplications(withBundleIdentifier:)`；每次刷新取一次，本来就已经在取，用于把实时 Hook 绑定到同一个 Desktop 进程生命周期 | `LiveCodexMonitorService.swift:990` |
| Claude Code | 至少有一个活跃会话 | `claude agents --json`，经 `ClaudeCodeSessionListing.liveSessions()`。没有应用可问，会话列表就是在场信号 | `ClaudeCodeSessionRegistry.swift` |

`ClaudeCodeSessionRegistry` 自己的契约就是这里需要的那条界线：它的输出无论会话正在处理还是空闲都逐字节相同——它回答「有哪些会话」，Turn reducer 回答「它们在做什么」。**在场画出矩阵，reducer 点亮它**，两者不得重新合并。

`Connected` 继承 tech-design 已经为 `Idle` 写下的规则：只有当前态来源确认集合确实为空时，空集合才能被读成「没有东西在工作」，绝不能在看不见时这样读；否则 `Connected` 就成了新的谎言。

有一处不对称值得刻意保留：Codex 的在场在本应用启动的瞬间就可知，它的处理轮次不可知（产品刻意不显示启动前的任何东西）。因此刚启动的应用可以诚实地为 Codex 显示 `Connected`，而此时它对工作还一无所知——这比今天显示一片空白严格更好。

在场的可信度按产品不同，只有 Claude Code 一侧需要额外规则：`NSRunningApplication` 是内核事实，不存在缓存与过期；`claude agents --json` 背后是 `~/.claude/sessions/<pid>.json`，每个会话一个文件，**没有心跳字段，mtime 也不更新**，因此文件本身无法自行过期。两处后果：

1. **幽灵会话——已实测，官方命令自己做掉了，而且用的正是那条正确的判据。** 被 `SIGKILL` 的会话确实来不及删除自己的文件，所以这个担心是对的；但 `claude agents --json` 并不会列出它。实测 2.1.229：把一个活会话的文件逐字节复制、**只改 `procStart`**，它就从输出里消失；写一个指向活着但不相干进程（`pid 1`）的会话文件，同样消失。也就是说该命令按 `pid` + `procStart` 成对校验——正是这里需要的判据，也正是只查 `kill(pid, 0)` 会被 PID 回收骗过的那一条。

    因此本应用**不重做、也不应重做**这条校验：`--json` 根本不输出 `procStart`，要自己判断就必须改去直接读 `~/.claude/sessions/<pid>.json` 这套私有 schema，等于为了复制一条已经正确的公开实现而登记一项非公开依赖（`AGENTS.md` §8）。结论记在 [`ClaudeCodeSessionRegistry.swift`](../Notchline/Notchline/ClaudeCodeSessionRegistry.swift) 的 `runOfficialCommand` 注释里。
2. **我们自己的缓存没有上限。** `ClaudeCodeSessionRegistry.refresh()` 在读取失败时返回上一次结果且不更新 `readAt`。这对「行」是对的（一次失败不该退休所有行），但在场现在决定 `Connected` 与 `Disconnected`：只要 `claude` 被卸载或改名，读取会永久失败，而药丸会永远显示 `Connected`。因此「多久重读一次」（`freshness`，`30` 秒）与「陈旧答案还能被相信多久」必须分开，后者建议 `90` 秒（三次连续失败）。

超过上限时在场是**未知**，而未知落到 `Disconnected`。按 §6.7 的语义这不是妥协而是字面真相：我们确实没有任何可用的连接。这与 tech-design 为 `Idle` 写下的规则是同一条，只是对称地用在非空集合上。

### 6.6 已退休的薄层状态

| 已退休 | 去处 |
| --- | --- |
| 静息的熄灭产品矩阵 | 直接删除。灰槽不指认任何产品 |
| `Idle` / `No active sessions` | 并入 `Connected`（§6.4） |
| `Connecting to Codex` | 删除。在场由系统 API 直接回答，没有需要向用户解释的等待 |
| `Update Codex` | 设置里的产品行，以及用户打开时的展开面板；名字里的产品已去掉，见下 |
| `Codex version unsupported` | 同上 |
| `Set up integration` | 引导流程，以及设置里的开关 |

`Codex disconnected` 不退休，而是被重新定义为 `Disconnected`，见 §6.7。薄层 `520 × 94` 只保留给展开面板。

**去处保留，但去到那里的句子不再指名产品。** `Connecting to [产品]`、`Update [产品]`、`[产品] version unsupported`、`[产品] disconnected` 四句一律改为 `Connecting`、`Update required`、`Version unsupported`、`Disconnected`：**哪个**产品不健康是设置窗口的事，那里逐行列着每个产品和它自己的状态，刘海不必替它说。这条同时了结了展开面板的按产品定宽（§3.3）——最宽的整句从 `Claude Code version unsupported` 变成 `Version unsupported`，单侧收窄 `79.55`。

### 6.7 `Disconnected` 的定义

在场与可观察性现在是两件独立的事实，因此可以互相矛盾。「打开了但监视不到」是普通的首次运行，而不是边缘情况：两个产品的 hook 注册都由用户在设置里拨一下开关才发生（[ADR 0016](adr/0016-write-the-users-claude-code-settings-and-keep-a-copy.md)），所以一台刚装好的机器上，产品开着而这里够不着它是常态。~~此前这句的理由是 Claude Code 的注册留给用户自己粘贴（ADR 0010）；写入能力收回来之后理由变了，结论一个字没动。~~两个状态必须覆盖它，且不能变成三个。

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

现行设计是 `08 — Onboarding` 上的 `First run — one window`（`750:2`），**一个 `580` 宽的窗口**，浅色与深色是同一批节点。`232:95` 的三窗口流程保留为 v1 参考，不再是验收对象。

三个窗口各自只承载一个决定：价值、同意、确认。但同意就是那个开关，确认就是那一行变绿——另外两个窗口是围着两个控件说的话。合成一页之后，腾出的位置留给了这个流程从来没讲过的东西：刘海到底画了什么。

窗口用的是设置窗口的全部形状（§8.0：`22` 组间距、`8` 组标题到卡片、卡片圆角 `12`、行内边距 `14 × 11`、胶囊按钮），因为它**就会变成**设置窗口——同一个 scene 在 `hasCompletedOnboarding` 前后分别显示 `OnboardingView` 与 `AppSettingsView`，第二次打开时不该有任何东西移动过位置。标题栏写 `Welcome to Notchline`，内容区不再有第二个标题。

自上而下：

1. **Hero**：应用图标 `52` 加一句话，不重复窗口标题。
2. **`Connect your agents`**：`ProductConnectionRows`——与设置窗口**同一个视图**，不是它的副本。**两行各一个 switch**（[ADR 0016](adr/0016-write-the-users-claude-code-settings-and-keep-a-copy.md)）；~~此前是 Codex 一个 switch、Claude Code 一个 `Set Up…`，两行并排正是 ADR 0010 的不对称唯一被看见的地方~~——那处不对称已经没有了。脚注写清两个开关写进 `~/.codex/hooks.json` 与 `~/.claude/settings.json` 的定义可逆、不动用户自己的设置与 hooks，并写明改动任一文件之前会先在同目录复制出一份 `.notchline-backup` 副本；尾部是 `Recheck`：Codex 那个开关打开还不是终点，它按定义在文件里的位置记信任，要用户在 `/hooks` 里信任之后跑过一轮，那一行才会说 `Connected`。Claude Code 没有这一步。
3. **`Reading the notch`**：四个规格件加四个状态名，**没有解释句**——一个叫 `Running` 的状态不需要一句话说明有一轮正在跑。规格件按 `PanelMetrics.statusMatrixSize`（`16.6`）画在一小块黑底上，是实物而不是示意图，并且**是活的**：轨道是 render server 上的图层动画，`Connected` 自己就不动（它的 state 没有 period）。
4. **颜色键**：两个单色规格件加两个产品名，落在与上面四列相同的栅格上。

**规格件按 mark 的对角线切成两色**（Codex 在上、Claude Code 在下），这是引导独有的画法：刘海上每个矩阵只属于一个产品，因为色相正是用来分辨两个矩阵的。切开是为了让一行四个讲完四种图案，而不是两行八个——那会说成图案随产品而变，而它并不变。实现见 `NotchPalette.MatrixSplit` 与 `MatrixIndicatorView.trailingHalf`；接缝方向由 `theSplitMatrixCutsOnTheSameDiagonalAsTheMark` 锁定，因为四种图案上下都对称，`isFlipped` 画反了没有任何别的东西会发现。

窗口不请求辅助功能或屏幕录制，也不承诺静默绕过 Codex 信任。底部一行是那句只读声明加主按钮 `Start`，**不设门槛**：一个产品都没连也可以进去，刘海会照实说 `Disconnected`。

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

板上三个分组自上而下是 `Products`、`Session list`、`Privacy`；实现现在是 `Products`、`Display`、`Session list` —— `Privacy` 已删除（§8.3），`Display` 板上没有（§8.4）。每个分组的形状都是「小标题 + 一张圆角卡片 + 卡片下方的脚注文字」。脚注取代了 v1 的蓝色提示条——macOS 用脚注而不是色块陈述后果，色块在原生窗口里只会读作一个没人点得动的控件。

窗口最后一行是 `closing note`：左边是那句只读声明，右边是胶囊按钮 `Quit Codex in Notch`。它与 `Recheck` 同形不是巧合——两者都是「说明文字尾部挂一个它所说的那个动作」。退出不属于任何一个分组：它不是一项设置，而它要收走的那个组件也没有自己的窗口可关，Settings 是唯一能承载它的界面。这一行不加内缩（分组脚注的 `2 pt` 左内缩只属于分组），因此它与三个组标题落在同一条竖线上。

所有主标签共用同一左缩进：产品行的绿色状态点移到说明行行首，而不是站在产品名左边，因此三张卡片的标题列在同一条竖线上。

浅色与深色是**同一批节点**：颜色全部绑定到两模式集合 `Color / macOS Window`（`Light` / `Dark`），深色窗口是浅色窗口的 clone 加一次 mode override。改一次颜色两边同时生效，不存在两套值漂移的可能。实现侧对应 [`SettingsWindow.swift`](../Notchline/Notchline/SettingsWindow.swift) 的 `MacOSWindowColor`：每个 token 是一个 `NSColor(name:dynamicProvider:)`，一次声明同时回答两种外观，这是两模式集合在代码里的等价物。状态点例外，取系统色 —— `status/green` 的两个值本来就是 `systemGreen` 的两个值，用系统色还能跟随「增强对比度」。

**标题栏按 macOS 自己的样子渲染，不按本表这一行。** 板上的标题栏与窗口同色、高 `52`、不画分隔线；SwiftUI 持有 scene 窗口的标题栏并在每次布局重新应用自己的配置，`titlebarAppearsTransparent`、`backgroundColor`、`titlebarSeparatorStyle` 与 `.fullSizeContentView` 实测全部无效。剩下的做法是 `.hiddenTitleBar` 加自绘 `52` 色带与居中标题——那会让「用原生控件而不是它们的近似物」这个论点里最显眼的一块变成唯一的近似物。因此标题栏保持系统材质，`52` 是板上的排版约定而不是验收项。

**窗口如何出现：永远在最前，居中落在 Notchline 所在的那块屏幕上。** 板上没有这一条，它是交互而不是版面，写在这里因为它决定用户第一眼在哪看到这扇窗。本应用唯一常驻的界面在刘海里，所以打开 Settings 的请求几乎总是在别的应用处于前台时发出——SwiftUI 只把窗口排到本应用之内，从外面看就是「点了齿轮什么也没发生」。因此打开时先激活应用，再把窗口排到最前。落点取**组件此刻所在的那块显示器**（`Show Notchline on` 选中的那块，按标识符而不是按 frame 匹配到 `NSScreen`），而不是持有键盘焦点的那块：这扇窗改的每一样东西都只在刘海里看得见，其中一项就是「刘海在哪块屏」；而且它是一个在排窗过程中不会变的答案，焦点那块屏从来不是——晚一步问，答案就是 Settings 自己那块屏，等于把问题重述一遍。**每次打开都放一次**，不再只在跨屏时放：横向居中、余量的三分之一留在上方，也就是 macOS 自己居中窗口的落点；代价是用户自己拖过的位置会被覆盖，这是明知而选的一边。选中的那块屏此刻不存在（刚被拔掉，store 还没跟上）时退到 `NSScreen.main`。**摆放永远发生在窗口还看不见的时候**：视图刚进入窗口时摆一次（早于 SwiftUI 把它排上屏），窗口每次被隐藏时再摆一次，于是下一次出现的第一帧就在正确位置；摆在出现之后就是用户看到的那一下闪。窗口留在别的 Space 时取到当前 Space，而不是把用户送过去。实现见 [`SettingsWindow.swift`](../Notchline/Notchline/SettingsWindow.swift) 的 `SettingsWindowPresenter` 与 `SettingsWindowPlacement`。

### 8.1 Products

`Codex Desktop` 与 `Claude Code` 是同一张卡片里的两行，不是两个分组。加入第三个产品的代价是一行，而不是一个新面板。

- 每行左侧是产品名，说明行以状态点开头，写连接结论与能力信息（`Connected · compatible version`、`Connected · hooks installed`）。
- **说明行下面还可以再有一行，写该产品自己报出的失败，板上没有，这是实现与板不一致的第三处。** 例如 `Ignored 2 hook payloads that could not be read.`、`Claude Code is not running the PreToolUse hook, so Input needed and Approval needed cannot be shown.` 它**只在有话说的时候出现**：一行为了不存在的失败常驻的空行，读起来就像那个失败正在发生。这一行是本窗口里唯一为「报告失败」而存在的东西——集成失败在本产品里天然安静，界面会照旧写着 `Connected`——所以它按本次运行累计、而不是报一次就清（[`PRD.md`](PRD.md) 第 12 节、CR-029）。它与 `Quota reading transcripts` 那一行的「卡片会自己长出一行」是同一个代价，区别在于这一行长出来的时候，用户正需要它。
- Codex 行右侧是一个原生 macOS switch，启停该产品所需的 lifecycle event 定义；切换进行中 disabled。
- **Claude Code 行也是一个 switch，实现与板上的双 switch 就此对上了。** ~~此前那一行没有 switch：ADR 0010 决定本应用永不写 `~/.claude/settings.json`，于是它的尾部是胶囊按钮 `Set Up…`，展开卡片内的粘贴路径、JSON 片段、`Copy` 与 `Reveal Settings File`；两行并排是那处不对称唯一被看见的地方。~~ [ADR 0016](adr/0016-write-the-users-claude-code-settings-and-keep-a-copy.md) 把写入能力收了回来，粘贴卡片、片段与两个按钮一并删除。板上原本注为「若日后恢复写入能力」的那个形态，就是现在的实现。
- 卡片下方脚注说明每个开关只安装 Notchline 需要的定义（Codex **七项**），关闭时移除，用户其他设置与 hooks 不受影响，并写明改动任一文件之前会先把它复制到同目录，副本名是原文件名加 `.notchline-backup`。此前这里只写了 Claude Code 那一份，而 Codex 那份副本一直在写；~~再之前是把 `hooks.json.notchline-backup` 与 `settings.json.notchline-backup` 两个全名都列出来~~——两个全名念的是同一条规则的两个实例，却占掉脚注一半的长度，全名留在 [ADR 0016](adr/0016-write-the-users-claude-code-settings-and-keep-a-copy.md)。这里此前写的是「六项」，与实现不符：`CodexHookVocabulary.managedDefinitions` 当时注册的是 `UserPromptSubmit`、`PermissionRequest`、`PreToolUse`、`PostToolUse`、`Stop` 五项，`SessionEnd` 是**故意不注册**的；加入 `SubagentStart` 与 `SubagentStop` 之后是七项。Claude Code 那边是十三项：`Notification` 的类型实测完毕后已退掉注册（CC-011），`SessionEnd` 同样故意不注册，而 `SubagentStart` 与 `SubagentStop` 在那边也注册——它的 `Agent` 调用同样会留下活得比轮次更久的子智能体。
- **卡片里还多一行 `Quota reading transcripts`，板上没有，这是实现与板不一致的第二处。** 读取 Claude Code 额度的每一次调用都是一个真实会话，因而在 Claude Code 自己的 project 目录里留下一份约 `3 KB` 的 transcript，没有任何东西会清掉它们。这一行报出它们的总大小（`43.2 MB`），尾部是文件夹图标按钮 `Show in Finder`（见下一条）。**只报大小，不报个数。** 曾经写作 `43.2 MB · 1,284 files`，而个数那一半回答的是没人会问的问题：这一行存在是为了让人判断这堆残留值不值得去清，散落在多少个文件里并不改变那个判断；真想数的人离那个目录只有一个按钮。
  **这一行从第一次刷新起就在，哪怕那时还没有数字可写。** 那个目录不是推导出来的而是找出来的——要等一次额度读取跑完（几秒的子进程）才知道它在哪。在此之前这一行原本根本不存在，于是卡片会在用户刚把窗口打开时自己长出一行来。现在改为把状态画出来：数字的位置写 `Calculating…`，`Show in Finder` 同时置灰（此刻它没有地方可去，一个揭示不了任何东西的按钮比一个明显还没准备好的按钮更糟）；读取落地后换成数字并恢复可点。读取已经跑完却仍未找到目录——机器上没有 `claude` 就是这种情况——写 `Unavailable` 而不是继续写 `Calculating…`：后者是一句关于正在进行的工作的话，而那件工作已经结束了（CC-020）。
  **只报不删，这是决定而不是省事。** Claude Code 给 project 目录起名的规则未公开，且压平分隔符与空格后并非一一对应（实测 `…/a b` 与 `…/a-b` 同属一个目录），因此那个目录里可能同时躺着用户真实项目的会话记录。把数字摆在用户眼前、并把门打开，比替他们删要正确。这一行与 `Display` 分组同类：既有行为在新形状里的安置，不是往设置里塞新功能。
- **卡片里三行各有一个 `Show in Finder`，是一个文件夹图标而不是一行字，板上没有，这是实现与板不一致的第四处。** 每一行都在讲磁盘上的一个地方：两个产品行讲的是各自 hooks 注册所在的那个文件（`~/.codex/hooks.json`、`~/.claude/settings.json`），`Quota reading transcripts` 讲的是额度读取留下 transcript 的那个目录。点下去打开那个文件所在的文件夹，并在里面选中它。
  **图标而不是胶囊按钮，理由是数量。** 这个动作原本只有 transcripts 那一行有，写作胶囊按钮 `Reveal in Finder`；三行都有之后，同一句话在一张卡片里竖着写三遍，而且就压在每个产品行真正要讲的那个开关旁边。图标用四分之一的宽度承载同一个动作，句子搬进 tooltip（`Show in Finder`）。**它同时是无障碍标签**：按钮由 `Label` 加 `.iconOnly` 画出而不是一个裸 `Image`，因此 VoiceOver 念的是 `Show in Finder`，不是某个 SF Symbol 的名字。
  **不画边框，鼠标移上去才有底。** 符号按 `12 × 12` 量着画（实测落在 `12 × 9.5`，第二个数是文件夹自身的长宽比装进方框的结果），点击区 `22 × 22`（那是点击区不是画面：按图形自身尺寸取点击区，就成了一个要瞄准的东西）。**「`12` 号字」与「`12` 点大的图标」不是一回事**：SF Symbol 写 `.system(size: 12)` 是让它跟 `12` 号**正文**并排时协调，`folder` 在那个配置下实测 `17 × 13`；因此这里用 `resizable` 把字形自身的框缩进 `12 × 12`，写下的数字就是屏幕上的尺寸，底是圆角 `5` 的一块，浅色 `black 7%`、深色 `white 10%`，只在 hover 时出现；置灰时连 hover 底也不给——按不动的东西不该在指针下亮起来。围着一个符号画一圈胶囊，等于在开关旁边再立一个形状与它争这一行的主控件位置；不画边框，它就读作它本来的样子——一个通往别处的入口，而「可以按」这件事在有人问的那一刻（指针移上去）才回答。
  **位置在每一行的最后，开关之后。** 三行都以它收尾，因此三个图标落在同一条尾缘上、竖成一列——这只有在它后面不再有别的东西时才成立。~~此前放在开关之前，理由是「开关该留在尾缘」；代价是 transcripts 那一行没有开关，它的图标落在尾缘上，三个图标站在两个横坐标上。~~ 那一处不齐换成了「开关不在尾缘」：开关因此整体内移一个固定步长，仍然自成一列，而一个连边框都不画的符号不会被读成这一行的主控件。三个同类图标对不齐，比开关离尾缘一段距离更显眼。
  **文件可能根本不存在，而那是常态不是错误。** `~/.codex/hooks.json` 与 `~/.claude/settings.json` 都要等有人（本应用或用户）往里写过东西才存在，因此开关从没打开过的那一行指着的是一个末端没有文件的路径，而 `activateFileViewerSelecting` 对这种路径什么也不做、且不出声。于是：文件在就选中它，文件不在就打开本该装着它的那个文件夹，两者都不在才置灰——置灰的判据仍然是「有没有地方可去」这一个来源，与 transcripts 那一行同一条规则（CC-020）。
- `Recheck` 是脚注行尾部的胶囊按钮，重新检测能力。
- Off 后保持 Settings 可达；再次 On 安装或修复完整集合。首次安装或定义变化后的 `/hooks` 信任仍由 Codex 处理。

### 8.2 Session list

弹出菜单 `Distinguish products`，值为 `Name and colour`（默认）／`Name only`／`Badge`／`Colour bar`，语义见 [`dual-agent-design.md`](dual-agent-design.md) §6。脚注说明它只在两个产品都已连接时有效果（不要求两个产品此刻都有会话，见 [`dual-agent-design.md`](dual-agent-design.md) §4）；单产品时该项仍然可见但无效果，隐藏它会让用户恰好在准备接入第二个产品时找不到它。

**卡片只有这一行。** ~~卡片里还有第二行 `Clear the session list`，尾部胶囊按钮 `Clear`，列表为空时 disabled。它在 v1 是 Codex 卡片里的一枚破坏性按钮；产品分组现在只讲产品，而这个动作的对象是会话列表，它属于这里。板上没有这一行，因为板只画了三个已确认的**设置**，而这是一个动作。~~ 在终态行上右键移除单行（§17）之后这一行被删掉，**功能本身也一并删除，而不是只把入口撤走**（`tech-design.md` §16.2 记了删掉的符号）：两者本就共用同一份移除记录，而右键是在用户看着那一行的时候给出的；一个设置窗口里的「全清」要先把窗口打开，然后对一批用户此刻没有在看的行动手，其中可能有一行是他还没读的答案。卡片因此回到板上的形状——只有 `Distinguish products` 一行。

### 8.3 Privacy（已删除）

板上有这一组，实现里没有。`Show current content previews` 唯一的用途是兑现一条已经作废的隐私承诺（[`PRD.md`](PRD.md) 第 7 节），开关、`PrivacySettings` 与 `privacySafeTitle` 回退一并删除，窗口因此少一组。板上保留为历史形态。

### 8.4 Display

板上没有这一组，实现里有，位置在 `Products` 与 `Session list` 之间。卡片里现在是两行。

`Show Codex in Notch on` 是一个已经存在的控件：组件只出现在一台显示器上，由用户选定，说明行报出该显示器的形态与真实菜单栏高度（`Notch display · 39 pt menu bar`）。删掉它会拿走一个真实功能，所以它按同一形状留下——小标题、一张卡片。**没有脚注**：~~脚注写的是「组件占用所选显示器的菜单栏，并随之取得它的几何——一处要绕开的缺口，或者没有缺口时的一枚胶囊」。~~两行的说明行都已经就当前选中的那台显示器报出了结论——形态与菜单栏高度，以及为什么这块屏上收不起翼，脚注只是把同一件事抽象地再说一遍。

#### `Hide the wings`

| 标签 | `Hide the wings` |
| --- | --- |
| 控件 | 原生 macOS switch，默认 off，跨启动记忆（`hidesCompactWings`） |
| 说明（有刘海） | `Collapsed, Notchline is the cut-out and nothing else — no marks and no timer. Hovering still opens the panel.` |
| 说明（无刘海，置灰） | `Needs a notched display. Without a cut-out to hide behind there would be nothing left to hover.` |
| 说明（有刘海但量不出，置灰） | `This display reports a notch but not where it is, so there is nothing to shrink the collapsed component onto.` |

收起态因此只剩刘海本身：两侧的翼都不画，前导侧没有矩阵，尾侧没有计时，面板本体宽度正好等于遮挡宽度、尾边落在刘海右边缘上。这**不是一个新形态**：§6.4 的「有刘海、静息、什么都不画」画的就是它，这一项只是把那个形态从「没有产品连接时」推广到任何时候。

**只作用于收起态。** hover 照常落下面板，面板照常带着矩阵、会话行与齿轮。刘海是本产品唯一的入口——没有菜单栏项，也没有 Dock 图标（[`PRD.md`](PRD.md) 第 11 节）——把它一起收掉就等于把应用藏死了。

**可用的条件是「量得出的刘海」，不是「报得出的刘海」。** 收起翼意味着把面板本体缩到硬件自己的那个形状上，因此本应用必须确切知道那个形状在哪、有多宽——屏幕上不再有第二样东西可以用来定位它。两种显示器因此不满足条件，理由是同一条说两遍：

- **无刘海屏**：根本没有那个形状。收起药丸会把它在菜单栏里的位置一起带走，而且屏幕上不再有任何形状可供 hover。
- **报了刘海却量不出遮挡宽度的屏**：那个形状本应用定位不了。它本来就因为这一条被当作**模拟刘海**布局（§6.4 与 `PanelMetrics.size`），再往一个宽度读作 `0` 的缺口上缩，得到的是一块零宽面板——什么都不画，也没有东西可以 hover。

**两种情况都置灰而不是隐藏，而且偏好本身不清空。** 隐藏的代价写在 §8.2 同一条论证里：只在有刘海时才出现的开关，恰好在用户刚把外接显示器插上、正想找它的那一刻不见了。置灰的行还照旧说明它会做什么、以及为什么这块屏上做不到——**两种原因分开写**，不并成一句关于缺口的话：内建屏报了刘海却定位不了，与外接显示器根本没有刘海，是两种处境，而在一台 MacBook 上看到 `Needs a notched display` 底下压着一个灰开关，用户只会得出「这应用坏了」。偏好属于用户而不属于此刻插着哪块屏，因此换屏只置灰，换回来即恢复。

这不是「加入尚未确认的功能」的例外：下面那条禁止的是把没定过的功能塞进设置，而 `Show Codex in Notch on` 是既有功能在新形状里的安置，`Hide the wings` 是同一张卡片上就近增加的一项显示偏好——它不新增任何被监视的对象，也不改变任何状态判定，只决定收起态画多少。板与窗口的差异记在这里，等板更新时一起消掉。

不在 V1 设置画板中加入登录启动、动画、通知、模型选择或其他尚未确认的功能。

## 9. 交互

### 9.1 展开/收起

- Hover intent 参考 `150 ms`。
- 展开参考 `180–220 ms`。
- 鼠标离开后参考 `250 ms` 收起。
- Escape 立即收起。
- 所有中间帧保持相同 `maxY`。水平方向上，展开态与无刘海形态保持相同 `midX`；带刘海的收起态锚定缺口右缘（§3.4）。
- Reduce Motion 下使用短淡入淡出，不使用明显弹簧或缩放。

#### 状态名在两种形态之间的交接

收起时状态名同时换字与换宽：`Approval needed` → `Approval`、`Input needed` → `Input`、`Update required` → `Update`。两件事必须走同一条曲线。字先换、宽后收，短字形就会被拉伸到旧读数的宽度再挤回自己——字形层原先按 `bounds` 定框，而 `CALayer` 的 `contentsGravity` 默认就是拉伸。

约定：

- 字形永远按**自己的光栅尺寸**定框，左对齐、垂直居中。被动画的只有它外面的视图，视图对字形做裁剪；被裁掉的部分正是那句「所有中间帧保持相同 `maxY`」在水平方向上的对应物。
- 旧读数留在新读数**之上**淡出，时长与曲线与面板一致（`PanelMotion`：`200 ms` / `cubic-bezier(0.22, 1, 0.36, 1)`，Reduce Motion 为 `80 ms`）。收起时被丢掉的那个词就在关闭的边缘下淡出，而不是凭空消失。
- **一个读数是另一个的前缀时，新读数不淡入。** 共有的字形是同一批像素、同一个位置，再叠一层淡入只会让一个从没动过的词暗下去一趟（合成后最低约 75%）。只有两个真正不同的读数（`Running` → `Approval`）才双向交叉淡化。
- Reduce Motion 缩短这次交接而不是取消它：该设置要免掉的是位移，淡化正是用来替代位移的那个东西——面板还在收、字却已经硬切，并不是更安静的做法。
- 计时读数与会话行正文**不参与**交接：它们按自己的节奏整帧替换，替换频率高于淡化时长时叠加起来会糊成一片（见 `system-architecture.md` 第 6 节）。

### 9.2 会话点击

- 点击成功进入相同 Desktop Thread 并收起 Panel。
- Notch 点击本身不改变已读；等待 Desktop 蓝点消失事件。
- 导航失败时 Panel 与行保持，不把打开首页当作成功。
- 会话行不提供批准、回答、取消或归档操作。
- **终态行右键即移除该行**，不弹菜单、不做二次确认：面板在指针离开后就收起，一个只有一项的菜单要用第二次点击去换一个不删除任何东西的动作。其余三态不装这个响应，因此右键落空而不是落在一个决定什么都不做的处理器上。板上没有这一条，因为它没有可画的形态。

## 10. 无障碍

- 所有状态必须有文字或可访问名称，不能只依赖颜色。
- 系统级状态与四个会话级状态使用不同文案与语义。
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
- [x] Quota unavailable 局部降级。
- [x] ~~No active sessions、Connecting、Disconnected、Update、unsupported、setup 薄层。~~ 收敛为 `Disconnected` 与 `Connected` 两个系统状态，见 §6.4 与 §6.6。
- [x] 收起态在场规则与开合序列（§6.4，`624:1560`）：矩阵随智能体打开与关闭出现和离开，第一个产品接管灰槽。**画法已随 [#35](https://github.com/soondubu137/notchline/issues/35) 落地**：每个已连接产品一个矩阵，各自跑自己的曲线；无产品时一个灰色静息标记；有刘海形态静息时整条前导翼消失。
- [x] hover 只横向展开药丸、不落下面板；展开尾部为齿轮。**宽度改为按组成计算**，原因见 §6.4 的实现记录。
- [x] `Disconnected` 按 §6.7 重定义为「没有任何智能体已连接」；灰色取 `#151515`，为界面上最暗值（§6.4）。
- [x] 无刘海药丸在单产品工作集合内固定为 `196`，双产品 `218`，`Disconnected` 为 `136`；宽度用系统字体本机实测（§6.4）。
- [ ] 会话行里的 `alpha fade mask` 仍是 `273` 定宽。行从 `472` 一路走到 `508`、内边距又从 `16` 收到 `6` 之后，渐隐的收尾离右缘比原先远了 `56`；遮罩应该跟着行走，或改为距右缘定距。
- [x] 会话行的边距拆成 `6` 行块缩进 + `6` 行内边距，行内文字因此与状态矩阵、额度规则同落在 `12`（§3.3）；由 `aRowsTextLandsOnTheSameMarginAsTheRestOfThePanel` 锁定。
- [x] 折叠额度块（[`dual-agent-design.md`](dual-agent-design.md) §5.4，Figma §09）：折叠后页脚 `28`、面板恒为 `520 × 314`；`quota fold` 控件 `16 × 16`，两个状态由同一枚 chevron 旋转 `180°` 得到。**已实现**；点击区就是 chevron 那 `16 × 16`（悬停铺 `12%` 白底、圆角 `4`），状态存于 `quotaFolded`。
- [x] `Colour bar` 作为第四个 `Distinguish products` 选项（[`dual-agent-design.md`](dual-agent-design.md) §4，Figma §06）：`2` 宽竖条、圆角 `1`，行内 `x = 0`，高度取该行文字的实高（三行 `53`、无预览行 `33`），不再是行高的一半 `40`。**已实现**；`Distinguish products` 弹出菜单现在是四项。画竖条的那一形态里行块缩进为 `12`、行内边距为 `8`（§3.3），竖条因此与状态矩阵、额度规则同落一条边距。
- [ ] §3.3 的三条 compact 参考基线（`348 × 46`、`168 × 46`、`200 × 46`）在这次改动前就与文件里的组件不一致，本次未一并修正；组件当前是 `237`（刘海静息）、`285`（刘海计时）与 `165`（无刘海）。
- [ ] `Disconnected` 这个词是否保留（备选 `No agents`、`Nothing running`），上屏后判断。
- [x] ~~Claude Code 在场的第一条校正：按 `pid` + `procStart` 成对过滤幽灵会话。~~ **实测后撤销：`claude agents --json` 自己就是这么校验的**，而且它不输出 `procStart`，自己重做只能改读私有 schema。见 §6.5。
- [x] Claude Code 在场的第二条校正：为陈旧缓存设上限（`90` 秒 = 三次连续失败），超过后在场为未知并落到 `Disconnected`。`freshness` 与 `trustCeiling` 现在是两个参数。
- [x] 首次安装三步流程。
- [x] Settings 预览 On/Off 与集成管理。
- [x] Settings 已按 macOS 26 重做为单面板窗口，浅色与深色由 `Color / macOS Window` 的两个 mode 驱动。**实现已落地**（[`SettingsWindow.swift`](../Notchline/Notchline/SettingsWindow.swift)），与板不一致之处均已记录：标题栏保持系统材质（§8.0）、Claude Code 行是 `Set Up…` 而不是 switch（§8.1）、Products 卡片多一行 `Quota reading transcripts`（§8.1）、产品行说明行下多一行失败报告（§8.1）、Products 三行各多一个 `Show in Finder` 文件夹图标（§8.1）、多一个 `Display` 分组、且该分组是两行而不是一行（§8.4）、少一个 `Privacy` 分组（§8.3）。~~多一行 `Clear the session list`（§8.2）~~ 这一处已经消掉：那一行被右键移除单行取代后删除。
- [ ] 在装有 SF Pro 的 Figma 桌面端打开 `609:2`，确认字形正常渲染、多行脚注的换行落位与预期一致。
- [ ] 同一次打开时，把 `closing note` 的四条 Inter 文字（`665:3`、`665:5`、`667:3`、`667:5`）重新键入为 SF Pro Regular，原因见 §3.1。
- [x] 会话行已同步 Running／等待人工／Completed 三种计时表现，一行只有一个标记。
- [ ] 收起态计时变体的文字层改为 hug contents（见 4.6），消除固定文本宽度带来的整体偏宽。
- [ ] 刘海计时变体中的计时 TEXT 在渲染中不可见（节点数据正确、坐标与实现一致，`24` 高面板中同一文本正常）；需在 Figma 桌面端确认是渲染问题还是文件缺陷。
- [ ] 外部 Figma 文件中的历史 Runtime Badge 变体已删除；计时不是独立徽标，而是未完成行的唯一状态标记。
- [x] Usage Ring 已同步为从十二点逆时针增长的暗色消耗弧，并覆盖 `100`、`0` 与 Unavailable 边界。
- [ ] Panel 外轮廓在 Figma 中仍是单圆角（`38 → 10`、`24 → 6.316`、`19 → 5`），需按 §3.3 改为上下两个半径：肩 `menuBarHeight / 8`、下角 `menuBarHeight / 4`，并覆盖 `38`、`32`、`24`、`22` 四档。**`10 — Double Apps` 已改完**：该页 27 个 `surface / PanelContour` 矢量按 `46` 高菜单栏重绘为肩 `5.75`、下角 `11.5`（顺带修掉了旧路径右下角一个不是正圆弧的控制柄）。剩下 `Panel` 组件集本身（`115:82`）与 §3.3 的响应式示例（`287:8`、`287:12`、`287:16`）——组件集跨页共用，改它会动到其余页面，所以单列。
- [x] Figma 组件集结构合法，且同步范围内无 Inter、旧尺寸或旧计时文案残留。
- [ ] 从外部 Figma 删除不属于四态模型的历史会话状态变体。
- [ ] 不同真实菜单栏高度与至少两种物理刘海设备的原生几何验证。
- [ ] 真实 Codex 集成事件、Project、未读和精确导航的 Phase 0 能力验证。

## 12. 实现映射

产品与技术行为以 [`PRD.md`](PRD.md)、[`tech-design.md`](tech-design.md)、[`CONTEXT.md`](../CONTEXT.md) 和 [`docs/adr`](adr/) 为准。Figma 节点用于视觉与布局验收，不作为 Codex 协议事实来源。
