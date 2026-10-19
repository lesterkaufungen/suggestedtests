<p align="center">
  <img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/packages/dart/assets/logo.png" alt="suggestedtests logo" width="140">
</p>

<h1 align="center">suggestedtests for Swift</h1>

<p align="center">
  XCTest and Swift Testing helpers that make tests faster to write, and keep your code fast.
</p>

<p align="center">
  <a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md"><img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/bench/tokens/banner.png" alt="Tokens an AI coding agent spends per test, hand-written vs with suggestedtests, projected to larger test suites (estimate)" width="900"></a>
</p>

<p align="center">
  <a href="https://swiftpackageindex.com/lesterkaufungen/suggestedtests-swift"><img src="https://img.shields.io/badge/SwiftPM-suggestedtests--swift-F05138?logo=swift&logoColor=white" alt="Swift Package Manager"></a>
  <img src="https://img.shields.io/badge/Swift-5.10%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.10+">
  <img src="https://img.shields.io/badge/platforms-Linux%20%7C%20macOS%20%7C%20Windows-F05138" alt="Linux, macOS and Windows">
  <img src="https://img.shields.io/badge/XCTest%20%7C%20Swift%20Testing-ready-0D96F6" alt="XCTest and Swift Testing">
  <img src="https://img.shields.io/badge/dependencies-none-brightgreen" alt="no dependencies">
  <!-- tokens:badge -->
<!-- prettier-ignore-start -->
<a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md"><img src="https://img.shields.io/badge/AI%20agents-~75%25%20fewer%20tokens-8A2BE2" alt="~75% fewer tokens for AI agents (estimate)"></a>
<!-- prettier-ignore-end -->
<!-- /tokens:badge -->
  <a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/packages/swift/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <sub>The same helpers in <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/dart">Flutter & Dart</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/python">Python</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/js">JS & TS</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/php">PHP</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/java">Java</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/go">Go</a> · <b>Swift</b> · <a href="https://github.com/lesterkaufungen/suggestedtests">one repo, one native bridge</a></sub>
</p>

---

| Helper | What it's for |
| --- | --- |
| `expectPerformance`, `benchmark` | Timing statistics and performance budgets, on wall-clock or CPU time, for sync and async code. |
| `expectMemory`, `measureMemory` | Budgets for resident memory and its peak, via a native bridge for Linux, macOS and Windows. |
| `SystemProbe` | Process CPU time, thread CPU time, current and peak RSS, CPU count. |
| `eventually` | Polling instead of `Thread.sleep` / `Task.sleep`. |
| `Scenario` | Given/when/then steps whose failure names the failing step. |
| `TestData` | Seeded, reproducible fake data, the same on every platform. |
| `assertUnique`, `check` | Duplicate check that names the positions; a throwing assertion for `eventually` and steps. |

Every helper **throws** on failure (`SuggestedTestsFailure`). XCTest and Swift
Testing both report an error thrown from a test as a failure, so the package
works with either and depends on neither. Mark tests `throws` and call the
helpers with `try`. For parameterized tests use Swift Testing's
`@Test(arguments:)`; for mocks, your protocols. This package doesn't
duplicate them.

## Built for AI coding agents

<!-- tokens:section -->
<!-- prettier-ignore-start -->
An agent that knows these helpers writes one call where it would otherwise
write the loop, the timer, the statistics and the failure message, and then
read all of it again on every later change. For the tests in the
[benchmark](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md), that is **928 → 236 tokens
(75% fewer)**:

| Test | Hand-written | With suggestedtests | Saved |
| --- | ---: | ---: | ---: |
| Performance budget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/swift/performance.without.swift), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/swift/performance.with.swift)) | 195 | 46 | 76% |
| Wait for a condition ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/swift/eventually.without.swift), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/swift/eventually.with.swift)) | 84 | 45 | 46% |
| Peak-RSS budget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/swift/memory.without.swift), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/swift/memory.with.swift)) | 206 | 66 | 68% |
| Seeded fake data ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/swift/seeded_data.without.swift), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/swift/seeded_data.with.swift)) | 443 | 79 | 82% |

Estimated with the public `o200k_base` tokenizer: other models count
differently, so compare the ratios, not the numbers. Reasoning and retries
aren't counted, and the hand-written versions are often weaker (Linux-only
memory reads, no seed in the failure).

Tell your agent the helpers exist. Paste this into `CLAUDE.md`, `AGENTS.md`
or your editor's rules (206 tokens of context, paid back after about
2 tests):

````markdown
## Tests: use SuggestedTests (`import SuggestedTests`; XCTest or Swift Testing)

- Helpers throw on failure: mark tests `throws` and call them with `try` (`try await` in async tests).
- Timing budgets: `try expectPerformance(budget: 0.005) { ... }` (seconds); statistics: `try benchmark("name") { ... }`.
- Never sleep: `try eventually { try check(cache.isWarm, "why") }`.
- Memory: `try expectMemory(maxPeakGrowth: 50 * MiB) { ... }` after `try XCTSkipUnless(SystemProbe.isAvailable)`.
- Given/when/then: `try Scenario().given("...") { }.when("...") { }.then("...") { try check(...) }`.
- Seeded data: `TestData(seed: 42)` (`word()`, `email()`, `uuid()`, `integer(in: 18...90)`); duplicates: `try assertUnique(items)`.
````
<!-- prettier-ignore-end -->
<!-- /tokens:section -->

## Install

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/lesterkaufungen/suggestedtests-swift.git", from: "0.1.1"),
],
targets: [
  .testTarget(
    name: "AppTests",
    dependencies: ["App", .product(name: "SuggestedTests", package: "suggestedtests-swift")]
  ),
]
```

Requires Swift 5.10+ (tested with 5.10 and 6.4) on macOS 10.15+, Linux or
Windows. It also builds for iOS 13, tvOS 13 and watchOS 6, where there is no
native bridge: everything except `SystemProbe` and the memory budgets works
there, and `SystemProbe.isAvailable` is `false`.

```swift
import SuggestedTests
import XCTest
```

## Performance budgets

```swift
// Fail when code gets slower than a budget (the median of 20 runs, in seconds).
func testParsingStaysFast() throws {
  try expectPerformance(budget: 0.005) { _ = parse(bigJSON) }
}

func testBenchmarkReport() throws {
  let result = try benchmark("sort", iterations: 50, clock: .cpu) { _ = data.sorted() }
  print(result) // sort (cpu): n=50 min=1.02ms median=1.10ms mean=1.15ms p95=1.40ms max=2.01ms ±120µs
}
```

```
performance budget exceeded: median 7.31ms > budget 5.00ms
benchmark: n=20 min=6.90ms median=7.31ms mean=7.40ms p95=8.02ms max=8.30ms ±310µs
at AppTests/ParserTests.swift:12
```

Every failure ends with the line that called the helper, since XCTest on
Linux reports thrown errors without one.

The budget is checked against the median by default, which is robust against
one-off pauses. Pass `statistic: .p95` (or `.min`, `.mean`, `.max`) to check
something else. `clock: .cpu` measures the process's CPU time through the
native bridge: it ignores sleeping, I/O waits and other processes, so it is
far less noisy on busy CI machines. Both functions take async bodies too
(`try await expectPerformance(budget: 0.1) { try await api.load() }`).

## Memory budgets

```swift
func testImportStaysSmall() throws {
  try XCTSkipUnless(SystemProbe.isAvailable, SystemProbe.skipReason ?? "")
  try expectMemory(maxPeakGrowth: 50 * MiB) { importer.run(bigFile) }
}
```

```
memory budget exceeded: peak RSS grew 64.0 MiB > budget 50.0 MiB
MemoryReport(rss: +64.0 MiB, peak: +64.0 MiB, now: MemoryUsage(current: 152.8 MiB, peak: 180.8 MiB))
at AppTests/ImporterTests.swift:20
```

Resident memory is process-wide: allocators keep freed memory, and other
threads share the process. Use it to catch leaks and blow-ups measured in
megabytes. `maxRSSGrowth:` checks the current RSS instead of the peak.

## Native bridge (Linux / macOS / Windows)

```swift
try SystemProbe.processCPUTime()           // CPUTime(user: 1.25s, system: 80.00ms)
try SystemProbe.threadCPUTimeNanoseconds() // this thread only
try SystemProbe.memoryUsage()              // MemoryUsage(current: 40.1 MiB, peak: 52.3 MiB)
try SystemProbe.cpuCount()
```

**You don't need Rust.** The package contains the bridge prebuilt for Linux
(x64, arm64, x86, ARMv7 and RISC-V 64, both glibc and musl, so the static
Linux SDK works too), macOS (Intel and Apple Silicon) and Windows (x64, arm64,
x86), and loads it with `dlopen` / `LoadLibraryW`: no C target, no linker
settings. To use your own build, point `$SUGGESTEDTESTS_NATIVE_LIB` at it.

### Startup report

The bridge can describe the machine the tests run on: OS, architecture, C
library, container, VM and machine kind, as three `suggestedtests: ...` lines on
stderr. It is off by default, so nothing is printed. Turn it on for the whole
run, which prints it as the bridge loads:

```sh
SUGGESTEDTESTS_VERBOSE=1 swift test
```

Using any of this package's APIs loads the bridge, so the report appears even
in runs that never call a native helper. Or turn it on from code:

```swift
try SystemProbe.setVerbose(true)
```

```
suggestedtests: native bridge loaded (ABI v1)
suggestedtests: platform: linux x86_64 glibc 2.39, 64-bit, os 6.8.0-45-generic
suggestedtests: environment: server, container docker, vm kvm (KVMKVMKVM), flags: ci
```

## Eventually

```swift
func testCacheWarmsUp() async throws {
  try await eventually { try check(cache.isWarm, "cache is still cold") }
}

let job = try eventually(timeout: 10, interval: 0.1) { try queue.finishedJob() }
```

`eventually` runs its body until it stops throwing (every 20 ms, for up to
5 s by default) and returns its result. On timeout it throws with the last
error. The body must throw to fail: `XCTAssert…` records a failure without
throwing, so use `check(_:_:)`, `XCTUnwrap` or Swift Testing's `try #require`.

## Given / when / then

```swift
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
```

```
Then: the total is 30
check failed at AppTests/CartTests.swift:9: total is 20
Passed steps:
  ✓ Given: an empty cart
  ✓ When: two items are added
```

Each step runs as it is chained, and steps can be async
(`try await Scenario().given(...) { try await ... }`).

## Test data

```swift
let data = TestData(seed: 42) // same seed → same values, on every platform
let user = User(id: data.uuid(), name: data.word(), email: data.email(), age: data.integer(in: 18...90))
let users = try data.list(100) { d in User(name: d.word(), age: d.integer(in: 18...90)) }
```

`TestData.randomSeed()` picks a seed; print its `seed` (or the `TestData`
itself) in a failure message to reproduce a run.

## Duplicates

```swift
try assertUnique(ids) // expected unique elements, but 7 appears at index 2 and 5
```

## License

MIT
