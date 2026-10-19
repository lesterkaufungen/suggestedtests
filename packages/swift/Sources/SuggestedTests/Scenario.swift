/// Given/when/then steps whose failure names the failing step.
///
/// Each step runs as soon as it is chained; the first that throws stops the
/// chain with a ``ScenarioStepFailure``:
///
/// ```swift
/// func testAddingItemsUpdatesTheTotal() throws {
///   var cart = Cart()
///   try Scenario()
///     .given("an empty cart") { cart = Cart() }
///     .when("two items are added") { cart.add(10); cart.add(20) }
///     .then("the total is 30") { try check(cart.total == 30, "total is \(cart.total)") }
/// }
/// // Then: the total is 30
/// // check failed at CartTests/CartTests.swift:9: total is 20
/// // Passed steps:
/// //   ✓ Given: an empty cart
/// //   ✓ When: two items are added
/// ```
///
/// Steps must throw to fail: use ``check(_:_:file:line:)``, `XCTUnwrap` or
/// Swift Testing's `try #require`, not `XCTAssert…` (which doesn't throw).
public final class Scenario {
  private var passed: [String] = []

  /// Starts an empty scenario.
  public init() {
    NativeBridge.preload()
  }

  /// A precondition step.
  @discardableResult
  public func given(_ description: String, _ body: () throws -> Void) throws -> Scenario {
    try step("Given", description, body)
  }

  /// The action under test.
  @discardableResult
  public func when(_ description: String, _ body: () throws -> Void) throws -> Scenario {
    try step("When", description, body)
  }

  /// An expected outcome.
  @discardableResult
  public func then(_ description: String, _ body: () throws -> Void) throws -> Scenario {
    try step("Then", description, body)
  }

  /// Another step of the same kind as the previous one.
  @discardableResult
  public func and(_ description: String, _ body: () throws -> Void) throws -> Scenario {
    try step("And", description, body)
  }

  /// ``given(_:_:)`` with an async body.
  @discardableResult
  public func given(_ description: String, _ body: () async throws -> Void) async throws -> Scenario
  {
    try await step("Given", description, body)
  }

  /// ``when(_:_:)`` with an async body.
  @discardableResult
  public func when(_ description: String, _ body: () async throws -> Void) async throws -> Scenario
  {
    try await step("When", description, body)
  }

  /// ``then(_:_:)`` with an async body.
  @discardableResult
  public func then(_ description: String, _ body: () async throws -> Void) async throws -> Scenario
  {
    try await step("Then", description, body)
  }

  /// ``and(_:_:)`` with an async body.
  @discardableResult
  public func and(_ description: String, _ body: () async throws -> Void) async throws -> Scenario {
    try await step("And", description, body)
  }

  private func step(_ keyword: String, _ description: String, _ body: () throws -> Void) throws
    -> Scenario
  {
    do {
      try body()
    } catch {
      throw ScenarioStepFailure(keyword: keyword, step: description, error: error, passed: passed)
    }
    passed.append("\(keyword): \(description)")
    return self
  }

  private func step(
    _ keyword: String, _ description: String, _ body: () async throws -> Void
  ) async throws -> Scenario {
    do {
      try await body()
    } catch {
      throw ScenarioStepFailure(keyword: keyword, step: description, error: error, passed: passed)
    }
    passed.append("\(keyword): \(description)")
    return self
  }
}

/// A ``Scenario`` step threw.
public struct ScenarioStepFailure: Error, CustomStringConvertible {
  /// `Given`, `When`, `Then` or `And`.
  public let keyword: String
  /// The failing step's description.
  public let step: String
  /// What the step threw.
  public let error: Error
  /// The steps that passed before it, as `"Given: an empty cart"`.
  public let passed: [String]

  /// `Then: the total is 30`, what it threw, and the steps that passed.
  public var description: String {
    let passedSteps =
      passed.isEmpty ? "" : "\nPassed steps:" + passed.map { "\n  ✓ " + $0 }.joined()
    return "\(keyword): \(step)\n\(error)\(passedSteps)"
  }
}
