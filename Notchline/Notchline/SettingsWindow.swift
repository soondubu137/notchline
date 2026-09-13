// The Settings window, as redesigned for macOS 26. See `figma-design.md` §8.
//
// Three toolbar panes — Products, Display, Quota. It was one pane with no
// source list while it held three groups, because a one-item sidebar announces
// a navigation that does not exist; at fifteen rows doing three jobs it
// measured 1,292 pt of content in a window capped at 860, so a third of it was
// reachable only by scrolling, and every product added grew it twice.
//
// The shape of every group is the same: a small header, one rounded card, and
// footnote text under it. The footnote replaced V1's blue callout — macOS
// states a consequence in a footnote, and a tinted block inside a native window
// only ever reads as a control nobody can click. Every caption is one line;
// the rest of what a row has to say is its tooltip or, for a product, its ⓘ
// popover. A failure a product reported is the one line allowed to wrap.
import AppKit
import SwiftUI

/// The three panes, in toolbar order.
enum SettingsPane: String, CaseIterable {
    case products
    case display
    case quota

    /// Where the last pane used is remembered. Absent the first time, which
    /// opens on Products: the pane somebody opens Settings to diagnose.
    static let defaultsKey = "settingsPane"

    /// The tab's label, which is also the window's title while it is selected.
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

/// **No store here.** This view draws the toolbar and the window's title, and
/// neither reads the store — but observing it rebuilt the three toolbar
/// symbols and re-titled the window on every publish. Each pane reads what it
/// needs itself; see "Reading the store" below.
struct AppSettingsView: View {
    @AppStorage(SettingsPane.defaultsKey) private var pane: SettingsPane = .products

    var body: some View {
        // A `TabView` inside the `Settings` scene is the toolbar-pane window
        // macOS draws for every utility's settings: the tabs sit in the
        // toolbar and the selected tab names the window.
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

/// The one size every pane is drawn at.
enum SettingsWindowLayout {
    static let width: CGFloat = 580

    /// Everything under the toolbar: the pane's content and the closing row.
    ///
    /// **One height for every pane**, the tallest pane's — Display's three
    /// cards. The window used to take each pane's own height, which moved the
    /// version and `Quit` up and down the screen with every tab; they belong to
    /// the window rather than to a pane, so they stay where they were. A test
    /// holds every pane to this height.
    static let paneHeight: CGFloat = 491

    /// What a pane is drawn at on a screen too short for ``paneHeight``: the
    /// shortest connected screen, less the title bar, toolbar and a margin.
    @MainActor
    static var fittedPaneHeight: CGFloat {
        let shortest = NSScreen.screens.map(\.visibleFrame.height).min() ?? 940
        return min(paneHeight, max(320, shortest - 140))
    }
}

/// One pane: its content, scrolling if it must, and the closing row pinned
/// under it.
///
/// **The closing row is outside the scroll view.** It is the same row in the
/// same place under every pane, so a pane whose content runs long — a product
/// row carrying a wrapped failure, a registry grown past what the card holds —
/// scrolls its own content and never pushes the row off the window.
///
/// **The height is fixed, not measured.** The `Settings` scene sizes its window
/// from a tab's fixed height and never from a flexible frame — measured, a
/// `maxHeight` over the scroll view left all three panes in the first one's
/// window — and a fixed height is what this window wants anyway.
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

/// A pane's groups at the window's margins, top-aligned.
struct SettingsPaneContent<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            content()
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        // The `22` between groups, kept between the last group and the
        // closing row that now sits outside this stack.
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The closing row at the window's margins.
struct SettingsClosingFooter: View {
    var body: some View {
        SettingsClosingRow()
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
    }
}

/// The version and the action that quits the app, under every pane.
///
/// They belong to the window rather than to a settings group, so they sit in
/// the same place whichever pane is in front.
///
/// The two sit at opposite ends of the row rather than side by side on the
/// left: a version is a fact to read and `Quit` is the one action this window
/// offers, and macOS puts a window's action in its bottom trailing corner —
/// beside the version it read as a second caption someone had made pressable.
/// Baselines align rather than tops, so the version sits on the same line as
/// the button's label instead of riding above it.
struct SettingsClosingRow: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            AppVersionLine()

            Spacer(minLength: 16)

            // Red is in the label's ink, not in the bezel. `.tint` on macOS's
            // `.bordered` style does nothing at all — measured, the capsule
            // came back the standard grey — and `.borderedProminent` draws its
            // fill from the accent, which a window loses the moment it stops
            // being key: the red would leave every time the user clicked
            // something else. The ink holds in every state.
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
// How a pane reads `MonitorStore` without redrawing for what it does not show.
//
// The store publishes for everything the overlay draws — a row's latest line,
// the quota, the hover — and a publish re-evaluates every view observing it,
// whatever changed. A view here that re-evaluates can re-lay out and re-measure
// the whole window, and an open ⓘ popover is handed its content again.
// Measured on a Release build at ten publishes a second, by differencing
// cumulative CPU time, a publish cost this window 14–18 ms on any pane; it is
// now 1–2 ms. Most of it was the app observing the store (see
// `NotchlineApp.store`), the rest the panes.
//
// So a pane observes the store in one small view that reads what the pane
// draws into an `Equatable` value, and hands that value to the view that draws
// it behind `.equatable()`. A publish that leaves the value alone stops at the
// comparison. The drawing view keeps the store as a plain reference, which
// observes nothing, so its switches can write through it. Their bindings still
// read the store itself; the value carries each switch's position only so that
// a change to it redraws.

// MARK: - Products

/// Every product is a row in one card, not a group of its own, and the card
/// needs no header: the pane's name is the header.
///
/// Rows come from ``ProductRegistry/builtIn``. Four products or ten, it is one
/// card of one-line rows; what a product cannot do is behind its ⓘ.
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

/// Asks every product for its state again, now.
///
/// A view of its own so that it alone takes the store from the environment,
/// for the one action it needs: the pane around it draws nothing a publish can
/// change, and first run's connection group uses the same button.
///
/// **The button itself is behind `.equatable()` too**, though it draws nothing
/// from the store. A `Button` rebuilt with a fresh action closure updates the
/// AppKit button under it, and that re-laid out the whole window: measured,
/// `4.5 ms` of CPU per publish in a Debug build, most of what the Products
/// pane still cost once nothing else in it redrew.
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

/// Three cards: the screen itself, the collapsed component, the expanded
/// panel. The group names do the explaining the captions' second sentences
/// used to — `Collapsed` says where a preference shows before the row says
/// what it does.
///
/// No footnote. Each row's own caption already names the consequence for the
/// display that is actually selected; a standing sentence about cut-outs and
/// pills only said the same thing in the abstract.
struct DisplaySettingsPane: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        DisplaySettingsGroups(settings: DisplaySettings(store), store: store)
            .equatable()
    }
}

/// What the Display pane draws, read off the store in one place.
struct DisplaySettings: Equatable {
    /// A display as the picker offers it.
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
        // The band the component is drawn at, named for what it is here: on a
        // notched display that is the cut-out, which is a couple of points
        // shorter than the menu bar around it.
        let band = display.geometry == .notched ? "pt notch" : "pt menu bar"
        return "\(geometry) · \(Int(display.panelBandHeight.rounded())) \(band)"
    }
}

/// The Display pane's three cards, drawn from ``DisplaySettings``.
struct DisplaySettingsGroups: View, Equatable {
    let settings: DisplaySettings
    /// Written through by the controls, and never read to draw.
    let store: MonitorStore

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.settings == rhs.settings
    }

    var body: some View {
        // Their own stack, at the pane's `22`. Behind `.equatable()` the three
        // cards reach the stack in ``SettingsPaneContent`` as one view, and
        // it lost the space between them — measured, the cards closed up.
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

    /// Which display the component appears on — the first card's subject, so
    /// it stands first.
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

    /// Cover every word the component draws (`cover-the-words.md`).
    ///
    /// **Straight after the display picker.** It is the only row here somebody
    /// opens this window in a hurry to find — everything under it is taste,
    /// answered once and left — and the picker stays first because it is the
    /// card's subject.
    ///
    /// **Never greyed, and it needs nothing of the display.** The panel is
    /// covered on any screen, notched or not.
    ///
    /// **The caption names the gesture**, which is how macOS teaches one. A
    /// secondary press on the component does this without the window, which is
    /// the form that matters — opening Settings mid-call is itself a thing on
    /// the shared screen, and that is why a pane deeper than before is enough.
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

    /// Give the black surface an edge of its own.
    ///
    /// In the first card rather than under `Collapsed` or `Expanded`, because
    /// it draws the same edge in both. Never greyed: any surface has an edge,
    /// notched or not.
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

    /// Give the cut-out back, and draw nothing beside it until something is
    /// wanted.
    ///
    /// **Always drawn, and always settable — including where it cannot apply
    /// yet.** A switch that appears only on a notched display is one nobody
    /// finds, and a greyed one makes the person sitting at the wrong screen
    /// come back later, on the right one, to say what they want. The store
    /// keeps `hidesCompactWings` and asks `canHideCompactWings` separately, so
    /// the setting waits for a screen that can honour it (§8.4.1). What the row
    /// owes the user instead is the truth about *this* screen, which the
    /// caption says in one line and the tooltip explains.
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

    /// Name the work between the pill's two ends.
    ///
    /// **Live on a notched display too, where it has nothing to do yet** — the
    /// mirror of `Hide the wings`, and settable for the same reason.
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

    /// One block per product on the live list, or one list.
    ///
    /// On, each product's rows stand under a heading that names them once, and
    /// every heading stays on screen however far the list is scrolled
    /// (`expanded-panel-v2.md` §4.6). Off, the rows keep one order across
    /// products and each names its product with its own badge. Either way the
    /// Recent queue is one list, and either way the viewport shows four rows.
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

    /// One of the store's own switches, read and written on the store.
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

/// The quota table's choices, and the transcripts its readings leave.
///
/// The transcripts row used to sit in the Products card, where it was the one
/// row about something other than connecting a product; it stands here beside
/// the readings that leave it.
struct QuotaSettingsPane: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        QuotaSettingsGroups(settings: QuotaSettings(store), store: store)
            .equatable()
    }
}

/// What the Quota pane draws, read off the store in one place.
struct QuotaSettings: Equatable {
    let productsHiddenFromQuotaTable: Set<AgentKind>
    let diskFootprints: [AgentKind: AgentDiskFootprintReport]

    init(_ store: MonitorStore) {
        productsHiddenFromQuotaTable = store.productsHiddenFromQuotaTable
        diskFootprints = store.diskFootprints
    }
}

/// The Quota pane's cards, drawn from ``QuotaSettings``.
struct QuotaSettingsGroups: View, Equatable {
    let settings: QuotaSettings
    /// Written through by the switches, and never read to draw.
    let store: MonitorStore

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.settings == rhs.settings
    }

    var body: some View {
        // Their own stack, for the reason ``DisplaySettingsGroups`` gives.
        VStack(alignment: .leading, spacing: 22) {
            quotaTableGroup

            // Only the products that leave anything have a key; the presence
            // of the key is what decides whether the row is drawn (CC-020), so
            // this is not a filter on the value, and a machine where nothing
            // does has no group.
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

    /// Which products get a block in the quota table (`quota-footer-v2.md` §13).
    ///
    /// **A card of switches, one per registered product**, in the order the
    /// table draws them — not a pop-up of checkmarks. A menu closes on every
    /// choice, so choosing two products out of four is four trips into it, and
    /// its closed label can only summarise what a card simply shows.
    ///
    /// **Every product is listed, connected or not.** The choice is a standing
    /// answer about what the table should hold, and the moment somebody wants
    /// to leave a product out is not necessarily a moment it is open.
    ///
    /// The footnote says the one thing a switch cannot: today's total counts
    /// every product whatever is on here. What a switch does is its tooltip.
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

    /// What reading the quota costs on disk, and a way to go and look.
    ///
    /// Shown rather than tidied away. Each reading is a real Claude Code
    /// session and leaves a transcript behind; the folder they go to belongs to
    /// Claude Code and can hold the user's own sessions as well, so this app
    /// reports the size and opens the door rather than deleting anything on
    /// somebody's behalf.
    ///
    /// The row is drawn from the first refresh, before there is a figure to put
    /// in it: `Calculating…` while a reading is actually out, `Unavailable`
    /// where none will ever start, and a button that is plainly not ready
    /// rather than one that would reveal nowhere (CC-020).
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
                // Beside the button rather than in the status slot: that slot
                // draws a health dot, and a number of megabytes is not a health.
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

/// Every caption and footnote a pane draws that does not come off a product's
/// own state, held apart from the views so a test can hold each to one line.
///
/// A caption says what the control does on this screen in one line at `580`
/// pt; anything longer is an explanation and belongs in the row's tooltip.
enum SettingsCaption {
    static let productsFootnote = "Switches edit only Notchline’s hooks, after a .notchline-backup copy."
    static let privacyMode = "Draws every name and line as a bar. Secondary-click Notchline to toggle."
    static let outline = "A hairline edge, for dark wallpapers."
    static let groupByProduct = "One block per product, each headed by its badge."
    static let quotaTableFootnote = "Today’s total counts every connected product, whatever is on here."

    /// What `Hide the wings` does on *this* display. The two ways a display
    /// can fail to qualify are named apart: a laptop's built-in screen
    /// reporting a notch it cannot place is a different situation from an
    /// external monitor, and a user reading `Needs a notched display` on a
    /// MacBook would reasonably conclude the app was broken.
    static func hideWings(canHide: Bool, geometry: DisplayGeometry) -> String {
        guard canHide else {
            guard geometry == .notched else {
                return "Waits for a display with a cut-out."
            }
            return "Waits for a display Notchline can measure."
        }
        return "Only the cut-out, until a turn needs you."
    }

    /// What `Name the work` does on *this* display.
    static func nameWork(canName: Bool) -> String {
        guard canName else {
            return "Waits for a display without a notch."
        }
        return "Names each live project between the counts and the clock."
    }

    static func quotaTranscripts(for agent: AgentKind) -> String {
        "Kept in \(agent.displayName)’s project folder. Notchline never deletes them."
    }

    /// Every caption a pane can draw, for the test that holds them to one line.
    static var all: [String] {
        [productsFootnote, privacyMode, outline, groupByProduct, quotaTableFootnote,
         nameWork(canName: true), nameWork(canName: false)]
            + [true, false].flatMap { canHide in
                DisplayGeometry.allCases.map { hideWings(canHide: canHide, geometry: $0) }
            }
            + AgentKind.allCases.map(quotaTranscripts(for:))
    }
}

/// The connections the app needs, as the rows that ask for them — one per
/// registered product.
///
/// Shared by first run and Settings rather than drawn twice. Every row asks for
/// managed setup in the same shape: one switch (ADR 0016). No-setup products
/// show observation status alone. Everything a row says about its product is
/// read off its ``ProductDescriptor``, so a new product is an element in the
/// registry and nothing here.
///
/// **Status and the switch, one line each, then ⓘ.** What a product watches,
/// what it will never show, its hooks file and its trust step are explanation
/// rather than state, and moved into ``ProductInfoPopover``. Every product has
/// one, so the column of ⓘ is straight down the card. A failure the product
/// reported never moves there (CR-029): it is the one line in this window that
/// exists to report something going wrong, and a click to find it is a failure
/// nobody sees.
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
            // Per row rather than around the card: a publish about one product
            // redraws that product's row, and an open ⓘ on another row is left
            // alone.
            .equatable()
        }
    }

    /// Read off that product's own answer, never the merged one. The Codex row
    /// used to read `store.availability`, which is ready when *any* product is,
    /// so a ready Claude Code made the Codex row say `Connected` on Claude
    /// Code's evidence (`integration-settings-behaviour.md` §4).
    private func copy(for descriptor: ProductDescriptor) -> ProductSettingsCopy {
        ProductSettingsCopy(
            descriptor: descriptor,
            setup: store.setupStatus(for: descriptor.kind),
            availability: store.agentAvailability(for: descriptor.kind),
            diagnostic: store.diagnostic(for: descriptor.kind)
        )
    }
}

/// One product's row, drawn from what ``ProductConnectionRows`` read for it.
struct ProductConnectionRow: View, Equatable {
    let descriptor: ProductDescriptor
    let copy: ProductSettingsCopy
    /// Where the switch sits. The switch reads the store itself; this is here
    /// so that the row redraws when it moves.
    let isOn: Bool
    let isBusy: Bool
    /// Written through by the switch, and never read to draw.
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

/// What a product's ⓘ popover says, read off its descriptor.
///
/// A value for ``ProductSettingsCopy``'s reason: the popover is where a
/// product's declared boundary now lives, and a value can be asserted by a
/// test where a `body` cannot.
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
    /// What setting the product up asks of the user beyond the switch — Codex's
    /// trust step, Trae's reopened windows.
    let setup: [Paragraph]
    /// The file this product's switch writes.
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
            // The trust step is phrased to follow a semicolon in the installed
            // message, so it gains a capital and a full stop to stand alone.
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

/// The ⓘ at the end of a product's row.
///
/// Drawn like ``ShowInFinderButton`` — a `14` pt glyph in a `22 × 22` target,
/// with a ground only under the pointer — and for its reason: a bordered shape
/// here would compete with the switch beside it. The ground also stays while
/// the popover is open, so it is plain which row the popover belongs to.
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

/// What a product's row used to say in three or four lines, on demand.
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
                        // Same rule as the glyph it replaced: a button with
                        // nowhere to go is greyed rather than silently inert.
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


/// The one-glyph way into a folder a row is about.
///
/// **A glyph rather than the words.** It was one of three down the Products
/// card — the file each product's hooks are registered in, and the folder the
/// quota readings leave transcripts in — where a capsule reading `Reveal in
/// Finder` on each was one sentence written out three times beside the
/// switches. The product rows' copies moved into their ⓘ popovers, where a
/// sentence has room and the capsule is back; the glyph stays on the
/// transcripts row, which has no popover to put it in.
///
/// They also stay in the accessibility label — `.accessibilityLabel` on the
/// glyph — so VoiceOver reads `Show in Finder` and not the name of an SF
/// Symbol.
///
/// **No border until the pointer is on it.** A bordered capsule around a
/// single glyph is a second shape competing with the switch beside it, on a
/// row where the switch is the control. Bare, the glyph reads as what it is —
/// a way through to somewhere — and the background that says it can be pressed
/// arrives on hover, which is when the question is being asked. The `22 × 22`
/// square is the click target rather than the drawing: the glyph is `12 × 12`
/// measured, and a target the size of the drawing would be a thing you aim at.
///
/// **Last in the row**, on the trailing edge, as the product rows' ⓘ is.
struct ShowInFinderButton: View {
    /// Where a press goes, and `nil` when there is nowhere for it to go —
    /// which is what greys the button out. Same rule the `Reveal in Finder`
    /// capsule was held to: a button that reveals nothing is worse than one
    /// that is plainly not ready (CC-020).
    let target: FinderRevealTarget?

    @State private var isHovering = false

    var body: some View {
        Button {
            target?.reveal()
        } label: {
            // Drawn to a measured `12 × 12` rather than set in a 12-point
            // font. A symbol at `.system(size: 12)` is sized to sit beside
            // 12-point *text*, not to be 12 points: `folder` under that
            // configuration measures `17 × 13`. `resizable` fits the glyph's
            // own box to the frame instead, so the number here is the size on
            // screen — measured off a screenshot at `12 × 9.5`, the second
            // figure being the folder's own aspect inside a square box.
            Image(systemName: "folder")
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
                // The words the `Label` used to carry. VoiceOver still reads
                // `Show in Finder` rather than the name of an SF Symbol.
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
                // The whole square takes the click, not just the glyph's own
                // strokes — a `folder` is mostly empty inside.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        // Nothing lights up under a button that cannot be pressed, so the
        // hover state is refused rather than drawn and then ignored.
        .onHover { isHovering = $0 && target != nil }
        .help("Show in Finder")
    }
}

/// Where a ``ShowInFinderButton`` press goes.
///
/// A value rather than a closure per row, for the reason ``ProductSettingsCopy``
/// is one: nothing in this window has a test that can press a button, but which
/// folder a press would open is a plain answer a test can assert.
nonisolated enum FinderRevealTarget: Equatable {
    /// Open the enclosing folder with this item selected.
    case select(URL)
    /// Open this folder itself, because the item the button points at is not
    /// in it yet.
    case open(URL)

    /// What revealing `url` should do, and `nil` when there is nothing on disk
    /// to reveal.
    ///
    /// **The file may not be there, and that is the ordinary case rather than
    /// an error.** Neither `~/.codex/hooks.json` nor `~/.claude/settings.json`
    /// exists until somebody — this app or the user — has put something in it,
    /// so a row whose switch has never been on points at a path with no file
    /// at the end of it, and `activateFileViewerSelecting` on one of those does
    /// nothing at all, silently. So the file is selected when it is there, the
    /// folder that would hold it is opened when it is not, and only a product
    /// with neither greys the button out.
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
///
/// **One rule for every product, reading the product's own availability.**
/// There used to be a factory per product with different control flow, and the
/// two disagreed in ways the behaviour document had to list as smells: the
/// Codex one read the merged availability, and let a registration written but
/// never trusted fall through to `Connected`. The rule now, top to bottom:
///
/// 1. A registration that does not match this build gets its own sentence,
///    because it is the failure with no other symptom. An event left out
///    simply never arrives; a handler in an older shape does arrive and
///    misbehaves quietly — an `http` handler from before ADR 0013 posts every
///    event to a port nothing listens on. Neither reports an error anywhere.
///    The app can repair it and the switch already reads off in this state, so
///    the sentence says to turn it on.
/// 2. Off is off.
/// 3. Written but never seen to fire, on a product with a trust step, says what
///    the step is. Only Codex can be here: Claude Code has no trust step and
///    never reports `reviewRequired`.
/// 4. Registered, and then whatever the product's own boundary says about
///    being able to watch. **`Connected` is a claim about being able to
///    watch**, so it needs `.ready`; registered and `.disconnected` is one
///    neutral headline for every way of being registered and blind — the
///    helper and its socket, no command to run, a command that will not
///    answer, an App Server that will not start — because each writes its own
///    diagnostic, that sentence is drawn directly underneath, and a headline
///    naming one of them would be wrong about the others.
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

/// A header, one card, and a footnote — the macOS 26 grouped-row shape.
///
/// The header is optional. A pane's first card can go without one, because the
/// pane's own name, in the toolbar and the title bar, already heads it.
///
/// The card is drawn here rather than taken from `Form`/`Section`, because §8
/// pins the metrics (`12` radius, `14 × 11` rows, `22` between groups) and a
/// grouped `Form` reaches none of them. The controls *inside* it are native, so
/// the switch, the popup and the capsule buttons are the real Tahoe shapes
/// rather than approximations of them.
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

/// A group whose card says everything, with no consequence left to footnote.
///
/// `EmptyView` is dropped from the stack rather than laid out, so the group
/// closes at the card and the `22` between groups is the only gap under it.
extension SettingsGroup where Footnote == EmptyView {
    init(header: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(header: header, content: content, footnote: { EmptyView() })
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
///
/// **The status and the caption are one line each.** A caption says what the
/// control does on this screen; anything longer is an explanation, and the
/// row's `help` holds it — over the whole row, not only the control, since the
/// words it continues are on the left. **The diagnostic is the exception and
/// has no limit**: a failure the product reported is drawn in primary ink under
/// a warning glyph and wraps if it must, because a truncated failure is a
/// failure nobody reads (CR-029).
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
        // A title alone sits in a shorter row, as the quota table's do: the
        // `11` that clears a caption line leaves a bare title floating.
        .padding(.vertical, caption == nil && status == nil && diagnostic == nil ? 9 : 11)
        // The row's empty middle takes the pointer too, so the tooltip is
        // there wherever the row is, not only over its words.
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

/// A row's tooltip, or no tooltip at all rather than an empty one.
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

/// Footnote text, optionally with a control on its trailing side.
struct SettingsFootnote<Accessory: View>: View {
    private let text: String
    private let accessory: () -> Accessory

    init(_ text: String, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.text = text
        self.accessory = accessory
    }

    var body: some View {
        // Baselines rather than tops, so a one-line footnote reads on the
        // line of its capsule's label instead of riding above it.
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
    /// What appears under a borderless glyph while the pointer is on it.
    ///
    /// Lighter than ``wellBackground``: that one is a recess something sits
    /// in permanently, this one is a control saying it can be pressed and has
    /// to stay quieter than the switch on the same row.
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

    /// Status dots take the system colours, which already carry the exact two
    /// values `Color / macOS Window` names — `status/green` is `systemGreen` in
    /// both modes — and stay correct under an accessibility appearance.
    static let statusHealthy = Color(nsColor: .systemGreen)
    static let statusWarning = Color(nsColor: .systemOrange)
    static let statusPending = Color(nsColor: .systemBlue)
    static let statusBlocked = Color(nsColor: .systemPurple)
    static let statusIdle = Color(nsColor: .systemGray)

    /// The ink of `Quit`, the one action in this window that ends something
    /// rather than changing it. The system red for the status dots' reason:
    /// it is the value macOS itself uses for exactly this, and it follows an
    /// accessibility appearance where a literal red would not.
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
///
/// And always while the window is off screen — that is what the two hooks are
/// for. `SettingsWindowTracker` reports the window as the view enters it, which
/// is before SwiftUI has ordered it anywhere, and the `isVisible` observation
/// puts it back on the right display the moment it is *hidden*, so the frame it
/// will next be shown at is already the right one. Placing it after it appears
/// is what the user sees as a flash: the window arriving on the display it was
/// last closed on and stepping across to this one a frame or two later.
@MainActor
enum SettingsWindowPresenter {
    private static weak var window: NSWindow?
    private static var visibility: NSKeyValueObservation?

    /// Opens Settings frontmost, centred on Notchline's display.
    static func present(using openSettings: () -> Void) {
        openSettings()
        DispatchQueue.main.async { reveal() }
    }

    /// Takes the window the `Settings` scene has just built, before it is on
    /// screen.
    ///
    /// Also the hook for any *other* way this window opens. `⌘,` and the app
    /// menu used to be one — they go through SwiftUI's own item, which this
    /// app does not see — and are now gone entirely, because an `LSUIElement`
    /// app has no menu bar to put that item in. Watching the window cross
    /// between hidden and shown catches whatever is left, and is what places
    /// the window anyway.
    static func track(_ window: NSWindow) {
        guard window !== Self.window else { return }
        Self.window = window
        // A window left on another Space comes to this one rather than taking
        // the user to it: what was asked for is Settings here, not a trip to
        // wherever it was last closed.
        window.collectionBehavior.insert(.moveToActiveSpace)
        visibility = window.observe(\.isVisible, options: [.old, .new]) { window, change in
            guard change.oldValue != change.newValue else { return }
            // KVO is delivered on the thread that ordered the window, which is
            // the main one.
            MainActor.assumeIsolated {
                // Both edges, and the *hiding* one is the load-bearing half:
                // it is the only moment the window can be moved with nobody
                // watching. The showing edge is a second chance at a window
                // that was somehow parked wrong, not the plan.
                place(window)
                guard change.newValue == true else { return }
                // Activation waits for the next turn rather than re-entering
                // AppKit while it is still ordering this window.
                DispatchQueue.main.async { reveal() }
            }
        }
        place(window)
        DispatchQueue.main.async { reveal() }
    }

    /// Centres the window on Notchline's display.
    ///
    /// Called only when the window cannot be seen — that is the whole design.
    /// Moving a window that is already on screen is a window the user watches
    /// jump, which is what this did when the move waited for the turn after
    /// SwiftUI ordered the window front: it appeared on the display it was
    /// last closed on, and stepped across to this one about `50 ms` later.
    private static func place(_ window: NSWindow) {
        // `NSScreen.main` only as the answer of last resort: the chosen display
        // has been unplugged since the store last looked, and a window with
        // nowhere of its own to go still has to be somewhere.
        guard let screen = MonitorStore.shared.selectedScreen ?? NSScreen.main
        else { return }

        let origin = SettingsWindowPlacement.origin(
            for: window.frame.size,
            on: screen.visibleFrame
        )
        guard window.frame.origin != origin else { return }
        window.setFrameOrigin(origin)
    }

    /// Brings the app and the window forward. The placing is `place`'s job and
    /// has already happened by here; the call is repeated because `present`
    /// reaches this on a window that was open all along.
    ///
    /// `ignoringOtherApps:` rather than the cooperative `NSApp.activate()`,
    /// because the cooperative call is a **request** and this app has already
    /// measured it being refused while returning as if it had not: at launch
    /// for an accessory application (see ``AppDelegate``) and with a
    /// full-screen application in the foreground (`tech-design.md` §14.2). A
    /// refusal here *is* the defect this presenter exists to prevent — the
    /// window is ordered to the front of this app's own list, this app stays
    /// behind, and what the user sees is a gear that opened Settings somewhere
    /// under the window they were already looking at. Ignoring other apps is
    /// what the gear is entitled to do: it answers a click the user has just
    /// made on this app's surface, which is the one moment an accessory
    /// application taking the foreground is the thing that was asked for.
    private static func reveal() {
        guard let window else { return }
        place(window)
        NSApp.activate(ignoringOtherApps: true)
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
        WindowReportingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Reports its window the instant it has one.
    ///
    /// `makeNSView` is too early — the view is not in a window yet — and a hop
    /// to the next turn is too late: SwiftUI orders the window on screen inside
    /// that turn, so a frame set afterwards is a window the user watches jump.
    /// `viewDidMoveToWindow` is the moment in between.
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
