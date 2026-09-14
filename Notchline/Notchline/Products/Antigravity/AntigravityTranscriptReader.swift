import Foundation

/// The prompt and model text, which Antigravity writes down but never sends.
nonisolated protocol AntigravityTranscriptReading: Sendable {
    /// Fields are nil where the file is absent, unreadable, or has no such step in the window.
    func tail(ofTranscriptAt path: String) -> AntigravityTranscriptTail
}

nonisolated struct AntigravityTranscriptTail: Sendable, Equatable {
    var latestUserRequest: String?
    /// The newest model text since the user last asked.
    var latestModelText: AntigravityModelText?

    nonisolated init(latestUserRequest: String? = nil, latestModelText: AntigravityModelText? = nil) {
        self.latestUserRequest = latestUserRequest
        self.latestModelText = latestModelText
    }
}

nonisolated struct AntigravityModelText: Sendable, Equatable {
    /// `step_index`, so the same words read at two events are one message.
    let step: Int
    let text: String
}

/// Reads the prompt and later model text from the JSONL transcript the payload names. On `agy`
/// 1.2.2 (2026-09-12) the user's step lands ~2 s before the first model response.
///
/// - The prompt is only the `<USER_REQUEST>` inside a `USER_INPUT` step's `content`;
///   `SYSTEM_MESSAGE` steps are excluded by `source`.
/// - A `PLANNER_RESPONSE` step is written whole when its call finishes (polled at 30 ms). Empty
///   `content` is skipped; `thinking` is never read. The walk back stops at the user's step.
/// - Only ``tailBytes`` is read, on the hook path; output past the window hides older steps.
/// - Nothing is written and no lock is taken, so it cannot race the product's append.
struct AntigravityTranscriptFile: AntigravityTranscriptReading {
    /// 256 KB: far past the 4 KB measured turns wrote, still bounded on the hook path.
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
        // A window starting mid-file opens on half a line.
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

    /// Nil for content without the envelope.
    nonisolated static func request(in content: String) -> String? {
        guard let open = content.range(of: requestOpen),
              let close = content.range(of: requestClose, range: open.upperBound..<content.endIndex)
        else { return nil }
        let request = content[open.upperBound..<close.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return request.isEmpty ? nil : request
    }
}
