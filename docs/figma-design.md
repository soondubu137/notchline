# Codex in Notch — Figma 设计规范

| 字段 | 内容 |
| --- | --- |
| 文档状态 | 已同步当前 Figma 文件 |
| 版本 | 0.5 |
| 日期 | 2026-08-11 |
| 文件 | [Codex in Notch — V1](https://www.figma.com/design/B9qIi46zhdjbQYbjZo3AnM/Codex-in-Notch-%E2%80%94-V1) |

## 1. 设计原则

1. 顶部组件是当前处理轮次的实时汇总中心，不是历史入口。
2. 带刘海与无刘海的收起几何不同，但展开后共享同一内容结构。
3. 展开组件始终贴住屏幕上沿、锁定水平中心；顶部汇总区只横向扩张。
4. 状态、额度、处理时间、Project、标题和当前内容都来自真实 Codex Desktop 语义。
5. 无法可靠取得的数据明确降级，不用 Mock、缓存或近似值填补。
6. 所有 Figma 文字统一使用 SF Pro；不得继续引入 Inter、SF Compact 或其他产品字体。

## 2. Figma 文件结构

| Page | 作用 | 关键节点 |
| --- | --- | --- |
| `00 — Cover & Notes` | 文件说明 | — |
| `01 — Getting Started` | 使用说明 | — |
| `02 — Foundations` | 颜色、布局、字体、Motion | — |
| `03 — Status Components` | Status Dot、Readout、Usage Ring、Badge | `107:18`, `109:34`, `137:184` |
| `04 — Session Row` | 会话行、列表和运行时胶囊 | `112:28`, `140:201`, `196:71` |
| `05 — Panel` | 收起与展开 Panel 变体 | `115:82` |
| `Notch Core` | 核心产品状态 | `118:120`, `185:310` |
| `06 — Integration States` | 隐私、Unknown、局部降级、空和全局可用性 | `227:3` |
| `07 — Onboarding` | 首次安装三步流程 | `232:95` |
| `08 — Settings` | 集成管理与预览隐私 | `233:3` |

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

### 3.2 Color

- Panel 背景：纯黑或现有 `surface/notch` / `surface/panel` token。
- Primary text：白色（暗色 Panel）或近黑色（原生窗口）。
- Secondary text：中性灰。
- Running：蓝色。
- Input/Approval：橙色。
- Completed：绿色。
- Error：红色。
- Cancelled：冷灰色。
- Unknown：中性灰色。
- Disconnected/版本不可用：紫色。

Unknown 是单会话状态；Disconnected 是全局集成状态，颜色与语义不得混用。

### 3.3 Layout tokens

| 项目 | 值 |
| --- | --- |
| Notch compact | `348 × 46` 参考基线 |
| No-notch Running compact | `166 × 46` 参考基线 |
| No-notch Input needed compact | `198 × 46` 参考基线 |
| Shared expanded | `520 × 302` 参考基线 |
| Expanded header | `520 × 46` 外框，内容宽 `472` |
| Expanded content region | `256` 高 |
| Session viewport | `472 × 240` |
| Session row | `472 × 80` |
| Thin expanded state | `520 × 94` |
| Horizontal Panel padding | `24` |
| Status dot | `8 × 8` |
| Usage ring | `18 × 18`, stroke `2` |
| Row badge | `24` 高 |

目标显示器菜单栏高度不是 `46` 时，顶部汇总区使用真实菜单栏高度，总高度为 `menuBarHeight + 256`。带物理刘海时，宽度还要根据中央不可显示区继续增加，确保 `Approval needed`、`Input needed`、`Codex version unsupported` 等最长状态名完整位于可显示区域。

## 4. 核心组件

### 4.1 Status Dot

`Status Dot` 包含：Idle、Running、Input Needed、Approval Needed、Completed、Error、Cancelled、Disconnected 与 Unknown。

- Idle 只用于健康空集合的汇总。
- Unknown 可用于会话行与汇总；只有所有被监视会话都 Unknown 时成为汇总。
- Disconnected 不用于会话行。

### 4.2 Status Readout

Compact 与 Expanded 两个 Context 都提供完整状态文本。Expanded 组内圆点—名称间距为 `12`；状态名称不得被物理刘海遮挡。

### 4.3 Usage Ring 与 Indicator

- 彩色圆弧从十二点方向逆时针绘制，非满环两端为圆头。
- `> 50%` 白色，`15%–50%` 橙色，`< 15%` 红色。
- Unavailable 为灰色圆环，不显示伪造百分比。
- 有 Running 时 Expanded leading value 为最长 Running 时长；否则为剩余百分比。

### 4.4 Session Row

每行左侧依次显示 Project、标题、当前内容；右侧为状态控件。

- Running 始终显示蓝色 Runtime Badge。
- 非 Running 默认显示圆点，Hover 显示状态名称 Badge。
- 左侧文字接近尾部控件时 Alpha 渐隐，不换行、不显示省略号。
- 最多三行可见；更多行使用垂直滚动。
- 隐私关闭时移除预览文字，但保持 `80` 行高和 Panel 几何；标题与 Project 仍保留。

### 4.5 Panel

Panel 组件集保留 Notch Compact、No Notch Compact 和 Expanded。Expanded 的正式参考尺寸已经从 `444 × 310` 修正为 `520 × 302`：

- header 高度从 `54` 修正为 `46`。
- 展开时 header 只横向扩张。
- 内容区使用 `256`，三行视口使用 `240`，底部保留 `15`。
- 现有 `Notch Core` Running Desktop 画板已按 `1512` 屏幕重新居中到 `x = 496`。

## 5. 实时监视列表

### 5.1 成员语义

一行代表一个可导航根 Thread。活动 Turn 始终显示；Completed、Error、Cancelled 只在 Desktop 仍为未读时显示。Desktop 已读、归档、删除或失去可导航性后自动移除。

列表覆盖当前 Desktop 账户所有 Project 与 `Chats`，不跟随侧边栏选择，不展示子智能体，也不承担历史浏览。

### 5.2 排序

```text
Input needed
> Approval needed
> Running
> Unknown
> Error
> Cancelled
> Completed
```

同级按最近可信更新时间降序。排序实时变化，但不得在用户滚动或悬停时强制改变当前视口锚点。

### 5.3 当前内容

| 状态 | 内容 |
| --- | --- |
| Input needed | 当前问题 |
| Approval needed | 固定 `Approval requested` |
| Running | 最新公开进度，回退到本轮输入 |
| Error | 用户可见错误摘要 |
| Cancelled | 最后公开进度，回退到本轮输入 |
| Completed | final answer 开头 |
| Unknown | 最后允许展示的公开片段 |

禁止 raw reasoning、工具参数、命令输出、diff、敏感路径和批准理由。

## 6. Integration States

`06 — Integration States`（`227:3`）包含：

### 6.1 Content previews hidden

- 保留 Project、Desktop 标题、状态与 Running 时长。
- 未生成 Desktop 标题的会话显示 `Untitled`。
- 不显示正文预览，不改变行高。

### 6.2 Unknown stays local

单行 Unknown 使用中性灰 Badge。画板同时存在 Input needed 与 Running，用来证明 Unknown 不覆盖已知的高优先级汇总状态。

### 6.3 Quota unavailable

额度环为灰色 unavailable，但会话列表、状态、时长和点击能力继续工作。该场景表达局部降级，不是 Disconnected。

### 6.4 Monitoring lifecycle

注释卡明确：提交输入后入列；活动 Turn 始终保留；终态只在 Desktop 未读时保留；已读、归档、删除或失去可导航性后自动移除；Notch 不主动标记已读。

### 6.5 Thin states

| 状态 | 展开正文 | 操作 |
| --- | --- | --- |
| Healthy empty | `No active turns` | 无 |
| Connecting | `Connecting to Codex` | 无，最长 5 秒 |
| Disconnected | `Codex disconnected` | 无，列表清空 |
| Old version | `Update Codex` | 无 |
| Unverified version | `Codex version unsupported` | 无 |
| First setup | `Set up integration` | 操作只发生在 Onboarding |

薄层使用 `520 × 94`。No active turns、Update Codex、Codex version unsupported 与 Codex disconnected 均不可点击。

## 7. 首次安装引导

`07 — Onboarding`（`232:95`）由三个 `580 × 640` 的 macOS 窗口组成：

1. **Welcome**：Notch 预览、实时监视价值、人工请求优先级和精确会话返回。
2. **Connect to Codex**：列出受支持的本地元数据与额度读取，说明本地、最小、可逆；只有用户点击 `Set Up Integration` 后才改变配置。
3. **Ready**：确认实时状态与精确导航，提醒预览默认开启并可在设置中关闭。

引导窗口使用标准 macOS 视觉层级：交通灯、单列内容、底部主操作。它不请求用户允许辅助功能或屏幕录制，也不承诺静默绕过 Codex 信任。

## 8. 设置

`08 — Settings`（`233:3`）同时展示默认与隐私关闭两种状态。设置页只包含已确认的两类控制：

### 8.1 Codex integration

- 显示 Codex Desktop connected 与兼容性信息。
- `Recheck` 重新检测能力。
- `Remove Integration` 只移除 Codex in Notch 管理的集成。

### 8.2 Privacy

- `Show current content previews` 默认 On。
- Off 时说明 Project、标题、状态和时长仍然显示。
- 明确提示 prompt fallback 被禁用，缺失标题为 `Untitled`。

不在 V1 设置画板中加入登录启动、动画、通知、模型选择或其他尚未确认的功能。

## 9. 交互

### 9.1 展开/收起

- Hover intent 参考 `150 ms`。
- 展开参考 `180–220 ms`。
- 鼠标离开后参考 `250 ms` 收起。
- Escape 立即收起。
- 所有中间帧保持相同 `midX` 与 `maxY`。
- Reduce Motion 下使用短淡入淡出，不使用明显弹簧或缩放。

### 9.2 会话点击

- 点击成功进入相同 Desktop Thread 并收起 Panel。
- Notch 点击本身不改变已读；等待 Desktop 蓝点消失事件。
- 导航失败时 Panel 与行保持，不把打开首页当作成功。
- 会话行不提供批准、回答、取消或归档操作。

## 10. 无障碍

- 所有状态必须有文字或可访问名称，不能只依赖颜色。
- Unknown 与 Disconnected 使用不同文案与语义。
- 隐私关闭后旁白不读取已隐藏正文。
- 长状态名称在带刘海 Expanded 几何中必须完整可读。
- Reduce Motion 不影响状态可理解性。

旁白示例：

```text
Codex，三个当前轮次，其中一个需要输入，最长运行三分四十二秒，额度剩余百分之七十二
确认未读生命周期，Project Codex in Notch，需要输入
检查未知事件，Chats，状态未知
```

## 11. 验证清单

- [x] 展开宽度 `520`，参考高度 `302`。
- [x] header 固定参考 `46`，只横向扩张。
- [x] 三行 `472 × 80` 视口与滚动契约。
- [x] SF Pro 文件级字体统一。
- [x] 隐私关闭场景。
- [x] Unknown 与 quota unavailable 局部降级。
- [x] No active turns、Connecting、Disconnected、Update、unsupported、setup 薄层。
- [x] 首次安装三步流程。
- [x] Settings 预览 On/Off 与集成管理。
- [ ] 不同真实菜单栏高度与至少两种物理刘海设备的原生几何验证。
- [ ] 真实 Codex 集成事件、Project、未读和精确导航的 Phase 0 能力验证。

## 12. 实现映射

产品与技术行为以 [`PRD.md`](PRD.md)、[`tech-design.md`](tech-design.md)、[`CONTEXT.md`](../CONTEXT.md) 和 [`docs/adr`](adr/) 为准。Figma 节点用于视觉与布局验收，不作为 Codex 协议事实来源。
