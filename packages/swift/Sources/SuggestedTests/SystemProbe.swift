/// CPU time spent by a process or thread.
public struct CPUTime: Equatable, Sendable, CustomStringConvertible {
  /// Time in user mode, in nanoseconds.
  public let userNanoseconds: UInt64
  /// Time in the kernel on the process's behalf, in nanoseconds.
  public let systemNanoseconds: UInt64

  /// Creates a value from its two parts.
  public init(userNanoseconds: UInt64, systemNanoseconds: UInt64) {
    self.userNanoseconds = userNanoseconds
    self.systemNanoseconds = systemNanoseconds
  }

  /// User plus system time, in nanoseconds.
  public var totalNanoseconds: UInt64 { userNanoseconds + systemNanoseconds }

  /// The CPU time spent between `earlier` and `self`.
  public static func - (later: CPUTime, earlier: CPUTime) -> CPUTime {
    CPUTime(
      userNanoseconds: later.userNanoseconds &- earlier.userNanoseconds,
      systemNanoseconds: later.systemNanoseconds &- earlier.systemNanoseconds)
  }

  public var description: String {
    "CPUTime(user: \(formatNanoseconds(Double(userNanoseconds))), "
      + "system: \(formatNanoseconds(Double(systemNanoseconds))))"
  }
}

/// The process's resident memory (RSS).
public struct MemoryUsage: Equatable, Sendable, CustomStringConvertible {
  /// Resident memory now, in bytes.
  public let currentRSSBytes: Int
  /// The highest resident memory so far, in bytes.
  public let peakRSSBytes: Int

  /// Creates a value from its two parts.
  public init(currentRSSBytes: Int, peakRSSBytes: Int) {
    self.currentRSSBytes = currentRSSBytes
    self.peakRSSBytes = peakRSSBytes
  }

  public var description: String {
    "MemoryUsage(current: \(formatBytes(currentRSSBytes)), peak: \(formatBytes(peakRSSBytes)))"
  }
}

/// The native bridge is missing, or an OS call failed.
public struct NativeBridgeError: Error, CustomStringConvertible {
  /// The `SystemProbe` operation that failed.
  public let operation: String
  /// The bridge's status: negative for a bridge error, positive for an OS
  /// error code (`errno`, `GetLastError()`).
  public let code: Int32
  /// Why, when known (for example why the bridge couldn't be loaded).
  public let detail: String?

  public var description: String {
    let reason: String
    switch code {
    case NativeBridge.errNull: reason = "null pointer"
    case NativeBridge.errUnsupported: reason = "not supported on this OS"
    case NativeBridge.errUnknown: reason = "unknown OS error"
    default: reason = "OS error \(code)"
    }
    return "\(operation) failed: \(reason)" + (detail.map { "\n" + $0 } ?? "")
  }
}

/// Process metrics read through the OS-agnostic Rust bridge, which ships
/// prebuilt for Linux (glibc and musl), macOS and Windows.
///
/// The bridge loads on first use of anything in this module. Check
/// ``isAvailable``, or skip where it isn't:
///
/// ```swift
/// func testImportStaysSmall() throws {
///   try XCTSkipUnless(SystemProbe.isAvailable, SystemProbe.skipReason ?? "")
///   let before = try SystemProbe.memoryUsage()
///   …
/// }
/// ```
public enum SystemProbe {
  /// Whether the bridge is loaded and has the expected ABI version.
  public static var isAvailable: Bool {
    if case .success = NativeBridge.shared { return true }
    return false
  }

  /// `nil` when the bridge is available; otherwise why not.
  public static var skipReason: String? {
    switch NativeBridge.shared {
    case .success: return nil
    case .failure(let error):
      return "suggestedtests native bridge is not available for this platform (\(error)). "
        + "Set $\(NativeBridge.envVar) to a library built from native/."
    }
  }

  /// CPU time spent by the whole process so far.
  public static func processCPUTime() throws -> CPUTime {
    let bridge = try require("processCPUTime")
    var out: (UInt64, UInt64) = (0, 0)
    try check("processCPUTime", call(bridge.processCPUTime, &out))
    return CPUTime(userNanoseconds: out.0, systemNanoseconds: out.1)
  }

  /// CPU time spent by the calling thread, in nanoseconds. Only meaningful
  /// between two samples on the same thread; in async code use
  /// ``processCPUTime()``.
  public static func threadCPUTimeNanoseconds() throws -> UInt64 {
    let bridge = try require("threadCPUTimeNanoseconds")
    var out: UInt64 = 0
    try check("threadCPUTimeNanoseconds", bridge.threadCPUTimeNs(&out))
    return out
  }

  /// The process's current and peak resident memory.
  public static func memoryUsage() throws -> MemoryUsage {
    let bridge = try require("memoryUsage")
    var out: (UInt64, UInt64) = (0, 0)
    try check("memoryUsage", call(bridge.memoryUsage, &out))
    return MemoryUsage(currentRSSBytes: Int(clamping: out.0), peakRSSBytes: Int(clamping: out.1))
  }

  /// The number of logical CPUs available to the process.
  public static func cpuCount() throws -> Int {
    Int(try require("cpuCount").cpuCount())
  }

  /// Turns the bridge's startup report on or off; returns the previous setting.
  ///
  /// The report is three `suggestedtests: ...` lines on stderr describing the
  /// platform and environment (OS, arch, libc, container, VM). It is printed
  /// at most once per process; turning verbose on prints it now if it hasn't
  /// been printed. To get it while the bridge loads, set
  /// `SUGGESTEDTESTS_VERBOSE=1` before running the tests. Verbose controls
  /// nothing else.
  @discardableResult
  public static func setVerbose(_ verbose: Bool) throws -> Bool {
    try require("setVerbose").setVerbose(verbose ? 1 : 0) != 0
  }

  /// Whether the bridge's startup report is on (see ``setVerbose(_:)``).
  public static func verbose() throws -> Bool {
    try require("verbose").verbose() != 0
  }

  /// How the bridge's load-time code ran: 1 from the OS loader, 2 lazily.
  static func loadState() throws -> UInt32 {
    try require("loadState").loadState()
  }

  private static func require(_ operation: String) throws -> NativeBridge {
    switch NativeBridge.shared {
    case .success(let bridge): return bridge
    case .failure:
      throw NativeBridgeError(
        operation: operation, code: NativeBridge.errUnsupported, detail: skipReason)
    }
  }

  private static func call(
    _ function: NativeBridge.PairFunction, _ out: inout (UInt64, UInt64)
  ) -> Int32 {
    withUnsafeMutablePointer(to: &out) {
      $0.withMemoryRebound(to: UInt64.self, capacity: 2) { function($0) }
    }
  }

  private static func check(_ operation: String, _ status: Int32) throws {
    if status != NativeBridge.ok {
      throw NativeBridgeError(operation: operation, code: status, detail: nil)
    }
  }
}
