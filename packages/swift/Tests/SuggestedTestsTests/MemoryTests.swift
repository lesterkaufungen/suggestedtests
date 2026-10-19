import XCTest

@testable import SuggestedTests

final class MemoryTests: XCTestCase {
  func testMeasureMemorySeesAnAllocation() throws {
    try XCTSkipUnless(SystemProbe.isAvailable, SystemProbe.skipReason ?? "")
    var keep: [UInt8] = []
    let report = try measureMemory {
      keep = [UInt8](repeating: 1, count: 64 * MiB)
    }
    XCTAssertEqual(keep.count, 64 * MiB)
    // Not the peak: earlier tests may have raised it above what this adds.
    XCTAssertGreaterThan(report.rssGrowthBytes, 32 * MiB, "\(report)")
    XCTAssertTrue(report.description.hasPrefix("MemoryReport(rss: +"), report.description)
  }

  func testExpectMemoryFailsOverBudget() throws {
    try XCTSkipUnless(SystemProbe.isAvailable, SystemProbe.skipReason ?? "")
    var keep: [UInt8] = []
    XCTAssertThrowsError(
      try expectMemory(maxRSSGrowth: 1 * MiB) { keep = [UInt8](repeating: 1, count: 64 * MiB) }
    ) { error in
      XCTAssertTrue("\(error)".hasPrefix("memory budget exceeded: RSS grew "), "\(error)")
    }
    XCTAssertEqual(keep.count, 64 * MiB)
  }

  func testExpectMemoryPassesWithinBudget() throws {
    try XCTSkipUnless(SystemProbe.isAvailable, SystemProbe.skipReason ?? "")
    try expectMemory(maxRSSGrowth: 512 * MiB) { _ = [1, 2, 3].map { $0 * 2 } }
  }

  func testBudgetsAreValidatedBeforeTheBody() {
    var ran = false
    XCTAssertThrowsError(try expectMemory { ran = true }) {
      XCTAssertTrue($0 is SuggestedTestsArgumentError)
    }
    XCTAssertThrowsError(try expectMemory(maxPeakGrowth: -1) { ran = true }) {
      XCTAssertTrue($0 is SuggestedTestsArgumentError)
    }
    XCTAssertFalse(ran)
  }

  func testFormatBytes() {
    XCTAssertEqual(formatBytes(512), "512 B")
    XCTAssertEqual(formatBytes(1536), "1.5 KiB")
    XCTAssertEqual(formatBytes(-3 * MiB), "-3.0 MiB")
    XCTAssertEqual(formatNanoseconds(412_400), "412µs")
    XCTAssertEqual(formatNanoseconds(1_250_000), "1.25ms")
    XCTAssertEqual(formatNanoseconds(2_010_000_000), "2.01s")
  }
}
