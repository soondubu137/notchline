import Foundation
import Testing
@testable import Notchline

@MainActor
struct TraeSoloBoundaryTests {
    @Test func recordedSoloTurnsKeepRequestIdentityThroughReconnectSkipAndCancellation() async throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Trae/solo-3.5.91.jsonl")
        let frames = try Data(contentsOf: file).split(separator: 10).map {
            try JSONDecoder().decode(TraeFrame.self, from: Data($0))
        }
        #expect(frames.count == 22)
        let first = "6aa642888ab013dda2150eb0"
        let second = "6aa644278ab013dda2150ebd"
        let secondTurn = "6aa644cd8ab013dda2150ee2"
        let thirdTurn = "6aa6464a8ab013dda2150efc"
        var boundary = TraeEvidenceBoundary()
        let repository = MonitoringRepository(policy: .explicit)
        var skippedRequest: String?

        for (index, frame) in frames.enumerated() {
            if index > 0, frame.baseline == true { boundary.lost(peer: "solo") }
            try boundary.consume(frame, peer: "solo", repository: repository,
                                 epoch: repository.observationEpoch)
            let state = await repository.drainDeliveredEvents()
            let a = state.turns.first { $0.threadID == first }
            let b = state.turns.first { $0.threadID == second }
            switch index {
            case 0:
                // Readable, but it makes no submission or monitored row.
                #expect(state.turns.isEmpty)
                let request = try #require(frame.rows?.first?.requests.first)
                #expect(request.questions?.count == 3)
                #expect(request.questions?[1].multiple == true)
                #expect(request.questions?[0].maximumTextLength == 500)
                #expect(request.questions?[2].optional == true)
                #expect(request.questions?[2].maximumTextLength == 1000)
            case 1:
                #expect(a == nil)
                #expect(b?.status == .running)
            case 5:
                // This sandboxed command actually ran without a manual wait.
                #expect(b?.status == .completed)
                #expect(b?.requestsAwaitingAnAnswer.isEmpty == true)
            case 10:
                #expect(a?.turnID == secondTurn)
                #expect(a?.status == .running)
                #expect(b?.status == .completed)
            case 11, 14:
                // The same native request survives observer reconnection.
                #expect(a?.turnID == secondTurn)
                #expect(a?.status == .inputNeeded)
                let request = try #require(a?.requestsAwaitingAnAnswer.first)
                #expect(request.id.hasSuffix("6aa644d08ab013dda2150ee6"))
                #expect(request.operations == .readingOnly)
                #expect(!request.canBeAnswered)
            case 13:
                // Entering Plan withholds its route; it does not invent an end
                // or admit the excluded Plan Turn under the previous identity.
                #expect(boundary.peer(for: second) == nil)
                #expect(b?.turnID == "6aa644288ab013dda2150ec3")
            case 15, 21:
                #expect(a?.status == .completed)
                #expect(a?.requestsAwaitingAnAnswer.isEmpty == true)
            case 17:
                #expect(a?.turnID == thirdTurn)
                #expect(a?.status == .running)
                #expect(a?.requestsAwaitingAnAnswer.isEmpty == true)
            case 18:
                #expect(a?.status == .inputNeeded)
                skippedRequest = try #require(a?.requestsAwaitingAnAnswer.first?.id)
            case 19:
                #expect(a?.status == .running)
                #expect(a?.requestsAwaitingAnAnswer.isEmpty == true)
            case 20:
                #expect(a?.turnID == thirdTurn)
                #expect(a?.status == .inputNeeded)
                let requests = try #require(a?.requestsAwaitingAnAnswer)
                #expect(requests.count == 1)
                #expect(requests.first?.id != skippedRequest)
                #expect(requests.first?.id.hasSuffix("6aa6467f8ab013dda2150f03") == true)
            default:
                break
            }
        }
    }
}
