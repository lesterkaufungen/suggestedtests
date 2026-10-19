import XCTest

@testable import SuggestedTests

final class ScenarioTests: XCTestCase {
  func testStepsRunInOrder() throws {
    var log: [String] = []
    try Scenario()
      .given("a") { log.append("given") }
      .when("b") { log.append("when") }
      .then("c") { log.append("then") }
      .and("d") { log.append("and") }
    XCTAssertEqual(log, ["given", "when", "then", "and"])
  }

  func testAFailingStepIsNamedAndStopsTheRest() {
    var ranAfter = false
    XCTAssertThrowsError(
      try Scenario()
        .given("an empty cart") {}
        .when("two items are added") {}
        .then("the total is 30") { try check(false, "total is 20") }
        .and("nothing else runs") { ranAfter = true }
    ) { error in
      guard let failure = error as? ScenarioStepFailure else { return XCTFail("\(error)") }
      XCTAssertEqual(failure.keyword, "Then")
      XCTAssertEqual(failure.step, "the total is 30")
      XCTAssertEqual(failure.passed, ["Given: an empty cart", "When: two items are added"])
      XCTAssertTrue(
        failure.description.hasPrefix("Then: the total is 30\ncheck failed at "),
        failure.description)
      XCTAssertTrue(
        failure.description.hasSuffix(
          "Passed steps:\n  ✓ Given: an empty cart\n  ✓ When: two items are added"))
    }
    XCTAssertFalse(ranAfter)
  }

  func testAsyncSteps() async throws {
    var value = 0
    try await Scenario()
      .given("zero") { value = 0 }
      .when("an async add") {
        try await Task.sleep(nanoseconds: 1_000)
        value += 1
      }
      .then("one") { try check(value == 1) }
  }
}
