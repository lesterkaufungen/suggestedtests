# Changelog

## 0.1.0

- Optional startup report: with `SUGGESTEDTESTS_VERBOSE=1` or `SystemProbe.setVerbose()` / `SystemProbe.verbose()` (also `-Dsuggestedtests.verbose=true`), the native bridge prints the platform and environment (OS, arch, libc, container, VM) to stderr once. Off by default.
- Java 8+ (bytecode 52), Gradle and Kotlin. `SuggestedTestsRule` for JUnit 4 (Android's default). `Scenario.givenThat` for setup steps without a value (an overload broke Kotlin's lambda resolution).
- `suggestedtests-android` AAR with the bridge for arm64-v8a, armeabi-v7a, x86_64 and x86 (API 21+); the Java API needs API 26+ or core library desugaring.
- `TestData` uses its own xoshiro256** generator: the same values on every JVM, on Android, and as the Go package.
- Initial release: `Benchmark`, `Memory` and `@MemoryBudget`, `SystemProbe` (JNI bridge for Windows, Linux glibc/musl and macOS, x64 and arm64), `Concurrency.race`, `Leaks`, `Eventually`, `Scenario`, `Spy`, `TestData` with `@SuggestedTests`/`@Seed`, `SuggestedAssertions`, `@RequiresNativeBridge`.
- The native bridge loads when a JUnit Platform session starts (a `LauncherSessionListener`; `junit-platform-launcher` is a `provided` dependency) and in `SuggestedTestsRule` and the extension, so `SUGGESTEDTESTS_VERBOSE=1` prints its startup report in every run.
- Works with TestNG: the helpers need no JUnit class, and a TestNG listener (`provided` dependency on TestNG 7.5.1) loads the native bridge when a TestNG run starts. Tested by `compat/testng` on Java 8 and 21 with no JUnit on the classpath.
