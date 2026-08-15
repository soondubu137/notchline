import AppKit
import SwiftUI

struct ProductRootView: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        Group {
            if store.hasCompletedOnboarding {
                AppSettingsView()
            } else {
                OnboardingView()
            }
        }
        .background(Color(red: 0.973, green: 0.976, blue: 0.980))
    }
}

private struct OnboardingView: View {
    @EnvironmentObject private var store: MonitorStore
    @State private var step = 0
    @State private var isAwaitingHookTrust = false
    @State private var setupMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("STEP \(step + 1) OF 3")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignColor.tertiaryText)

            Group {
                switch step {
                case 0:
                    welcomeContent
                case 1:
                    connectContent
                default:
                    readyContent
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 32)
        .frame(width: 580, height: 588, alignment: .topLeading)
        .background(DesignColor.windowBackground)
        .background(WindowTitleSetter(title: windowTitle))
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            NotchPreview()
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                pageTitle("Keep every Codex turn in view")
                bodyText(
                    "A quiet, top-of-screen monitor for the turns that are running, waiting, or finished but unread."
                )
            }

            BenefitRow(
                systemImage: "person.crop.circle.badge.exclamationmark",
                title: "Know what needs you",
                detail: "Input and approval requests rise above background work."
            )
            BenefitRow(
                systemImage: "arrow.up.forward.app",
                title: "Return to the exact chat",
                detail: "Every visible row opens the same Codex Desktop thread."
            )

            Spacer(minLength: 0)
            PrimaryButton(title: "Continue") {
                step = 1
            }
        }
    }

    private var connectContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                pageTitle("Connect to Codex Desktop")
                bodyText(
                    "Codex in Notch needs your confirmation before it installs or registers any user-level integration."
                )
            }

            BenefitRow(
                systemImage: "doc.text.magnifyingglass",
                title: "Read supported local metadata",
                detail: "Active state, Desktop Projects, chat titles, and public progress."
            )
            BenefitRow(
                systemImage: "gauge.with.dots.needle.33percent",
                title: "Read the account quota window",
                detail: "The same primary quota source used by the current Codex account."
            )

            InformationBlock(
                title: isAwaitingHookTrust
                    ? "Review the integration in Codex"
                    : "Local, minimal, and reversible",
                detail: isAwaitingHookTrust
                    ? "Open /hooks in Codex, trust the new definitions, start a turn, then recheck the connection."
                    : "No prompt or answer is persisted by Codex in Notch. Setup can be removed later from Settings.",
                color: DesignColor.blueInformation
            )

            if let setupMessage {
                Text(setupMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.82, green: 0.12, blue: 0.15))
            }

            Spacer(minLength: 0)

            PrimaryButton(
                title: isAwaitingHookTrust ? "Recheck Connection" : "Set Up Integration",
                isBusy: store.isInstallingIntegration
            ) {
                Task {
                    if isAwaitingHookTrust {
                        let status = await store.recheckIntegrationAndWait()
                        if status == .active {
                            setupMessage = nil
                            step = 2
                        } else {
                            setupMessage = "Codex has not delivered a trusted lifecycle event yet."
                        }
                    } else if await store.installIntegrationHooksAndWait() {
                        isAwaitingHookTrust = true
                        setupMessage = nil
                    }
                }
            }

            SecondaryButton(title: "Back") {
                step = 0
            }
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color(red: 0.11, green: 0.68, blue: 0.31))
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                pageTitle("Codex is connected")
                bodyText(
                    "The monitor will now rebuild its list from active Codex Desktop turns. Completed turns remain until archived or deleted in this test build."
                )
            }

            BenefitRow(
                systemImage: "waveform.path.ecg",
                title: "Real-time turn state",
                detail: "Running, input, approval, and completed states."
            )
            BenefitRow(
                systemImage: "arrow.up.forward.app",
                title: "Exact chat navigation",
                detail: "The supported Codex deep link targets the same Desktop thread."
            )

            InformationBlock(
                title: "Content previews are on by default",
                detail: "You can hide all current-content previews at any time in Settings.",
                color: DesignColor.greenInformation
            )

            Spacer(minLength: 0)
            PrimaryButton(title: "Start Monitoring") {
                store.completeOnboarding()
            }
        }
    }

    private var windowTitle: String {
        switch step {
        case 0: "Welcome"
        case 1: "Connect to Codex"
        default: "Ready"
        }
    }

    private func pageTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(DesignColor.primaryText)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(DesignColor.secondaryText)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct AppSettingsView: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(red: 0.03, green: 0.45, blue: 0.98))
                        .frame(width: 8, height: 8)
                    Text("General")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignColor.primaryText)
                }
                .padding(.horizontal, 10)
                .frame(width: 142, height: 34, alignment: .leading)
                .background(DesignColor.sidebarSelection, in: RoundedRectangle(cornerRadius: 8))

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 24)
            .frame(width: 180, height: 680, alignment: .topLeading)
            .background(DesignColor.sidebar)

            VStack(alignment: .leading, spacing: 18) {
                Text("General")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(DesignColor.primaryText)

                displayCard
                integrationCard
                privacyCard

                Text("Settings affect Codex in Notch only. Passive Notch states never modify Codex.")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignColor.tertiaryText)

                Spacer(minLength: 0)
            }
            .padding(.leading, 32)
            .padding(.trailing, 34)
            .padding(.vertical, 30)
            .frame(width: 500, height: 680, alignment: .topLeading)
            .background(DesignColor.windowBackground)
        }
        .frame(width: 680, height: 680)
        .background(WindowTitleSetter(title: "Codex in Notch Settings"))
    }

    private var displayCard: some View {
        SettingsCard {
            Text("Display")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show Codex in Notch on")
                        .font(.system(size: 13, weight: .medium))
                    Text(selectedDisplayDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignColor.tertiaryText)
                }

                Spacer(minLength: 12)

                if store.displays.isEmpty {
                    Text("No display available")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignColor.tertiaryText)
                } else {
                    Picker("Display for Codex in Notch", selection: displaySelection) {
                        ForEach(store.displays) { display in
                            Text(display.pickerTitle).tag(display.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
            }
            .frame(minHeight: 42)
        }
    }

    private var integrationCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(integrationColor)
                        .frame(width: 10, height: 10)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(integrationTitle)
                            .font(.system(size: 14, weight: .semibold))
                        Text(integrationDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(DesignColor.tertiaryText)
                    }
                }

                Spacer(minLength: 12)

                Toggle("Codex in Notch integration", isOn: integrationSelection)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(
                        store.isInstallingIntegration
                            || store.isRemovingIntegration
                    )
                    .help("Turns all six required Codex lifecycle hooks on or off together.")
            }

            Text(
                "One switch installs or removes all six required lifecycle definitions. Other Codex hooks are left unchanged."
            )
            .font(.system(size: 12))
            .foregroundStyle(DesignColor.secondaryText)
            .lineSpacing(2)

            HStack(spacing: 10) {
                SettingsButton(title: "Recheck") {
                    store.refreshNow()
                }
                SettingsButton(
                    title: store.isClearingSessions
                        ? "Clearing…"
                        : "Clear Session List",
                    isDestructive: true
                ) {
                    store.clearSessions()
                }
                .disabled(store.sessions.isEmpty || store.isClearingSessions)
                .help("Clears rows from Codex in Notch without deleting Codex chats.")
            }
        }
    }

    private var privacyCard: some View {
        SettingsCard {
            Text("Privacy")
                .font(.system(size: 15, weight: .semibold))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show current content previews")
                        .font(.system(size: 13, weight: .medium))
                    Text(
                        store.showsContentPreviews
                            ? "User-visible prompt, progress, and final-answer snippets."
                            : "Projects, titles, and status remain visible."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(DesignColor.tertiaryText)
                }
                Spacer()
                Toggle("Show current content previews", isOn: $store.showsContentPreviews)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .frame(height: 58)

            InformationBlock(
                title: store.showsContentPreviews
                    ? "Previews are on by default"
                    : "Preview content is hidden",
                detail: store.showsContentPreviews
                    ? "No preview text is persisted by Codex in Notch."
                    : "Prompt fallback is disabled; missing Desktop titles display as Untitled.",
                color: store.showsContentPreviews
                    ? DesignColor.sidebarSelection
                    : Color(red: 0.941, green: 0.945, blue: 0.957),
                height: 68
            )
        }
    }

    private var integrationTitle: String {
        if store.hookSetupStatus == .repairRequired {
            return "Codex integration needs repair"
        }
        if store.hookSetupStatus == .notInstalled {
            return "Codex integration is off"
        }

        return switch store.availability {
        case .ready: "Codex Desktop connected"
        case .setupRequired: "Codex integration not installed"
        case .connecting: "Connecting to Codex Desktop"
        case .updateCodex: "Update Codex Desktop"
        case .unsupportedVersion: "Codex version unsupported"
        case .disconnected: "Codex Desktop disconnected"
        }
    }

    private var integrationDetail: String {
        store.availability == .ready && store.hookSetupStatus == .active
            ? "Compatible version detected"
            : store.hookSetupStatus.displayName
    }

    private var integrationColor: Color {
        if store.hookSetupStatus == .repairRequired {
            return Color(red: 0.96, green: 0.58, blue: 0.10)
        }
        if store.hookSetupStatus == .notInstalled {
            return Color(red: 0.56, green: 0.56, blue: 0.58)
        }

        return switch store.availability {
        case .ready:
            Color(red: 0.11, green: 0.68, blue: 0.31)
        case .connecting:
            Color(red: 0.03, green: 0.45, blue: 0.98)
        case .setupRequired:
            Color(red: 0.56, green: 0.56, blue: 0.58)
        case .updateCodex, .unsupportedVersion, .disconnected:
            Color(red: 0.75, green: 0.35, blue: 0.95)
        }
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

    private var selectedDisplayDescription: String {
        guard let display = store.selectedDisplay else {
            return "Connect a display to choose where the component appears."
        }

        let geometry = display.geometry == .notched
            ? "Notch display"
            : "Display without a notch"
        return "\(geometry) · \(Int(display.menuBarHeight.rounded())) pt menu bar"
    }
}

private struct NotchPreview: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(red: 0.04, green: 0.52, blue: 1))
                .frame(width: 8, height: 8)
            Text("Codex in Notch")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Circle()
                .stroke(.white, lineWidth: 2)
                .frame(width: 18, height: 18)
        }
        .padding(.horizontal, 22)
        .frame(width: 300, height: 72)
        .background(.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct BenefitRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.03, green: 0.45, blue: 0.98))
                .frame(width: 28, height: 28)
                .background(DesignColor.sidebarSelection, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignColor.primaryText)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignColor.secondaryText)
                    .lineLimit(2)
            }
        }
        .frame(height: 44)
    }
}

private struct InformationBlock: View {
    let title: String
    let detail: String
    let color: Color
    var height: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignColor.primaryText)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(DesignColor.secondaryText)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
        .background(color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PrimaryButton: View {
    let title: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .foregroundStyle(.white)
            .background(
                Color(red: 0.02, green: 0.45, blue: 0.98),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}

private struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(DesignColor.primaryText)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DesignColor.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .frame(width: 434, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignColor.border, lineWidth: 1)
        }
    }
}

private struct SettingsButton: View {
    let title: String
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    isDestructive
                        ? Color(red: 0.82, green: 0.12, blue: 0.15)
                        : DesignColor.primaryText
                )
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(.white, in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(DesignColor.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct WindowTitleSetter: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.title = title
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = title
        }
    }
}

private enum DesignColor {
    static let windowBackground = Color(red: 0.973, green: 0.976, blue: 0.980)
    static let sidebar = Color(red: 0.933, green: 0.941, blue: 0.949)
    static let sidebarSelection = Color(red: 0.878, green: 0.941, blue: 1)
    static let blueInformation = Color(red: 0.898, green: 0.949, blue: 1)
    static let greenInformation = Color(red: 0.898, green: 0.980, blue: 0.929)
    static let primaryText = Color(red: 0.075, green: 0.082, blue: 0.102)
    static let secondaryText = Color(red: 0.341, green: 0.361, blue: 0.412)
    static let tertiaryText = Color(red: 0.478, green: 0.502, blue: 0.549)
    static let border = Color(red: 0.820, green: 0.839, blue: 0.878)
}

#Preview("Onboarding") {
    ProductRootView()
        .environmentObject(MonitorStore())
}
