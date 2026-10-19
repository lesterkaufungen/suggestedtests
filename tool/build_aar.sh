#!/usr/bin/env bash
# Builds packages/java/target/suggestedtests-android-<version>.aar: the Java
# library's classes plus the Android native libraries from
# native/prebuilt/android-<abi>/ (tool/build_prebuilt.sh android).
#
#   (cd packages/java && ./mvnw -B package -DskipTests) && tool/build_aar.sh
#
# Android loads the library with System.loadLibrary from the APK, so the
# desktop libraries bundled in the jar are left out.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
java="$root/packages/java"
version="$(sed -n 's|^  <version>\(.*\)</version>|\1|p' "$java/pom.xml" | head -1)"
jar="$java/target/suggestedtests-$version.jar"
[[ -f "$jar" ]] || { echo "missing $jar: run ./mvnw package first" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/classes" "$work/aar"
(cd "$work/classes" && unzip -q "$jar" -x 'io/github/lesterkaufungen/suggestedtests/native/*' 'META-INF/maven/*')
(cd "$work/classes" && zip -q -r -X "$work/aar/classes.jar" .)

count=0
for abi in arm64-v8a armeabi-v7a x86_64 x86; do
  lib="$root/native/prebuilt/android-$abi/libsuggestedtests_native.so"
  [[ -f "$lib" ]] || { echo "missing $lib: run tool/build_prebuilt.sh android" >&2; exit 1; }
  mkdir -p "$work/aar/jni/$abi"
  cp "$lib" "$work/aar/jni/$abi/"
  count=$((count + 1))
done
cp "$java/android/AndroidManifest.xml" "$java/android/proguard.txt" "$work/aar/"
: > "$work/aar/R.txt"

out="$java/target/suggestedtests-android-$version.aar"
rm -f "$out"
(cd "$work/aar" && zip -q -r -X "$out" AndroidManifest.xml classes.jar jni proguard.txt R.txt)
echo "built ${out#"$root"/} ($count ABIs)"
