import Foundation

/// What a Claude Code row says beyond its Turn's state, and which Turns draw a row: none for a
/// session missing from ``ClaudeCodeSessionSource``'s list.
struct ClaudeCodeRowContent: RowContentSource {
    let sessions: ClaudeCodeSessionSource
    let transcripts: ClaudeCodeTranscriptReader

    func content(
        for turns: [HookTurnState],
        messages: TurnMessageReading
    ) async -> [String: RowContent] {
        let listed = await sessions.currentReading().sessionsByID
        // Prune held titles to the sessions this refresh listed.
        await transcripts.retain(sessionIDs: Set(listed.keys))

        var content: [String: RowContent] = [:]
        for turn in turns {
            // No row for a session that is gone or that the reducer never heard of. Nothing is written
            // to the transcript while a Turn waits on the user, so a reconstruction could only be Running.
            guard let session = listed[turn.threadID] else { continue }
            content[turn.threadID] = RowContent(
                projectName: Self.projectName(for: session),
                // Empty when no title exists; the folder name never stands in (``RowContentFallback/title``).
                title: await transcripts.title(
                    forSession: session.sessionID,
                    workingDirectory: session.workingDirectory
                ) ?? "",
                // The beginning of the newest message this Turn printed, else its prompt. A wait shows the
                // words leading up to the question, never its tool arguments, command or a path.
                preview: messages.preview(forSession: session.sessionID, inTurn: turn.turnID)
                    ?? turn.promptPreview
            )
        }
        return content
    }

    /// Project is the working directory (ADR 0009); the path ban binds Codex only, since Claude
    /// Code files transcripts by directory. Empty reads as ``RowContentFallback/projectName``.
    nonisolated static func projectName(for session: ClaudeCodeSession) -> String {
        session.workingDirectory.lastPathComponent
    }
}
