import XCTest

@testable import SuggestedTests

final class BenchmarkTests: XCTestCase {
  func testStatisticsOfKnownSamples() {
    let result = BenchmarkResult(
      name: "x", clock: .wall, samplesNanoseconds: [5, 1, 4, 2, 3].map { $0 * 1_000_000 })
    XCTAssertEqual(result.minNanoseconds, 1e6)
    XCTAssertEqual(result.maxNanoseconds, 5e6)
    XCTAssertEqual(result.medianNanoseconds, 3e6)
    XCTAssertEqual(result.meanNanoseconds, 3e6)
    XCTAssertEqual(result.p95Nanoseconds, 5e6)
    XCTAssertEqual(result.standardDeviationNanoseconds, 2e6.squareRoot() * 1000, accuracy: 1)
    XCTAssertEqual(
      result.description,
      "x: n=5 min=1.00ms median=3.00ms mean=3.00ms p95=5.00ms max=5.00ms ±1.41ms")
  }

  func testBenchmarkRunsWarmupAndIterations() throws {
    var runs = 0
    let result = try benchmark("count", iterations: 7, warmup: 2) { runs += 1 }
    XCTAssertEqual(runs, 9)
    XCTAssertEqual(result.samplesNanoseconds.count, 7)
  }

  func testExpectPerformancePassesWithinBudget() throws {
    try expectPerformance(budget: 1) { _ = (0..<100).reduce(0, +) }
  }

  func testExpectPerformanceFailsWithTheStatistics() {
    XCTAssertThrowsError(
      try expectPerformance("sleepy", budget: 0.000_001, statistic: .min, iterations: 3, warmup: 0)
      {
        Thread.sleep(forTimeInterval: 0.002)
      }
    ) { error in
      let message = "\(error)"
      XCTAssertTrue(error is SuggestedTestsFailure)
      XCTAssertTrue(message.hasPrefix("performance budget exceeded: min "), message)
      XCTAssertTrue(message.contains("sleepy: n=3 min="), message)
    }
  }

  func testCPUClockIgnoresSleeping() throws {
    try XCTSkipUnless(SystemProbe.isAvailable, SystemProbe.skipReason ?? "")
    let result = try benchmark(iterations: 3, warmup: 0, clock: .cpu) {
      Thread.sleep(forTimeInterval: 0.02)
    }
    XCTAssertLessThan(result.medianNanoseconds, 15e6, "\(result)")
    XCTAssertTrue(result.description.contains("(cpu)"))
  }

  func testAsyncBenchmark() async throws {
    let result = try await expectPerformance(budget: 1, iterations: 3, warmup: 1) {
      try await Task.sleep(nanoseconds: 1_000)
    }
    XCTAssertEqual(result.samplesNanoseconds.count, 3)
  }

  func testArgumentsAreValidatedBeforeTheBody() {
    var ran = false
    for (iterations, warmup, budget) in [(0, 3, 1.0), (20, -1, 1.0), (20, 3, 0.0), (20, 3, -1.0)] {
      XCTAssertThrowsError(
        try expectPerformance(budget: budget, iterations: iterations, warmup: warmup) { ran = true }
      ) { XCTAssertTrue($0 is SuggestedTestsArgumentError, "\($0)") }
    }
    XCTAssertFalse(ran)
  }
}
