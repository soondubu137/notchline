import Foundation

/// Runs blocking work on a GCD thread and suspends the caller until it returns: a child's pipes
/// read to the end, a `recv` left to run out its timeout.
///
/// Every `@MainActor` test in a run shares the one main thread, so blocking it holds up all the
/// others. On 2026-10-04, two expected 2 s `recv` timeouts and the hook helper's pipes held it for
/// about 6 s of a full run's opening burst. Every answer-row test whose 5 s `eventually` window
/// fell behind them failed, 23–36 per run.
func offTheMainThread<T: Sendable, Failure: Error>(
    _ work: @escaping @Sendable () throws(Failure) -> T
) async throws(Failure) -> T {
    let result: Result<T, Failure> = await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: Result(catching: work))
        }
    }
    return try result.get()
}
