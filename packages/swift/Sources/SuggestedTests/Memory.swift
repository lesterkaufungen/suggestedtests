/// 1024 bytes.
public let KiB = 1024
/// 1024 KiB.
public let MiB = 1024 * KiB
/// 1024 MiB.
public let GiB = 1024 * MiB

/// Resident memory before and after a block of code.
public struct MemoryReport: Sendable, CustomStringConvertible {
  /// Memory when the block started.
  public let before: MemoryUsage
  /// Memory when the block ended.
  public let after: MemoryUsage

  /// How much resident memory grew (negative if it shrank), in bytes.
  public var rssGrowthBytes: Int { after.currentRSSBytes - before.currentRSSBytes }
  /// How much the process's peak resident memory rose, in bytes.
  public var peakGrowthBytes: Int { after.peakRSSBytes - before.peakRSSBytes }

  public var description: String {
    "MemoryReport(rss: \(signed(rssGrowthBytes)), peak: \(signed(peakGrowthBytes)), now: \(after))"
  }
}

/// Measures the process's resident memory around `body`.
///
/// RSS is a coarse, process-wide signal: allocators keep freed memory, and
/// other threads share the process. Use it to catch leaks and blow-ups of
/// megabytes. Throws ``NativeBridgeError`` where the bridge is unavailable.
public func measureMemory(_ body: () throws -> Void) throws -> MemoryReport {
  NativeBridge.preload()
  let before = try SystemProbe.memoryUsage()
  try body()
  return MemoryReport(before: before, after: try SystemProbe.memoryUsage())
}

/// ``measureMemory(_:)`` for an async body.
public func measureMemory(_ body: () async throws -> Void) async throws -> MemoryReport {
  NativeBridge.preload()
  let before = try SystemProbe.memoryUsage()
  try await body()
  return MemoryReport(before: before, after: try SystemProbe.memoryUsage())
}

/// Fails if `body` grows resident memory by more than `maxRSSGrowth` bytes,
/// or the process's peak by more than `maxPeakGrowth` bytes.
///
/// ```swift
/// func testImportStaysSmall() throws {
///   try XCTSkipUnless(SystemProbe.isAvailable, SystemProbe.skipReason ?? "")
///   try expectMemory(maxPeakGrowth: 50 * MiB) { importer.run(bigFile) }
/// }
/// ```
@discardableResult
public func expectMemory(
  maxRSSGrowth: Int? = nil, maxPeakGrowth: Int? = nil, _ body: () throws -> Void
) throws -> MemoryReport {
  NativeBridge.preload()
  try checkBudgets(maxRSSGrowth, maxPeakGrowth)
  let report = try measureMemory(body)
  try checkReport(report, maxRSSGrowth, maxPeakGrowth)
  return report
}

/// ``expectMemory(maxRSSGrowth:maxPeakGrowth:_:)`` for an async body.
@discardableResult
public func expectMemory(
  maxRSSGrowth: Int? = nil, maxPeakGrowth: Int? = nil, _ body: () async throws -> Void
) async throws -> MemoryReport {
  NativeBridge.preload()
  try checkBudgets(maxRSSGrowth, maxPeakGrowth)
  let report = try await measureMemory(body)
  try checkReport(report, maxRSSGrowth, maxPeakGrowth)
  return report
}

private func checkBudgets(_ maxRSSGrowth: Int?, _ maxPeakGrowth: Int?) throws {
  if maxRSSGrowth == nil, maxPeakGrowth == nil {
    throw SuggestedTestsArgumentError("give maxRSSGrowth and/or maxPeakGrowth")
  }
  for (name, value) in [("maxRSSGrowth", maxRSSGrowth), ("maxPeakGrowth", maxPeakGrowth)] {
    if let value = value, value < 0 {
      throw SuggestedTestsArgumentError("\(name) must be >= 0, got \(value)")
    }
  }
}

private func checkReport(_ report: MemoryReport, _ maxRSSGrowth: Int?, _ maxPeakGrowth: Int?) throws
{
  if let budget = maxRSSGrowth, report.rssGrowthBytes > budget {
    throw SuggestedTestsFailure(
      "memory budget exceeded: RSS grew \(formatBytes(report.rssGrowthBytes)) > "
        + "budget \(formatBytes(budget))\n\(report)")
  }
  if let budget = maxPeakGrowth, report.peakGrowthBytes > budget {
    throw SuggestedTestsFailure(
      "memory budget exceeded: peak RSS grew \(formatBytes(report.peakGrowthBytes)) > "
        + "budget \(formatBytes(budget))\n\(report)")
  }
}

private func signed(_ bytes: Int) -> String {
  (bytes >= 0 ? "+" : "") + formatBytes(bytes)
}
