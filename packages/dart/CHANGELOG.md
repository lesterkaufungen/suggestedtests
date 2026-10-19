## 0.1.0

Initial release.

- `testCases` / `testWidgetsCases`: table-driven tests, one test per row.
- `scenario` / `scenarioWidgets`: given/when/then tests that name the failing step.
- `benchmark`, `benchmarkSync`, `expectPerformance`, `expectCompletesWithin`: timing statistics and performance budgets, with `BenchmarkClock.wall` or `BenchmarkClock.cpu`.
- Native bridge in Rust with one C interface, precompiled for Linux x64, arm64, x86, ARMv7 and RISC-V (glibc ≥ 2.17 and musl), macOS x64 and arm64, Windows x64, arm64 and x86, and Android (for integration tests on a device). Bundled by a build hook; compiles from source only when no precompiled library matches.
- `SystemProbe`: process and thread CPU time, current and peak RSS, CPU count.
- Optional startup report: with `SUGGESTEDTESTS_VERBOSE=1` or `SystemProbe.setVerbose()` / `SystemProbe.verbose`, the native bridge prints the platform and environment (OS, arch, libc, container, VM) to stderr once. Off by default.
- `measureMemory` / `expectMemory`: memory budgets.
- `eventually`: polling assertion that replaces fixed sleeps.
- `Spy0` / `Spy1` / `Spy2` with `wasCalled`, `wasNotCalled`, `wasCalledTimes`, `wasCalledWith`.
- `TestData`: seeded, reproducible test data.
- Matcher: `hasUniqueElements`.
- `WidgetTester` extensions: `pumpApp`, `tapAndSettle`, `enterTextAndSettle`, `pumpUntilFound`, `pumpUntilGone`.
- Requires Flutter 3.38.4 / Dart 3.10: build hooks need Dart 3.10; Flutter 3.38.0 ships a beta Dart (3.10.0-290.4.beta) that `sdk: ^3.10.0` rejects, and before 3.38.4 `flutter test` on Linux fails for any package with a build hook unless `clang++` and a linker next to it are installed.
- Works with `hooks` 1.x and 2.x and `code_assets` 1.x and 2.x: Flutter 3.38 pins `meta` 1.17.0, which `hooks` 2.1+ doesn't accept.
- The native bridge loads on the first call into the package (usually while tests are registered), so `SUGGESTEDTESTS_VERBOSE=1` prints its startup report in every run.
