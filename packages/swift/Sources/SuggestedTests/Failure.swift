import Foundation

/// A failed check: thrown by every `expect…` / `assert…` helper.
///
/// XCTest and Swift Testing both report an error thrown from a test as a
/// failure, so the helpers work with either and depend on neither:
///
/// ```swift
/// func testParsingStaysFast() throws {             // XCTest
///   try expectPerformance(budget: 0.005) { parse(bigJSON) }
/// }
///
/// @Test func parsingStaysFast() throws {          // Swift Testing
///   try expectPerformance(budget: 0.005) { parse(bigJSON) }
/// }
/// ```
public struct SuggestedTestsFailure: Error, CustomStringConvertible, LocalizedError {
  /// What was wrong, and where.
  public let message: String

  /// Creates a failure with `message`.
  public init(_ message: String) {
    self.message = message
  }

  /// Ends `message` with the caller's position: XCTest on Linux reports a
  /// thrown error at `<EXPR>:0`.
  init(_ message: String, file: StaticString, line: UInt) {
    self.message = "\(message)\nat \(file):\(line)"
  }

  public var description: String { message }
  public var errorDescription: String? { message }
}

/// A helper was called with an invalid argument (a negative budget, zero
/// iterations, …). Thrown before the body runs.
public struct SuggestedTestsArgumentError: Error, CustomStringConvertible, LocalizedError {
  /// Which argument was wrong, and why.
  public let message: String

  init(_ message: String) {
    self.message = message
  }

  public var description: String { message }
  public var errorDescription: String? { message }
}

/// Throws a ``SuggestedTestsFailure`` if `condition` is false.
///
/// `XCTAssert…` records a failure without throwing, so `eventually`
/// and ``Scenario`` steps can't see it; `check` (or Swift Testing's
/// `try #require`) throws, which they retry or report:
///
/// ```swift
/// try eventually { try check(cache.isWarm, "cache is still cold") }
/// ```
public func check(
  _ condition: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
  file: StaticString = #fileID, line: UInt = #line
) throws {
  if try !condition() {
    let text = message()
    throw SuggestedTestsFailure(
      "check failed at \(file):\(line)" + (text.isEmpty ? "" : ": \(text)"))
  }
}
