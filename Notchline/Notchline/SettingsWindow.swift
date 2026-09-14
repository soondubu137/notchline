// The Settings window for macOS 26 (`figma-design.md` §8): Products, Display and Quota panes.
// Captions are one line; longer text is a tooltip or ⓘ popover. Only a reported failure wraps.
import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable {
    case products
    case display
    case quota

    /// Absent the first time, which opens on Products.
    static let defaultsKey = "settingsPane"

    /// Also the window's title while selected.
    var title: String {
        switch self {
        case .products: "Products"
        case .display: "Display"
        case .quota: "Quota"
        }
    }

    var systemImage: String {
        switch self {
        case .products: "puzzlepiece.extension"
        case .display: "macbook"
        case .quota: "gauge.with.needle"
        }
    }
}

/// No store here: observing it rebuilt the toolbar on every publish.
struct AppSettingsView: View {
    @AppStorage(SettingsPane.defaultsKey) private var pane: SettingsPane = .products

    var body: some View {
        TabView(selection: $pane) {
            Tab(SettingsPane.products.title, systemImage: SettingsPane.products.systemImage, value: .products) {
                SettingsPaneLayout { ProductsSettingsPane() }
            }
            Tab(SettingsPane.display.title, systemImage: SettingsPane.display.systemImage, value: .display) {
                SettingsPaneLayout { DisplaySettingsPane() }
            }
            Tab(SettingsPane.quota.title, systemImage: SettingsPane.quota.systemImage, value: .quota) {
                SettingsPaneLayout { QuotaSettingsPane() }
            }
        }
        .background(SettingsWindowChrome(title: pane.title))
    }
}

enum SettingsWindowLayout {
    static let width: CGFloat = 580

    /// One height for every pane (Display's), so the closing row never moves; a test holds it.
    static let paneHeight: CGFloat = 491

    /// For screens shorter than ``paneHeight``.
    @MainActor
    static var fittedPaneHeight: CGFloat {
        let shortest = NSScreen.screens.map(\.visibleFrame.height).min() ?? 940
        return min(paneHeight, max(320, shortest - 140))
    }
}

/// Content scrolls; the closing row stays pinned outside the scroll view. The `Settings`
/// scene sizes its window only from a fixed tab height (a `maxHeight` did not work).
struct SettingsPaneLayout<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                SettingsPaneContent(content: content)
            }
            .scrollBounceBehavior(.basedOnSize)

            SettingsClosingFooter()
        }
        .frame(width: SettingsWindowLayout.width, height: SettingsWindowLayout.fittedPaneHeight)
        .background(MacOSWindowColor.windowBackground)
    }
}

struct SettingsPaneContent<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            content()
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        // The `22` between groups, kept before the closing row outside this stack.
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsClosingFooter: View {
    var body: some View {
        SettingsClosingRow()
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
    }
}

/// The version and `Quit` under every pane, at opposite ends, baselines aligned.
struct SettingsClosingRow: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            AppVersionLine()

            Spacer(minLength: 16)

            // Red ink, not bezel: `.tint` does nothing on `.bordered`, and `.borderedProminent` loses the
            // accent when the window is not key.
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .foregroundStyle(MacOSWindowColor.destructiveAction)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .help("Quits Notchline and takes the component off the menu bar.")
        }
    }
}

// MARK: - Reading the store
//
// A pane observes `MonitorStore` in one small view that extracts an `Equatable` value and hands
// it to the drawing view behind `.equatable()`, which holds the store only to write through.
// A publish cost this window 14–18 ms before, 1–2 ms after (Release).

// MARK: - Products

/// One headerless card of rows from ``ProductRegistry/builtIn``.
struct ProductsSettingsPane: View {
    var body: some View {
        SettingsGroup {
            ProductConnectionRows()
        } footnote: {
            SettingsFootnote(SettingsCaption.productsFootnote) {
                RecheckButton()
            }
        }
    }
}

/// Asks every product for its state again, now. Also behind `.equatable()`: a `Button` rebuilt
/// with a fresh closure re-laid out the whole window, 4.5 ms per publish (Debug).
struct RecheckButton: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        Drawing(store: store)
            .equatable()
    }

    private struct Drawing: View, Equatable {
        let store: MonitorStore

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.store === rhs.store
        }

        var body: some View {
            Button("Recheck") {
                store.refreshNow()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
    }
}

// MARK: - Display

/// Three cards: the screen, the collapsed component, the expanded panel.
struct DisplaySettingsPane: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        DisplaySettingsGroups(settings: DisplaySettings(store), store: store)
            .equatable()
    }
}

struct DisplaySettings: Equatable {
    struct Choice: Equatable, Identifiable {
        let id: String
        let title: String
    }

    let displays: [Choice]
    let selectedDisplayID: String
    let selectedDisplayDescription: String
    let privacyMode: Bool
    let drawsSurfaceOutline: Bool
    let hidesCompactWings: Bool
    let canHideCompactWings: Bool
    let geometry: DisplayGeometry
    let namesWorkOnPill: Bool
    let canNameWorkOnPill: Bool
    let groupsSessionsByProduct: Bool

    init(_ store: MonitorStore) {
        displays = store.displays.map { Choice(id: $0.id, title: $0.pickerTitle) }
        selectedDisplayID = store.selectedDisplayID
        selectedDisplayDescription = Self.description(of: store.selectedDisplay)
        privacyMode = store.privacyMode
        drawsSurfaceOutline = store.drawsSurfaceOutline
        hidesCompactWings = store.hidesCompactWings
        canHideCompactWings = store.canHideCompactWings
        geometry = store.geometry
        namesWorkOnPill = store.namesWorkOnPill
        canNameWorkOnPill = store.canNameWorkOnPill
        groupsSessionsByProduct = store.groupsSessionsByProduct
    }

    private static func description(of display: DisplayOption?) -> String {
        guard let display else {
            return "Connect a display to choose where the component appears."
        }

        let geometry = display.geometry == .notched
            ? "Notch display"
            : "Display without a notch"
        // On a notched display the band is the cut-out, a couple of points shorter than the menu bar.
        let band = display.geometry == .notched ? "pt notch" : "pt menu bar"
        return "\(geometry) · \(Int(display.panelBandHeight.rounded())) \(band)"
    }
}

struct DisplaySettingsGroups: View, Equatable {
    let settings: DisplaySettings
    /// Written through by the controls, never read to draw.
    let store: MonitorStore

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.settings == rhs.settings
    }

    var body: some View {
        // Own stack at `22`: behind `.equatable()` the parent's spacing no longer applies (measured).
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                showOnRow
                SettingsSeparator()
                privacyModeRow
                SettingsSeparator()
                outlineRow
            }

            SettingsGroup(header: "Collapsed") {
                hideWingsRow
                SettingsSeparator()
                nameWorkRow
            }

            SettingsGroup(header: "Expanded") {
                groupByProductRow
            }
        }
    }

    private var showOnRow: some View {
        SettingsRow(
            title: "Show Notchline on",
            caption: settings.selectedDisplayDescription,
            help: "Notchline appears on one display at a time. The caption gives "
                + "that display's shape and the height of the band the component "
                + "is drawn in."
        ) {
            if settings.displays.isEmpty {
                Text("No display available")
                    .font(.system(size: 11))
                    .foregroundStyle(MacOSWindowColor.secondaryText)
            } else {
                Picker("Display for Notchline", selection: displaySelection) {
                    ForEach(settings.displays) { display in
                        Text(display.title).tag(display.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    /// Cover every word the component draws (`cover-the-words.md`). Never greyed; the caption
    /// names the secondary-press gesture.
    private var privacyModeRow: some View {
        SettingsRow(
            title: "Privacy Mode",
            caption: SettingsCaption.privacyMode,
            help: "Covers every word Notchline draws while somebody else is "
                + "looking at the screen: each row's project, title and latest "
                + "line becomes a bar, and the collapsed pill stops naming the "
                + "work. The mark, the counts and the clock stay. Opening a row "
                + "uncovers that row, and the panel waits for a click instead of "
                + "opening when the pointer merely crosses it."
        ) {
            Toggle("Privacy Mode", isOn: binding(\.privacyMode))
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    /// Give the black surface an edge of its own. Applies to both states; never greyed.
    private var outlineRow: some View {
        SettingsRow(
            title: "Outline the panel",
            caption: SettingsCaption.outline,
            help: "Traces the sides and lower corners in a grey just off "
                + "Notchline's own black, collapsed and expanded alike."
        ) {
            Toggle("Outline the panel", isOn: binding(\.drawsSurfaceOutline))
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    /// Give the cut-out back. Always settable, even where it cannot apply: `hidesCompactWings` is
    /// kept apart from `canHideCompactWings` and waits for a screen that can honour it (§8.4.1).
    private var hideWingsRow: some View {
        SettingsRow(
            title: "Hide the wings",
            caption: SettingsCaption.hideWings(
                canHide: settings.canHideCompactWings,
                geometry: settings.geometry
            ),
            help: "Leaves the collapsed component as the cut-out alone, with no "
                + "clock beside it. The mark and its counts slide out while a "
                + "turn is waiting on approval, on an answer, or to be read, and "
                + "go back when it is dealt with; hovering still opens the panel. "
                + "Takes effect on a display whose cut-out Notchline can measure "
                + "— not on a display without a notch, nor on one that reports a "
                + "notch but not where it is."
        ) {
            Toggle("Hide the wings", isOn: binding(\.hidesCompactWings))
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    /// Name the work between the pill's two ends. Settable anywhere, as `Hide the wings` is.
    private var nameWorkRow: some View {
        SettingsRow(
            title: "Name the work",
            caption: SettingsCaption.nameWork(canName: settings.canNameWorkOnPill),
            help: "Names each project with a live turn in the middle of the "
                + "collapsed component, five seconds apiece; the component keeps "
                + "its width either way. Takes effect on a display without a "
                + "notch — on a notched one the cut-out is where the name would "
                + "stand."
        ) {
            Toggle("Name the work", isOn: binding(\.namesWorkOnPill))
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    /// Grouped blocks or one list (`expanded-panel-v2.md` §4.6).
    private var groupByProductRow: some View {
        SettingsRow(
            title: "Group by product",
            caption: SettingsCaption.groupByProduct,
            help: "Stands each product's sessions under a heading that names "
                + "them once, and keeps every heading on screen while the list "
                + "scrolls — the block you are in at the top, the ones you have "
                + "passed beside it, the ones still to come at the foot. Off, the "
                + "list is one list in order of urgency, and every row carries "
                + "its own badge."
        ) {
            Toggle("Group by product", isOn: binding(\.groupsSessionsByProduct))
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<MonitorStore, Bool>) -> Binding<Bool> {
        Binding(
            get: { store[keyPath: keyPath] },
            set: { store[keyPath: keyPath] = $0 }
        )
    }

    private var displaySelection: Binding<String> {
        Binding(
            get: { store.selectedDisplayID },
            set: { store.selectDisplay(id: $0) }
        )
    }
}

// MARK: - Quota

struct QuotaSettingsPane: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        QuotaSettingsGroups(settings: QuotaSettings(store), store: store)
            .equatable()
    }
}

struct QuotaSettings: Equatable {
    let productsHiddenFromQuotaTable: Set<AgentKind>
    let diskFootprints: [AgentKind: AgentDiskFootprintReport]

    init(_ store: MonitorStore) {
        productsHiddenFromQuotaTable = store.productsHiddenFromQuotaTable
        diskFootprints = store.diskFootprints
    }
}

struct QuotaSettingsGroups: View, Equatable {
    let settings: QuotaSettings
    /// Written through by the switches, never read to draw.
    let store: MonitorStore

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.settings == rhs.settings
    }

    var body: some View {
        // Their own stack, for the reason ``DisplaySettingsGroups`` gives.
        VStack(alignment: .leading, spacing: 22) {
            quotaTableGroup

            // Only products that leave anything have a key, and the key decides whether the row is
            // drawn (CC-020); with none, no group.
            if !settings.diskFootprints.isEmpty {
                SettingsGroup(header: "Quota readings") {
                    ForEach(Array(settings.diskFootprints.keys.sorted().enumerated()), id: \.element) { index, agent in
                        if let report = settings.diskFootprints[agent] {
                            if index > 0 {
                                SettingsSeparator()
                            }
                            transcriptRow(report, for: agent)
                        }
                    }
                }
            }
        }
    }

    /// Which products get a block (`quota-footer-v2.md` §13): a switch per product, connected or not.
    private var quotaTableGroup: some View {
        SettingsGroup(header: "Quota table") {
            ForEach(Array(ProductRegistry.builtIn.enumerated()), id: \.element.kind) { index, descriptor in
                if index > 0 {
                    SettingsSeparator()
                }
                SettingsRow(
                    title: descriptor.displayName,
                    help: "A product switched on gets its own block — its usage "
                        + "today and its limits — in the table under today’s "
                        + "total. With every product off, the footer shows the "
                        + "total alone."
                ) {
                    Toggle(
                        "Show \(descriptor.displayName) in the quota table",
                        isOn: quotaTableSelection(for: descriptor.kind)
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
        } footnote: {
            SettingsFootnote(SettingsCaption.quotaTableFootnote)
        }
    }

    /// Each quota reading is a Claude Code session leaving a transcript in a folder that may hold
    /// the user's own sessions, so this reports and reveals, never deletes. `Calculating…`,
    /// `Unavailable`, or a plainly not-ready button (CC-020).
    private func transcriptRow(_ report: AgentDiskFootprintReport, for agent: AgentKind) -> some View {
        SettingsRow(
            title: "Quota reading transcripts",
            caption: SettingsCaption.quotaTranscripts(for: agent),
            help: "Each quota reading is a real \(agent.displayName) session and "
                + "leaves a transcript in \(agent.displayName)’s project folder, "
                + "which can hold your own sessions too — so Notchline reports "
                + "the size and opens the folder, and deletes nothing."
        ) {
            HStack(spacing: 10) {
                // Not in the status slot: that slot draws a health dot, and megabytes are not health.
                Text(report.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(MacOSWindowColor.secondaryText)
                    .monospacedDigit()

                ShowInFinderButton(target: report.directory.map(FinderRevealTarget.select))
            }
        }
    }

    private func quotaTableSelection(for agent: AgentKind) -> Binding<Bool> {
        Binding(
            get: { store.showsInQuotaTable(agent) },
            set: { store.setShowsInQuotaTable($0, for: agent) }
        )
    }
}

/// Captions and footnotes not read off a product's state, so a test can hold each to one line
/// at `580` pt.
enum SettingsCaption {
    static let productsFootnote = "Switches edit only Notchline’s hooks, after a .notchline-backup copy."
    static let privacyMode = "Draws every name and line as a bar. Secondary-click Notchline to toggle."
    static let outline = "A hairline edge, for dark wallpapers."
    static let groupByProduct = "One block per product, each headed by its badge."
    static let quotaTableFootnote = "Today’s total counts every connected product, whatever is on here."

    /// A built-in screen that cannot place its notch is named apart from an external monitor, so a
    /// MacBook never reads `Needs a notched display`.
    static func hideWings(canHide: Bool, geometry: DisplayGeometry) -> String {
        guard canHide else {
            guard geometry == .notched else {
                return "Waits for a display with a cut-out."
            }
            return "Waits for a display Notchline can measure."
        }
        return "Only the cut-out, until a turn needs you."
    }

    static func nameWork(canName: Bool) -> String {
        guard canName else {
            return "Waits for a display without a notch."
        }
        return "Names each live project between the counts and the clock."
    }

    static func quotaTranscripts(for agent: AgentKind) -> String {
        "Kept in \(agent.displayName)’s project folder. Notchline never deletes them."
    }

    static var all: [String] {
        [productsFootnote, privacyMode, outline, groupByProduct, quotaTableFootnote,
         nameWork(canName: true), nameWork(canName: false)]
            + [true, false].flatMap { canHide in
                DisplayGeometry.allCases.map { hideWings(canHide: canHide, geometry: $0) }
            }
            + AgentKind.allCases.map(quotaTranscripts(for:))
    }
}

/// One connection row per registered product, shared by first run and Settings, read off
/// ``ProductDescriptor``. Managed setup is one switch (ADR 0016). A reported failure stays on
/// the row, never only in the ⓘ popover (CR-029).
struct ProductConnectionRows: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        ForEach(Array(ProductRegistry.builtIn.enumerated()), id: \.element.kind) { index, descriptor in
            if index > 0 {
                SettingsSeparator()
            }
            ProductConnectionRow(
                descriptor: descriptor,
                copy: copy(for: descriptor),
                isOn: store.integrationSwitchIsOn(for: descriptor.kind),
                isBusy: store.isIntegrationBusy(for: descriptor.kind),
                store: store
            )
            // Per row, so a publish about one product leaves another row's open ⓘ alone.
            .equatable()
        }
    }

    /// Read off that product's own answer, never the merged `store.availability`
    /// (`integration-settings-behaviour.md` §4).
    private func copy(for descriptor: ProductDescriptor) -> ProductSettingsCopy {
        ProductSettingsCopy(
            descriptor: descriptor,
            setup: store.setupStatus(for: descriptor.kind),
            availability: store.agentAvailability(for: descriptor.kind),
            diagnostic: store.diagnostic(for: descriptor.kind)
        )
    }
}

struct ProductConnectionRow: View, Equatable {
    let descriptor: ProductDescriptor
    let copy: ProductSettingsCopy
    /// The switch reads the store itself; this makes the row redraw when it moves.
    let isOn: Bool
    let isBusy: Bool
    /// Written through by the switch, never read to draw.
    let store: MonitorStore

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.descriptor.kind == rhs.descriptor.kind
            && lhs.copy == rhs.copy
            && lhs.isOn == rhs.isOn
            && lhs.isBusy == rhs.isBusy
    }

    var body: some View {
        SettingsRow(
            title: descriptor.settingsTitle,
            status: SettingsRowStatus(color: copy.color, text: copy.status),
            diagnostic: copy.diagnostic
        ) {
            HStack(spacing: 6) {
                if descriptor.setup.isConfigurable {
                    Toggle("\(descriptor.displayName) integration", isOn: integrationSelection)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(isBusy)
                        .help(descriptor.setup.switchHelp)
                }

                ProductInfoButton(content: ProductInfoContent(descriptor: descriptor))
            }
        }
    }

    private var integrationSelection: Binding<Bool> {
        let agent = descriptor.kind
        return Binding(
            get: { store.integrationSwitchIsOn(for: agent) },
            set: { store.setIntegrationEnabled($0, for: agent) }
        )
    }
}

/// What a product's ⓘ popover says; a value so a test can assert it.
struct ProductInfoContent: Equatable {
    struct Paragraph: Equatable {
        let heading: String
        let text: String
    }

    struct HooksFile: Equatable {
        /// `~/.codex/hooks.json`, as the user knows it.
        let displayPath: String
        let url: URL
    }

    let title: String
    /// `Watches` and `Not shown`: what the product's rows can and cannot say.
    let boundary: [Paragraph]
    /// What setup asks beyond the switch: Codex's trust step, Trae's reopened windows.
    let setup: [Paragraph]
    let hooksFile: HooksFile?

    init(descriptor: ProductDescriptor) {
        title = descriptor.settingsTitle
        boundary = [
            descriptor.watches.map { Paragraph(heading: "Watches", text: $0) },
            descriptor.notShown.map { Paragraph(heading: "Not shown", text: $0) }
        ].compactMap { $0 }

        switch descriptor.setup {
        case .none:
            setup = [Paragraph(heading: "Setup", text: "This product needs no setup.")]
            hooksFile = nil
        case let .managedHooks(description):
            // The trust step is phrased to follow a semicolon; capitalise and end it to stand alone.
            setup = description.trustStep.map {
                [Paragraph(heading: "After turning it on", text: $0.prefix(1).uppercased() + $0.dropFirst() + ".")]
            } ?? []
            hooksFile = HooksFile(
                displayPath: description.displayPath,
                url: description.configurationFile(fileManager: .default)
            )
        case .companionExtension:
            setup = [Paragraph(
                heading: "Companion",
                text: "The switch installs a companion extension in Trae. Reopen Trae’s windows afterwards to connect."
            )]
            hooksFile = nil
        }
    }
}

/// The ⓘ, drawn like ``ShowInFinderButton``; the ground stays while its popover is open.
struct ProductInfoButton: View {
    let content: ProductInfoContent

    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(MacOSWindowColor.secondaryText)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovering || isPresented ? MacOSWindowColor.hoverBackground : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("About \(content.title)")
        .help("About \(content.title)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ProductInfoPopover(content: content)
        }
    }
}

struct ProductInfoPopover: View {
    let content: ProductInfoContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(content.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MacOSWindowColor.primaryText)

            ForEach(content.boundary, id: \.heading) { paragraph($0) }

            if !content.boundary.isEmpty, !content.setup.isEmpty || content.hooksFile != nil {
                SettingsSeparator()
            }

            ForEach(content.setup, id: \.heading) { paragraph($0) }

            if let hooksFile = content.hooksFile {
                VStack(alignment: .leading, spacing: 3) {
                    heading("Hooks file")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(hooksFile.displayPath)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(MacOSWindowColor.primaryText)
                            .textSelection(.enabled)

                        Button("Show in Finder") {
                            FinderRevealTarget.revealing(hooksFile.url)?.reveal()
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        // A button with nowhere to go is greyed rather than silently inert.
                        .disabled(FinderRevealTarget.revealing(hooksFile.url) == nil)
                    }
                }
            }
        }
        .padding(.top, 14)
        .padding([.horizontal, .bottom], 16)
        .frame(width: 300, alignment: .leading)
    }

    private func paragraph(_ paragraph: ProductInfoContent.Paragraph) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            heading(paragraph.heading)
            Text(paragraph.text)
                .font(.system(size: 12))
                .foregroundStyle(MacOSWindowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MacOSWindowColor.secondaryText)
    }
}


/// The one-glyph way into a folder a row is about. No border until hovered; the `22 × 22`
/// square is the target, the glyph `12 × 12`.
struct ShowInFinderButton: View {
    /// `nil` greys the button out (CC-020).
    let target: FinderRevealTarget?

    @State private var isHovering = false

    var body: some View {
        Button {
            target?.reveal()
        } label: {
            // A measured `12 × 12` via `resizable`, not a 12-point font: `.system(size: 12)` sizes `folder`
            // to `17 × 13`.
            Image(systemName: "folder")
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
                .accessibilityLabel("Show in Finder")
                .foregroundStyle(
                    target == nil
                        ? MacOSWindowColor.tertiaryText
                        : MacOSWindowColor.secondaryText
                )
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovering ? MacOSWindowColor.hoverBackground : .clear)
                )
                // The whole square takes the click; a `folder` is mostly empty inside.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        // No hover state under a button that cannot be pressed.
        .onHover { isHovering = $0 && target != nil }
        .help("Show in Finder")
    }
}

/// Where a ``ShowInFinderButton`` press goes; a value so a test can assert it.
nonisolated enum FinderRevealTarget: Equatable {
    /// Open the enclosing folder with this item selected.
    case select(URL)
    /// Open this folder itself, because the item is not in it yet.
    case open(URL)

    /// Nil with nothing on disk. A missing file is ordinary and `activateFileViewerSelecting`
    /// silently ignores it, so the folder that would hold it opens instead.
    static func revealing(_ url: URL, fileManager: FileManager = .default) -> Self? {
        if fileManager.fileExists(atPath: url.path) {
            return .select(url)
        }
        let directory = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return .open(directory)
    }

    @MainActor
    func reveal() {
        switch self {
        case .select(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .open(let directory):
            NSWorkspace.shared.open(directory)
        }
    }
}

/// What one product's row in Settings says; a value so a test can assert it (CR-029). The status
/// never repeats the product name. Top to bottom:
///
/// 1. A registration not matching this build gets its own sentence: it fails silently (e.g. a
///    pre-ADR 0013 `http` handler). The switch reads off, so it says to turn it on.
/// 2. Off is off.
/// 3. Written but never seen to fire, with a trust step (Codex only): names the step.
/// 4. Registered: `Connected` needs `.ready`; `.disconnected` is one neutral headline, with the
///    boundary's own diagnostic underneath.
struct ProductSettingsCopy: Equatable {
    /// The caption line the status dot starts.
    let status: String
    let color: Color
    /// Shown under the status line only when present; an empty line reads as a failure.
    let diagnostic: String?

    init(
        descriptor: ProductDescriptor,
        setup: IntegrationSetupStatus,
        availability: MonitorAvailability?,
        diagnostic: String?
    ) {
        self.diagnostic = diagnostic
        if !descriptor.setup.isConfigurable {
            switch availability {
            case .ready: status = "Connected"; color = MacOSWindowColor.statusHealthy
            case .connecting, nil: status = "Connecting…"; color = MacOSWindowColor.statusPending
            case .updateAgent: status = "Update \(descriptor.settingsTitle)"; color = MacOSWindowColor.statusBlocked
            case .unsupportedVersion: status = "Version unsupported"; color = MacOSWindowColor.statusBlocked
            case .setupRequired, .disconnected:
                status = "Not watching \(descriptor.displayName)"; color = MacOSWindowColor.statusWarning
            }
            return
        }
        if case .companionExtension = descriptor.setup {
            switch setup {
            case .notInstalled: status = "Integration is off"; color = MacOSWindowColor.statusIdle
            case .repairRequired: status = "Reinstall the companion"; color = MacOSWindowColor.statusWarning
            case .notRequired: status = "No setup required"; color = MacOSWindowColor.statusIdle
            case .reviewRequired, .active:
                if availability == .unsupportedVersion {
                    status = "Version unsupported"; color = MacOSWindowColor.statusBlocked
                } else if availability == .ready {
                    status = "Connected · companion installed"; color = MacOSWindowColor.statusHealthy
                } else {
                    status = "Installed · reopen the Trae window to connect"; color = MacOSWindowColor.statusPending
                }
            }
            return
        }
        switch setup {
        case .notRequired:
            status = "No setup required"
            color = MacOSWindowColor.statusIdle
        case .repairRequired:
            status = "Registration is out of date · turn the switch on to rewrite it"
            color = MacOSWindowColor.statusWarning
        case .notInstalled:
            status = "Integration is off"
            color = MacOSWindowColor.statusIdle
        case .reviewRequired where descriptor.setup.managedHooks?.trustStep != nil:
            status = "Installed · \(descriptor.setup.managedHooks?.trustStep ?? "")"
            color = MacOSWindowColor.statusPending
        case .reviewRequired, .active:
            switch availability {
            case .ready:
                status = "Connected · \(descriptor.setup.managedHooks?.connectedDetail ?? "")"
                color = MacOSWindowColor.statusHealthy
            case .connecting, nil:
                status = "Connecting…"
                color = MacOSWindowColor.statusPending
            case .setupRequired:
                status = "Integration not installed"
                color = MacOSWindowColor.statusIdle
            case .updateAgent:
                status = "Update \(descriptor.settingsTitle)"
                color = MacOSWindowColor.statusBlocked
            case .unsupportedVersion:
                status = "Version unsupported"
                color = MacOSWindowColor.statusBlocked
            case .disconnected:
                status = "Registered · not watching \(descriptor.displayName)"
                color = MacOSWindowColor.statusWarning
            }
        }
    }
}

// MARK: - Group chrome

/// A header, one card, and a footnote. Drawn here, not with `Form`/`Section`, to reach §8's
/// `12` radius, `14 × 11` rows and `22` gaps; the controls inside are native.
struct SettingsGroup<Content: View, Footnote: View>: View {
    let header: String?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footnote: () -> Footnote

    init(
        header: String? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footnote: @escaping () -> Footnote
    ) {
        self.header = header
        self.content = content
        self.footnote = footnote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacOSWindowColor.primaryText)
            }

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

/// A group with no footnote; `EmptyView` is dropped, so the `22` is the only gap under the card.
extension SettingsGroup where Footnote == EmptyView {
    init(header: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(header: header, content: content, footnote: { EmptyView() })
    }
}

struct SettingsRowStatus {
    let color: Color
    let text: String
}

/// One row: a filling label column and a trailing control. The status dot starts the caption
/// line. Status and caption are one line each, longer text is the row's `help`; the diagnostic
/// wraps without limit (CR-029).
struct SettingsRow<Control: View>: View {
    let title: String
    var caption: String?
    var status: SettingsRowStatus?
    var diagnostic: String?
    var help: String?
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

                if let diagnostic {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(MacOSWindowColor.statusWarning)
                            .accessibilityLabel("Warning")
                        Text(diagnostic)
                            .font(.system(size: 11))
                            .foregroundStyle(MacOSWindowColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
        }
        .padding(.horizontal, 14)
        // A bare title sits in a shorter row (`9`), as the quota table's do.
        .padding(.vertical, caption == nil && status == nil && diagnostic == nil ? 9 : 11)
        // The row's empty middle takes the pointer too, so the tooltip covers the whole row.
        .contentShape(Rectangle())
        .modifier(RowHelp(text: help))
    }

    private func captionText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(MacOSWindowColor.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// A row's tooltip, or none rather than an empty one.
private struct RowHelp: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}

struct SettingsSeparator: View {
    var body: some View {
        Rectangle()
            .fill(MacOSWindowColor.separator)
            .frame(height: 1)
    }
}

struct SettingsFootnote<Accessory: View>: View {
    private let text: String
    private let accessory: () -> Accessory

    init(_ text: String, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.text = text
        self.accessory = accessory
    }

    var body: some View {
        // Baselines, so a one-line footnote sits on its capsule label's line.
        HStack(alignment: .firstTextBaseline, spacing: 16) {
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

/// `Color / macOS Window` (`figma-design.md` §3.2) as two-mode dynamic colours.
enum MacOSWindowColor {
    /// Also the window's `backgroundColor`, so the transparent title bar matches the content.
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
    /// Under a hovered borderless glyph; lighter than ``wellBackground``, quieter than a switch.
    static let hoverBackground = dynamic(
        light: 0x00_00_00, lightAlpha: 0.07,
        dark: 0xFF_FF_FF, darkAlpha: 0.10
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

    /// System colours match `Color / macOS Window` and follow accessibility appearances.
    static let statusHealthy = Color(nsColor: .systemGreen)
    static let statusWarning = Color(nsColor: .systemOrange)
    static let statusPending = Color(nsColor: .systemBlue)
    static let statusBlocked = Color(nsColor: .systemPurple)
    static let statusIdle = Color(nsColor: .systemGray)

    /// The ink of `Quit`, for the same reason.
    static let destructiveAction = Color(nsColor: .systemRed)

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

/// Names the window. §8's custom title bar is not implemented: SwiftUI re-applies its own
/// configuration, so `titlebarAppearsTransparent`, `backgroundColor`, `titlebarSeparatorStyle`
/// and `.fullSizeContentView` had no visible effect.
struct SettingsWindowChrome: NSViewRepresentable {
    /// The same scene shows first run and then Settings, so the title is passed in.
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
        // Reaches only the window's edges, but stops a resize or first paint flashing grey.
        window.backgroundColor = MacOSWindowColor.windowBackgroundColor
    }
}

// MARK: - Presentation

/// Activates the app (the `Settings` scene only orders the window front within it) and centres
/// the window on Notchline's display. Placed while off screen, via `SettingsWindowTracker` and
/// the `isVisible` observation, so it never visibly jumps.
@MainActor
enum SettingsWindowPresenter {
    private static weak var window: NSWindow?
    private static var visibility: NSKeyValueObservation?

    static func present(using openSettings: () -> Void) {
        openSettings()
        DispatchQueue.main.async { reveal() }
    }

    /// Takes the window the `Settings` scene has just built, before it is on screen; watching
    /// hidden/shown also catches any other way it opens.
    static func track(_ window: NSWindow) {
        guard window !== Self.window else { return }
        Self.window = window
        // A window on another Space comes to this one.
        window.collectionBehavior.insert(.moveToActiveSpace)
        visibility = window.observe(\.isVisible, options: [.old, .new]) { window, change in
            guard change.oldValue != change.newValue else { return }
            // KVO arrives on the thread that ordered the window: the main one.
            MainActor.assumeIsolated {
                // Both edges; the hiding one is load-bearing, the only moment the window moves unseen.
                place(window)
                guard change.newValue == true else { return }
                // Activate on the next turn rather than re-entering AppKit while it orders this window.
                DispatchQueue.main.async { reveal() }
            }
        }
        place(window)
        DispatchQueue.main.async { reveal() }
    }

    /// Called only while the window is unseen; a move after ordering front jumped ~`50 ms` later.
    private static func place(_ window: NSWindow) {
        // `NSScreen.main` only as a last resort, when the chosen display has been unplugged.
        guard let screen = MonitorStore.shared.selectedScreen ?? NSScreen.main
        else { return }

        let origin = SettingsWindowPlacement.origin(
            for: window.frame.size,
            on: screen.visibleFrame
        )
        guard window.frame.origin != origin else { return }
        window.setFrameOrigin(origin)
    }

    /// `ignoringOtherApps:`: the cooperative `NSApp.activate()` was measured refused while
    /// returning normally, for an accessory app at launch (``AppDelegate``) and behind a
    /// full-screen app (`tech-design.md` §14.2).
    private static func reveal() {
        guard let window else { return }
        place(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// The arithmetic of placing the Settings window, testable without a window.
nonisolated enum SettingsWindowPlacement {
    /// Centred horizontally, with a third of the leftover height above, as macOS centres windows.
    static func origin(for size: NSSize, on visibleFrame: NSRect) -> NSPoint {
        let slack = max(0, visibleFrame.height - size.height)
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.maxY - size.height - slack / 3
        // Clamped so an oversized window keeps its leading and top edges on screen.
        let rightmost = max(visibleFrame.maxX - size.width, visibleFrame.minX)
        return NSPoint(
            x: min(max(x, visibleFrame.minX), rightmost),
            y: max(y, visibleFrame.minY)
        )
    }
}

/// Hands the Settings window to ``SettingsWindowPresenter``. On the `Settings` scene, not
/// ``AppSettingsView``, which the first-run window also shows.
struct SettingsWindowTracker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowReportingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// `viewDidMoveToWindow`: `makeNSView` is before the view has a window, and the next turn is
    /// after SwiftUI orders it on screen.
    private final class WindowReportingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            SettingsWindowPresenter.track(window)
        }
    }
}

#Preview("Settings") {
    AppSettingsView()
        .environmentObject(MonitorStore())
}
