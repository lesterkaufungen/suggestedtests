import XCTest

@testable import SuggestedTests

final class UniqueTests: XCTestCase {
  func testNamesTheDuplicatesPositions() {
    let line = #line + 1
    XCTAssertThrowsError(try assertUnique([3, 1, 7, 4, 2, 7])) {
      XCTAssertEqual(
        "\($0)",
        "expected unique elements, but 7 appears at index 2 and 5\n"
          + "at SuggestedTestsTests/UniqueTests.swift:\(line)")
    }
  }

  func testUniqueElementsPass() throws {
    try assertUnique(["a", "b", "c"])
    try assertUnique([Int]())
  }
}
