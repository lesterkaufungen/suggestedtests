# Changelog

## 0.1.2

- Minor fixes.

## 0.1.1

- `expectNoLeakedHandles` no longer misses a leak when another handle of the same type closes meanwhile (as Vitest's own timers do): the resources the body opened are tracked one by one. Unref'd handles don't count as leaks on any Node version.
- `suggestedtests/vitest` types work with Vitest 5 (`Assertion<R, T>`) as well as 1-4, also without `skipLibCheck`.
- The package ships `src/`, so source-mapped stack frames point at files that exist.

## 0.1.0

- Optional startup report: with `SUGGESTEDTESTS_VERBOSE=1` or `SystemProbe.setVerbose()` / `SystemProbe.verbose`, the native bridge prints the platform and environment (OS, arch, libc, container, VM) to stderr once. Off by default.
- Runs on Node.js 10.20+ (ES2018 build); leaked-handle detection falls back to `async_hooks` before Node 17.3.
- Node-API addon for Linux x64/arm64/x86/ARMv7/RISC-V (glibc and musl), macOS and Windows x64/arm64/x86.
- `suggestedtests/vitest` and `suggestedtests/jest` setup files that register the matchers and ship their types (Vitest `Assertion`, Jest global `expect` and `@jest/globals`).
- Initial release: `expectPerformance`/`benchmark`, `expectMemory`, `SystemProbe` (Node-API addon for Windows, Linux glibc/musl and macOS, x64 and arm64), `expectNoLeakedHandles`, `eventually`, `deferred`/`flushPromises`, `scenario`, `TestData`, `assertUnique` and the `toHaveUniqueElements` matcher.
- The native bridge loads on import (and from the Vitest and Jest setup files), so `SUGGESTEDTESTS_VERBOSE=1` prints its startup report in every run.
