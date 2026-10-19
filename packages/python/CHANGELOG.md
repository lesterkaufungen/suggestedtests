# Changelog

## 0.1.1

- pytest tracebacks of failed helpers (`assert_unique`, `expect_performance`, `eventually`, `expect_memory`, `expect_allocations`, `no_leaked_threads`, `completes_within`) end at the test's line instead of inside the package.

## 0.1.0

- Optional startup report: with `SUGGESTEDTESTS_VERBOSE=1` or `SystemProbe.set_verbose()` / `SystemProbe.verbose()`, the native bridge prints the platform and environment (OS, arch, libc, container, VM) to stderr once. Off by default.
- Supports Python 3.8+ (CPython and PyPy; `expect_allocations` needs CPython) and pytest 7+.
- Native bridge for Linux x64/arm64/x86/ARMv7/RISC-V (glibc and musl), macOS, Windows x64/arm64/x86 and Android (Termux).
- Initial release: `expect_performance`/`benchmark` (sync and async), `expect_memory`, `expect_allocations`, `SystemProbe` (ctypes bridge for Windows, Linux glibc/musl and macOS, x64 and arm64), `eventually`/`eventually_async`, `completes_within`, `Steps`, `TestData`, `assert_unique`, `no_leaked_threads`, and a pytest plugin with the `test_data` and `steps` fixtures, `--st-seed` and the `requires_native_bridge` marker.
- The native bridge loads on import (the pytest plugin imports the package), so `SUGGESTEDTESTS_VERBOSE=1` prints its startup report in every run.
