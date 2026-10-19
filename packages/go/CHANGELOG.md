# Changelog

## 0.1.0

- Optional startup report: with `SUGGESTEDTESTS_VERBOSE=1` or `SetNativeBridgeVerbose` / `NativeBridgeVerbose`, the native bridge prints the platform and environment (OS, arch, libc, container, VM) to stderr once. Off by default.
- Also embeds the bridge for linux/386, linux/arm, linux/riscv64 (Go 1.25+), windows/386 and Android (all four ABIs, with cgo).
- Initial release, for Go 1.18+: `ExpectPerformance`/`Benchmark` (wall or CPU clock), `ExpectMemory` (RSS, Go heap, allocations), the native bridge (`ProcessCPUTime`, `ThreadCPUTime`, `ReadMemoryUsage`, `CPUCount`) embedded for Linux glibc/musl, macOS and Windows on amd64/arm64 and loaded with purego (no cgo), `Eventually`, `Scenario`, `NoGoroutineLeaks`, `Race`, `Golden`, `Data`/`TestData`, `AssertUnique`.
- The native bridge loads in the package's `init`, so `SUGGESTEDTESTS_VERBOSE=1` prints its startup report in every test binary that imports it.
