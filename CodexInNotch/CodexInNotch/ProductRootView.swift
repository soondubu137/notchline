import AppKit
import SwiftUI

struct ProductRootView: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        // No shared backdrop: onboarding is a light-only design and paints its
        // own, while Settings paints the two-mode window colour. One colour
        // behind both would be wrong for whichever of them it did not belong to.
        Group {
            if store.hasCompletedOnboarding {
                AppSettingsView()
            } else {
                OnboardingView()
            }
        }
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
                    "A quiet, top-of-screen monitor for the turns you start while it is running — waiting, working, or finished but unread."
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
                    "The monitor tracks turns that start from now on. Turns already underway in Codex Desktop stay invisible until their next lifecycle event. Completed turns remain until you read them in Desktop."
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
