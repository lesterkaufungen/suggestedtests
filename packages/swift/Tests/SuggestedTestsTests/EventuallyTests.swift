import XCTest

@testable import SuggestedTests

final class EventuallyTests: XCTestCase {
  func testRetriesUntilTheBodyStopsThrowing() throws {
    var attempts = 0
    let value = try eventually(timeout: 2, interval: 0.001) { () -> Int in
      attempts += 1
      try check(attempts >= 3, "not yet")
      return attempts
    }
    XCTAssertEqual(value, 3)
  }

  func testTimesOutWithTheLastError() {
    let line = #line + 1
    XCTAssertThrowsError(try eventually(timeout: 0.05, interval: 0.01) { try check(false, "cold") })
    {
      let message = "\($0)"
      XCTAssertTrue(message.hasPrefix("eventually: still failing after 50.00ms ("), message)
      XCTAssertTrue(
        message.hasSuffix("cold\nat SuggestedTestsTests/EventuallyTests.swift:\(line)"), message)
    }
  }

  func testAsyncVersion() async throws {
    let start = Date()
    try await eventually(timeout: 2, interval: 0.001) {
      try check(Date().timeIntervalSince(start) > 0.01)
    }
  }

  func testArgumentsAreValidatedBeforeTheBody() {
    var ran = false
    XCTAssertThrowsError(try eventually(timeout: -1) { ran = true }) {
      XCTAssertTrue($0 is SuggestedTestsArgumentError)
    }
    XCTAssertThrowsError(try eventually(interval: 0) { ran = true }) {
      XCTAssertTrue($0 is SuggestedTestsArgumentError)
    }
    XCTAssertFalse(ran)
  }

  func testCheckNamesItsPlace() {
    XCTAssertThrowsError(try check(1 > 2, "math")) {
      XCTAssertTrue(
        "\($0)".hasPrefix("check failed at SuggestedTestsTests/EventuallyTests.swift:"), "\($0)")
      XCTAssertTrue("\($0)".hasSuffix(": math"), "\($0)")
    }
    XCTAssertNoThrow(try check(true))
  }
}
