# CLAUDE.md

Guidance for Claude Code (and other contributors) working in this repository.

## What this is

A **monorepo of test-helper packages**, one per language, that share one
**Rust native bridge** (`native/`) for process CPU time, memory, and
platform/environment detection:

| Package | Published as | Oldest supported | Runner integration | Bridge binding |
| --- | --- | --- | --- | --- |
| `packages/dart` | pub.dev `suggestedtests` | Flutter 3.38.4 / Dart 3.10 | `flutter_test` | `@Native` FFI + build hook |
| `packages/python` | PyPI `suggestedtests` | Python 3.8, PyPy; pytest 7 | pytest plugin (`pytest11`) | ctypes |
| `packages/js` | npm `suggestedtests` (TypeScript → CommonJS ES2018) | Node.js 10.20 | runner-agnostic; `suggestedtests/vitest`, `/jest` | Node-API addon (`native/node`) |
| `packages/php` | Packagist `lesterkaufungen/suggestedtests` | PHP 7.4; PHPUnit 9.6 | PHPUnit trait | ext-ffi |
| `packages/java` | Maven Central `io.github.lesterkaufungen:suggestedtests` (+ `suggestedtests-android` AAR) | Java 8; Android API 21 (Java API: 26 or desugaring) | JUnit 5/6 extension, JUnit 4 rule; helpers framework-free (TestNG tested) | JNI (`native/src/jni.rs`) |
| `packages/go` | Go module `github.com/lesterkaufungen/suggestedtests/packages/go` | Go 1.18 (riscv64: 1.25) | `testing.TB` | purego (no cgo), library embedded |
| `packages/swift` | SwiftPM, split repo `lesterkaufungen/suggestedtests-swift` | Swift 5.10; macOS 10.15 / iOS 13 (no bridge on iOS) | XCTest and Swift Testing (helpers throw) | `dlopen` / `LoadLibraryW`, libraries as SwiftPM resources |

**Portability is a requirement**: every package supports the oldest runtime
listed above and the newest, on every platform with a prebuilt. Test both
ends before changing anything (see Commands), and don't raise a minimum
without a reason that's written down here.

They are libraries for tests only. There are no apps and no Flutter platform
folders (android/ios/web/etc.). Do not add any.

## Toolchains

Everything is installed without root under `~/.local` (see the commands of
the session that set it up in git history if one is missing):

- Flutter SDK at `~/development/flutter` (add `~/development/flutter/bin` to `PATH`).
  The oldest supported Flutter goes in `~/development/flutter-3.38.4`
  (`git clone --depth 1 -b 3.38.4 https://github.com/flutter/flutter.git`);
  `tool/release_build.sh` tests with it when present and says so when not.
  Why 3.38.4: build hooks need Dart 3.10; 3.38.0 bundles Dart
  `3.10.0-290.4.beta`, which `sdk: ^3.10.0` rejects; and 3.38.1-3.38.3 fail
  `flutter test` on Linux for any package with a hook unless `clang++` has an
  `ld.lld`/`ld` in its own directory (Ubuntu needs `lld` for that). Flutter 3.38
  pins `meta` 1.17.0, so `hooks`/`code_assets` stay `>=1.0.0 <3.0.0` (`hooks`
  2.1+ needs meta 1.19), and `matcher` 0.12.17: no `isSorted` before Flutter 3.41.
- Rust via rustup (`~/.cargo/bin`), all targets installed. Prebuilts are built
  on Linux: zig 0.14+ (`~/.local/share/zig-0.14.1`) + `cargo-zigbuild` for
  Linux (zig 0.10 can't target ARMv7), `/opt/zig` (0.10) for the macOS stubs,
  `cargo-xwin` for Windows (`XWIN_ARCH=x86,x86_64,aarch64`), and the Android NDK
  (`~/.local/share/android-ndk/android-ndk-r30`; `ANDROID_NDK_HOME`).
- QEMU user mode (`~/.local/share/qemu/usr/bin/qemu-*-static`) to run Rust tests
  for ARMv7 / RISC-V / ARM64; 32-bit x86 binaries run directly.
- Python via `uv` (`~/.local/bin/uv`): 3.8, 3.12 (system), 3.14 and PyPy 3.10.
  The system Python has no `ensurepip`.
- Node.js via nvm: 10, 12, 14, 16, 18 and 24 (`nvm exec <v> ...`).
- PHP 8.3 (system) with ext-ffi; `dom`/`mbstring`/`xml`/`xmlwriter` are unpacked
  from the matching Ubuntu debs into `~/.local/share/php-ext` and loaded via
  `PHP_INI_SCAN_DIR=":$HOME/.local/share/php-ext/conf.d"` (in `~/.bashrc`).
  PHP 7.4.33 built from source with FFI at `~/.local/share/php74` (run it with
  `PHP_INI_SCAN_DIR` unset). Composer at `~/.local/bin/composer` (needs 8.3:
  the 7.4 build has no OpenSSL; resolve 7.4 deps with `config.platform.php`).
- Java: JDK 21 at `~/.local/share/jdk21` (the system has only a JRE), JDK 8 at
  `~/.local/share/jdk8`; `./mvnw` builds with 21 and `-Djvm=<jdk>/bin/java`
  runs the tests on another JVM. Gradle 9.8 at `~/.local/share/gradle`.
- Go: gvm's 1.25.4 plus `~/.local/share/go1.18.10` and `~/.local/share/go1.27.2`;
  run those with `GOROOT=<dir> PATH=<dir>/bin:$PATH GOTOOLCHAIN=local` (gvm
  exports a `GOROOT`).
- Swift: `~/.local/share/swift-5.10.1` (the oldest release with an Ubuntu 24.04
  build, hence the 5.10 minimum) and `~/.local/share/swift-6.4.1`, the
  swift.org tarballs checked against swift.org's GPG keys; run them with
  `PATH=<dir>/usr/bin:$PATH`. The downloads resume from
  `~/.cache/suggestedtests-swift/fetch-swift.sh` (download.swift.org resets
  connections often).
- Android SDK at `~/.local/share/android-sdk` (platform-tools, emulator,
  build-tools 35, system images API 21 and 35) and AVDs `st21`/`st35` in
  `~/.local/share/android-avd` (`/dev/kvm` is usable).
- `shellcheck` (system) for the scripts in `tool/`.
- Publishing logins are the maintainer's tokens at the repo root, gitignored
  (`/*.token`) and mode 600: `github.token` (to git via a credential helper),
  `pypi.token` (`UV_PUBLISH_TOKEN`), `npm.token` (`${NPM_TOKEN}` in a generated
  `release/npmrc`), `maven.token` (the `<server>` snippet Central Portal
  generates; `${env.*}` in a generated `release/settings.xml`) and
  `packagist.token` (`USERNAME:TOKEN`, the main API token from
  packagist.org/profile: creating a package needs it). pub.dev has no
  tokens: `flutter pub login` once. Maven Central signatures use the GPG key
  `58EAE1216EAD04A2F803975D42F2E759ECB698A8` in `~/.gnupg` (RSA 4096, no
  passphrase, no expiry; public key on keyserver.ubuntu.com). If it's lost,
  generate and upload a new one: Central doesn't pin keys. Without a file, `tool/release_publish.sh`
  uses the usual login. Never print a token, pass one on a command line (curl
  reads headers from a pipe), or commit one. Editors set `GIT_ASKPASS`,
  which opens a login dialog on every git network command without a stored
  login; `tool/release_publish.sh` turns that off and fails instead.

## Commands

`tool/release_build.sh` runs all of the below (and more: every toolchain,
QEMU, the emulators); these are the pieces, for working on one package.

```sh
# native bridge (C ABI + JNI + Node addon)
(cd native && cargo fmt --all --check && cargo test --release --workspace && cargo clippy --release --workspace -- -D warnings)
(cd native && cargo run --example platform)   # st_platform / st_environment from Rust
PATH=~/.local/share/zig-0.14.1:$PATH tool/build_prebuilt.sh linux
for os in macos windows android; do PATH=/opt/zig:$PATH tool/build_prebuilt.sh $os; done
python3 tool/check_load.py native/prebuilt/linux-x64/libsuggestedtests_native.so
node tool/check_load_node.js native/prebuilt/linux-x64/suggestedtests_native.node
tool/stage.sh go          # then commit packages/go/internal/native/prebuilt

# dart (packages/dart); also `flutter pub downgrade` before testing, for the lowest deps
flutter pub get && flutter analyze && dart format . && flutter test && flutter test example/example.dart

# python (packages/python): .venv (3.12), .venv-3.8-pytest70, .venv-3.14, .venv-pypy
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/pytest
.venv-3.8-pytest70/bin/python -m pytest && .venv-pypy/bin/python -m pytest

# js (packages/js)
npm ci && npm run typecheck && npm run format:check && npm test && npm run test:types
npm run build && for v in 10 12 14 16 18; do nvm exec $v node test-compat/smoke.js; done

# php (packages/php): 8.3 + PHPUnit 12; no lock file (gitignored), so `update`
composer validate --strict --no-check-lock && composer update && vendor/bin/phpunit
# 7.4 + PHPUnit 9: tool/release_build.sh php resolves into vendor-7.4/ (gitignored) via a
# generated composer-7.4.json (config.platform.php 7.4.33), then runs
env -u PHP_INI_SCAN_DIR ~/.local/share/php74/bin/php vendor-7.4/bin/phpunit --bootstrap vendor-7.4/autoload.php

# java (packages/java)
./mvnw -B verify -Djvm=$HOME/.local/share/jdk8/bin/java && ./mvnw -B verify && ./mvnw -B javadoc:javadoc
./mvnw -B install -DskipTests && (cd compat/gradle-kotlin && ~/.local/share/gradle/bin/gradle test)
./mvnw -B -f compat/testng/pom.xml test -Djvm=$HOME/.local/share/jdk8/bin/java && ./mvnw -B -f compat/testng/pom.xml test
../../tool/build_aar.sh

# go (packages/go); Go 1.18 and the newest, CGO_ENABLED=0 and 1, GOARCH=amd64 and 386
gofmt -l . && go vet ./... && go test -count=1 ./... && go test -race ./...

# swift (packages/swift); Swift 5.10.1 and 6.4.1; the staged package is tested outside the repo
swift build -Xswiftc -warnings-as-errors && swift test
tool/stage.sh swift   # Sources/SuggestedTests/Prebuilt/ (gitignored) for the split repo

# Android: boot an emulator, then (needs ./mvnw package and tool/stage.sh go)
~/.local/share/android-sdk/emulator/emulator -avd st35 -no-window -no-snapshot &
tool/android_smoke.sh

# release scripts
shellcheck -x -P SCRIPTDIR/.. -e SC2012 tool/release_*.sh tool/stage.sh
tool/release_build.sh dart python   # some steps only (no checksums written)
```

## Layout

```
native/                        Rust workspace, shared by every package
  src/lib.rs                   C ABI (st_* functions); src/sys/{unix,linux,macos,windows}.rs
  src/jni.rs                   JNI exports for packages/java (same cdylib)
  node/                        Node-API addon crate (links the core as an rlib)
  include/suggestedtests_native.h
  tests/prebuilt.rs            checks every committed prebuilt without running it: CPU, libc, exports vs header + jni.rs
  examples/platform.rs         st_platform / st_environment from Rust, and picking the prebuilt to download
  prebuilt/<os>-<arch>[-musl]/ committed binaries: the C/JNI library + suggestedtests_native.node
tool/build_prebuilt.sh         builds both libraries for one OS family (linux|macos|windows)
tool/check_load.py             ctypes smoke test of a prebuilt C library
tool/check_load_node.js        smoke test of a prebuilt Node addon
tool/check_macho.py            the macOS prebuilts as dyld sees them: ad-hoc signature (page hashes), minimum macOS, libraries, initializer
tool/stage.sh                  copies native/ into packages/{dart,php} before publishing, and into packages/go (committed)
tool/build_aar.sh              packages/java/target/suggestedtests-android-<v>.aar (classes + jni/<abi>/)
tool/android_smoke.sh          Java on ART (app_process) and Go tests on a connected device/emulator
tool/release_build.sh          the maintainer's release build: prebuilts + every check; writes release/prebuilt.sha256
tool/release_publish.sh        pushes and uploads a release without compiling Rust (`--dry-run` checks only)
tool/release_verify.py         the native libraries inside an artifact are the checksummed ones
tool/release_registries.py     Packagist (create, then re-crawl) and the Swift Package Index (a PackageList pull request once)
tool/macos_check.sh            starts .github/workflows/macos.yml (all packages on arm64 + Intel macOS) and waits for it
tool/token_estimate.py         counts bench/tokens/ (o200k_base); --readme rewrites the READMEs' numbers and bench/tokens/banner.{svg,png}
bench/tokens/<language>/       <case>.with/.without.<ext>: one test with and without the helpers; AGENTS.md: the agent snippet
release/                       gitignored: build logs, checksums, publish artifacts

packages/dart/                 lib/src/<helper>.dart, test/<helper>_test.dart, hook/build.dart, example/
packages/python/               src/suggestedtests/<helper>.py, tests/test_<helper>.py, examples/, hatch_build.py
packages/js/                   src/<helper>.ts, test/<helper>.test.ts, examples/, scripts/stage-prebuilds.mjs
packages/php/                  src/<Helper>.php, src/PHPUnit/SuggestedTests.php (trait), tests/<Helper>Test.php, examples/
packages/java/                 src/main/java/io/github/lesterkaufungen/suggestedtests/{,junit/,junit4/,internal/}, src/test/java/...
packages/java/android/         AAR manifest, consumer ProGuard rules, POM of the AAR
packages/java/compat/          gradle-kotlin/ (Gradle + Kotlin consumer), testng/ (TestNG, no JUnit), android/AndroidSmoke.java
packages/js/test-compat/       dependency-free smoke test of dist/ for Node 10-18
packages/go/                   <helper>.go + <helper>_test.go, example_test.go, internal/native/{native.go,load_*.go,embed_*.go,prebuilt/}
packages/swift/                Sources/SuggestedTests/<Helper>.swift (+ NativeBridge.swift), Tests/SuggestedTestsTests/<Helper>Tests.swift,
                               Tests/ExampleTests/ (the README's examples), Tests/SuggestedTestsReportCheck/ (child process for report tests)
packages/js/{vitest,jest}.*    setup files + matcher types (vitest.d.mts is ESM: Vitest's types can't be required)
```

## How each package finds the native library

Every loader checks, in order:

1. an explicit path: `$SUGGESTEDTESTS_NATIVE_LIB` (Dart hook excepted,
   JS uses `$SUGGESTEDTESTS_NATIVE_ADDON`, Java also accepts `-Dsuggestedtests.native.lib`);
2. the copy bundled in the published artifact;
3. the monorepo's `native/prebuilt/<platform>/` (development checkout).

How the prebuilts get into each artifact:

- Dart: the hook uses `packages/dart/native/` when staged, else `../../native/`.
  `tool/stage.sh dart` stages it for `pub publish` (it's in `.gitignore`, but
  not in `.pubignore`).
- Python: `hatch_build.py` force-includes the C libraries into `suggestedtests/_prebuilt/`.
- JS: `npm pack`/`publish` runs `prepack`, which copies the `.node` files into `prebuilds/`.
- Java: `pom.xml` adds `../../native/prebuilt` as a resource directory (desktop
  C libraries only). Android: `tool/build_aar.sh` puts `android-<abi>/` into the
  AAR's `jni/`, and `NativeBridge` uses `System.loadLibrary` when it detects ART.
- PHP: `tool/stage.sh php` copies them into `packages/php/native/prebuilt/` for the split repo.
- Swift: `tool/stage.sh swift` copies the 15 desktop libraries into
  `packages/swift/Sources/SuggestedTests/Prebuilt/` for the split repo;
  `Package.swift` declares them as resources (and `SUGGESTEDTESTS_BUNDLED`)
  only when that directory exists. A monorepo checkout finds `native/prebuilt/`
  from `#filePath`. The split repos (PHP, Swift) commit the staged copy:
  `tool/release_publish.sh` drops its line from the split repo's `.gitignore`
  and checks `git ls-files` has every library.
- Go: `packages/go/internal/native/prebuilt/` is a **committed** copy (Go
  modules come from git; `//go:embed` can't leave the module), refreshed with
  `tool/stage.sh go`; `tool/release_publish.sh` refuses if it differs from `native/prebuilt/`.
  Build-tagged `embed_<os>_<arch>.go` files put only the matching library in a
  test binary; it's extracted to a content-addressed temp file and loaded with
  purego. Platforms without a prebuilt don't import purego at all.

## Conventions (all languages)

- Every public API member has a doc comment (dartdoc, docstring, TSDoc,
  PHPDoc, Javadoc). Main entry points include a short example.
- The READMEs' token numbers and agent snippets are generated: edit
  `bench/tokens/` (keep each `.without` file equivalent to its `.with` file:
  same iterations, timeouts and failure details, written as a careful agent
  would), then run `uv run --no-project --with tiktoken python
  tool/token_estimate.py --readme`. Call the numbers estimates. Rerun it when
  a helper's API changes.
- One helper per source file, with a matching test file. Each package also
  has a runnable example that is itself a test. Keep it in sync with that
  package's README.
- Failures are the runner's assertion type: `TestFailure`/`fail()` in Dart,
  `AssertionError` in Python, Java and JS, `AssertionFailedError` in PHP
  (via `SuggestedTests\Failure`), `t.Errorf` in Go (helpers return
  whether they passed), and a thrown `SuggestedTestsFailure` in Swift (XCTest
  and Swift Testing both fail a test that throws; the package imports
  neither). Messages say *what* was wrong and *where*:
  the step, the duplicate's positions, the allocating line, the seed.
- Validate arguments eagerly, before running the body. Use
  `ArgumentError`/`RangeError` in Dart, `ValueError`/`TypeError` in Python,
  `RangeError`/`TypeError` in JS, `InvalidArgumentException`/`OutOfRangeException`
  in PHP, `IllegalArgumentException` in Java, and in Go `t.Fatalf` (helpers
  with a `testing.TB`), a returned `error`, or a panic (`TestData`, like
  math/rand), and a thrown `SuggestedTestsArgumentError` in Swift (or a type
  that can't be wrong, like `ClosedRange`). Test that you do.
- Don't duplicate what the runner already has. That means no parameterized
  helpers outside Dart, no spies in Python and JS (`unittest.mock`, `vi.fn`),
  no snapshots in JS, and no timeouts in Java (`assertTimeout`). Don't
  duplicate `flutter_test` matchers (`isSorted`, `containsOnce`, …).
- Keep runtime dependencies at zero: Dart only `flutter`, `flutter_test`,
  `meta`, `hooks`, `code_assets`; Python, JS, PHP and Swift none; Java only
  `junit-jupiter-api`, `junit` (the JUnit 4 rule), `junit-platform-launcher`
  and `testng` 7.5.1 (the two run listeners) as `provided`, and the helpers
  themselves reference no JUnit class (`compat/testng` runs without JUnit); Go only `github.com/ebitengine/purego`
  (pinned to v0.10.x, the last release supporting Go 1.18; v0.11 needs 1.25).
  Go code must not use APIs newer than 1.18 (`min`/`max`, `slices`, `maps`,
  `math/rand/v2`, `errors.Join`, `atomic.Int64`, …). No code generation. Dart uses no
  `package:ffi`: leaf calls take `.address` of `Struct.create` or typed data.
- Units follow each language: Dart `Duration`, Python seconds or `timedelta`,
  JS and PHP milliseconds, Java and Go `Duration`, Swift seconds as `Double`
  (like XCTest's `TimeInterval`; `Duration` needs macOS 13). Byte sizes are plain integers
  with `KiB`/`MiB`/`GiB` constants.
- Dart: annotate test-registering functions with `@isTest` / `@isTestGroup`.
  Helpers that rely on real timers don't work inside `testWidgets`; document
  this and offer a `WidgetTester` equivalent. JS timing helpers capture the
  real timers on import, so they keep working under fake timers.
- Python: give classes named `Test*` the attribute `__test__ = False`.
- **Stay within each language's minimum** (see the table at the top). The
  linters and the old toolchains catch most slips:
  - Python 3.8: `from __future__ import annotations` everywhere; no runtime
    `X | Y`, `StrEnum`, `datetime.UTC`, `add_note` (use `scenario.add_note`),
    `tracemalloc.reset_peak` without a `hasattr`; `tracemalloc` is imported
    lazily (PyPy lacks it). ruff targets `py38`.
  - JS: TypeScript targets ES2018 with `lib` ES2018 + BigInt; no `globalThis`
    (use `timers.globalObject`), no `node:` import prefixes, no
    `new Error(msg, { cause })` (use `withCause`). Vitest/Jest only in tests.
  - PHP 7.4: no enums (constant classes), `readonly`, constructor promotion,
    `match`, named arguments, `mixed`/union/`never` types, `throw`
    expressions, nullsafe `?->`, `str_*` 8.0 functions (use `Compat`). Tests
    keep a `@dataProvider` docblock next to the attribute for PHPUnit 9; lint
    with `~/.local/share/php74/bin/php -l`.
  - Java 8 (`--release 8`): no `List.of`, `var`, `Optional.isEmpty`,
    `Path.of`, `ProcessHandle`, `String.repeat`. For Android: no
    `java.lang.management` and no `SplittableRandom`; the API's `java.time` /
    `java.util.function` need API 26 or core library desugaring.
  - Kotlin calls the Java API: don't overload on `Runnable` vs `Supplier`
    (Kotlin picks the `Unit` one for `{ value }`), hence `Scenario.givenThat`.
  - Go 1.18 (see Dependencies above); 32-bit (`GOARCH=386`) must pass too.
  - Swift 5.10 (`swift-tools-version:5.10`): no typed throws, `sending`,
    `~Copyable` generics or other 6.x features, and the package's own tests use
    XCTest (Swift Testing needs 6.0). It must also build without warnings on
    the newest toolchain (`-warnings-as-errors`).

## Native bridge rules

- Changing the C ABI means updating `native/src/lib.rs`,
  `native/include/suggestedtests_native.h` and every binding together:
  `packages/dart/lib/src/native/bindings.dart`, `packages/python/src/suggestedtests/_native.py`,
  `packages/php/src/Native/Bridge.php`, `native/src/jni.rs` +
  `packages/java/.../internal/NativeBridge.java`, `native/node/src/lib.rs` +
  `packages/js/src/native.ts`, `packages/go/internal/native/native.go`, and
  `packages/swift/Sources/SuggestedTests/NativeBridge.swift`. Bump `ST_ABI_VERSION` and every `ABI_VERSION`
  on breaking changes.
- Exported functions never panic and never call back into the host language.
  Errors are status codes: 0 ok, <0 bridge error, >0 OS error. The JNI and
  Node wrappers write struct results into a caller-allocated `long[]` or
  `BigUint64Array` and return the same codes.
- The core library has no link-time dependency on a JVM or on Node: JNI
  goes through the `JNIEnv` table. The Node addon resolves `napi_*` at load
  time (`dlsym(RTLD_DEFAULT)` / `GetProcAddress`), so it needs neither
  `node.lib` nor `-undefined dynamic_lookup`.
- Avoid heap allocation in exports; a single `Vec` adds ~280 KB to the macOS dylib.
- Packages must **prefer prebuilt libraries**. Only the Dart hook may fall
  back to `cargo` (for users on platforms without a prebuilt; keep it), and
  only when no prebuilt matches. The release scripts remove cargo and rustc
  from `PATH` outside the native step to enforce this.
- glibc and musl builds can't load into each other's processes. Each loader
  picks one by the ELF interpreter of the running executable.
- 19 prebuilt targets: Linux x64, arm64, x86, ARMv7 (hard float) and riscv64,
  each glibc and musl; macOS x64/arm64; Windows x64/arm64/x86; Android
  arm64-v8a/armeabi-v7a/x86_64/x86 (API 21, 16 KB pages, no Node addon).
  Linux glibc builds target 2.17 (`cargo zigbuild --target <triple>.2.17`;
  riscv64: 2.27). Windows uses `+crt-static`; musl uses `-crt-static`
  (otherwise no cdylib).
- macOS arm64 prebuilts must be signed (ad-hoc is enough; the linker does it):
  macOS refuses an unsigned arm64 library in every host ("Trying to load an
  unsigned library"). x86_64 needs no signature. Tested on macOS 26.5 (Apple
  Silicon + Rosetta): unsigned x86_64 loads in plain hosts and in hardened ones
  with `disable-library-validation` (notarized Python, JDKs), exactly like
  ad-hoc signed; hardened hosts without it refuse every outside library, signed
  or not. No Developer ID or notarization is needed. `tool/check_macho.py`
  verifies the arm64 signature's page hashes, so nothing may modify a dylib
  after linking.
- 32-bit Linux x86 is built for **i586**, not i686: i686 code uses SSE
  (`movaps`) and faults when a caller aligns the stack to 4 bytes, as purego's
  386 trampoline does.
- Code that must run when the library is loaded goes in `native/src/load.rs`
  (`INITIALIZERS`): `.init_array` (ELF), `__mod_init_func` (Mach-O) or
  `.CRT$XCU` (Windows), else lazily from `st_abi_version`. They run under the
  OS loader lock: never panic (release aborts), no threads, no `dlopen`, no
  calls into the host. `st_load_state()` must be `ST_LOAD_AT_LOAD` (1) on every
  shipped target; `tool/check_load.py`, the Python and Go tests check it.
- The startup report (`native/src/report.rs`) is the only thing the verbose
  flag controls, and it is off by default: the bridge never prints unless asked.
  Callers turn it on with `SUGGESTEDTESTS_VERBOSE=1` (read by the load hook) or
  `st_set_verbose(1)`, exposed as `setVerbose`/`set_verbose`/`SetNativeBridgeVerbose`
  in every package. Go and Java forward their own setting (`os.Getenv`,
  `-Dsuggestedtests.verbose`) after loading, because neither can change the C
  environment. It prints once, to stderr, in one write. On Windows the
  load-time report waits for `st_abi_version` (registry reads under the loader
  lock are forbidden). Tests check the output in a child process.
- Every package **loads the bridge by default**, as early as its language
  allows, so the load-time report prints in every verbose run, even one that
  never calls a native helper. The print stays in the load hook; never move it
  into a package. Python: on import (the pytest plugin imports the package);
  JS: on import (the Vitest/Jest setup files import it); PHP: Composer's
  `autoload.files` (`src/load_bridge.php`, CLI only); Java: a JUnit Platform
  `LauncherSessionListener` and a TestNG `IExecutionListener` (both
  `META-INF/services`), and the JUnit 4 rule's and the extension's constructors; Go: `init()`; Dart and Swift, which run nothing
  on import: the first call of any public API (`preloadNativeBridge()`,
  `NativeBridge.preload()`). Loading never throws; a missing bridge is reported
  when a native helper is used. Each package tests this in a child process
  (Dart: `tool/release_build.sh` runs `test/load_report_test.dart` verbosely).
- Struct layouts are pinned by tests (`size_of` / `offset_of!` vs the C header)
  and by `tool/check_load.py`; they must also hold on 32-bit targets. Strings in
  structs are fixed, NUL-terminated `char[N]` (see `platform::copy_str`), so
  bindings never allocate.
- `st_platform` / `st_environment` (`platform.rs`, `environment.rs`): the
  classification logic is pure functions over gathered inputs; add a fixture
  test for every new case (container runtime, hypervisor vendor, DMI string).
- Thread CPU time is only meaningful between two samples on the same OS
  thread. In Dart and JS async benchmarks, use process CPU time; in Go, lock
  the goroutine with `runtime.LockOSThread` (the CPU clock does).

## Releasing

There is no CI: releases are built, checked and published from this machine.
The one exception is the macOS check (`.github/workflows/macos.yml`), which
runs only when `tool/macos_check.sh` starts it and never compiles Rust.
**Only the maintainer compiles the native bridge** (`tool/release_build.sh`);
nothing else may run `cargo` for a release. Recompiling package code (tsc,
javac, wheels) while publishing is fine. **Never publish or push on your
own**: only when the maintainer asks for that release.

Packages are versioned independently. Tag `<lang>-v<version>` (e.g.
`python-v0.1.0`; the PHP split repo gets plain `v<version>`, the Swift split
repo a plain `<version>` as SwiftPM expects). The Go module's
tags must be `packages/go/v<version>`: Go requires the subdirectory prefix.
PHP, Go and Swift have no version field: their newest `CHANGELOG.md` entry is the
version. Publishing is permanent: pub.dev, PyPI, npm and Maven Central don't
allow re-uploading a version.

1. Bump the version (`pubspec.yaml`, `pyproject.toml`, `package.json`,
   `pom.xml` and `android/pom.xml`) and add a `CHANGELOG.md` entry
   (`## <version>`) for each package being released.
2. The maintainer runs `tool/release_build.sh` (resume with `--from <step>`).
   It builds the 19 prebuilts, runs every package's checks with Rust hidden,
   and writes `release/prebuilt.sha256`. It can't run anything on macOS or
   Windows, or on other Linux distributions: those prebuilts only get
   `tests/prebuilt.rs` here (macOS: step 4's check; Windows: untested).
3. Commit everything, including `native/prebuilt/` and the Go copy, and tag
   each released package on that commit.
4. When asked: `tool/release_publish.sh --dry-run <packages|all>`; then
   `--push-only` (the same checks, then pushes `main` without tags, since the Go
   tag would publish Go) and `tool/macos_check.sh`, which runs every package
   on GitHub's arm64 and Intel macOS runners and waits for them; then, if that
   passed, without a flag. It checks the tree is clean and tagged, the
   prebuilts and every artifact match the checksums, and the logins; pushes
   `main` + tags to GitHub and checks GitHub serves the same prebuilts; then
   uploads to pub.dev, PyPI, npm, Maven Central (jar via `-P release deploy`;
   the AAR as a signed bundle to the Central Portal API; logins: Toolchains)
   and the split repos `lesterkaufungen/suggestedtests-php` and
   `lesterkaufungen/suggestedtests-swift`; then `tool/release_registries.py`
   creates (first release) or re-crawls the Packagist package and waits for
   the version, and, while the Swift package isn't in the Swift Package Index,
   opens the pull request that adds it to `SwiftPackageIndex/PackageList`
   (the index polls tags itself afterwards). Both run on every publish of
   php/swift, so a rerun finishes a failed registration. Versions
   already published are skipped, so a failed run can be repeated.

The whole pipeline, from the repo root (steps 3-5 only when the maintainer asks):

```sh
tool/release_build.sh                       # 1. the maintainer: prebuilts, every check, release/prebuilt.sha256
git add -A && git commit -m "Release <version>: ..."   # 2. commit and tag
for t in dart-v<v> python-v<v> js-v<v> java-v<v> php-v<v> packages/go/v<v> swift-v<v>; do git tag "$t"; done
tool/release_publish.sh --dry-run all       # 3. every check, logins included; nothing leaves the machine
tool/release_publish.sh --push-only all     # 4. optional: main only (no tags), then
tool/macos_check.sh                         #    every package on GitHub's arm64 + Intel macOS runners
tool/release_publish.sh all                 # 5. permanent: tags, registries, split repos, Packagist, SPI PR
```

`all` means every package with a release tag on `HEAD`. The macOS check was
done by hand for 0.1.0 instead (macOS 26.5, Apple Silicon with Rosetta:
native load hook, signatures, Python, Node, Java), so step 4 is optional.
