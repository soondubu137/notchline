// The two answering shapes, walked into their state through the store's own acts
// (`takeAnswer(.option:)`, `takeAnswer(.affirmative)`), so a figure shows only reachable states.
import AppKit
import SwiftUI

@testable import Notchline

@MainActor
enum ApprovalSpecimens {
    struct Staged {
        let command: MonitorStore
        let series: MonitorStore
    }

    // MARK: - Form 01: a permission request

    /// The body draws the product's arguments as labelled fields (`answer-in-notch.md` §4.2); the
    /// command string is never parsed back out.
    static func commandRequest() -> AgentRequest {
        AgentRequest(
            id: "anatomy-command",
            toolName: "Bash",
            form: .command("npm run build -- --profile"),
            // Two fields: a third exceeds `requestBodyMaximumHeight` and the body scrolls, cutting a label.
            argumentFields: [
                ApprovalArgument(
                    id: "command",
                    label: "Command",
                    value: "npm run build -- --profile",
                    role: .code
                ),
                ApprovalArgument(
                    id: "description",
                    label: "Description",
                    value: "Build the production bundle and write a profile.",
                    role: .prose
                )
            ],
            answerHandle: AnswerHandle(ticket: 0)
        )
    }

    // MARK: - Form 03: questions

    static func seriesRequest() -> AgentRequest {
        func question(
            _ id: Int,
            _ header: String,
            _ text: String,
            _ options: [(String, String)]
        ) -> AgentQuestion {
            AgentQuestion(
                id: id,
                header: header,
                text: text,
                options: options.enumerated().map { index, option in
                    AgentQuestionOption(id: index, label: option.0, description: option.1)
                },
                allowsSeveralAnswers: false
            )
        }
        return AgentRequest(
            id: "anatomy-series",
            toolName: "AskUserQuestion",
            form: .questions([
                question(0, "Scope", "Which packages should the change cover?", [
                    ("Just the web app", "Leave the API and the shared packages alone."),
                    ("Web app and API", "Change both, and leave the shared packages alone."),
                    ("Every package", "Change all of them in one pass.")
                ]),
                question(1, "Rollout", "How should it reach production?", [
                    ("Behind a flag", "Ship it dark and turn it on per account."),
                    ("Straight to main", "Merge and deploy on the next release."),
                    ("In a release branch", "Hold it until the next scheduled release.")
                ]),
                question(2, "Docs", "What should the changelog say?", [
                    ("One line", "Name the change and nothing else."),
                    ("A short entry", "Name the change and what it affects."),
                    ("Nothing", "Leave it out of the changelog.")
                ])
            ]),
            answerHandle: AnswerHandle(ticket: 0)
        )
    }

    // MARK: - The rows

    private static func session(
        id: String,
        agent: AgentKind,
        project: String,
        title: String,
        preview: String?,
        status: SessionStatus,
        request: AgentRequest,
        at now: Date
    ) -> MonitoredSession {
        MonitoredSession(
            agent: agent,
            threadID: "anatomy-\(id)",
            turnID: "anatomy-\(id)-turn",
            projectName: project,
            title: title,
            preview: preview,
            status: status,
            startedAt: now.addingTimeInterval(-96),
            request: request
        )
    }

    private static func store(
        holding session: MonitoredSession,
        at now: Date
    ) -> MonitorStore {
        // No services; preferences are a throwaway suite, not `nil`
        // (``AnatomyFigureRenderer/preferences``).
        let store = MonitorStore(
            displays: [AnatomyFigureRenderer.panelDisplay],
            services: [],
            // Both products connected: the badge follows presence (`panel-v2.md` §2), so one product would
            // draw a caption with no chip.
            initialSnapshots: [AgentKind.codex, .claudeCode].map { agent in
                AgentSnapshot(
                    agent: agent,
                    availability: .ready,
                    sessions: agent == session.agent ? [session] : [],
                    quota: .unavailable,
                    diagnostic: nil,
                    setupStatus: .active,
                    presence: .open
                )
            },
            preferences: AnatomyFigureRenderer.preferences
        )
        store.isExpanded = true
        store.toggleOpenRow(session)
        return store
    }

    static func staged(at now: Date) -> Staged {
        let command = store(
            holding: session(
                id: "command",
                agent: .codex,
                project: "notchline",
                title: "Rebuild the checkout bundle",
                preview: "Ready to run the production build.",
                status: .approvalNeeded,
                request: commandRequest(),
                at: now
            ),
            at: now
        )
        // Arming alone, so `Approve` draws at its arrived weight rather than `45%`.
        command.stageSpecimenAnswer(selectedOptions: [])

        // A set of three drawn at the second, the only place both `Back` and `Next` stand.
        let series = store(
            holding: session(
                id: "series",
                agent: .claudeCode,
                project: "design-tokens",
                title: "Migrate the colour tokens",
                preview: nil,
                status: .inputNeeded,
                request: seriesRequest(),
                at: now
            ),
            at: now
        )
        // One call per question; the moving frontier is what puts `Back` on the row.
        series.stageSpecimenAnswer(selectedOptions: [1], showingQuestion: 0)
        series.stageSpecimenAnswer(selectedOptions: [0], showingQuestion: 1)

        return Staged(command: command, series: series)
    }
}
