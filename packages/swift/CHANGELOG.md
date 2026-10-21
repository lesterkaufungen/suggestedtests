## 0.1.2

- Minor fixes.

## 0.1.1

- Failures of `expectPerformance`, `expectMemory`, `eventually` and `assertUnique` end with the line that called the helper (`at AppTests/ParserTests.swift:12`), like `check`: XCTest on Linux reports thrown errors at `<EXPR>:0`. The helpers take `file:` and `line:` parameters with defaults.

## 0.1.0

Initial release.

- `expectPerformance` / `benchmark`: timing statistics and performance budgets (min, median, mean, p95, max) on wall-clock or CPU time, for sync and async code.
- `expectMemory` / `measureMemory`: budgets for resident memory and its peak, read through the native bridge.
- `eventually`: polling instead of fixed sleeps, sync and async.
- `Scenario`: given/when/then steps whose failure names the failing step and lists the steps that passed.
- `TestData`: seeded, reproducible fake data (SplitMix64, the same on every platform).
- `assertUnique`, `check`: a duplicate check that names the positions, and a throwing assertion for `eventually` and scenario steps.
- `SystemProbe`: process and thread CPU time, current and peak RSS and CPU count from the Rust native bridge, prebuilt for Linux (x64, arm64, x86, ARMv7, RISC-V 64; glibc and musl), macOS (x64, arm64) and Windows (x64, arm64, x86), and loaded with `dlopen` / `LoadLibraryW`. Using any API loads it, so `SUGGESTEDTESTS_VERBOSE=1` prints the startup report in every run.
- Helpers throw `SuggestedTestsFailure`, which XCTest and Swift Testing both report as a test failure; the package depends on neither.
- Requires Swift 5.10 (tested with 5.10.1 and 6.4.1); macOS 10.15, iOS 13, tvOS 13, watchOS 6 (no native bridge on iOS, tvOS and watchOS: `SystemProbe.isAvailable` is false there).
