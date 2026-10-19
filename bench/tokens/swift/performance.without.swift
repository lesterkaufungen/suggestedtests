import Dispatch
import Foundation
import XCTest

final class ParserTests: XCTestCase {
  func testParsingStaysFast() {
    for _ in 0..<3 { parse(bigJSON) }
    var samples: [Double] = []
    for _ in 0..<20 {
      let start = DispatchTime.now().uptimeNanoseconds
      parse(bigJSON)
      samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
    }
    samples.sort()
    let median = (samples[9] + samples[10]) / 2
    XCTAssertLessThanOrEqual(
      median, 5,
      "parse: median \(String(format: "%.2f", median))ms > budget 5ms "
        + "(min \(String(format: "%.2f", samples[0]))ms, max \(String(format: "%.2f", samples[19]))ms)"
    )
  }
}
