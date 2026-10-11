## 0.1.0

Initial release.

- `testCases` / `testWidgetsCases`: table-driven tests, one test per row.
- `scenario` / `scenarioWidgets`: given/when/then tests that name the failing step.
- `benchmark`, `benchmarkSync`, `expectPerformance`, `expectCompletesWithin`: timing statistics and performance budgets, with `BenchmarkClock.wall` or `BenchmarkClock.cpu`.
- Native bridge in Rust with one C interface for Windows, Linux (glibc ≥ 2.17 and musl) and macOS, x64 and arm64. Ships precompiled and is bundled by a build hook. Compiles from source only when no precompiled library matches.
- `SystemProbe`: process and thread CPU time, current and peak RSS, CPU count.
- `measureMemory` / `expectMemory`: memory budgets.
- `eventually`: polling assertion that replaces fixed sleeps.
- `Spy0` / `Spy1` / `Spy2` with `wasCalled`, `wasNotCalled`, `wasCalledTimes`, `wasCalledWith`.
- `TestData`: seeded, reproducible test data.
- Matcher: `hasUniqueElements`.
- `WidgetTester` extensions: `pumpApp`, `tapAndSettle`, `enterTextAndSettle`, `pumpUntilFound`, `pumpUntilGone`.
