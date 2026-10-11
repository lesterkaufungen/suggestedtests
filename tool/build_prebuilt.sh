#!/usr/bin/env bash
# Builds the Rust bridge for every target of one OS family and copies the
# results into native/prebuilt/<os>-<arch>[-musl]/, the layout hook/build.dart
# looks up.
#
#   tool/build_prebuilt.sh linux    # needs: zig + cargo-zigbuild
#   tool/build_prebuilt.sh macos    # on macOS, or elsewhere with zig (for its libSystem stubs)
#   tool/build_prebuilt.sh windows  # on Windows (Git Bash), or elsewhere with cargo-xwin
#
# All 8 targets can be built on one Linux machine:
#   for os in linux macos windows; do PATH=/opt/zig:$PATH tool/build_prebuilt.sh $os; done
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
    if [[ "$(uname -s)" != Darwin ]]; then
      # Cross build: link with rust-lld against the libSystem stubs zig ships.
      # Unlike zig's own linker, it honours rustc's export list and ad-hoc
      # signs arm64 like Apple's ld does.
      zig_lib=$(zig env | sed -n 's/.*"lib_dir": *"\([^"]*\)".*/\1/p')
      export SDKROOT="$PWD/target/macos-stub-sdk"
      mkdir -p "$SDKROOT/usr/lib"
      cp "$zig_lib/libc/darwin/libSystem.13.tbd" "$SDKROOT/usr/lib/libSystem.tbd"
      ln -sf libSystem.tbd "$SDKROOT/usr/lib/libc.tbd"
      ln -sf libSystem.tbd "$SDKROOT/usr/lib/libm.tbd"
      # std links -liconv but uses none of its symbols.
      printf '%s\n' '--- !tapi-tbd' 'tbd-version: 4' \
        'targets: [ x86_64-macos, arm64-macos ]' \
        "install-name: '/usr/lib/libiconv.2.dylib'" \
        'current-version: 7' 'compatibility-version: 7' '...' \
        > "$SDKROOT/usr/lib/libiconv.tbd"
      lld=$(find "$(rustc --print sysroot)/lib/rustlib" -name rust-lld -path '*/bin/*' | head -1)
      export RUSTFLAGS="-C linker=$lld -C linker-flavor=ld64.lld -C link-arg=-install_name -C link-arg=@rpath/$dylib"
      build() { # same as above, but keeps RUSTFLAGS
        local triple=$2 dir=$3 file=$4
        rustup target add "$triple" >/dev/null
        echo "==> $triple -> prebuilt/$dir/$file (cross)"
        cargo build --release --locked --target "$triple"
        mkdir -p "prebuilt/$dir"
        cp "target/$triple/release/$file" "prebuilt/$dir/$file"
      }
    fi
    export MACOSX_DEPLOYMENT_TARGET=10.13
    build build x86_64-apple-darwin macos-x64 $dylib
    export MACOSX_DEPLOYMENT_TARGET=11.0
    build build aarch64-apple-darwin macos-arm64 $dylib
    ;;
  windows)
    dll=suggestedtests_native.dll
    # Cross build: cargo-xwin supplies the MSVC CRT and Windows SDK.
    cmd=build
    case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) ;; *) cmd="xwin build" ;; esac
    # Static CRT: no dependency on the Visual C++ redistributable.
    build "$cmd" x86_64-pc-windows-msvc windows-x64 $dll "-C target-feature=+crt-static"
    build "$cmd" aarch64-pc-windows-msvc windows-arm64 $dll "-C target-feature=+crt-static"
    ;;
  *)
    echo "unknown OS family: $family" >&2
    exit 64
    ;;
esac
