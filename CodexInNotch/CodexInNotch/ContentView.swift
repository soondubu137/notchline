import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Codex in Notch")
                    .font(.system(size: 22, weight: .semibold))
                Text("UI 可行性 Demo · 全部内容均为 Mock 数据")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            GroupBox("目标显示器") {
                VStack(alignment: .leading, spacing: 8) {
                    if store.displays.isEmpty {
                        Text("未检测到可用显示器")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("目标显示器", selection: displaySelection) {
                            ForEach(store.displays) { display in
                                Text(display.pickerTitle).tag(display.id)
                            }
                        }
                        .labelsHidden()

                        if let display = store.selectedDisplay {
                            Text("自动识别：\(display.configurationSummary)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
            }

            GroupBox("Mock 状态") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        Text("汇总状态")
                            .foregroundStyle(.secondary)
                        Picker("汇总状态", selection: $store.status) {
                            ForEach(DemoStatus.allCases) { status in
                                Text(status.controlTitle).tag(status)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }

                    GridRow {
                        Text("剩余用量")
                            .foregroundStyle(.secondary)
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(store.tokenRemainingPercent) },
                                    set: { store.tokenRemainingPercent = Int($0.rounded()) }
                                ),
                                in: 0 ... 100,
                                step: 1
                            )
                            Text(store.tokenText)
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                        }
                    }

                    GridRow {
                        Text("动效")
                            .foregroundStyle(.secondary)
                        Toggle("减少动态效果", isOn: $store.reduceMotion)
                    }
                }
                .padding(10)
            }

            HStack(spacing: 12) {
                Button(store.isExpanded ? "收起组件" : "展开组件") {
                    store.toggleFromDebugWindow()
                }
                .keyboardShortcut(.space, modifiers: [])

                Text(panelSizeDescription)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Notch 与非 Notch 屏：悬停约 150 ms 展开，离开约 250 ms 收起。", systemImage: "cursorarrow.motionlines")
                Label("两种模式始终贴住屏幕顶边并保持水平居中。", systemImage: "rectangle.center.inset.filled")
                Label("展开顶栏保持菜单栏高度；Notch 屏会按中央遮挡区自动扩宽。", systemImage: "arrow.left.and.right")
                Label("运行中显示最长会话时长；其他状态显示剩余用量。展开列表最多可见 3 条。", systemImage: "timer")
                Label("两种模式均可按 Escape 收起；点击会话只记录模拟动作。", systemImage: "escape")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            Text(store.lastDemoAction)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 500)
    }

    private var panelSizeDescription: String {
        let size = store.currentPanelSize
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    private var displaySelection: Binding<String> {
        Binding(
            get: { store.selectedDisplayID },
            set: { store.selectDisplay(id: $0) }
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(DemoStore())
}
