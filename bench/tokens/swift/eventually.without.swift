import Foundation
import XCTest

final class CacheTests: XCTestCase {
  func testCacheWarmsUp() {
    let deadline = Date().addingTimeInterval(5)
    while !cache.isWarm {
      if Date() >= deadline {
        XCTFail("cache is still cold after 5 s")
        return
      }
      Thread.sleep(forTimeInterval: 0.02)
    }
  }
}
