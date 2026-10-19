#!/usr/bin/env bash
# Copies the shared native/ into a package that must ship it inside its own
# directory, before publishing:
#
#   tool/stage.sh dart          # native/ (sources + prebuilts) -> packages/dart/native/
#   tool/stage.sh php           # native/prebuilt/              -> packages/php/native/prebuilt/
#   tool/stage.sh go            # native/prebuilt/              -> packages/go/internal/native/prebuilt/
#   tool/stage.sh swift         # native/prebuilt/ (desktop)    -> packages/swift/Sources/SuggestedTests/Prebuilt/
#   tool/stage.sh dart --clean  # removes the copy again
#
# The dart, php and swift copies are gitignored. The go copy is committed: Go modules
# are fetched from git, and //go:embed can't reach outside the module.
# tool/release_publish.sh checks it matches native/prebuilt/. Python (hatch_build.py), JavaScript
# (prepack) and Java (pom.xml resources) bundle native/prebuilt/ by themselves.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
package="${1:?usage: $0 dart|php|go|swift [--clean]}"
target="$root/packages/$package/native"

case "$package" in
  dart | php) ;;
  go) target="$root/packages/go/internal/native" ;;
  swift) target="$root/packages/swift/Sources/SuggestedTests/Prebuilt" ;;
  *)
    echo "unknown package: $package (only dart, php, go and swift need staging)" >&2
    exit 64
    ;;
esac

if [[ "$package" == go ]]; then
  target="$target/prebuilt" # the rest of internal/native is Go source
fi
rm -rf "$target"
[[ "${2:-}" == --clean ]] && exit 0

if [[ "$package" == dart ]]; then
  # The hook falls back to `cargo build` of these sources (see hook/build.dart).
  mkdir -p "$target"
  (cd "$root/native" && tar cf - --exclude='./target*' --exclude='*.node' .) | (cd "$target" && tar xf -)
else
  [[ "$package" == php ]] && target="$target/prebuilt"
  for dir in "$root"/native/prebuilt/*/; do
    name="$(basename "$dir")"
    # SwiftPM resources: the desktop libraries (no Swift for Android here yet).
    [[ "$package" == swift && "$name" == android-* ]] && continue
    mkdir -p "$target/$name"
    find "$dir" -maxdepth 1 -type f ! -name '*.node' -exec cp {} "$target/$name/" \;
  done
fi
echo "staged $(find "$target" -type f | wc -l) files into ${target#"$root"/}"
