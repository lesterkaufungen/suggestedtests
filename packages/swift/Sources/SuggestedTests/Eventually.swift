import Dispatch
import Foundation

/// Runs `body` until it stops throwing, every `interval` seconds for up to
/// `timeout` seconds, and returns its result. Use it instead of a fixed sleep.
///
/// ```swift
/// try eventually { try check(cache.isWarm, "cache is still cold") }
/// let job = try eventually(timeout: 10) { try queue.finishedJob() }
/// ```
///
/// On timeout it throws a ``SuggestedTestsFailure`` with the last error.
/// The sync version blocks the thread between attempts; in async code use
/// `try await eventually { ... }`.
@discardableResult
public func eventually<T>(
  timeout: Double = 5, interval: Double = 0.02, file: StaticString = #fileID, line: UInt = #line,
  _ body: () throws -> T
) throws -> T {
  NativeBridge.preload()
  try checkTimes(timeout, interval)
  let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1e9)
  var attempts = 0
  while true {
    attempts += 1
    do {
      return try body()
    } catch {
      if DispatchTime.now().uptimeNanoseconds >= deadline {
        throw timedOut(timeout, attempts, error, file, line)
      }
      Thread.sleep(forTimeInterval: interval)
    }
  }
}

/// ``eventually(timeout:interval:_:)`` for an async body; waits with
/// `Task.sleep`, so it doesn't block a thread.
@discardableResult
public func eventually<T>(
  timeout: Double = 5, interval: Double = 0.02, file: StaticString = #fileID, line: UInt = #line,
  _ body: () async throws -> T
) async throws -> T {
  NativeBridge.preload()
  try checkTimes(timeout, interval)
  let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1e9)
  var attempts = 0
  while true {
    attempts += 1
    do {
      return try await body()
    } catch {
      if DispatchTime.now().uptimeNanoseconds >= deadline {
        throw timedOut(timeout, attempts, error, file, line)
      }
      try await Task.sleep(nanoseconds: UInt64(interval * 1e9))
    }
  }
}

private func checkTimes(_ timeout: Double, _ interval: Double) throws {
  if !(timeout >= 0) || !timeout.isFinite {
    throw SuggestedTestsArgumentError("timeout must be >= 0 seconds, got \(timeout)")
  }
  if !(interval > 0) || !interval.isFinite {
    throw SuggestedTestsArgumentError("interval must be > 0 seconds, got \(interval)")
  }
}

private func timedOut(
  _ timeout: Double, _ attempts: Int, _ error: Error, _ file: StaticString, _ line: UInt
) -> SuggestedTestsFailure {
  SuggestedTestsFailure(
    "eventually: still failing after \(formatNanoseconds(timeout * 1e9)) "
      + "(\(attempts) attempts). Last error:\n\(error)", file: file, line: line)
}
