import Dispatch

/// Which statistic of a benchmark a budget is checked against.
public enum Statistic: String, Sendable {
  case min, median, mean, p95, max
}

/// What a benchmark measures.
public enum BenchmarkClock: Sendable {
  /// Elapsed wall-clock time (the default).
  case wall
  /// CPU time of the whole process, read through the native bridge. It
  /// ignores sleeping, I/O waits and other processes, so it is far less noisy
  /// on busy CI machines.
  case cpu
}

/// The samples of a benchmark, with their statistics.
public struct BenchmarkResult: Sendable, CustomStringConvertible {
  /// The benchmark's name, used in reports.
  public let name: String
  /// What was measured.
  public let clock: BenchmarkClock
  /// Each iteration's time in nanoseconds, in the order they ran.
  public let samplesNanoseconds: [UInt64]
  private let sorted: [UInt64]

  init(name: String, clock: BenchmarkClock, samplesNanoseconds: [UInt64]) {
    self.name = name
    self.clock = clock
    self.samplesNanoseconds = samplesNanoseconds
    self.sorted = samplesNanoseconds.sorted()
  }

  /// The fastest sample, in nanoseconds.
  public var minNanoseconds: Double { Double(sorted.first!) }
  /// The slowest sample, in nanoseconds.
  public var maxNanoseconds: Double { Double(sorted.last!) }
  /// The median sample (the default budget statistic), in nanoseconds.
  public var medianNanoseconds: Double { percentileNanoseconds(50) }
  /// The 95th percentile, in nanoseconds.
  public var p95Nanoseconds: Double { percentileNanoseconds(95) }
  /// The mean, in nanoseconds.
  public var meanNanoseconds: Double {
    Double(samplesNanoseconds.reduce(0, +)) / Double(samplesNanoseconds.count)
  }
  /// The population standard deviation, in nanoseconds.
  public var standardDeviationNanoseconds: Double {
    let mean = meanNanoseconds
    let squares = samplesNanoseconds.reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) }
    return (squares / Double(samplesNanoseconds.count)).squareRoot()
  }

  /// The nearest-rank `p`th percentile (0...100), in nanoseconds.
  public func percentileNanoseconds(_ p: Double) -> Double {
    precondition((0...100).contains(p), "p must be in 0...100, got \(p)")
    let rank = Swift.min(
      Swift.max(Int((p / 100 * Double(sorted.count)).rounded(.up)), 1), sorted.count)
    return Double(sorted[rank - 1])
  }

  /// `statistic`, in nanoseconds.
  public subscript(statistic: Statistic) -> Double {
    switch statistic {
    case .min: return minNanoseconds
    case .median: return medianNanoseconds
    case .mean: return meanNanoseconds
    case .p95: return p95Nanoseconds
    case .max: return maxNanoseconds
    }
  }

  /// `parse: n=20 min=3.10ms median=3.42ms mean=3.51ms p95=4.02ms max=4.30ms ±210µs`
  public var description: String {
    let cpu = clock == .cpu ? " (cpu)" : ""
    return "\(name)\(cpu): n=\(samplesNanoseconds.count) min=\(formatNanoseconds(minNanoseconds)) "
      + "median=\(formatNanoseconds(medianNanoseconds)) mean=\(formatNanoseconds(meanNanoseconds)) "
      + "p95=\(formatNanoseconds(p95Nanoseconds)) max=\(formatNanoseconds(maxNanoseconds)) "
      + "±\(formatNanoseconds(standardDeviationNanoseconds))"
  }
}

/// Runs `body` `warmup` times, then measures `iterations` runs.
///
/// ```swift
/// let result = try benchmark("sort", iterations: 50) { _ = data.sorted() }
/// print(result) // sort: n=50 min=1.02ms median=1.10ms mean=1.15ms p95=1.40ms max=2.01ms ±120µs
/// ```
public func benchmark(
  _ name: String = "benchmark", iterations: Int = 20, warmup: Int = 3,
  clock: BenchmarkClock = .wall, _ body: () throws -> Void
) throws -> BenchmarkResult {
  NativeBridge.preload()
  try checkCounts(iterations, warmup)
  for _ in 0..<warmup { try body() }
  var samples: [UInt64] = []
  samples.reserveCapacity(iterations)
  for _ in 0..<iterations {
    let start = try now(clock)
    try body()
    samples.append(try now(clock) &- start)
  }
  return BenchmarkResult(name: name, clock: clock, samplesNanoseconds: samples)
}

/// ``benchmark(_:iterations:warmup:clock:_:)`` for an async body. With
/// `clock: .cpu` it measures the whole process, which an async body may
/// share with other tasks.
public func benchmark(
  _ name: String = "benchmark", iterations: Int = 20, warmup: Int = 3,
  clock: BenchmarkClock = .wall, _ body: () async throws -> Void
) async throws -> BenchmarkResult {
  NativeBridge.preload()
  try checkCounts(iterations, warmup)
  for _ in 0..<warmup { try await body() }
  var samples: [UInt64] = []
  samples.reserveCapacity(iterations)
  for _ in 0..<iterations {
    let start = try now(clock)
    try await body()
    samples.append(try now(clock) &- start)
  }
  return BenchmarkResult(name: name, clock: clock, samplesNanoseconds: samples)
}

/// Fails if `statistic` (the median by default) of `body`'s runs is over
/// `budget` seconds.
///
/// ```swift
/// func testParsingStaysFast() throws {
///   try expectPerformance(budget: 0.005) { parse(bigJSON) }
/// }
/// // performance budget exceeded: median 7.31ms > budget 5.00ms
/// // benchmark: n=20 min=6.90ms median=7.31ms mean=7.40ms p95=8.02ms max=8.30ms ±310µs
/// ```
@discardableResult
public func expectPerformance(
  _ name: String = "benchmark", budget: Double, statistic: Statistic = .median,
  iterations: Int = 20, warmup: Int = 3, clock: BenchmarkClock = .wall,
  _ body: () throws -> Void
) throws -> BenchmarkResult {
  NativeBridge.preload()
  try checkBudget(budget)
  let result = try benchmark(name, iterations: iterations, warmup: warmup, clock: clock, body)
  try checkResult(result, budget: budget, statistic: statistic)
  return result
}

/// ``expectPerformance(_:budget:statistic:iterations:warmup:clock:_:)`` for an async body.
@discardableResult
public func expectPerformance(
  _ name: String = "benchmark", budget: Double, statistic: Statistic = .median,
  iterations: Int = 20, warmup: Int = 3, clock: BenchmarkClock = .wall,
  _ body: () async throws -> Void
) async throws -> BenchmarkResult {
  NativeBridge.preload()
  try checkBudget(budget)
  let result = try await benchmark(
    name, iterations: iterations, warmup: warmup, clock: clock, body)
  try checkResult(result, budget: budget, statistic: statistic)
  return result
}

private func checkCounts(_ iterations: Int, _ warmup: Int) throws {
  if iterations < 1 {
    throw SuggestedTestsArgumentError("iterations must be >= 1, got \(iterations)")
  }
  if warmup < 0 { throw SuggestedTestsArgumentError("warmup must be >= 0, got \(warmup)") }
}

private func checkBudget(_ budget: Double) throws {
  if !(budget > 0) || !budget.isFinite {
    throw SuggestedTestsArgumentError("budget must be a positive number of seconds, got \(budget)")
  }
}

private func checkResult(_ result: BenchmarkResult, budget: Double, statistic: Statistic) throws {
  let actual = result[statistic]
  let budgetNanoseconds = budget * 1e9
  if actual > budgetNanoseconds {
    throw SuggestedTestsFailure(
      "performance budget exceeded: \(statistic.rawValue) \(formatNanoseconds(actual)) > "
        + "budget \(formatNanoseconds(budgetNanoseconds))\n\(result)")
  }
}

private func now(_ clock: BenchmarkClock) throws -> UInt64 {
  switch clock {
  case .wall: return DispatchTime.now().uptimeNanoseconds
  case .cpu: return try SystemProbe.processCPUTime().totalNanoseconds
  }
}
