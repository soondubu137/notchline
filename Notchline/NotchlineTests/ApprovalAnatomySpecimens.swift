// The two shapes a person answers in, staged as the product stages them.
//
// **Each specimen is walked into its state through the store's own acts**,
// never assigned one: the row is opened, options are ticked with
// `takeAnswer(.option:)` — the click an `OptionRow` sends — and a set is walked
// forward with `takeAnswer(.affirmative)`, which on any question but the last
// draws the next one and sends nothing (`MonitorStore.answerTheQuestion`). So a
// figure can only show a state the notch itself can reach.
import AppKit
import SwiftUI

@testable import Notchline

@MainActor
enum ApprovalSpecimens {
    /// The two, in the order the figure sets them beside each other.
    struct Staged {
        let command: MonitorStore
        let series: MonitorStore
    }

    // MARK: - Form 01: a permission request

    /// A `Bash` approval carrying the arguments the product sent, which is what
    /// the body draws as labelled fields (`answer-in-notch.md` §4.2). The
    /// command string stays as the compatibility reading and is never parsed
    /// back out.
    static func commandRequest() -> AgentRequest {
        AgentRequest(
            id: "anatomy-command",
            toolName: "Bash",
            form: .command("npm run build -- --profile"),
            // Two fields, because a third took the body past
            // `requestBodyMaximumHeight` (`140` then) and the row starts scrolling —
            // which is what the product should do and not what a picture of it
            // should show, with the last argument cut off mid-label.
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
        // No services, on `NotchSpecimen`'s terms: nothing is watched, no
        // socket is bound and no file of the user's is read. Preferences are a
        // throwaway suite rather than `nil` — see
        // ``AnatomyFigureRenderer/preferences``.
        let store = MonitorStore(
            displays: [AnatomyFigureRenderer.panelDisplay],
            services: [],
            // **Both products connected, with the rows on one of them.** The
            // badge is drawn on presence rather than on who has threads right
            // now (`panel-v2.md` §2), so a store holding one product draws a
            // caption line with no chip on it — which is a true drawing of a
            // one-product install and the wrong one to put beside a figure
            // whose every row carries a badge.
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
        // Nothing to tick on a permission request; this is the arming alone,
        // so `Approve` is drawn at the weight it wears once the row has
        // arrived rather than at the `45%` of a row still coming up.
        command.stageSpecimenAnswer(selectedOptions: [])

        // A set of three, one answer each, drawn at the second — which is the
        // only place both of a set's own controls stand: `Back`, because there
        // is a question behind this one, and `Next`, because there is one in
        // front. It is reached by answering the first, which is what a person
        // does and what draws the second.
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
        // Two calls, one per question: the first is the answer that was given
        // to `Scope`, the second is `Rollout` showing with an answer of its
        // own. The frontier moves with them, which is what puts `Back` on the
        // row.
        series.stageSpecimenAnswer(selectedOptions: [1], showingQuestion: 0)
        series.stageSpecimenAnswer(selectedOptions: [0], showingQuestion: 1)

        return Staged(command: command, series: series)
    }
}
