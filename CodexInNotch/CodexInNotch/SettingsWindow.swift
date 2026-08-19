// The Settings window, as redesigned for macOS 26. See `figma-design.md` §8.
//
// One pane, no source list. V1 carried a sidebar holding a single item, which
// announced a navigation that does not exist and forced the content area to
// repeat a `General` title the window title already said.
//
// The shape of every group is the same: a small header, one rounded card, and
// footnote text under it. The footnote replaced V1's blue callout — macOS
// states a consequence in a footnote, and a tinted block inside a native window
// only ever reads as a control nobody can click.
import AppKit
import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var store: MonitorStore
    @State private var isShowingClaudeCodeSetup = false
    @State private var didCopyClaudeCodeSnippet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            productsGroup
            displayGroup
            sessionListGroup
            privacyGroup

            // The closing note, and the one action that ends the app.
            //
            // Quit belongs to the window, not to a group: it is not a setting,
            // and the component it removes has no window of its own to close.
            // Same shape as `Recheck` — a footnote line with a control on its
            // trailing side — because it is the same kind of thing: the action
            // that the text beside it is about.
            HStack(alignment: .top, spacing: 16) {
                Text(
                    "Codex in Notch only reads. Nothing here changes state in "
                        + "Codex or Claude Code."
                )
                .settingsFootnote(MacOSWindowColor.tertiaryText)

                Button("Quit Codex in Notch") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .help("Quits Codex in Notch and takes the component off the menu bar.")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(width: 580, alignment: .leading)
        .background(MacOSWindowColor.windowBackground)
        .background(SettingsWindowChrome())
    }

    // MARK: - Products

    /// Both products are rows in one card, not two groups.
    ///
    /// A third product costs a row, not a pane. The switch belongs to Codex
    /// alone: ADR 0010 says this app never writes `~/.claude/settings.json`, so
    /// Claude Code's row carries the setup it actually has instead of a switch
    /// it cannot honour. The asymmetry is the decision, not an oversight, and
    /// putting the two rows side by side is what makes it visible.
    private var productsGroup: some View {
        SettingsGroup(header: "Products") {
            SettingsRow(
                title: "Codex Desktop",
                status: SettingsRowStatus(
                    color: codexStatusColor,
                    text: codexStatusLine
                )
            ) {
                Toggle("Codex integration", isOn: integrationSelection)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(store.isInstallingIntegration || store.isRemovingIntegration)
                    .help("Installs or removes the six Codex lifecycle definitions together.")
            }

            if let setup = store.manualSetups[.claudeCode] {
                SettingsSeparator()

                SettingsRow(
                    title: "Claude Code",
                    status: SettingsRowStatus(
                        color: claudeCodeStatusColor,
                        text: claudeCodeStatusLine
                    )
                ) {
                    Button(isShowingClaudeCodeSetup ? "Hide Setup" : "Set Up…") {
                        isShowingClaudeCodeSetup.toggle()
                        didCopyClaudeCodeSnippet = false
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }

                if isShowingClaudeCodeSetup {
                    SettingsSeparator()
                    claudeCodeSetup(setup)
                }
            }

            if let transcripts = store.diskFootprints[.claudeCode] {
                SettingsSeparator()
                claudeCodeTranscriptRow(transcripts)
            }
        } footnote: {
            SettingsFootnote(
                "The switch installs only the six lifecycle events Codex in Notch needs, "
                    + "and removes them again when it is off. Claude Code is registered by "
                    + "hand — this app reads that file and never writes it."
            ) {
                Button("Recheck") {
                    store.refreshNow()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }

    /// What reading the quota costs on disk, and a way to go and look.
    ///
    /// Shown rather than tidied away. Each reading is a real Claude Code
    /// session and leaves a transcript behind; the folder they go to belongs to
    /// Claude Code and can hold the user's own sessions as well, so this app
    /// reports the size and opens the door rather than deleting anything on
    /// somebody's behalf.
    ///
    /// The row is drawn from the first refresh, before there is a figure to put
    /// in it. Locating the folder means waiting for a quota reading to finish —
    /// several seconds of subprocess — and while the row waited for that, the
    /// card grew a line under whoever had just opened the window. So the state
    /// is drawn instead of the row being withheld: `Calculating…` where the
    /// figure will go, and a button that is plainly not ready rather than one
    /// that would reveal nowhere (CC-020).
    private func claudeCodeTranscriptRow(_ report: AgentDiskFootprintReport) -> some View {
        SettingsRow(
            title: "Quota reading transcripts",
            caption: "Each reading leaves one in Claude Code's project folder. "
                + "Codex in Notch never deletes them."
        ) {
            HStack(spacing: 10) {
                // Beside the button rather than in the status slot: that slot
                // draws a health dot, and a number of megabytes is not a health.
                Text(report.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(MacOSWindowColor.secondaryText)
                    .monospacedDigit()

                Button("Reveal in Finder") {
                    guard let directory = report.directory else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([directory])
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(report.directory == nil)
            }
        }
    }

    /// The paste-it-yourself half of ADR 0010, inside the row it belongs to.
    private func claudeCodeSetup(_ setup: AgentManualSetup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add this block to \(setup.settingsURL.path) yourself.")
                .font(.system(size: 11))
                .foregroundStyle(MacOSWindowColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(setup.configurationSnippet)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MacOSWindowColor.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 132)
            .background(
                MacOSWindowColor.wellBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )

            HStack(spacing: 8) {
                Button(didCopyClaudeCodeSnippet ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        setup.configurationSnippet,
                        forType: .string
                    )
                    didCopyClaudeCodeSnippet = true
                }
                Button("Reveal Settings File") {
                    NSWorkspace.shared.activateFileViewerSelecting([setup.settingsURL])
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Display

    /// Not on the redesign board, which shows the three confirmed groups only.
    ///
    /// It is a control that already exists and has nowhere else to live: the
    /// component appears on exactly one display and the user picks which. Kept
    /// in the same shape rather than dropped, and recorded in `figma-design.md`
    /// §8.4 so the board and the window can be reconciled deliberately.
    private var displayGroup: some View {
        SettingsGroup(header: "Display") {
            SettingsRow(
                title: "Show Codex in Notch on",
                caption: selectedDisplayDescription
            ) {
                if store.displays.isEmpty {
                    Text("No display available")
                        .font(.system(size: 11))
                        .foregroundStyle(MacOSWindowColor.secondaryText)
                } else {
                    Picker("Display for Codex in Notch", selection: displaySelection) {
                        ForEach(store.displays) { display in
                            Text(display.pickerTitle).tag(display.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        } footnote: {
            SettingsFootnote(
                "The component takes the menu bar of the display you choose, and its "
                    + "geometry with it — a cut-out to wrap, or a pill where there is none."
            )
        }
    }

    // MARK: - Session list

    private var sessionListGroup: some View {
        SettingsGroup(header: "Session list") {
            SettingsRow(
                title: "Distinguish products",
                caption: "How a row shows which product it came from."
            ) {
                Picker("Distinguish products", selection: $store.productAttribution) {
                    ForEach(ProductAttributionStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsSeparator()

            SettingsRow(
                title: "Clear the session list",
                caption: "Removes rows from Codex in Notch. No Codex chat is deleted."
            ) {
                Button(store.isClearingSessions ? "Clearing…" : "Clear") {
                    store.clearSessions()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(store.sessions.isEmpty || store.isClearingSessions)
            }
        } footnote: {
            // Visible with one product too. A preference you cannot find until a
            // second product happens to be running is one you never find.
            SettingsFootnote(
                "Only applies when both products are running — with one product there is "
                    + "nothing to tell apart."
            )
        }
    }

    // MARK: - Privacy

    private var privacyGroup: some View {
        SettingsGroup(header: "Privacy") {
            SettingsRow(
                title: "Show current content previews",
                caption: "User-visible prompt, progress, error, and final-answer snippets."
            ) {
                Toggle("Show current content previews", isOn: $store.showsContentPreviews)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        } footnote: {
            // Only the switch moves. The row keeps its geometry either way, so
            // the consequence is stated in the footnote and nowhere else.
            SettingsFootnote(
                store.showsContentPreviews
                    ? "Previews are on. No preview text is written to disk by Codex in Notch."
                    : "Previews are hidden. Project, title and status still show; a session "
                        + "with no Desktop title reads as Untitled."
            )
        }
    }

    // MARK: - Status copy

    /// The product name is the row label now, so the status line must not
    /// repeat it: `Codex Desktop / Codex Desktop connected` reads as a stutter.
    private var codexStatusLine: String {
        if store.hookSetupStatus == .repairRequired {
            return "Integration needs repair"
        }
        if store.hookSetupStatus == .notInstalled {
            return "Integration is off"
        }

        return switch store.availability {
        case .ready: "Connected · compatible version"
        case .setupRequired: "Integration not installed"
        case .connecting: "Connecting…"
        case .updateAgent: "Update Codex Desktop"
        case .unsupportedVersion: "Version unsupported"
        case .disconnected: "Disconnected"
        }
    }

    private var codexStatusColor: Color {
        if store.hookSetupStatus == .repairRequired {
            return MacOSWindowColor.statusWarning
        }
        if store.hookSetupStatus == .notInstalled {
            return MacOSWindowColor.statusIdle
        }

        return switch store.availability {
        case .ready: MacOSWindowColor.statusHealthy
        case .connecting: MacOSWindowColor.statusPending
        case .setupRequired: MacOSWindowColor.statusIdle
        case .updateAgent, .unsupportedVersion, .disconnected: MacOSWindowColor.statusBlocked
        }
    }

    /// A registration that does not match this build gets its own sentence,
    /// because it is the failure with no other symptom. An event left out
    /// simply never arrives; a handler in an older shape does arrive and
    /// misbehaves quietly — one missing `async` is a session that waits on
    /// this app three times a second while a turn talks. Neither reports an
    /// error anywhere.
    private var claudeCodeStatusLine: String {
        switch store.setupStatus(for: .claudeCode) {
        case .active:
            store.agentAvailability(for: .claudeCode) == .disconnected
                ? "Registered · the port in your settings is unavailable"
                : "Connected · hooks installed"
        case .repairRequired:
            "Registration is out of date · nothing here reports an error"
        default:
            "Not registered yet"
        }
    }

    private var claudeCodeStatusColor: Color {
        switch store.setupStatus(for: .claudeCode) {
        case .active:
            store.agentAvailability(for: .claudeCode) == .disconnected
                ? MacOSWindowColor.statusWarning
                : MacOSWindowColor.statusHealthy
        case .repairRequired:
            MacOSWindowColor.statusWarning
        default:
            MacOSWindowColor.statusIdle
        }
    }

    private var selectedDisplayDescription: String {
        guard let display = store.selectedDisplay else {
            return "Connect a display to choose where the component appears."
        }

        let geometry = display.geometry == .notched
            ? "Notch display"
            : "Display without a notch"
        return "\(geometry) · \(Int(display.menuBarHeight.rounded())) pt menu bar"
    }

    private var displaySelection: Binding<String> {
        Binding(
            get: { store.selectedDisplayID },
            set: { store.selectDisplay(id: $0) }
        )
    }

    private var integrationSelection: Binding<Bool> {
        Binding(
            get: { store.integrationSwitchIsOn },
            set: { store.setIntegrationEnabled($0) }
        )
    }
}

// MARK: - Group chrome

/// A header, one card, and a footnote — the macOS 26 grouped-row shape.
///
/// The card is drawn here rather than taken from `Form`/`Section`, because §8
/// pins the metrics (`12` radius, `14 × 11` rows, `22` between groups) and a
/// grouped `Form` reaches none of them. The controls *inside* it are native, so
/// the switch, the popup and the capsule buttons are the real Tahoe shapes
/// rather than approximations of them.
private struct SettingsGroup<Content: View, Footnote: View>: View {
    let header: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footnote: () -> Footnote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MacOSWindowColor.primaryText)

            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MacOSWindowColor.groupBackground, in: cardShape)
            .overlay {
                cardShape.strokeBorder(MacOSWindowColor.groupStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 0.5)
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)

            footnote()
                .padding(.leading, 2)
                .padding(.top, 2)
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }
}

private struct SettingsRowStatus {
    let color: Color
    let text: String
}

/// One row: a label column that fills the width, and a trailing control.
///
/// The status dot starts the caption line rather than standing left of the
/// product name, so every primary label in the window shares one indent and
/// there is a single column to read down.
private struct SettingsRow<Control: View>: View {
    let title: String
    var caption: String?
    var status: SettingsRowStatus?
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(MacOSWindowColor.primaryText)

                if let status {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 6, height: 6)
                        captionText(status.text)
                    }
                }

                if let caption {
                    captionText(caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func captionText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(MacOSWindowColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsSeparator: View {
    var body: some View {
        Rectangle()
            .fill(MacOSWindowColor.separator)
            .frame(height: 1)
    }
}

/// Footnote text, optionally with a control on its trailing side.
private struct SettingsFootnote<Accessory: View>: View {
    private let text: String
    private let accessory: () -> Accessory

    init(_ text: String, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.text = text
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(text)
                .settingsFootnote(MacOSWindowColor.secondaryText)
            accessory()
        }
    }
}

extension SettingsFootnote where Accessory == EmptyView {
    init(_ text: String) {
        self.init(text, accessory: { EmptyView() })
    }
}

private extension Text {
    func settingsFootnote(_ color: Color) -> some View {
        font(.system(size: 11))
            .foregroundStyle(color)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Colours

/// `Color / macOS Window` from `figma-design.md` §3.2, as one two-mode value
/// each rather than two hard-coded batches.
///
/// A `dynamicProvider` is the code form of a two-mode Figma collection: one
/// declaration answers for both appearances, so light and dark cannot drift
/// apart the way two separate palettes eventually do.
enum MacOSWindowColor {
    /// Also the window's own `backgroundColor`, so the transparent title bar
    /// sits on the same value the content does.
    static let windowBackgroundColor = dynamicColor(light: 0xEC_EC_EE, dark: 0x1E_1E_20)
    static let windowBackground = Color(nsColor: windowBackgroundColor)
    static let groupBackground = dynamic(light: 0xFF_FF_FF, dark: 0x2C_2C_2E)
    static let groupStroke = dynamic(
        light: 0x00_00_00, lightAlpha: 0.07,
        dark: 0xFF_FF_FF, darkAlpha: 0.08
    )
    static let separator = dynamic(
        light: 0x00_00_00, lightAlpha: 0.09,
        dark: 0xFF_FF_FF, darkAlpha: 0.11
    )
    /// The recessed well the Claude Code snippet sits in.
    static let wellBackground = dynamic(
        light: 0x00_00_00, lightAlpha: 0.04,
        dark: 0x00_00_00, darkAlpha: 0.22
    )
    static let primaryText = dynamic(
        light: 0x00_00_00, lightAlpha: 0.85,
        dark: 0xFF_FF_FF, darkAlpha: 0.92
    )
    static let secondaryText = dynamic(
        light: 0x00_00_00, lightAlpha: 0.50,
        dark: 0xFF_FF_FF, darkAlpha: 0.55
    )
    static let tertiaryText = dynamic(
        light: 0x00_00_00, lightAlpha: 0.32,
        dark: 0xFF_FF_FF, darkAlpha: 0.38
    )

    /// Status dots take the system colours, which already carry the exact two
    /// values `Color / macOS Window` names — `status/green` is `systemGreen` in
    /// both modes — and stay correct under an accessibility appearance.
    static let statusHealthy = Color(nsColor: .systemGreen)
    static let statusWarning = Color(nsColor: .systemOrange)
    static let statusPending = Color(nsColor: .systemBlue)
    static let statusBlocked = Color(nsColor: .systemPurple)
    static let statusIdle = Color(nsColor: .systemGray)

    private static func dynamic(
        light: Int,
        lightAlpha: CGFloat = 1,
        dark: Int,
        darkAlpha: CGFloat = 1
    ) -> Color {
        Color(
            nsColor: dynamicColor(
                light: light,
                lightAlpha: lightAlpha,
                dark: dark,
                darkAlpha: darkAlpha
            )
        )
    }

    private static func dynamicColor(
        light: Int,
        lightAlpha: CGFloat = 1,
        dark: Int,
        darkAlpha: CGFloat = 1
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat(hex >> 16 & 0xFF) / 255,
                green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: isDark ? darkAlpha : lightAlpha
            )
        }
    }
}

/// Names the window.
///
/// §8 draws the title bar in the window's own colour with no rule under it.
/// That part is not implemented and is not worth what it costs: SwiftUI owns
/// the title bar of a scene's window and re-applies its own configuration, so
/// `titlebarAppearsTransparent`, `backgroundColor`, `titlebarSeparatorStyle`
/// and `.fullSizeContentView` were all tried and all had no visible effect.
/// What is left is drawing a `52pt` band and a centred title by hand under
/// `.hiddenTitleBar` -- which would make the most conspicuous element in a
/// window whose whole argument is "native controls, not approximations of
/// them" the one piece that is an approximation. The band stays macOS's.
private struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.title = "Codex in Notch Settings"
        // Only reaches the window's own edges, not the title bar, but it keeps
        // a resize or a first paint from flashing the default grey.
        window.backgroundColor = MacOSWindowColor.windowBackgroundColor
    }
}

#Preview("Settings") {
    AppSettingsView()
        .environmentObject(MonitorStore())
}
