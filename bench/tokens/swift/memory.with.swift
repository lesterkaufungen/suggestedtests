import SuggestedTests
import XCTest

final class ImporterTests: XCTestCase {
  func testImportStaysSmall() throws {
    try XCTSkipUnless(SystemProbe.isAvailable, SystemProbe.skipReason ?? "")
    try expectMemory(maxPeakGrowth: 50 * MiB) { importer.run(bigFile) }
  }
}
