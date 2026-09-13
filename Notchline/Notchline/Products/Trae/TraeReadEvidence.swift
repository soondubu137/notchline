import Darwin
import Foundation

/// Positive evidence for one exact completion. A missing proof is never an
/// authoritative empty unread set. Native focus/visibility stays at the boundary.
nonisolated struct TraeReadProof: Codable, Equatable, Sendable {
    let windowID: Int
    let threadID: String
    let turnID: String
    let messageID: String
    let observedAt: Double

    func matches(_ turn: TraeDisplayedTurn, requestedAt: Date, receivedAt: Date) -> Bool {
        windowID > 0 && [threadID, turnID, messageID].allSatisfy(TraeEvidenceBoundary.validID)
            && threadID == turn.threadID && turnID == turn.turnID && messageID == turn.messageID
            && turn.status != "in_progress" && turn.requests.isEmpty
            && observedAt.isFinite && observedAt >= requestedAt.timeIntervalSince1970
            && observedAt <= receivedAt.timeIntervalSince1970
            && receivedAt.timeIntervalSince(requestedAt) <= 2
    }
}

nonisolated protocol TraeReadReporting: Sendable {
    func readCompletions() async -> [TraeReadProof]
}

/// Stateless per-refresh readings, composed by TraeProvider. The shared gate
/// alone owns settling, immutable retirement and the next recheck deadline.
nonisolated struct TraeReadEvidence: ReadEvidenceSource {
    let screen: any ScreenAvailabilityReporting
    let foreground: any DesktopReadingReporting
    let transport: any TraeReadReporting

    func verdicts(for candidates: [ReadGateCandidate], now: Date) async -> ReadEvidenceJudgement {
        let terminal = candidates.filter { $0.row.agent == .trae && MonitorAggregation.effectiveStatus(of: $0.row) == .completed }
        guard !terminal.isEmpty else { return ReadEvidenceJudgement(verdicts: [:], diagnostic: nil) }
        // This known negative also parks the gate's user-wait deadline when the
        // screen is unavailable. No renderer IPC is needed in the background.
        guard screen.isAvailable(), await foreground.isInFrontOfTheUser() else {
            return judgement(terminal, proofs: [], now: now, knownUnread: true)
        }
        let proofs = await transport.readCompletions()
        guard screen.isAvailable(), await foreground.isInFrontOfTheUser() else {
            return judgement(terminal, proofs: [], now: now, knownUnread: true)
        }
        return judgement(terminal, proofs: proofs, now: now, knownUnread: false)
    }

    private func judgement(_ candidates: [ReadGateCandidate], proofs: [TraeReadProof], now: Date,
                           knownUnread: Bool) -> ReadEvidenceJudgement {
        var result: [String: ReadGateVerdict] = [:]
        for candidate in candidates {
            if let proof = proofs.first(where: {
                $0.threadID == candidate.row.threadID && $0.turnID == candidate.row.turnID
                    && $0.observedAt >= candidate.turnEndedAt.timeIntervalSince1970
            }) {
                result[candidate.row.id] = .judged(by: DesktopUnreadStateSnapshot(
                    unreadThreadIDs: [], source: .current, currentAsOf: Date(timeIntervalSince1970: proof.observedAt)))
            } else if knownUnread {
                result[candidate.row.id] = .judged(by: DesktopUnreadStateSnapshot(
                    unreadThreadIDs: [candidate.row.threadID], source: .current, currentAsOf: now))
            } else {
                // In particular, the gap between native completion and render
                // must not fabricate an unread->read edge that skips settling.
                result[candidate.row.id] = .judged(by: .unavailable("Trae has not confirmed this completion is visible."))
            }
        }
        return ReadEvidenceJudgement(verdicts: result, diagnostic: nil)
    }

    func forget() async {}
}

/// A short-lived same-user socket is separate from the sole lifecycle watch.
/// Slow/broken readers cannot reset that watch or feed lifecycle state.
nonisolated enum TraeReadQuery {
    private struct Reply: Decodable {
        let ok: Bool
        let schema: Int?
        let version: String?
        let reading: TraeReadProof?
    }
    static func read(path: String) -> TraeReadProof? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var timeout = timeval(tv_sec: 1, tv_usec: 0), noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        guard TraeBridgeTransport.connect(fd, path: path) == 0 else { return nil }
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { return nil }
        let request = Data("{\"op\":\"read\"}\n".utf8)
        guard request.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress, $0.count) }) == request.count else { return nil }
        let deadline = Date().addingTimeInterval(1)
        var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
        while data.count < 4096 && Date() < deadline {
            let count = Darwin.read(fd, &buffer, min(buffer.count, 4096 - data.count))
            guard count > 0 else { return nil }
            data.append(contentsOf: buffer.prefix(count))
            if let newline = data.firstIndex(of: 10) {
                guard newline == data.count - 1,
                      let reply = try? JSONDecoder().decode(Reply.self, from: Data(data[..<newline])),
                      reply.ok, reply.schema == 1, reply.version == TraeInstallation.traeVersion else { return nil }
                return reply.reading
            }
        }
        return nil
    }
}
