# CLAUDE.md

Guidance for Claude Code (and other contributors) working in this repository.

## What this is

`suggestedtests` is a **Flutter test-helper package** published to pub.dev. It
builds on `flutter_test` and only runs inside tests. There is no app and there
are no platform folders (android/ios/web/etc.). Do not add any.

It includes a **Rust native bridge** (`native/`). It exposes one C interface on
Windows, Linux and macOS and is bundled through a Dart build hook (`hook/build.dart`).

## Toolchain

- Flutter SDK lives at `~/development/flutter` (add `~/development/flutter/bin` to `PATH`).
- Dart comes bundled with Flutter. Use `flutter`/`dart` from that SDK.
- Rust via rustup (`~/.cargo/bin`). Prebuilts for all 8 targets are built on Linux:
  zig (`/opt/zig`) + `cargo install cargo-zigbuild` for Linux and macOS,
  `cargo install cargo-xwin` for Windows (downloads the MSVC CRT/SDK into
  `~/.cache/cargo-xwin` on first use).

## Commands

```sh
flutter pub get
flutter analyze                    # must report "No issues found!"
dart format .                      # CI expects formatted code
flutter test                       # unit + widget tests for the package
flutter test example/example.dart  # the example is itself a test file
dart pub publish --dry-run         # must report 0 warnings before publishing

# native bridge
(cd native && cargo test --release && cargo clippy --release -- -D warnings)
for os in linux macos windows; do PATH=/opt/zig:$PATH tool/build_prebuilt.sh $os; done
python3 tool/check_load.py native/prebuilt/linux-x64/libsuggestedtests_native.so
```

## Layout

```
lib/suggestedtests.dart      public entry point; only `export`s
lib/src/parameterized.dart   testCases, testWidgetsCases, TestCase
lib/src/scenario.dart        scenario, scenarioWidgets, Steps, ScenarioStepFailure
lib/src/performance.dart     benchmark, benchmarkSync, expectPerformance, expectCompletesWithin, BenchmarkResult, BenchmarkClock, Statistic
lib/src/eventually.dart      eventually
lib/src/spy.dart             Spy, Spy0/1/2, wasCalled/wasNotCalled/wasCalledTimes/wasCalledWith
lib/src/test_data.dart       TestData (seeded random data)
lib/src/matchers.dart        hasUniqueElements
lib/src/widget_tester_x.dart SuggestedWidgetTester extension (pumpApp, tapAndSettle, ...)
lib/src/system_probe.dart    SystemProbe, CpuTime, MemoryUsage, NativeBridgeException, formatBytes
lib/src/memory.dart          measureMemory, expectMemory, MemoryReport
lib/src/native/bindings.dart raw @Native FFI bindings (private; asset id = this file's URI)
hook/build.dart              picks native/prebuilt/<os>-<arch>[-musl]/, else cargo build, else nothing
native/                      Rust crate (cdylib): src/lib.rs = C ABI, src/sys/{unix,linux,macos,windows}.rs
native/include/*.h           C header; must match lib.rs and bindings.dart
native/prebuilt/             shipped binaries (committed; built locally with tool/build_prebuilt.sh)
tool/build_prebuilt.sh       builds prebuilts for one OS family (linux|macos|windows)
tool/check_load.py           ctypes smoke test for a prebuilt library
.github/workflows/ci.yml     cargo test x3 OS, prebuilts, Alpine/CentOS7 load checks, flutter test x4
test/<file>_test.dart        one test file per lib/src file
example/example.dart         runnable tour; keep it in sync with README
assets/logo.svg|png          logo (PNG rendered from SVG: rsvg-convert -w 512 -h 512 assets/logo.svg -o assets/logo.png)
```

## Conventions

- Every public API member needs a `///` doc comment (`public_member_api_docs` is on).
  Include a short ```` ```dart ```` example for main entry points.
- New helpers go in a new `lib/src/<name>.dart`. Export it from
  `lib/suggestedtests.dart` and add `test/<name>_test.dart`.
- Annotate functions that register tests with `@isTest`, and those that register
  groups with `@isTestGroup` (from `package:meta`). IDEs then show run buttons for them.
- Failures should be `TestFailure`s (use `fail(...)`) or matchers with a helpful
  `describeMismatch`. Messages must say *what* was wrong and *where*.
- Helpers that rely on real timers (`eventually`, `expectCompletesWithin`) don't work
  inside `testWidgets`' fake-async zone. Document this. Offer a `WidgetTester`
  equivalent where it makes sense.
- Keep dependencies minimal: `flutter`, `flutter_test`, `meta`, `hooks`, `code_assets`.
  No code generation. Use no `package:ffi`: leaf calls take `.address` of
  `Struct.create`/typed data.
- Don't duplicate matchers `flutter_test` already has (`isSorted`, `isSortedBy`,
  `containsOnce`, …). Names would clash.
- Validate arguments eagerly (`ArgumentError`/`RangeError`) and test that you do.

## Native bridge rules

- Changing the C ABI means updating `native/src/lib.rs`,
  `native/include/suggestedtests_native.h` and `lib/src/native/bindings.dart`
  together, and bumping `ST_ABI_VERSION` / `stAbiVersion` on breaking changes.
- Exported functions never panic and never call back into Dart (they are
  `isLeaf: true`). Errors are status codes: 0 ok, <0 bridge error, >0 OS error.
- The hook must **prefer prebuilt libraries** and must not run or look for cargo
  when a matching prebuilt exists (users shouldn't need Rust). CI enforces this
  by hiding cargo.
- glibc and musl builds can't load into each other's processes. The hook
  chooses by the ELF interpreter of the running `dart` executable.
- Linux prebuilts target glibc 2.17 (`cargo zigbuild --target <triple>.2.17`).
  Windows uses `+crt-static`. musl uses `-crt-static` (otherwise no cdylib).
- Thread CPU time is only meaningful between two samples with no `await` in
  between.

## Releasing to pub.dev

1. Bump `version` in `pubspec.yaml` (semver) and add a `CHANGELOG.md` entry.
   If `native/` changed, rebuild all 8 prebuilts locally (see Commands) on the
   `local-only` branch, which is never pushed, then bring them to `main` with
   `git checkout local-only -- native/prebuilt` and commit.
2. `flutter analyze && flutter test && dart pub publish --dry-run`.
3. `dart pub publish`. Publishing is permanent: a version can't be deleted, only retracted within 7 days.
4. Tag the commit: `git tag v<version> && git push --tags`.
