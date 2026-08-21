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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            productsGroup
            displayGroup
            sessionListGroup

            // The closing note, and the one action that ends the app.
            //
            // Quit belongs to the window, not to a group: it is not a setting,
            // and the component it removes has no window of its own to close.
            // Same shape as `Recheck` — a footnote line with a control on its
            // trailing side — because it is the same kind of thing: the action
            // that the text beside it is about.
            HStack(alignment: .top, spacing: 16) {
                Text(
                    "Notchline only reads. Nothing here changes state in "
                        + "Codex or Claude Code."
                )
                .settingsFootnote(MacOSWindowColor.tertiaryText)

                Button("Quit Notchline") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .help("Quits Notchline and takes the component off the menu bar.")
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
            ProductConnectionRows()

            if let transcripts = store.diskFootprints[.claudeCode] {
                SettingsSeparator()
                claudeCodeTranscriptRow(transcripts)
            }
        } footnote: {
            SettingsFootnote(
                "The switch installs only the five lifecycle events Notchline needs, "
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
                + "Notchline never deletes them."
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
                title: "Show Notchline on",
                caption: selectedDisplayDescription
            ) {
                if store.displays.isEmpty {
                    Text("No display available")
                        .font(.system(size: 11))
                        .foregroundStyle(MacOSWindowColor.secondaryText)
                } else {
                    Picker("Display for Notchline", selection: displaySelection) {
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
                caption: "Removes rows from Notchline. No Codex chat is deleted."
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
            // second product happens to be open is one you never find.
            SettingsFootnote(
                "Only applies while both products are connected — with one product there "
                    + "is nothing to tell apart."
            )
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
}

/// The two connections the app needs, as the two rows that ask for them.
///
/// Shared by first run and Settings rather than drawn twice. Both windows ask
/// for exactly the same thing, and the pair is the one place ADR 0010's
/// asymmetry is visible — a switch for Codex, a paste-it-yourself button for
/// Claude Code. A second copy would be a second place for that asymmetry to be
/// quietly evened out.
struct ProductConnectionRows: View {
    @EnvironmentObject private var store: MonitorStore
    @State private var isShowingClaudeCodeSetup = false
    @State private var didCopyClaudeCodeSnippet = false

    var body: some View {
        SettingsRow(
            title: "Codex Desktop",
            caption: codexCopy.diagnostic,
            status: SettingsRowStatus(
                color: codexCopy.color,
                text: codexCopy.status
            )
        ) {
            Toggle("Codex integration", isOn: integrationSelection)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(store.isInstallingIntegration || store.isRemovingIntegration)
                .help("Installs or removes the five Codex lifecycle definitions together.")
        }

        if let setup = store.manualSetups[.claudeCode] {
            SettingsSeparator()

            SettingsRow(
                title: "Claude Code",
                caption: claudeCodeCopy.diagnostic,
                status: SettingsRowStatus(
                    color: claudeCodeCopy.color,
                    text: claudeCodeCopy.status
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


    private var codexCopy: ProductSettingsCopy {
        .codex(
            setup: store.hookSetupStatus,
            availability: store.availability,
            diagnostic: store.diagnostic(for: .codex)
        )
    }

    private var claudeCodeCopy: ProductSettingsCopy {
        .claudeCode(
            setup: store.setupStatus(for: .claudeCode),
            availability: store.agentAvailability(for: .claudeCode),
            diagnostic: store.diagnostic(for: .claudeCode)
        )
    }

    private var integrationSelection: Binding<Bool> {
        Binding(
            get: { store.integrationSwitchIsOn },
            set: { store.setIntegrationEnabled($0) }
        )
    }
}

/// What one product's row in Settings says about itself.
///
/// A value rather than four computed properties on the view, and for one
/// reason: the line under the status is the only thing in this window that
/// exists to report a failure, and CR-029 was exactly that line being derived
/// correctly, carried down three layers, and then reaching no view at all. A
/// value can be asserted by a test; a `body` cannot, and this window has no
/// other test holding it.
///
/// The product name is the row's label, so the status line must not repeat it:
/// `Codex Desktop / Codex Desktop connected` reads as a stutter.
struct ProductSettingsCopy: Equatable {
    /// The caption line the status dot starts.
    let status: String
    /// The dot.
    let color: Color
    /// What that product's own boundary had to say, when it went wrong. Shown
    /// under the status line, and absent the rest of the time — a row that
    /// keeps an empty line for a failure that is not happening reads as one
    /// that is.
    let diagnostic: String?

    static func codex(
        setup: HookSetupStatus,
        availability: MonitorAvailability,
        diagnostic: String?
    ) -> Self {
        if setup == .repairRequired {
            return Self(
                status: "Integration needs repair",
                color: MacOSWindowColor.statusWarning,
                diagnostic: diagnostic
            )
        }
        if setup == .notInstalled {
            return Self(
                status: "Integration is off",
                color: MacOSWindowColor.statusIdle,
                diagnostic: diagnostic
            )
        }

        let status = switch availability {
        case .ready: "Connected · compatible version"
        case .setupRequired: "Integration not installed"
        case .connecting: "Connecting…"
        case .updateAgent: "Update Codex Desktop"
        case .unsupportedVersion: "Version unsupported"
        case .disconnected: "Disconnected"
        }
        let color = switch availability {
        case .ready: MacOSWindowColor.statusHealthy
        case .connecting: MacOSWindowColor.statusPending
        case .setupRequired: MacOSWindowColor.statusIdle
        case .updateAgent, .unsupportedVersion, .disconnected: MacOSWindowColor.statusBlocked
        }
        return Self(status: status, color: color, diagnostic: diagnostic)
    }

    /// A registration that does not match this build gets its own sentence,
    /// because it is the failure with no other symptom. An event left out
    /// simply never arrives; a handler in an older shape does arrive and
    /// misbehaves quietly — an `http` handler from before ADR 0013 posts every
    /// event to a port nothing listens on, which is a line in the user's
    /// session each time and nothing at all in the notch. Neither reports an
    /// error anywhere.
    static func claudeCode(
        setup: HookSetupStatus,
        availability: MonitorAvailability?,
        diagnostic: String?
    ) -> Self {
        let status: String
        let color: Color
        switch setup {
        case .active where availability == .disconnected:
            status = "Registered · the hook helper could not be set up"
            color = MacOSWindowColor.statusWarning
        case .active:
            status = "Connected · hooks installed"
            color = MacOSWindowColor.statusHealthy
        case .repairRequired:
            status = "Registration is out of date · nothing here reports an error"
            color = MacOSWindowColor.statusWarning
        default:
            status = "Not registered yet"
            color = MacOSWindowColor.statusIdle
        }
        return Self(status: status, color: color, diagnostic: diagnostic)
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
struct SettingsGroup<Content: View, Footnote: View>: View {
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

struct SettingsRowStatus {
    let color: Color
    let text: String
}

/// One row: a label column that fills the width, and a trailing control.
///
/// The status dot starts the caption line rather than standing left of the
/// product name, so every primary label in the window shares one indent and
/// there is a single column to read down.
struct SettingsRow<Control: View>: View {
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

struct SettingsSeparator: View {
    var body: some View {
        Rectangle()
            .fill(MacOSWindowColor.separator)
            .frame(height: 1)
    }
}

/// Footnote text, optionally with a control on its trailing side.
struct SettingsFootnote<Accessory: View>: View {
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

extension Text {
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
struct SettingsWindowChrome: NSViewRepresentable {
    /// Which of the two windows this is. The same scene shows first run and
    /// then Settings, so the band has to be told which one it is under.
    var title = "Notchline Settings"

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
        window.title = title
        // Only reaches the window's own edges, not the title bar, but it keeps
        // a resize or a first paint from flashing the default grey.
        window.backgroundColor = MacOSWindowColor.windowBackgroundColor
    }
}

// MARK: - Presentation

/// Puts the Settings window in front of the user, centred on the display
/// Notchline itself is on.
///
/// The `Settings` scene does neither on its own, and for this app both matter.
/// Its only permanent surface is in the notch, so the request almost always
/// arrives while some *other* app is active: SwiftUI orders the window front
/// within this app and this app stays behind, which from the outside is a gear
/// that was clicked and did nothing. And the window reopens on whichever screen
/// it was last closed on — on a second display, that is behind the user rather
/// than in front of them.
///
/// So: activate, and centre the window on the screen the component is on. That
/// screen rather than the one holding the keyboard focus, because it is the
/// screen this window is *about* — every control in it changes something the
/// user can only see in the notch, and one of them chooses which display the
/// notch is on, so the change and the thing it changes stay in one glance. It is
/// also an answer that does not move while the window is being ordered, which
/// the focused screen never was: read a moment too late and the focused window
/// is Settings itself.
///
/// Every open, not only the opens that cross a screen boundary. Placing the
/// window does discard a position the user dragged it to, which is a real cost
/// and the one this deliberately pays: a window that is sometimes centred and
/// sometimes wherever it was left is a window the user has to go and find.
@MainActor
enum SettingsWindowPresenter {
    private static weak var window: NSWindow?
    private static var visibility: NSKeyValueObservation?

    /// Opens Settings frontmost, centred on Notchline's display.
    static func present(using openSettings: () -> Void) {
        openSettings()
        DispatchQueue.main.async { reveal() }
    }

    /// Takes the window the `Settings` scene has just built.
    ///
    /// Also the hook for every *other* way this window opens — `⌘,` and the
    /// app menu go through SwiftUI's own item, which this app does not see.
    /// Those are caught by watching the window go visible instead.
    static func track(_ window: NSWindow) {
        guard window !== Self.window else { return }
        Self.window = window
        // A window left on another Space comes to this one rather than taking
        // the user to it: what was asked for is Settings here, not a trip to
        // wherever it was last closed.
        window.collectionBehavior.insert(.moveToActiveSpace)
        visibility = window.observe(\.isVisible, options: [.old, .new]) { _, change in
            guard change.oldValue == false, change.newValue == true else { return }
            // KVO is delivered on the thread that ordered the window, which is
            // the main one. The move waits for the next turn, so nothing
            // re-enters AppKit while it is still ordering.
            MainActor.assumeIsolated {
                DispatchQueue.main.async { reveal() }
            }
        }
        reveal()
    }

    private static func reveal() {
        guard let window else { return }

        // `NSScreen.main` only as the answer of last resort: the chosen display
        // has been unplugged since the store last looked, and a window with
        // nowhere of its own to go still has to be somewhere.
        if let screen = MonitorStore.shared.selectedScreen ?? NSScreen.main {
            window.setFrameOrigin(
                SettingsWindowPlacement.origin(
                    for: window.frame.size,
                    on: screen.visibleFrame
                )
            )
        }

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// The arithmetic of putting the Settings window on a screen, kept apart from
/// the window itself so it can be checked without one.
nonisolated enum SettingsWindowPlacement {
    /// Centred across `visibleFrame`, with a third of the leftover height above
    /// it — where macOS itself puts a window it is asked to centre, and higher
    /// than the true middle because a window sitting on the optical centre of a
    /// screen looks low.
    static func origin(for size: NSSize, on visibleFrame: NSRect) -> NSPoint {
        let slack = max(0, visibleFrame.height - size.height)
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.maxY - size.height - slack / 3
        // Clamped so a window wider or taller than the screen keeps its leading
        // and top edges on it: that is where the title bar and the controls are.
        let rightmost = max(visibleFrame.maxX - size.width, visibleFrame.minX)
        return NSPoint(
            x: min(max(x, visibleFrame.minX), rightmost),
            y: max(y, visibleFrame.minY)
        )
    }
}

/// Hands the Settings window to ``SettingsWindowPresenter`` as soon as the
/// scene builds it.
///
/// Attached to the `Settings` scene rather than to ``AppSettingsView``, because
/// that same view is what the first-run window shows once onboarding is done —
/// and that window is not the one this is about.
struct SettingsWindowTracker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { track(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { track(nsView) }
    }

    private func track(_ view: NSView) {
        guard let window = view.window else { return }
        SettingsWindowPresenter.track(window)
    }
}

#Preview("Settings") {
    AppSettingsView()
        .environmentObject(MonitorStore())
}
