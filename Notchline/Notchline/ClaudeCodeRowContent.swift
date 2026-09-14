import Foundation

/// What a Claude Code row says beyond its Turn's own state: the working
/// directory for a project, the session's own title, and what this Turn has
/// said — and which Turns draw a row at all.
///
/// This product's ``RowContentSource``, taken out of `ClaudeCodeMonitorService`
/// on 2026-09-12. It reads the session list the refresh has just taken
/// (``ClaudeCodeSessionSource``): a Turn whose session is not on it draws no
/// row, which is the whole reason that list is load-bearing rather than a
/// convenience.
struct ClaudeCodeRowContent: RowContentSource {
    let sessions: ClaudeCodeSessionSource
    let transcripts: ClaudeCodeTranscriptReader

    func content(
        for turns: [HookTurnState],
        messages: TurnMessageReading
    ) async -> [String: RowContent] {
        let listed = await sessions.currentReading().sessionsByID
        // The titles the transcript reader holds, pruned to what this refresh's
        // reading says exists.
        await transcripts.retain(sessionIDs: Set(listed.keys))

        var content: [String: RowContent] = [:]
        for turn in turns {
            // A turn whose session is gone is gone.
            //
            // And a session the reducer has never heard of contributes no row
            // either -- whether it was already running when this app started,
            // or its hooks were registered after it began. The transcript can
            // name the turn such a session is part-way through, and for a while
            // the product read it; that reconstruction was removed rather than
            // extended. Nothing is written to the transcript while a turn waits
            // on the user, so a reconstructed row could only ever be Running --
            // and a session that was in fact sitting on a permission prompt when
            // this app launched was therefore shown as working, which is the one
            // answer the product exists to get right.
            guard let session = listed[turn.threadID] else { continue }
            content[turn.threadID] = RowContent(
                projectName: Self.projectName(for: session),
                // Empty when a title cannot be obtained -- the folder name is
                // never allowed to stand in for one -- and
                // ``MonitoredSession/init`` supplies
                // ``RowContentFallback/title`` for the row.
                title: await transcripts.title(
                    forSession: session.sessionID,
                    workingDirectory: session.workingDirectory
                ) ?? "",
                // The beginning of the newest message *this turn* printed, and
                // the prompt it started from until it has printed one. The first
                // half reads the same in every state: when a turn stops it is
                // exactly the PRD's "beginning of the final answer", and while
                // it runs it is the opening of whatever it last said — a weaker
                // reading of "latest progress" than Codex's and the deliberate
                // trade, since a rolling tail would track a long answer more
                // closely but would stop being the beginning of it at the moment
                // the turn ends. Messages between tool calls are mostly shorter
                // than the cap, so the two readings usually coincide. A wait
                // shows the words that led up to the question — never the
                // question's own tool arguments, the command being approved, or
                // a path.
                //
                // The second half is the same fallback Codex's `Running` row has
                // always had, and this product went without it: the store is
                // keyed by session, so a turn that had not spoken yet drew
                // either nothing at all (a session's first turn, or the first
                // after this app started listening) or the previous turn's
                // closing words — the row describing finished work as the work
                // in hand. Both are answered by asking the store for *this*
                // turn's text and falling back to what the user just typed.
                preview: messages.preview(forSession: session.sessionID, inTurn: turn.turnID)
                    ?? turn.promptPreview
            )
        }
        return content
    }

    /// Project is the working directory (ADR 0009). The ban on deriving a
    /// Project from a path binds Codex only: there a path approximates a
    /// grouping the user made, here the directory *is* the grouping -- it is
    /// what Claude Code itself files transcripts by. Empty when there is no
    /// working directory, which ``MonitoredSession/init`` reads as
    /// ``RowContentFallback/projectName``.
    nonisolated static func projectName(for session: ClaudeCodeSession) -> String {
        session.workingDirectory.lastPathComponent
    }
}
