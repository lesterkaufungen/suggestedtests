import SuggestedTests
import XCTest

final class CacheTests: XCTestCase {
  func testCacheWarmsUp() throws {
    try eventually { try check(cache.isWarm, "cache is still cold") }
  }
}
