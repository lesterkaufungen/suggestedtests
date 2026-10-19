// The Rust bridge's C ABI (native/include/suggestedtests_native.h), loaded at
// runtime with dlopen / LoadLibraryW, so the package needs no C target, no
// link-time dependency and no copy of the header.
//
// Lookup order: $SUGGESTEDTESTS_NATIVE_LIB, the copy bundled as a resource
// (published package), then the monorepo's native/prebuilt/<platform>/.

import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Musl)
  import Musl
#elseif canImport(Android)
  import Android
#elseif os(Windows)
  import WinSDK
#endif

/// The loaded library's exports. Struct results (`StCpuTime`, `StMemory`:
/// two `uint64_t` each) are written into a `(UInt64, UInt64)` tuple, whose
/// layout Swift guarantees to match.
struct NativeBridge: @unchecked Sendable {
  static let abiVersion: UInt32 = 1
  static let envVar = "SUGGESTEDTESTS_NATIVE_LIB"
  static let verboseEnvVar = "SUGGESTEDTESTS_VERBOSE"
  static let ok: Int32 = 0
  static let errNull: Int32 = -1
  static let errUnsupported: Int32 = -2
  static let errUnknown: Int32 = -3

  typealias U32Function = @convention(c) () -> UInt32
  typealias PairFunction = @convention(c) (UnsafeMutablePointer<UInt64>?) -> Int32
  typealias SetFunction = @convention(c) (UInt32) -> UInt32
  typealias VoidFunction = @convention(c) () -> Void

  let path: String
  let abiVersion: U32Function
  /// `st_on_load`: side effects distinct from the version query `abiVersion`
  /// does. `nil` on an older prebuilt that predates this additive (no ABI
  /// bump) symbol.
  let onLoad: VoidFunction?
  let processCPUTime: PairFunction
  let threadCPUTimeNs: PairFunction
  let memoryUsage: PairFunction
  let cpuCount: U32Function
  let loadState: U32Function
  let setVerbose: SetFunction
  let verbose: U32Function

  /// The bridge, loaded once on first use, or why it is unavailable. Loading
  /// runs its load hook, which prints the startup report if
  /// `SUGGESTEDTESTS_VERBOSE` is on.
  static let shared: Result<NativeBridge, NativeBridgeUnavailable> = load()

  /// Loads the bridge now if it isn't loaded yet. Every public entry point
  /// calls this first: Swift runs nothing when a module is imported, so this
  /// is the earliest point. Never throws.
  static func preload() {
    _ = shared
  }

  /// `<os>-<arch>[-musl]` or `android-<abi>`: this build's prebuilt directory.
  static var platformDirectory: String? {
    #if os(Android)
      #if arch(arm64)
        return "android-arm64-v8a"
      #elseif arch(arm)
        return "android-armeabi-v7a"
      #elseif arch(x86_64)
        return "android-x86_64"
      #elseif arch(i386)
        return "android-x86"
      #else
        return nil
      #endif
    #else
      #if arch(x86_64)
        let arch = "x64"
      #elseif arch(arm64)
        let arch = "arm64"
      #elseif arch(i386)
        let arch = "x86"
      #elseif arch(arm)
        let arch = "arm"
      #elseif arch(riscv64)
        let arch = "riscv64"
      #else
        return nil
      #endif
      #if os(Linux)
        // A musl build (the static Linux SDK) can't load the glibc library.
        #if canImport(Musl)
          return "linux-\(arch)-musl"
        #else
          return "linux-\(arch)"
        #endif
      #elseif os(macOS)
        return "macos-\(arch)"
      #elseif os(Windows)
        return "windows-\(arch)"
      #else
        return nil
      #endif
    #endif
  }

  static var libraryFileName: String {
    #if os(Windows)
      return "suggestedtests_native.dll"
    #elseif canImport(Darwin)
      return "libsuggestedtests_native.dylib"
    #else
      return "libsuggestedtests_native.so"
    #endif
  }

  /// The paths tried, in order.
  static func candidates() -> [String] {
    if let explicit = ProcessInfo.processInfo.environment[envVar], !explicit.isEmpty {
      return [explicit]
    }
    guard let directory = platformDirectory else { return [] }
    var paths: [String] = []
    #if SUGGESTEDTESTS_BUNDLED
      if let resources = Bundle.module.resourceURL {
        paths.append(
          resources.appendingPathComponent("Prebuilt").appendingPathComponent(directory)
            .appendingPathComponent(libraryFileName).path)
      }
    #endif
    // packages/swift/Sources/SuggestedTests/NativeBridge.swift -> repository root
    var repository = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { repository.deleteLastPathComponent() }
    paths.append(
      repository.appendingPathComponent("native/prebuilt").appendingPathComponent(directory)
        .appendingPathComponent(libraryFileName).path)
    return paths
  }

  static func load() -> Result<NativeBridge, NativeBridgeUnavailable> {
    let paths = candidates()
    if paths.isEmpty {
      return .failure(NativeBridgeUnavailable("no prebuilt bridge for this platform"))
    }
    guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
      return .failure(
        NativeBridgeUnavailable("bridge library not found at: " + paths.joined(separator: ", ")))
    }
    let library: Library
    do {
      library = try Library(path: path)
    } catch let error as NativeBridgeUnavailable {
      return .failure(error)
    } catch {
      return .failure(NativeBridgeUnavailable("cannot load \(path): \(error)"))
    }
    do {
      let bridge = NativeBridge(
        path: path,
        abiVersion: try library.function("st_abi_version"),
        onLoad: try? library.function("st_on_load"),
        processCPUTime: try library.function("st_process_cpu_time"),
        threadCPUTimeNs: try library.function("st_thread_cpu_time_ns"),
        memoryUsage: try library.function("st_memory_usage"),
        cpuCount: try library.function("st_cpu_count"),
        loadState: try library.function("st_load_state"),
        setVerbose: try library.function("st_set_verbose"),
        verbose: try library.function("st_verbose"))
      // On Windows the load-time report waits for this first call.
      let version = bridge.abiVersion()
      if version != abiVersion {
        return .failure(
          NativeBridgeUnavailable(
            "suggestedtests native bridge has ABI v\(version), expected v\(abiVersion). Rebuild it."
          ))
      }
      bridge.onLoad?()
      return .success(bridge)
    } catch let error as NativeBridgeUnavailable {
      return .failure(error)
    } catch {
      return .failure(NativeBridgeUnavailable("\(error)"))
    }
  }
}

/// Why the bridge couldn't be loaded.
struct NativeBridgeUnavailable: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}

/// A loaded shared library. Never unloaded: the bridge stays for the process.
private struct Library {
  #if os(Windows)
    let handle: HMODULE
  #else
    let handle: UnsafeMutableRawPointer
  #endif
  let path: String

  init(path: String) throws {
    self.path = path
    #if os(Windows)
      guard let handle = path.withCString(encodedAs: UTF16.self, { LoadLibraryW($0) }) else {
        throw NativeBridgeUnavailable("cannot load \(path): error \(GetLastError())")
      }
    #else
      guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
        let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
        throw NativeBridgeUnavailable("cannot load \(path): \(reason)")
      }
    #endif
    self.handle = handle
  }

  func function<F>(_ name: String) throws -> F {
    #if os(Windows)
      guard let symbol = GetProcAddress(handle, name) else {
        throw NativeBridgeUnavailable("\(path) has no \(name)")
      }
    #else
      guard let symbol = dlsym(handle, name) else {
        throw NativeBridgeUnavailable("\(path) has no \(name)")
      }
    #endif
    return unsafeBitCast(symbol, to: F.self)
  }
}
