import Foundation
import Testing
@testable import Notchline

/// Every App Server frame's `id`, `error.code` and quota figure is read through `JSONValue`'s
/// integer accessors, so an out-of-range number must be a missing value, never a trap (#69).
struct JSONValueTests {
    @Test func aNumberAnIntegerCannotHoldReadsAsNoValue() throws {
        for text in ["1e300", "-1e300", "9223372036854775808", "-9.3e18"] {
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
            #expect(value.intValue == nil, "\(text)")
            #expect(value.int64Value == nil, "\(text)")
        }
    }

    @Test func aFractionIsStillTruncatedTowardZero() {
        #expect(JSONValue.number(42.5).intValue == 42)
        #expect(JSONValue.number(-42.5).intValue == -42)
        #expect(JSONValue.number(99.9).int64Value == 99)
        #expect(JSONValue.number(0).intValue == 0)
        #expect(JSONValue.number(9_007_199_254_740_992).int64Value == 9_007_199_254_740_992)
    }

    @Test func aQuotaWindowWithAnOutOfRangeFigureIsDroppedWithoutTheOtherOne() {
        let quota = CodexSnapshotParser.quota(from: .object([
            "rateLimits": .object([
                "primary": .object([
                    "usedPercent": .number(1e300),
                    "windowDurationMins": .number(300),
                    "resetsAt": .number(2_000)
                ]),
                "secondary": .object([
                    "usedPercent": .number(12.5),
                    "windowDurationMins": .number(1e300),
                    "resetsAt": .number(9_000)
                ])
            ])
        ]))

        #expect(quota.windows.map(\.remainingPercent) == [88])
    }
}
