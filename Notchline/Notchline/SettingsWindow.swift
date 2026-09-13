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
        ScrollView(.vertical) {
            contents
        }
        .frame(width: 580, height: min(860, max(420,
            (NSScreen.screens.map { $0.visibleFrame.height }.min() ?? 940) - 80)))
        .background(MacOSWindowColor.windowBackground)
        .background(SettingsWindowChrome())
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: 22) {
            productsGroup
            displayGroup
            quotaGroup

            // The build version and the action that quits the app belong to
            // the window rather than to a settings group.
            //
            // The two sit at opposite ends of the closing row rather than side
            // by side on the left: a version is a fact to read and `Quit` is
            // the one action this window offers, and macOS puts a window's
            // action in its bottom trailing corner — beside the version it
            // read as a second caption someone had made pressable. Baselines
            // align rather than tops, so the version sits on the same line as
            // the button's label instead of riding above it.
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                AppVersionLine()

                Spacer(minLength: 16)

                // Red is in the label's ink, not in the bezel. `.tint` on
                // macOS's `.bordered` style does nothing at all — measured, the
                // capsule came back the standard grey — and `.borderedProminent`
                // draws its fill from the accent, which a window loses the
                // moment it stops being key: the red would leave every time the
                // user clicked something else. The ink holds in every state.
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
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacOSWindowColor.windowBackground)
    }

    // MARK: - Products

    /// Every product is a row in one card, not a group of its own.
    ///
    /// Rows come from ``ProductRegistry/builtIn``. Only products declaring
    /// managed setup carry a configuration switch and file-reveal action.
    private var productsGroup: some View {
        SettingsGroup(header: "Products") {
            ProductConnectionRows()

            // Only the products that leave anything have a key here; the
            // presence of the key is what decides whether the row is drawn
            // (CC-020), so this is not a filter on the value.
            ForEach(store.diskFootprints.keys.sorted(), id: \.self) { agent in
                if let report = store.diskFootprints[agent] {
                    SettingsSeparator()
                    transcriptRow(report, for: agent)
                }
            }
        } footnote: {
            SettingsFootnote(
                "Trae uses a companion extension; reopen its windows after installation. "
                    + "The other switches manage Notchline’s hooks and preserve your own settings. "
                    + "Existing hook files are copied to .notchline-backup before changes."
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
    ///
    /// `Calculating…` only while a reading is actually out. A machine with no
    /// Claude Code on it never starts one — the refresh stops at the setup gate
    /// — so the row there reads `Unavailable` from the first refresh rather
    /// than claiming progress on work that is never going to begin.
    private func transcriptRow(_ report: AgentDiskFootprintReport, for agent: AgentKind) -> some View {
        SettingsRow(
            title: "Quota reading transcripts",
            caption: "Each reading leaves one in \(agent.displayName)'s project folder. "
                + "Notchline never deletes them."
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

    // MARK: - Display

    /// Not on the redesign board, which shows the three confirmed groups only.
    ///
    /// It is a control that already exists and has nowhere else to live: the
    /// component appears on exactly one display and the user picks which. Kept
    /// in the same shape rather than dropped, and recorded in `figma-design.md`
    /// §8.4 so the board and the window can be reconciled deliberately.
    ///
    /// No footnote. Each row's own caption already names the consequence for
    /// the display that is actually selected — its geometry and menu bar
    /// height, or why the wings cannot be given up on it; a standing sentence
    /// about cut-outs and pills only said the same thing in the abstract.
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

            SettingsSeparator()

            privacyModeRow

            SettingsSeparator()

            hideWingsRow

            SettingsSeparator()

            nameWorkRow

            SettingsSeparator()

            outlineRow

            SettingsSeparator()

            groupByProductRow
        }
    }

    /// One block per product on the live list, or one list.
    ///
    /// Beside `Outline the panel` because it is the same kind of preference —
    /// what the surface draws, decided by the person looking at it — and it
    /// needs nothing of the display. On, each product's rows stand under a
    /// heading that names them once, and every heading stays on screen
    /// however far the list is scrolled (`expanded-panel-v2.md` §4.6). Off,
    /// the rows keep one order across products and each names its product
    /// with its own badge. Either way the Recent queue is one list, and
    /// either way the viewport shows four rows.
    private var groupByProductRow: some View {
        SettingsRow(
            title: "Group by product",
            caption: "One block per product, each headed by its badge. "
                + "Off, one list, with a badge on every row."
        ) {
            Toggle("Group by product", isOn: $store.groupsSessionsByProduct)
                .labelsHidden()
                .toggleStyle(.switch)
                .help(
                    "Stands each product's sessions under a heading that names "
                        + "them once, and keeps every heading on screen while "
                        + "the list scrolls — the block you are in at the top, "
                        + "the ones you have passed beside it, the ones still "
                        + "to come at the foot. Off, the list is one list in "
                        + "order of urgency, and every row carries its own badge."
                )
        }
    }

    /// Cover every word the component draws (`cover-the-words.md`).
    ///
    /// **Second in the group, straight after the display picker.** It is the
    /// only row here somebody opens this window in a hurry to find —
    /// everything under it is taste, answered once and left — and the picker
    /// stays first because it is the group's subject.
    ///
    /// **Never greyed, and it needs nothing of the display.** Unlike its two
    /// neighbours there is no display that cannot honour it: the panel is
    /// covered on any screen, notched or not. What differs by display is only
    /// how much of it is visible, and that is not a reason to gate a switch.
    ///
    /// **The caption names the gesture**, which is how macOS teaches one. A
    /// secondary press on the component does this without the window, which is
    /// the form that matters — opening Settings mid-call is itself a thing on
    /// the shared screen.
    private var privacyModeRow: some View {
        SettingsRow(
            title: "Privacy Mode",
            caption: "Every name, title and line is drawn as a bar, and the "
                + "pill stops naming the work. The mark, the counts and the "
                + "clock stay, and the panel waits for a click instead of "
                + "opening on hover. Secondary-click the component to turn it "
                + "on and off."
        ) {
            Toggle("Privacy Mode", isOn: $store.privacyMode)
                .labelsHidden()
                .toggleStyle(.switch)
                .help(
                    "Covers every word Notchline draws while somebody else is "
                        + "looking at the screen: each row's project, title "
                        + "and latest line becomes a bar, and the collapsed "
                        + "pill stops naming the work. Opening a row uncovers "
                        + "that row. The panel stops expanding when the "
                        + "pointer merely crosses it."
                )
        }
    }

    /// Name the work between the pill's two ends.
    ///
    /// **Live on a notched display too, where it has nothing to do yet** — the
    /// mirror of `Hide the wings`, and settable for the same reason: the person
    /// who wants it is setting it on the machine it does not apply to, and a
    /// preference is a standing answer rather than a command for right now.
    private var nameWorkRow: some View {
        SettingsRow(
            title: "Name the work",
            caption: nameWorkDescription
        ) {
            Toggle("Name the work", isOn: $store.namesWorkOnPill)
                .labelsHidden()
                .toggleStyle(.switch)
                .help(
                    "Names each project with a live turn in the middle of the "
                        + "collapsed component, five seconds apiece. Takes "
                        + "effect on a display without a notch — on a notched "
                        + "one the cut-out is where the name would stand."
                )
        }
    }

    /// What the row says, which is the consequence on *this* display.
    private var nameWorkDescription: String {
        guard store.canNameWorkOnPill else {
            return "On this display the cut-out stands where the name would "
                + "go, so this waits for one without a notch."
        }
        return "Each project with a live turn, named in turn between the "
            + "counts and the clock. The component keeps its width either way."
    }

    /// Give the cut-out back, and draw nothing beside it until something is
    /// wanted.
    ///
    /// **Always drawn, and always settable — including where it cannot apply
    /// yet.** A switch that appears only on a notched display is one nobody
    /// finds: the person who would want it is looking for it on the laptop they
    /// have just plugged an external monitor into, which is exactly the moment
    /// it would be missing. That argument was answered by drawing the row and
    /// greying out the switch, which fixed the finding and broke the setting —
    /// the display that cannot honour a preference is precisely the display
    /// somebody is sitting at when they decide what they want, and a greyed
    /// switch makes them come back later, on the right screen, to say it.
    ///
    /// **A preference is a standing answer, not a command for right now.** This
    /// one already survives the display that cannot honour it — the store keeps
    /// `hidesCompactWings` and asks `canHideCompactWings` separately, so the
    /// wings come back on the external monitor and go again on the built-in
    /// screen without the setting moving. Blocking the switch never protected
    /// anything; it only stopped the answer being given. What the row owes the
    /// user instead is the truth about *this* screen, which the caption says.
    private var hideWingsRow: some View {
        SettingsRow(
            title: "Hide the wings",
            caption: hideWingsDescription
        ) {
            Toggle("Hide the wings", isOn: $store.hidesCompactWings)
                .labelsHidden()
                .toggleStyle(.switch)
                .help(
                    "Leaves the collapsed component as the cut-out alone, with "
                        + "no clock beside it. The mark and its counts slide "
                        + "out while a turn is waiting on approval, on an "
                        + "answer, or to be read, and go back when it is dealt "
                        + "with. Takes effect on a display whose cut-out "
                        + "Notchline can measure."
                )
        }
    }

    /// Give the black surface an edge of its own.
    ///
    /// Beside `Hide the wings` because it is the same kind of preference —
    /// what the surface draws, decided by the person looking at it — and the
    /// two answer the same wallpaper from opposite ends: one gives the notch
    /// back, the other makes the panel visible where the wallpaper is as dark
    /// as it is.
    ///
    /// Never greyed. It needs nothing of the display: any surface has an edge,
    /// notched or not, collapsed or expanded.
    private var outlineRow: some View {
        SettingsRow(
            title: "Outline the panel",
            caption: "A hairline edge, for dark wallpapers."
        ) {
            Toggle("Outline the panel", isOn: $store.drawsSurfaceOutline)
                .labelsHidden()
                .toggleStyle(.switch)
                .help(
                    "Traces the sides and lower corners in a grey just off "
                        + "Notchline's own black, collapsed and expanded alike."
                )
        }
    }

    /// What the row says, which is the consequence on *this* display.
    ///
    /// Where the display cannot honour it, the caption says why and says the
    /// setting is waiting rather than refused. The two ways a display can fail
    /// to qualify are named apart rather than merged into one sentence about
    /// cut-outs: a laptop's built-in screen reporting a notch it cannot place
    /// is a different situation from an external monitor, and a user reading
    /// `Needs a notched display` on a MacBook would reasonably conclude the app
    /// was broken.
    private var hideWingsDescription: String {
        guard store.canHideCompactWings else {
            guard store.geometry == .notched else {
                return "This display has no cut-out to hide behind, so this "
                    + "waits for one that has."
            }
            return "This display reports a notch but not where it is, so this "
                + "waits for one Notchline can measure."
        }
        return "Collapsed, Notchline is the cut-out and nothing else — until a "
            + "turn needs you, when the mark and its counts slide out. "
            + "Hovering still opens the panel."
    }

    private var selectedDisplayDescription: String {
        guard let display = store.selectedDisplay else {
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

    private var displaySelection: Binding<String> {
        Binding(
            get: { store.selectedDisplayID },
            set: { store.selectDisplay(id: $0) }
        )
    }

    // MARK: - Quota

    /// Which products get a block in the quota table (`quota-footer-v2.md` §13).
    ///
    /// **A card of switches, one per registered product**, in the order the
    /// table draws them — not a pop-up of checkmarks. A menu closes on every
    /// choice, so choosing two products out of four is four trips into it, and
    /// its closed label can only summarise what a card simply shows. The
    /// Products card above already holds one row per product, so this one
    /// grows with the registry by the same rule.
    ///
    /// **Every product is listed, connected or not.** The choice is a standing
    /// answer about what the table should hold, and the moment somebody wants
    /// to leave a product out is not necessarily a moment it is open.
    ///
    /// The footnote says the one thing a switch cannot: today's total counts
    /// every product whatever is on here.
    private var quotaGroup: some View {
        SettingsGroup(header: "Quota table") {
            ForEach(Array(ProductRegistry.builtIn.enumerated()), id: \.element.kind) { index, descriptor in
                if index > 0 {
                    SettingsSeparator()
                }
                SettingsRow(title: descriptor.displayName) {
                    Toggle(
                        "Show \(descriptor.displayName) in the quota table",
                        isOn: quotaTableSelection(for: descriptor.kind)
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
        } footnote: {
            SettingsFootnote(
                "A product switched on gets its own block — its usage today "
                    + "and its limits — in the table under today’s total. The "
                    + "total counts every connected product either way. With "
                    + "every product off, the footer shows the total alone."
            )
        }
    }

    private func quotaTableSelection(for agent: AgentKind) -> Binding<Bool> {
        Binding(
            get: { store.showsInQuotaTable(agent) },
            set: { store.setShowsInQuotaTable($0, for: agent) }
        )
    }
}

/// The connections the app needs, as the rows that ask for them — one per
/// registered product.
///
/// Shared by first run and Settings rather than drawn twice. Every row asks for
/// managed setup in the same shape: one switch (ADR 0016). No-setup products
/// show observation status alone. The rows used to be
/// two hand-written blocks, and the help text under one of them said "five"
/// definitions for a product that writes seven; everything a row says about
/// its product is now read off its ``ProductDescriptor``, so a third product is
/// an element in the registry and nothing here.
///
/// What is left of the difference between products is in the footnote each
/// window draws under this view, because the switches write different files
/// and only some of them are followed by a trust step.
struct ProductConnectionRows: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        ForEach(Array(ProductRegistry.builtIn.enumerated()), id: \.element.kind) { index, descriptor in
            if index > 0 {
                SettingsSeparator()
            }
            row(for: descriptor)
        }
    }

    private func row(for descriptor: ProductDescriptor) -> some View {
        let copy = copy(for: descriptor)
        return SettingsRow(
            title: descriptor.settingsTitle,
            // A failure the product reported, or else what the product's rows
            // will never say; never both, and the failure wins because it is
            // the one that is happening.
            caption: copy.diagnostic ?? descriptor.declaredBoundary,
            status: SettingsRowStatus(color: copy.color, text: copy.status)
        ) {
            if descriptor.setup.isConfigurable {
                HStack(spacing: 10) {
                    Toggle(
                        "\(descriptor.displayName) integration",
                        isOn: integrationSelection(for: descriptor.kind)
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(store.isIntegrationBusy(for: descriptor.kind))
                    .help(descriptor.setup.switchHelp)

                    if let setup = descriptor.setup.managedHooks {
                        ShowInFinderButton(target: .revealing(setup.configurationFile(fileManager: .default)))
                    }
                }
            }
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

    private func integrationSelection(for agent: AgentKind) -> Binding<Bool> {
        Binding(
            get: { store.integrationSwitchIsOn(for: agent) },
            set: { store.setIntegrationEnabled($0, for: agent) }
        )
    }
}

/// The one-glyph way into a folder a row is about.
///
/// **A glyph rather than the words, because there are now three of them.** Each
/// row in the Products card names a place on disk — the file each product's
/// hooks are registered in, and the folder this app's quota readings leave
/// transcripts in — and a capsule reading `Reveal in Finder` on all three is
/// the same sentence written out three times down one card, beside the switch
/// that is what each product row is actually about. The folder glyph carries
/// the same action in a quarter of the width, and the words move to the tooltip.
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
/// **Last in the row, after the switch.** Every row in the Products card ends
/// with one, so they line up on the trailing edge in a single column — which
/// only works if nothing else follows them. It puts the switches a fixed step
/// inboard of that edge; they stay a column of their own, and a glyph with no
/// border of its own is not the thing that reads as the row's control.
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

/// A group whose card says everything, with no consequence left to footnote.
///
/// `EmptyView` is dropped from the stack rather than laid out, so the group
/// closes at the card and the `22` between groups is the only gap under it.
extension SettingsGroup where Footnote == EmptyView {
    init(header: String, @ViewBuilder content: @escaping () -> Content) {
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
