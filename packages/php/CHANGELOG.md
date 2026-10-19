# Changelog

## 0.1.0

- Optional startup report: with `SUGGESTEDTESTS_VERBOSE=1` or `SystemProbe::setVerbose()` / `SystemProbe::verbose()`, the native bridge prints the platform and environment (OS, arch, libc, container, VM) to stderr once. Off by default.
- Supports PHP 7.4+ and PHPUnit 9.6 to 12. `TestData` uses its own generator, so seeds reproduce on every PHP version; `maxHeapPeakGrowth` needs PHP 8.2.
- Native bridge for Linux x64/arm64/x86/ARMv7/RISC-V (glibc and musl), macOS, Windows x64/arm64/x86 and Android (Termux).
- Initial release: `assertPerformance`/`Benchmark`, `assertMemory`/`Memory` (PHP heap and RSS), `SystemProbe` (ext-ffi bridge for Windows, Linux glibc/musl and macOS, x64 and arm64), `assertEventually`, `scenario`/`Steps`, `Spy`, `assertMatchesSnapshot`, `testData()`/`TestData`, `Sandbox` and `temporaryDirectory()`, `assertUniqueElements`.
- The native bridge loads with Composer's autoloader (CLI only), so `SUGGESTEDTESTS_VERBOSE=1` prints its startup report in every PHPUnit run.
