#!/usr/bin/env bash
# Runs the packages on a connected Android device or emulator (adb):
#  1. the Java library, dexed with D8 and started with app_process (ART,
#     System.loadLibrary of the AAR's native library). Needs API 26+: below
#     that, apps need core library desugaring for java.time / java.util.function.
#  2. the Go module's tests, cross-compiled with cgo and the NDK.
#
#   tool/android_smoke.sh            # needs ANDROID_HOME (or ~/.local/share/android-sdk),
#                                    # ANDROID_NDK_HOME, JAVA_HOME, go, and ./mvnw package done
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/.local/share/android-sdk}}"
ndk="${ANDROID_NDK_HOME:-$(ls -d "$sdk"/ndk/* "$HOME"/.local/share/android-ndk/android-ndk-* 2>/dev/null | sort -V | tail -1)}"
adb="$sdk/platform-tools/adb"
d8="$(ls "$sdk"/build-tools/*/d8 | sort -V | tail -1)"
bin="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
dev=/data/local/tmp/suggestedtests
jdk_bin="${JAVA_HOME:+$JAVA_HOME/bin/}" # javac and jar: a JRE on PATH has neither
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

api="$("$adb" shell getprop ro.build.version.sdk | tr -d '\r')"
abi="$("$adb" shell getprop ro.product.cpu.abi | tr -d '\r')"
echo "device: API $api, $abi"
"$adb" shell "rm -rf $dev && mkdir -p $dev/lib"
"$adb" push -q "$root/native/prebuilt/android-$abi/libsuggestedtests_native.so" "$dev/lib/"
status=0

# ---- Java on ART
classes="$root/packages/java/target/classes"
[[ -d "$classes" ]] || { echo "run ./mvnw package in packages/java first" >&2; exit 1; }
mkdir -p "$work/smoke" "$work/lib"
"${jdk_bin}javac" --release 8 -Xlint:-options -cp "$classes" -d "$work/smoke" "$root/packages/java/compat/android/AndroidSmoke.java"
(cd "$classes" && "${jdk_bin}jar" cf "$work/lib.jar" io/github/lesterkaufungen/suggestedtests/*.class \
  io/github/lesterkaufungen/suggestedtests/internal io/github/lesterkaufungen/suggestedtests/junit \
  io/github/lesterkaufungen/suggestedtests/junit4)
(cd "$work/smoke" && "${jdk_bin}jar" cf "$work/smoke.jar" .)
"$d8" --min-api 21 --release --output "$work/dex.jar" "$work/smoke.jar" "$work/lib.jar" 2>/dev/null
if (( api >= 26 )); then
  "$adb" push -q "$work/dex.jar" "$dev/"
  "$adb" shell "CLASSPATH=$dev/dex.jar app_process -Djava.library.path=$dev/lib $dev AndroidSmoke" | tr -d '\r' | tee "$work/java.log"
  grep -q "ALL PASSED" "$work/java.log" || status=1
else
  echo "SKIP Java on API $api: java.time / java.util.function need API 26 or core library desugaring"
fi

# ---- Go on Android (cgo, as Go requires there)
declare -A goarch=([arm64-v8a]=arm64 [armeabi-v7a]=arm [x86_64]=amd64 [x86]=386)
declare -A clang=([arm64-v8a]=aarch64-linux-android21-clang [armeabi-v7a]=armv7a-linux-androideabi21-clang [x86_64]=x86_64-linux-android21-clang [x86]=i686-linux-android21-clang)
for pkg in . ./internal/native; do
  name="$(basename "$(cd "$root/packages/go/$pkg" && pwd)")"
  (cd "$root/packages/go" && GOOS=android GOARCH="${goarch[$abi]}" CGO_ENABLED=1 CC="$bin/${clang[$abi]}" \
    go test -c -o "$work/$name.test" "$pkg")
  "$adb" push -q "$work/$name.test" "$dev/"
  result="$("$adb" shell "cd $dev && TMPDIR=$dev ./$name.test -test.count=1 2>&1; echo exit=\$?" | tr -d '\r')"
  echo "$result" | grep -E "^(--- FAIL|PASS|FAIL|exit=)" | sed "s|^|go $name: |"
  echo "$result" | grep -q "^exit=0" || status=1
done
exit $status
