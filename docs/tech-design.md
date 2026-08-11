# Codex in Notch — UI Demo 技术设计

| 字段 | 内容 |
| --- | --- |
| 文档状态 | 可运行原型 |
| 版本 | 0.3 |
| 日期 | 2026-08-10 |
| 实现范围 | SwiftUI + AppKit UI 可行性验证 |
| 上游设计 | [figma-design.md](./figma-design.md) |

## 1. 目标与边界

本阶段只验证带刘海与无刘海两套核心 UI 是否能在原生 macOS 窗口中实现，包括顶部定位、收起/展开几何、鼠标交互、会话列表、内容密度和基础动效。

当前明确不实现：

- Codex App Server、生命周期 hook 或其他真实 Codex 集成。
- 读取、监听或持久化真实会话数据。
- 审批、输入、会话编辑或真实的“打开 Codex”动作。
- Onboarding、Settings、登录启动和生产发布配置。

所有状态、token 百分比、会话标题和当前内容均来自本地 Mock 数据。

## 2. 当前开发环境

| 项目 | 当前值 |
| --- | --- |
| Xcode | 26.6（Build 17F113） |
| macOS SDK | 26.5 |
| 工程 | `CodexInNotch/CodexInNotch.xcodeproj` |
| Scheme | `CodexInNotch` |
| UI 技术 | SwiftUI |
| 窗口与定位 | AppKit `NSPanel` |
| 工程文件发现 | Xcode synchronized root group，新 Swift 文件自动加入 target |

## 3. 原型结构

```text
CodexInNotchApp
├── ContentView                 # 仅用于 Demo 的状态控制窗口
├── AppDelegate
│   └── OverlayPanelController  # 创建、定位和缩放顶部 NSPanel
├── NotchOverlayView            # 收起/展开 SwiftUI 组件
│   ├── CompactHeader
│   ├── ExpandedPanelContent
│   ├── SessionRow
│   └── StatusIndicatorView
└── DemoStore                   # 单一 Mock 状态源与交互时序
```

### `DemoStore`

负责：

- 枚举当前连接的显示器并保存用户选择的目标显示器。
- 根据目标显示器的顶部安全区与左右辅助区域自动判断 `notched` 或 `noNotch`。
- 根据目标显示器的 `frame`、`visibleFrame` 和安全区自动计算紧凑态高度。
- 管理收起/展开状态。
- 提供汇总状态、token 剩余百分比和四条 Mock 会话。
- 两种屏幕均在鼠标进入 `150 ms` 后展开、离开 `250 ms` 后收起。
- 记录“模拟打开 Codex”的会话标题，不产生外部副作用。

### `OverlayPanelController`

顶部组件使用无边框、非激活式 `NSPanel`，不使用只能出现在菜单栏右侧的 `NSStatusItem`。

关键配置：

- `level = .statusBar`
- `styleMask = [.borderless, .nonactivatingPanel]`
- 透明窗口背景，由 Figma 导出的纯黑 SVG 绘制组件轮廓。
- `canJoinAllSpaces`、`fullScreenAuxiliary` 和 `stationary`。
- 窗口不能成为 key/main window，避免组件抢占当前应用焦点。
- 使用屏幕完整 `frame` 而不是 `visibleFrame`，使组件顶部始终与屏幕上沿重合。
- 覆写面板的窗口约束，避免 AppKit 默认使用 `visibleFrame` 将组件推到菜单栏下方。
- 收起与展开目标框架均由同一个屏幕中心点计算，使水平中心和顶部边缘在动画前后保持锁定。
- 窗口外框尺寸只由 AppKit 动画；SwiftUI 根视图始终服从 `NSHostingView` 的当前 `bounds`，仅动画顶部内容间距和列表显隐，避免第二套外框几何动画造成横向漂移。
- 通过稳定的显示器 ID 将面板定位到用户选择的 `NSScreen`。
- 监听屏幕参数变化并刷新显示器列表；当前选择仍存在时保留选择，显示器断开时回退到主显示器。

Demo 控制窗口提供目标显示器选择。默认使用 `NSScreen.screens` 的第一块主显示器；菜单栏自动隐藏和全屏策略仍需在真机测试后决定。

## 4. Figma 到原生实现映射

| 设计项 | 原生实现 |
| --- | --- |
| 字体 | 系统 SF Pro；状态名和 token 为 Bold 13 pt，会话文字为 Regular 13 pt |
| 带刘海收起 | 宽度 `348`；高度取目标显示器顶部安全区或菜单栏实测高度，Figma 参考值为 `46` |
| 无刘海收起 | `Working + 72%` 基准宽度为 `168`，其他文案自然增宽；高度取目标显示器菜单栏实测高度 |
| 展开 | 两种模式均为 `444 × 390` |
| 表面 | 直接使用四个 Figma 导出的 SVG 轮廓 |
| 状态图标 | 直接使用 Figma 导出的 Waiting、Running、Completed、Failed SVG |
| 会话行 | 标题、状态图标和一行当前内容预览；不增加其他元数据 |
| 运行中反馈 | 安静的透明度呼吸；减少动态时关闭 |

本轮 Demo 只实现当前四张核心 Figma 画板实际出现的四种状态图标。八种完整状态矩阵仍是后续设计与原生验证项，不能把临时图标替代品当作最终设计。

## 5. 交互规则

### 带刘海与无刘海屏幕

- 鼠标进入组件后约 `150 ms` 展开。
- 鼠标离开整个展开区域后约 `250 ms` 收起。
- 组件尺寸在约 `200 ms` 内从对应收起尺寸变化为 `444 × 390`。
- 收起态与展开态始终水平居中，展开过程锁定同一个水平中心并贴住屏幕上沿，视觉上平滑向下生长。
- 按 Escape 立即收起。

### 无刘海收起几何

- `Working + 72%` 保持 `168` 的基准宽度；更长状态名只增加必要宽度，不加入弹性黑色空白。
- 高度使用目标显示器的 `frame.maxY - visibleFrame.maxY`；菜单栏自动隐藏等场景无法实测时回退到顶部安全区或系统状态栏厚度。

### 会话行

- 悬停显示轻量纯白透明背景。
- 点击仅在 Demo 控制窗口记录“模拟打开 Codex：会话标题”。
- 不提供批准、编辑或真实跳转。

## 6. Mock 数据

默认展开态使用以下四条数据：

| 标题 | 状态 | 当前内容 |
| --- | --- | --- |
| 验证 macOS 刘海窗口定位 | 等待批准 | 需要在本机运行窗口定位测试。 |
| 实现 Codex 状态事件适配器 | 运行中 | 正在核对事件顺序与状态映射…… |
| 更新产品需求文档 | 已完成 | 已更新收起与展开状态的产品要求。 |
| 同步本地任务事件 | 失败 | 连接已中断，正在等待重新连接。 |

## 7. 运行方式

1. 在 Xcode 中选择 `CodexInNotch` scheme 和 `My Mac`。
2. 按 Command-R 运行。
3. 顶部中央会出现组件；普通窗口为 Demo 控制器，不属于产品 UI。
4. 在控制器中选择目标显示器，并检查自动识别的屏幕类型与菜单栏高度。
5. 切换汇总状态、token 百分比和减少动态效果。
6. 分别验证带刘海与无刘海的悬停展开、离开收起交互。

命令行构建：

```bash
xcodebuild \
  -project CodexInNotch/CodexInNotch.xcodeproj \
  -scheme CodexInNotch \
  -configuration Debug \
  -derivedDataPath /private/tmp/codex-in-notch-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 8. 验证 Todo

- [x] 安装并选择 Xcode 开发工具。
- [x] 创建 macOS SwiftUI 工程并完成首次构建。
- [x] 将 Figma 核心文字统一为 SF Pro，并补齐“更新产品需求文档”。
- [x] 实现 Mock 状态模型和 Demo 控制窗口。
- [x] 实现顶部居中的非激活 `NSPanel`。
- [x] 实现带刘海与无刘海的悬停展开/离开收起。
- [x] 实现目标显示器选择、屏幕类型自动识别与菜单栏高度自适应。
- [x] 接入 Figma 导出的面板与四种状态 SVG。
- [x] 完成 Debug 命令行构建。
- [ ] 在真实带刘海内置屏幕验证位置、命中区域与物理刘海遮挡。
- [ ] 在无刘海屏幕或外接显示器验证菜单栏等高与内容驱动宽度。
- [ ] 验证全屏应用、Spaces 切换、缩放和屏幕配置变化。
- [ ] 补齐八种汇总状态与一个、三个、十个以上会话场景。
- [ ] 根据真机结果回写最终尺寸、时序和窗口策略。
- [ ] UI 设计验证通过后，再单独设计并实现 Codex 集成层。
