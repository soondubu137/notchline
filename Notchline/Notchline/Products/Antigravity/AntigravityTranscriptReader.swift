import Foundation

/// The prompt and the model's words, which Antigravity CLI writes down but
/// never sends.
///
/// A seam so the translator can be tested against a transcript the test wrote,
/// and so the one file read on the hook path has a name.
nonisolated protocol AntigravityTranscriptReading: Sendable {
    /// What the end of the file says, from one read of it. Every field is nil
    /// where the file is absent, unreadable, or holds no such step in the
    /// window read.
    func tail(ofTranscriptAt path: String) -> AntigravityTranscriptTail
}

/// What one read of a transcript's tail found.
nonisolated struct AntigravityTranscriptTail: Sendable, Equatable {
    /// The most recent thing the user asked in this conversation.
    var latestUserRequest: String?
    /// The newest thing the model has said since the user last asked.
    var latestModelText: AntigravityModelText?

    nonisolated init(latestUserRequest: String? = nil, latestModelText: AntigravityModelText? = nil) {
        self.latestUserRequest = latestUserRequest
        self.latestModelText = latestModelText
    }
}

/// One model response's words, and the step they were written in.
nonisolated struct AntigravityModelText: Sendable, Equatable {
    /// The step's `step_index`. Which response this is, so that the same words
    /// read at two events are one message rather than two.
    let step: Int
    let text: String
}

/// Reads the prompt, and what the model has said since, out of the transcript
/// the payload already names.
///
/// **Why a file is read at all.** No Antigravity hook payload carries the
/// prompt — measured across all five events
/// (`docs/technical-explorations/multi-product-provider-architecture/antigravity-cli.md`
/// §1) — so every row said `Untitled`. The transcript the payload points at
/// carries it, and carries it *early*: measured 2026-09-12 on `agy` 1.2.2, the
/// user's step is appended about 2.7 s after launch and roughly two seconds
/// before the first model response, so it is on disk by the time this app has
/// a Turn to name. The file is JSONL, appended live rather than flushed at the
/// end — watched growing 0 → 1 → 2 lines across one turn.
///
/// **What a user step looks like**, and it is the same shape for the first
/// turn of a conversation and every turn after it:
///
/// ```json
/// {"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE",
///  "created_at":"2026-09-12T07:24:42Z",
///  "content":"<USER_REQUEST>\nList the files…\n</USER_REQUEST>\n<ADDITIONAL_METADATA>…"}
/// ```
///
/// Only what is inside `<USER_REQUEST>` is the prompt. The metadata that
/// follows it — the local time, and a note about a settings change — is the
/// product talking to its own model, and drawing it would put a timestamp on
/// the row where the user's words belong. `SYSTEM_MESSAGE` steps are excluded
/// by their `source`, which matters: one of them opens with the sentence *"The
/// following is a `<SYSTEM_MESSAGE>` not actually sent by the user"*, and that
/// is exactly what it would be if the type were not checked.
///
/// **What a model step looks like**, measured 2026-09-12 on the same build:
///
/// ```json
/// {"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE",
///  "content":"I will execute the command for you right away.",
///  "thinking":"…","tool_calls":[…]}
/// ```
///
/// One per model call, **written whole once the call has finished** — polled
/// at 30 ms, a step never appeared half-written or `RUNNING` — with the words
/// the user sees in `content`. A call that only calls a tool has an empty
/// `content` and is passed over, so the row keeps the last thing actually said.
/// `thinking` is the model's reasoning and is never read (`CONTEXT.md`,
/// *Current content preview*). The walk back stops at the user's step: past it
/// every word belongs to an earlier turn.
///
/// **Three ceilings, stated.**
///
/// - **Only the tail is read** — ``tailBytes`` — because this runs on the hook
///   delivery path and a conversation's transcript grows without bound. At a
///   turn's first invocation the user's step is the last line in the file, so
///   the window is enormously generous; on the late re-read (see
///   ``AntigravityPayloadTranslator``) a turn that produced more than the
///   window keeps `Untitled` rather than costing a full read. The model's words
///   are nearly always the last step or two, but a tool that returned more than
///   the window after them hides them, and the row keeps the words it had.
/// - **It answers for the conversation, not for the Turn.** The last request
///   in the file is this Turn's prompt whenever the user started the Turn,
///   which is every Turn measured. A Turn the product started for itself —
///   nothing observed does, but nothing rules it out — would draw the last
///   thing the user asked, which is what the conversation is still about.
/// - **Nothing is written and no lock is taken**, so this cannot race the
///   product's own append.
struct AntigravityTranscriptFile: AntigravityTranscriptReading {
    /// How much of the end of the transcript one reading looks at.
    ///
    /// 256 KB: four orders of magnitude past the 4 KB the measured turns wrote,
    /// and still a bounded read on a path that must not stall a hook.
    static let tailBytes = 256 * 1024

    private static let requestOpen = "<USER_REQUEST>"
    private static let requestClose = "</USER_REQUEST>"

    nonisolated init() {}

    nonisolated func tail(ofTranscriptAt path: String) -> AntigravityTranscriptTail {
        var found = AntigravityTranscriptTail()
        guard let handle = FileHandle(forReadingAtPath: path) else { return found }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return found }
        let offset = size > UInt64(Self.tailBytes) ? size - UInt64(Self.tailBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let tail = try? handle.readToEnd(), !tail.isEmpty else {
            return found
        }

        var lines = tail.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        // A window that started mid-file opens on half a line, which is not
        // JSON and would only ever be discarded a step later; dropped here so
        // the reverse walk does not have to know about it.
        if offset > 0, !lines.isEmpty {
            lines.removeFirst()
        }
        var passedAUserStep = false
        for line in lines.reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                continue
            }
            switch object["type"] as? String {
            case "PLANNER_RESPONSE" where !passedAUserStep && found.latestModelText == nil:
                guard let step = (object["step_index"] as? NSNumber)?.intValue,
                      let content = object["content"] as? String,
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                found.latestModelText = AntigravityModelText(step: step, text: content)
            case "USER_INPUT":
                passedAUserStep = true
                guard object["source"] as? String == "USER_EXPLICIT",
                      let content = object["content"] as? String,
                      let request = Self.request(in: content) else {
                    continue
                }
                found.latestUserRequest = request
                return found
            default:
                continue
            }
        }
        return found
    }

    /// What the user actually asked, out of the envelope the product wraps it
    /// in. A step whose content carries no envelope is not a request this app
    /// can read, and is skipped rather than drawn whole.
    nonisolated static func request(in content: String) -> String? {
        guard let open = content.range(of: requestOpen),
              let close = content.range(of: requestClose, range: open.upperBound..<content.endIndex)
        else { return nil }
        let request = content[open.upperBound..<close.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return request.isEmpty ? nil : request
    }
}
