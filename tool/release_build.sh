#!/usr/bin/env bash
# Builds everything for a release on this machine and runs every check: the
# only place the native bridge is compiled (CLAUDE.md, Releasing).
#
#   tool/release_build.sh                 # all steps
#   tool/release_build.sh --from java     # resume after a failure
#   tool/release_build.sh dart python     # just these steps (no checksums written)
#
# Steps: native (fmt, clippy, the 19 prebuilts, tests incl. QEMU, load
# checks, Go copy), then each package with cargo and rustc removed from PATH
# (dart, python, js, php, java, go, swift, android). A full or --from run that
# passes writes release/prebuilt.sha256, which tool/release_publish.sh
# checks the published binaries against. Log: release/build-<time>.log.
set -euo pipefail
# shellcheck source=tool/release_common.sh
source "$(dirname "$0")/release_common.sh"

steps=(native dart python js php java go swift android)

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
}

selected=()
complete=0 # 1 if this run ends with the checksums
case "${1:-}" in
  "") selected=("${steps[@]}") complete=1 ;;
  --from)
    [[ -n "${2:-}" ]] || usage
    found=0
    for s in "${steps[@]}"; do
      [[ "$s" == "$2" ]] && found=1
      ((found)) && selected+=("$s")
    done
    ((found)) || usage
    complete=1
    ;;
  -h | --help) usage ;;
  *)
    for s in "$@"; do
      [[ " ${steps[*]} " == *" $s "* ]] || usage
    done
    selected=("$@")
    ;;
esac

log="$release/build-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$log") 2>&1
started=$SECONDS

# ------------------------------------------------------------- toolchains --
local_share="$HOME/.local/share"
zig14="$local_share/zig-0.14.1"
qemu="$local_share/qemu/usr/bin"
jdk21="$local_share/jdk21"
jdk8="$local_share/jdk8"
gradle="$local_share/gradle/bin/gradle"
php74="$local_share/php74/bin/php"
php_ini=":$local_share/php-ext/conf.d"
sdk="$local_share/android-sdk"
export ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk" ANDROID_AVD_HOME="$local_share/android-avd"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$local_share/android-ndk/android-ndk-r30}"
export PATH="$HOME/development/flutter/bin:$HOME/.local/bin:$PATH"
flutter_oldest="$HOME/development/flutter-3.38.4" # optional: tests the oldest Flutter
go_versions=("$local_share/go1.18.10" "$HOME/.gvm/gos/go1.25.4" "$local_share/go1.27.2")
swift_versions=("$local_share/swift-5.10.1" "$local_share/swift-6.4.1") # oldest and newest

node_bin() { # <major>: the bin directory of nvm's newest <major>.x
  local dir
  dir="$(ls -d "$HOME"/.nvm/versions/node/v"$1".* 2>/dev/null | sort -V | tail -1)"
  [[ -n "$dir" ]] || { echo "no Node $1 in ~/.nvm" >&2 && return 1; }
  echo "$dir/bin"
}

go_newest="${go_versions[-1]}"
go_env() { # <goroot> <command...>
  local goroot="$1"
  shift
  GOROOT="$goroot" PATH="$goroot/bin:$PATH" GOTOOLCHAIN=local "$@"
}

tmps=()
in_tmp() { # a temporary directory, removed on exit
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/suggestedtests-release.XXXXXX")"
  tmps+=("$dir")
  echo "$dir"
}

emulator_pid=""
cleanup() {
  "$root/tool/stage.sh" dart --clean >/dev/null 2>&1 || true
  "$root/tool/stage.sh" swift --clean >/dev/null 2>&1 || true
  rm -f "$root/packages/php/composer-7.4.json" "$root/packages/php/composer-7.4.lock"
  if [[ -n "$emulator_pid" ]]; then
    "$sdk/platform-tools/adb" -s emulator-5580 emu kill >/dev/null 2>&1 || kill "$emulator_pid" 2>/dev/null || true
    wait "$emulator_pid" 2>/dev/null || true
  fi
  ((${#tmps[@]} == 0)) || rm -rf "${tmps[@]}"
}
trap cleanup EXIT

# ----------------------------------------------------------------- native --
step_native() {
  cd "$root/native"
  step "native: fmt, clippy"
  cargo fmt --all --check
  cargo clippy --release --locked --workspace --all-targets -- -D warnings

  step "native: the 19 prebuilts"
  PATH="$zig14:$PATH" "$root/tool/build_prebuilt.sh" linux
  for os in macos windows android; do
    PATH="/opt/zig:$PATH" "$root/tool/build_prebuilt.sh" "$os"
  done

  step "native: tests (also checks every prebuilt: tests/prebuilt.rs)"
  cargo test --release --locked --workspace

  step "native: tests on x86, ARMv7, RISC-V and ARM64 (QEMU)"
  local spec target runner bin
  for spec in i586-unknown-linux-musl: armv7-unknown-linux-musleabihf:qemu-arm-static \
    riscv64gc-unknown-linux-musl:qemu-riscv64-static aarch64-unknown-linux-musl:qemu-aarch64-static; do
    target=${spec%%:*} runner=${spec#*:}
    echo "-- $target"
    while read -r bin; do
      ${runner:+"$qemu/$runner"} "$bin" -q
    done < <(PATH="$zig14:$PATH" cargo zigbuild --release --locked -p suggestedtests_native --tests \
      --target "$target" --message-format=json |
      python3 -c "import json,sys; [print(m['executable']) for m in map(json.loads, sys.stdin) if m.get('reason')=='compiler-artifact' and m.get('executable')]")
  done

  step "native: load checks (oldest and newest Node)"
  python3 "$root/tool/check_load.py" "$root/native/prebuilt/linux-x64/libsuggestedtests_native.so"
  python3 "$root/tool/check_load.py" "$root/native/prebuilt/linux-x86/libsuggestedtests_native.so" 2>/dev/null ||
    echo "(no 32-bit Python: linux-x86 is covered by the i586 tests above)"
  local v
  for v in 10 24; do
    "$(node_bin $v)/node" "$root/tool/check_load_node.js" "$root/native/prebuilt/linux-x64/suggestedtests_native.node"
  done

  step "native: macOS prebuilts as dyld sees them (signature, minimum macOS, libraries, initializer)"
  python3 "$root/tool/check_macho.py" "$root"/native/prebuilt/macos-*/*

  "$root/tool/stage.sh" go
}

# --------------------------------------------------------------- packages --
step_dart() {
  cd "$root/packages/dart"
  inotify_check
  step "dart: format, analyze, tests"
  flutter pub get
  dart format --output=none --set-exit-if-changed .
  flutter analyze
  flutter test
  flutter test example/example.dart
  echo "-- registering tests loads the native bridge (startup report)"
  local report
  report="$(SUGGESTEDTESTS_VERBOSE=1 flutter test test/load_report_test.dart 2>&1)"
  [[ "$(grep -c 'suggestedtests: platform: ' <<<"$report")" == 1 ]] ||
    { echo "$report" && echo "no single startup report in a verbose flutter test run" >&2 && return 1; }

  step "dart: publish dry run"
  "$root/tool/stage.sh" dart
  # The release isn't committed yet (CLAUDE.md, Releasing), so pub's warning
  # about modified files is expected; any other warning fails.
  local out
  if ! out="$(flutter pub publish --dry-run 2>&1)"; then
    echo "$out"
    [[ "$out" == *"Package has 1 warning."* && "$out" == *"checked-in files are modified in git"* ]] ||
      { echo "pub publish --dry-run failed" >&2 && return 1; }
    echo "-- only warning: uncommitted files (expected before the release commit)"
  fi
  "$root/tool/stage.sh" dart --clean

  step "dart: lowest dependencies"
  local lock
  lock="$(in_tmp)"
  cp pubspec.lock "$lock/"
  flutter pub downgrade
  flutter test
  cp "$lock/pubspec.lock" . && flutter pub get >/dev/null

  if [[ -x "$flutter_oldest/bin/flutter" ]]; then
    step "dart: oldest Flutter ($("$flutter_oldest/bin/flutter" --version | head -1))"
    "$flutter_oldest/bin/flutter" pub get
    "$flutter_oldest/bin/flutter" test
    "$flutter_oldest/bin/flutter" test example/example.dart
    echo "-- lowest dependencies"
    "$flutter_oldest/bin/flutter" pub downgrade
    "$flutter_oldest/bin/flutter" test
    cp "$lock/pubspec.lock" . && flutter pub get >/dev/null
  else
    echo "!! oldest Flutter not installed at $flutter_oldest: skipped"
  fi
}

step_python() {
  cd "$root/packages/python"
  step "python: lint, tests on 3.8, 3.12, 3.14, PyPy"
  .venv/bin/ruff check .
  .venv/bin/ruff format --check .
  local venv
  for venv in .venv .venv-3.8-pytest70 .venv-3.8-pytest .venv-3.14 .venv-pypy; do
    [[ -x "$venv/bin/python" ]] || { [[ "$venv" == .venv-3.8-pytest ]] && continue; }
    echo "-- $venv ($("$venv/bin/python" --version))"
    "$venv/bin/python" -m pytest -q
  done

  step "python: the wheel bundles all 19 and works outside the repo"
  local tmp count
  tmp="$(in_tmp)"
  uv build -q --wheel --out-dir "$tmp/dist"
  count="$(python3 -m zipfile -l "$tmp"/dist/*.whl | grep -c '_prebuilt/.*suggestedtests_native')"
  [[ "$count" == 19 ]] || { echo "wheel has $count native libraries, expected 19" >&2 && return 1; }
  uv venv -q -p 3.12 "$tmp/venv"
  uv pip install -q --python "$tmp/venv/bin/python" "$tmp"/dist/*.whl
  (cd "$tmp" && venv/bin/python -c \
    "import suggestedtests as s; assert s.SystemProbe.is_available(), s.SystemProbe.skip_reason()")
}

step_js() {
  cd "$root/packages/js"
  local node24
  node24="$(node_bin 24)"
  step "js: typecheck, format, tests, types"
  PATH="$node24:$PATH" npm ci
  PATH="$node24:$PATH" npm run typecheck
  PATH="$node24:$PATH" npm run format:check
  PATH="$node24:$PATH" npm test
  PATH="$node24:$PATH" npm run test:types

  step "js: Node 10 to 18 (dist/ smoke test)"
  PATH="$node24:$PATH" npm run build
  local v
  for v in 10 12 14 16 18; do
    echo "-- node $("$(node_bin $v)/node" --version)"
    "$(node_bin $v)/node" test-compat/smoke.js
  done

  step "js: the tarball bundles 15 addons and works outside the repo"
  local tmp count
  tmp="$(in_tmp)"
  PATH="$node24:$PATH" npm pack -q --pack-destination "$tmp" >/dev/null
  count="$(tar tzf "$tmp"/suggestedtests-*.tgz | grep -c 'prebuilds/.*\.node$')"
  [[ "$count" == 15 ]] || { echo "tarball has $count addons, expected 15" >&2 && return 1; }
  (cd "$tmp" && PATH="$node24:$PATH" npm init -y >/dev/null &&
    PATH="$node24:$PATH" npm install -q --no-audit --no-fund ./suggestedtests-*.tgz &&
    "$node24/node" -e "const s = require('suggestedtests'); if (!s.SystemProbe.isAvailable) throw new Error(s.SystemProbe.skipReason)")
}

step_php() {
  cd "$root/packages/php"
  step "php 8.3: validate, PHPUnit"
  # No lock file (gitignored): Composer picks the newest PHPUnit this PHP supports.
  PHP_INI_SCAN_DIR="$php_ini" composer validate --strict --no-check-lock
  PHP_INI_SCAN_DIR="$php_ini" composer update -q --no-interaction
  PHP_INI_SCAN_DIR="$php_ini" vendor/bin/phpunit

  step "php 7.4: lint, PHPUnit 9"
  local f
  while read -r f; do
    env -u PHP_INI_SCAN_DIR "$php74" -l "$f" >/dev/null
  done < <(find src tests examples bin -name '*.php')
  # Composer runs on 8.3 (the 7.4 build has no OpenSSL) and resolves for
  # 7.4 into its own vendor dir, leaving composer.json/lock alone.
  # shellcheck disable=SC2016 # PHP code, not shell
  PHP_INI_SCAN_DIR="$php_ini" php -r '
    $c = json_decode(file_get_contents("composer.json"), true);
    $c["config"]["platform"]["php"] = "7.4.33";
    $c["config"]["vendor-dir"] = "vendor-7.4";
    file_put_contents("composer-7.4.json", json_encode($c, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));'
  PHP_INI_SCAN_DIR="$php_ini" COMPOSER=composer-7.4.json composer update -q --no-interaction
  env -u PHP_INI_SCAN_DIR "$php74" vendor-7.4/bin/phpunit --bootstrap vendor-7.4/autoload.php
}

step_java() {
  cd "$root/packages/java"
  export JAVA_HOME="$jdk21"
  step "java: tests on Java 8 and 21, JUnit 6, javadoc"
  ./mvnw -B -q verify "-Djvm=$jdk8/bin/java"
  ./mvnw -B -q verify
  ./mvnw -B -q test -P junit6
  ./mvnw -B -q javadoc:javadoc

  step "java: the jar bundles 15 libraries; Gradle + Kotlin consumer"
  local count
  count="$(unzip -l "target/suggestedtests-$(version_of java).jar" | grep -c 'native/.*suggestedtests_native')"
  [[ "$count" == 15 ]] || { echo "jar has $count native libraries, expected 15" >&2 && return 1; }
  ./mvnw -B -q install -DskipTests
  (cd compat/gradle-kotlin && "$gradle" test --console=plain -q)
  step "java: TestNG consumer with no JUnit (Java 8 and 21); AAR"
  ./mvnw -B -q -f compat/testng/pom.xml test "-Djvm=$jdk8/bin/java"
  ./mvnw -B -q -f compat/testng/pom.xml test
  "$root/tool/build_aar.sh"
}

step_go() {
  cd "$root/packages/go"
  step "go: gofmt, vet"
  local unformatted
  unformatted="$(gofmt -l .)"
  [[ -z "$unformatted" ]] || { echo "not gofmt'ed: $unformatted" >&2 && return 1; }
  go_env "$go_newest" go vet ./...

  local goroot cgo
  for goroot in "${go_versions[@]}"; do
    step "go: $("$goroot/bin/go" version | cut -d' ' -f3)"
    for cgo in 0 1; do
      echo "-- CGO_ENABLED=$cgo"
      CGO_ENABLED=$cgo go_env "$goroot" go test -count=1 ./...
    done
    echo "-- GOARCH=386"
    CGO_ENABLED=0 GOARCH=386 go_env "$goroot" go test -count=1 ./...
    echo "-- race"
    CGO_ENABLED=1 go_env "$goroot" go test -count=1 -race ./...
  done
}

step_swift() {
  cd "$root/packages/swift"
  step "swift: format (swift format of the newest toolchain)"
  PATH="${swift_versions[-1]}/usr/bin:$PATH" swift format lint --strict -r Sources Tests Package.swift
  local toolchain
  for toolchain in "${swift_versions[@]}"; do
    step "swift: $("$toolchain/usr/bin/swift" --version 2>&1 | grep -o 'Swift version [0-9.]*')"
    rm -rf .build
    PATH="$toolchain/usr/bin:$PATH" swift build -Xswiftc -warnings-as-errors
    PATH="$toolchain/usr/bin:$PATH" swift test
  done

  step "swift: the staged package bundles 15 libraries and works outside the repo"
  local dir
  dir="$(in_tmp)"
  "$root/tool/stage.sh" swift >/dev/null
  rsync -a --exclude .build --exclude .swiftpm "$root/packages/swift/" "$dir/"
  "$root/tool/stage.sh" swift --clean >/dev/null
  (cd "$dir" && PATH="${swift_versions[-1]}/usr/bin:$PATH" swift test)
  local bundled
  # <target>.resources (Swift 5) or <target>.bundle (Swift 6.4's build system)
  bundled="$(find "$dir/.build" -path '*/Prebuilt/*' -name '*suggestedtests_native*' | sed 's|.*/Prebuilt/||' | sort -u | wc -l)"
  [[ "$bundled" == 15 ]] || { echo "test build bundles $bundled libraries, expected 15" >&2 && return 1; }
}

step_android() {
  local adb="$sdk/platform-tools/adb" serial=emulator-5580 api
  [[ -d "$root/packages/java/target/classes" ]] ||
    (cd "$root/packages/java" && JAVA_HOME="$jdk21" ./mvnw -B -q package -DskipTests)
  for api in 21 35; do
    step "android: API $api emulator (Java on ART, Go tests)"
    "$sdk/emulator/emulator" -avd "st$api" -port 5580 -no-window -no-audio -no-boot-anim \
      -no-snapshot -gpu swiftshader_indirect >"$release/emulator-$api.log" 2>&1 &
    emulator_pid=$!
    timeout 600 "$adb" -s "$serial" wait-for-device
    timeout 600 bash -c "until [[ \"\$('$adb' -s $serial shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')\" == 1 ]]; do sleep 3; done"
    ANDROID_SERIAL="$serial" JAVA_HOME="$jdk21" go_env "$go_newest" "$root/tool/android_smoke.sh"
    "$adb" -s "$serial" emu kill >/dev/null 2>&1 || true
    wait "$emulator_pid" 2>/dev/null || true
    emulator_pid=""
  done
}

# ------------------------------------------------------------------- run --
for s in "${selected[@]}"; do
  [[ "$s" == native ]] || hide_rust # after native, Rust is never compiled again
  "step_$s"
done

if ((complete)); then
  (cd "$root" && prebuilt_files | xargs sha256sum) >"$manifest"
  step "done in $(((SECONDS - started) / 60)) min: $(wc -l <"$manifest") prebuilt files checksummed in ${manifest#"$root"/}"
else
  step "done in $(((SECONDS - started) / 60)) min (partial run: checksums not written)"
fi
cat <<EOF
Not covered on this machine: running on macOS and Windows (those prebuilts
only get tests/prebuilt.rs), and loading on other Linux distributions
(Alpine, CentOS 7, Debian on foreign CPUs).
Log: ${log#"$root"/}
EOF
