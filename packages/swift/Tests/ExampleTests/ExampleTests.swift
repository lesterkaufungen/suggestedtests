// The README's examples, as tests. Keep the two in sync.
import Foundation
import SuggestedTests
import XCTest

final class Cart {
  private(set) var total = 0
  func add(_ price: Int) { total += price }
}

func parse(_ json: String) -> Int { json.filter { $0 == "{" }.count }

final class ExampleTests: XCTestCase {
  let bigJSON = String(repeating: "{\"id\": 1, \"tags\": [\"a\", \"b\"]},", count: 2_000)

  // Fail when code gets slower than a budget (the median of 20 runs, seconds).
  func testParsingStaysFast() throws {
    try expectPerformance(budget: 0.5) { _ = parse(bigJSON) }
  }

  func testBenchmarkReport() throws {
    let data = (0..<10_000).map { _ in Int.random(in: 0..<1_000_000) }
    let result = try benchmark("sort", iterations: 50, clock: .cpu) { _ = data.sorted() }
    print(result)  // sort (cpu): n=50 min=… median=… mean=… p95=… max=… ±…
  }

  // Fail when a block of code makes the process's peak memory grow too much.
  func testImportStaysSmall() throws {
    try XCTSkipUnless(SystemProbe.isAvailable, SystemProbe.skipReason ?? "")
    try expectMemory(maxPeakGrowth: 50 * MiB) { _ = parse(bigJSON) }
  }

  // Wait for a condition instead of sleeping a fixed time.
  func testCacheWarmsUp() async throws {
    let warmAt = Date().addingTimeInterval(0.05)
    try await eventually { try check(Date() >= warmAt, "cache is still cold") }
  }

  // Given/when/then: a failure names the step.
  func testAddingItemsUpdatesTheTotal() throws {
    var cart = Cart()
    try Scenario()
      .given("an empty cart") { cart = Cart() }
      .when("two items are added") {
        cart.add(10)
        cart.add(20)
      }
      .then("the total is 30") { try check(cart.total == 30, "total is \(cart.total)") }
  }

  // Reproducible fake data.
  func testSignupAcceptsGeneratedUsers() throws {
    let data = TestData(seed: 42)
    let users = try data.list(100) { d in
      (name: d.word(), email: d.email(), age: d.integer(in: 18...90))
    }
    XCTAssertTrue(users.allSatisfy { (18...90).contains($0.age) && $0.email.contains("@") })
    try assertUnique(users.map(\.email))
  }

  // Process metrics from the native bridge.
  func testSystemProbe() throws {
    try XCTSkipUnless(SystemProbe.isAvailable, SystemProbe.skipReason ?? "")
    print(try SystemProbe.processCPUTime())  // CPUTime(user: 1.25s, system: 80.00ms)
    print(try SystemProbe.memoryUsage())  // MemoryUsage(current: 40.1 MiB, peak: 52.3 MiB)
    XCTAssertGreaterThanOrEqual(try SystemProbe.cpuCount(), 1)
  }
}
