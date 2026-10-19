import XCTest

#if canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif

final class ImporterTests: XCTestCase {
  // Unix only: ru_maxrss is in bytes on macOS and in KiB on Linux.
  private func peakRSSBytes() -> Int {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    #if canImport(Darwin)
      return Int(usage.ru_maxrss)
    #else
      return Int(usage.ru_maxrss) * 1024
    #endif
  }

  func testImportStaysSmall() {
    let before = peakRSSBytes()
    importer.run(bigFile)
    let growth = peakRSSBytes() - before
    XCTAssertLessThanOrEqual(
      growth, 50 * 1024 * 1024, "peak RSS grew by \(growth / 1_048_576) MiB > 50 MiB")
  }
}
