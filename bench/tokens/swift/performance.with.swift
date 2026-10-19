import SuggestedTests
import XCTest

final class ParserTests: XCTestCase {
  func testParsingStaysFast() throws {
    try expectPerformance(budget: 0.005) { parse(bigJSON) }
  }
}
