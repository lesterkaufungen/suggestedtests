#!/usr/bin/env bash
# Builds the Rust bridge for every target of one OS family and copies the
# results into native/prebuilt/<os>-<arch>[-musl]/, the layout hook/build.dart
# looks up.
#
#   tool/build_prebuilt.sh linux    # needs: zig + cargo-zigbuild
#   tool/build_prebuilt.sh macos    # run on macOS
#   tool/build_prebuilt.sh windows  # run on Windows (Git Bash)
#
# Linux builds target glibc 2.17 (loads on practically every glibc distro)
# and musl (Alpine & co.).
set -euo pipefail

cd "$(dirname "$0")/../native"
family="${1:?usage: $0 linux|macos|windows}"

build() { # <cargo subcommand> <rust triple> <prebuilt dir> <file name> [rustflags]
  local cmd=$1 triple=$2 dir=$3 file=$4 flags=${5:-}
  rustup target add "${triple%.2.17}" >/dev/null
  echo "==> $triple -> prebuilt/$dir/$file"
  RUSTFLAGS="$flags" cargo $cmd --release --locked --target "$triple"
  mkdir -p "prebuilt/$dir"
  cp "target/${triple%.2.17}/release/$file" "prebuilt/$dir/$file"
}

case "$family" in
  linux)
    so=libsuggestedtests_native.so
    build zigbuild x86_64-unknown-linux-gnu.2.17 linux-x64 $so
    build zigbuild aarch64-unknown-linux-gnu.2.17 linux-arm64 $so
    # musl links libc statically by default, which can't make a shared library.
    build zigbuild x86_64-unknown-linux-musl linux-x64-musl $so "-C target-feature=-crt-static"
    build zigbuild aarch64-unknown-linux-musl linux-arm64-musl $so "-C target-feature=-crt-static"
    ;;
  macos)
    dylib=libsuggestedtests_native.dylib
    export MACOSX_DEPLOYMENT_TARGET=10.13
    build build x86_64-apple-darwin macos-x64 $dylib
    export MACOSX_DEPLOYMENT_TARGET=11.0
    build build aarch64-apple-darwin macos-arm64 $dylib
    ;;
  windows)
    dll=suggestedtests_native.dll
    # Static CRT: no dependency on the Visual C++ redistributable.
    build build x86_64-pc-windows-msvc windows-x64 $dll "-C target-feature=+crt-static"
    build build aarch64-pc-windows-msvc windows-arm64 $dll "-C target-feature=+crt-static"
    ;;
  *)
    echo "unknown OS family: $family" >&2
    exit 64
    ;;
esac
