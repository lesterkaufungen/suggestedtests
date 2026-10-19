import Foundation
import XCTest

@testable import SuggestedTests

final class SystemProbeTests: XCTestCase {
  func testBridgeLoadsFromThePrebuilts() throws {
    XCTAssertTrue(SystemProbe.isAvailable, SystemProbe.skipReason ?? "")
    XCTAssertNil(SystemProbe.skipReason)
    // The load-time code ran from the OS loader, not lazily.
    XCTAssertEqual(try SystemProbe.loadState(), 1)
  }

  func testProcessMetricsArePlausible() throws {
    try XCTSkipUnless(SystemProbe.isAvailable, SystemProbe.skipReason ?? "")
    let before = try SystemProbe.processCPUTime()
    var x = 0.0
    for i in 0..<2_000_000 { x += Double(i).squareRoot() }
    XCTAssertGreaterThan(x, 0)
    let spent = try SystemProbe.processCPUTime() - before
    XCTAssertGreaterThan(spent.totalNanoseconds, 0)
    XCTAssertGreaterThan(try SystemProbe.threadCPUTimeNanoseconds(), 0)
    let memory = try SystemProbe.memoryUsage()
    XCTAssertGreaterThan(memory.currentRSSBytes, MiB)
    XCTAssertGreaterThanOrEqual(memory.peakRSSBytes, memory.currentRSSBytes)
    XCTAssertTrue(memory.description.contains("MiB"), memory.description)
    XCTAssertGreaterThanOrEqual(try SystemProbe.cpuCount(), 1)
    XCTAssertEqual(try SystemProbe.cpuCount(), ProcessInfo.processInfo.activeProcessorCount)
  }

  func testUnavailableBridgeErrorsSayWhy() {
    let error = NativeBridgeError(operation: "memoryUsage", code: 2, detail: nil)
    XCTAssertEqual(error.description, "memoryUsage failed: OS error 2")
    XCTAssertTrue(
      NativeBridgeError(operation: "x", code: NativeBridge.errUnsupported, detail: "why")
        .description.hasSuffix("not supported on this OS\nwhy"))
  }

  func testPlatformDirectoryMatchesThisBuild() {
    #if os(Linux) && arch(x86_64) && !canImport(Musl)
      XCTAssertEqual(NativeBridge.platformDirectory, "linux-x64")
    #endif
    XCTAssertNotNil(NativeBridge.platformDirectory)
  }

  // MARK: the startup report, in a fresh process

  func testBridgeIsSilentByDefault() throws {
    let (out, err) = try runReportCheck("load")
    XCTAssertEqual(out, "true false\n")
    XCTAssertFalse(err.contains("suggestedtests:"), err)
  }

  func testVerboseEnvVarPrintsTheReportWhenTheBridgeLoads() throws {
    let (out, err) = try runReportCheck("load", verbose: "1")
    XCTAssertEqual(out, "true true\n")
    XCTAssertEqual(reports(err), 1, err)
    XCTAssertTrue(err.contains("suggestedtests: environment: "), err)
  }

  func testUsingAnyAPILoadsTheBridge() throws {
    let (_, err) = try runReportCheck("nothing", verbose: "1")
    XCTAssertEqual(reports(err), 1, err)
  }

  func testSetVerbosePrintsTheReportOnce() throws {
    let (out, err) = try runReportCheck("set")
    XCTAssertEqual(out, "false true true false\n")
    XCTAssertEqual(reports(err), 1, err)
  }

  private func reports(_ stderr: String) -> Int {
    stderr.components(separatedBy: "suggestedtests: platform: ").count - 1
  }

  /// Runs SuggestedTestsReportCheck (built next to the test bundle) in `mode`.
  private func runReportCheck(_ mode: String, verbose: String? = nil) throws -> (String, String) {
    try XCTSkipUnless(SystemProbe.isAvailable, SystemProbe.skipReason ?? "")
    #if os(macOS)
      let directory = Bundle(for: SystemProbeTests.self).bundleURL.deletingLastPathComponent()
    #else
      let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    #endif
    #if os(Windows)
      let executable = directory.appendingPathComponent("SuggestedTestsReportCheck.exe")
    #else
      let executable = directory.appendingPathComponent("SuggestedTestsReportCheck")
    #endif
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
      XCTFail("\(executable.path) is missing: run `swift build` before `swift test`")
      return ("", "")
    }
    let process = Process()
    process.executableURL = executable
    process.arguments = [mode]
    var environment = ProcessInfo.processInfo.environment
    environment[NativeBridge.verboseEnvVar] = verbose
    process.environment = environment
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let stdout = String(decoding: outData, as: UTF8.self)
    let stderr = String(decoding: errData, as: UTF8.self)
    XCTAssertEqual(process.terminationStatus, 0, stdout + stderr)
    return (stdout, stderr)
  }
}
