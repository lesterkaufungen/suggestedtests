#!/usr/bin/env bash
# Builds the Rust bridge for every target of one OS family and copies the
# results into native/prebuilt/<os>-<arch>[-musl]/, the layout every package
# looks up:
#   <lib>                       C ABI + JNI (Dart, Python, PHP, Java)
#   suggestedtests_native.node  Node-API addon (JavaScript)
#
#   tool/build_prebuilt.sh linux    # needs: zig + cargo-zigbuild
#   tool/build_prebuilt.sh macos    # on macOS, or elsewhere with zig (for its libSystem stubs)
#   tool/build_prebuilt.sh windows  # on Windows (Git Bash), or elsewhere with cargo-xwin
#   tool/build_prebuilt.sh android  # needs the Android NDK ($ANDROID_NDK_HOME); C/JNI library only
#
# All targets can be built on one Linux machine (zig 0.14+ for linux: older
# zig can't target armv7; the macOS stubs below are taken from /opt/zig 0.10):
#   PATH=~/.local/share/zig-0.14.1:$PATH tool/build_prebuilt.sh linux
#   for os in macos windows android; do PATH=/opt/zig:$PATH tool/build_prebuilt.sh $os; done
#
# CARGO_FEATURES enables extra cargo features in every prebuilt built this
# run; normal runs leave it unset. The `download` feature this used to
# enable (ureq/rustls, never shipped in a prebuilt) now lives only on the
# `local-only` branch (never pushed), not on main -- build from there to
# use CARGO_FEATURES=download again.
#
# Linux builds target glibc 2.17 (loads on practically every glibc distro;
# 2.27 on riscv64, the first glibc with RISC-V) and musl (Alpine & co.), on
# x64, arm64, x86, armv7 (hard float) and riscv64. Android targets API 21.
set -euo pipefail

cd "$(dirname "$0")/../native"
family="${1:?usage: $0 linux|macos|windows}"

# Copies the core library <file> and the Node addon built for <triple>.
strip_glibc() { echo "${1%.2.*}"; } # x86_64-unknown-linux-gnu.2.17 -> x86_64-unknown-linux-gnu

install() { # <rust triple> <prebuilt dir> <file name>
  local out="target/$(strip_glibc "$1")/release" dir=prebuilt/$2 file=$3
  mkdir -p "$dir"
  cp "$out/$file" "$dir/$file"
  cp "$out/${file/suggestedtests_native/suggestedtests_node}" "$dir/suggestedtests_native.node"
}

build() { # <cargo subcommand> <rust triple> <prebuilt dir> <file name> [rustflags]
  local cmd=$1 triple=$2 dir=$3 file=$4 flags=${5:-}
  rustup target add "$(strip_glibc "$triple")" >/dev/null
  echo "==> $triple -> prebuilt/$dir/{$file,suggestedtests_native.node}"
  RUSTFLAGS="$flags" cargo $cmd --release --locked --workspace --target "$triple" \
    ${CARGO_FEATURES:+--features "$CARGO_FEATURES"}
  install "$triple" "$dir" "$file"
}

case "$family" in
  linux)
    so=libsuggestedtests_native.so
    build zigbuild x86_64-unknown-linux-gnu.2.17 linux-x64 $so
    build zigbuild aarch64-unknown-linux-gnu.2.17 linux-arm64 $so
    # musl links libc statically by default, which can't make a shared library.
    build zigbuild x86_64-unknown-linux-musl linux-x64-musl $so "-C target-feature=-crt-static"
    build zigbuild aarch64-unknown-linux-musl linux-arm64-musl $so "-C target-feature=-crt-static"
    # i586, not i686: no SSE, so no 16-byte stack alignment requirement.
    # i686 code faults (movaps) when callers align the stack to 4 bytes, as
    # purego's 386 trampoline does; i586 also runs on any x86 CPU.
    #
    # CARGO_FEATURES=download doesn't apply below: ring (rustls/ureq's crypto
    # backend) hard-asserts SSE/SSE2 at compile time, which i586 doesn't
    # have; armv7 and riscv64 could in principle build it, but
    # gui_helper_url() (native/src/load.rs) only ever targets x64/arm64
    # desktops anyway, so there would be nothing to run it for.
    (
      unset CARGO_FEATURES
      build zigbuild i586-unknown-linux-gnu.2.17 linux-x86 $so
      build zigbuild i586-unknown-linux-musl linux-x86-musl $so "-C target-feature=-crt-static"
      build zigbuild armv7-unknown-linux-gnueabihf.2.17 linux-arm $so
      build zigbuild armv7-unknown-linux-musleabihf linux-arm-musl $so "-C target-feature=-crt-static"
      build zigbuild riscv64gc-unknown-linux-gnu.2.27 linux-riscv64 $so
      build zigbuild riscv64gc-unknown-linux-musl linux-riscv64-musl $so "-C target-feature=-crt-static"
    )
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
      if [[ -n "${CARGO_FEATURES:-}" ]]; then
        # ring (download feature) compiles C code, which needs an actual C
        # cross-compiler, not just the Rust linker above: zig cc, using the
        # same zig that supplies the libSystem stubs. CRATE_CC_NO_DEFAULTS=1
        # stops cc-rs adding its own --target=<rust-triple> (a format zig's
        # clang frontend doesn't understand, unlike the zig-style
        # <arch>-macos.<ver>-none zig cc itself wants); ring adds its own
        # flags regardless (e.g. -gfull, which zig's bundled clang
        # understands same as Apple's does). TargetConditionals.h is a
        # small set of standard, documented boolean macros (TARGET_OS_*),
        # not an Apple SDK framework header zig can ship, so it's stubbed in
        # since ring checks TARGET_OS_OSX.
        mkdir -p "$SDKROOT/usr/include"
        cat > "$SDKROOT/usr/include/TargetConditionals.h" <<'EOF'
#ifndef __TARGET_CONDITIONALS__
#define __TARGET_CONDITIONALS__
#define TARGET_OS_MAC 1
#define TARGET_OS_OSX 1
#define TARGET_OS_IPHONE 0
#define TARGET_OS_IOS 0
#define TARGET_OS_WATCH 0
#define TARGET_OS_TV 0
#define TARGET_OS_SIMULATOR 0
#define TARGET_OS_EMBEDDED 0
#define TARGET_OS_WIN32 0
#define TARGET_OS_UNIX 0
#define TARGET_OS_LINUX 0
#endif
EOF
        export CRATE_CC_NO_DEFAULTS=1
        export CC_x86_64_apple_darwin="zig cc -target x86_64-macos.11-none -isystem $SDKROOT/usr/include"
        export CC_aarch64_apple_darwin="zig cc -target aarch64-macos.11-none -isystem $SDKROOT/usr/include"
        export AR_x86_64_apple_darwin="zig ar"
        export AR_aarch64_apple_darwin="zig ar"
        export CFLAGS_x86_64_apple_darwin="-O3 -fPIC -fvisibility=hidden -DNDEBUG"
        export CFLAGS_aarch64_apple_darwin="-O3 -fPIC -fvisibility=hidden -DNDEBUG"
      fi
      build() { # same as above, but keeps RUSTFLAGS
        local triple=$2 dir=$3 file=$4
        rustup target add "$triple" >/dev/null
        echo "==> $triple -> prebuilt/$dir/{$file,suggestedtests_native.node} (cross)"
        cargo build --release --locked --workspace --target "$triple" \
          ${CARGO_FEATURES:+--features "$CARGO_FEATURES"}
        install "$triple" "$dir" "$file"
      }
    fi
    export MACOSX_DEPLOYMENT_TARGET=10.13
    build build x86_64-apple-darwin macos-x64 $dylib
    export MACOSX_DEPLOYMENT_TARGET=11.0
    build build aarch64-apple-darwin macos-arm64 $dylib
    ;;
  windows)
    dll=suggestedtests_native.dll
    # Cross build: cargo-xwin supplies the MSVC CRT and Windows SDK, for
    # every architecture built below.
    export XWIN_ARCH="${XWIN_ARCH:-x86,x86_64,aarch64}"
    cmd=build
    case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) ;; *) cmd="xwin build" ;; esac
    if [[ -n "${CARGO_FEATURES:-}" ]] && ! command -v llvm-lib >/dev/null 2>&1; then
      # ring (download feature) needs the unversioned "llvm-lib" name;
      # Ubuntu's clang package only installs "llvm-lib-<version>".
      llvm_lib=$(command -v llvm-lib-18 2>/dev/null || ls /usr/lib/llvm-*/bin/llvm-lib 2>/dev/null | sort -V | tail -1)
      [[ -n "$llvm_lib" ]] && PATH="$(dirname "$llvm_lib"):$PATH"
    fi
    # Static CRT: no dependency on the Visual C++ redistributable.
    build "$cmd" x86_64-pc-windows-msvc windows-x64 $dll "-C target-feature=+crt-static"
    # ring (download feature) forces plain `clang` (GNU-style flags) for
    # Windows AArch64 whenever the detected compiler doesn't itself report
    # as "clang" (ring's build.rs, configure_cc) -- but clang-cl, which
    # cargo-xwin configures here (and whose MSVC-style /imsvc flags this
    # needs), reports as MSVC-like instead. ring swaps the compiler out from
    # under cargo-xwin's flags and the mismatch fails to compile: an upstream
    # ring/cargo-xwin incompatibility, not fixable from here. Skip the
    # feature until that's resolved.
    (
      unset CARGO_FEATURES
      build "$cmd" aarch64-pc-windows-msvc windows-arm64 $dll "-C target-feature=+crt-static"
    )
    # gui_helper_url() (native/src/load.rs) never targets 32-bit Windows, so
    # there's nothing for CARGO_FEATURES=download to do here.
    (
      unset CARGO_FEATURES
      build "$cmd" i686-pc-windows-msvc windows-x86 $dll "-C target-feature=+crt-static"
    )
    ;;
  android)
    # The core library only: on Android the Java package loads it through JNI
    # from the AAR (tool/build_aar.sh); there is no Node.js addon.
    # gui_helper_url() (native/src/load.rs) never targets Android, so
    # CARGO_FEATURES=download is dropped for every target below.
    unset CARGO_FEATURES
    ndk="${ANDROID_NDK_HOME:-$(ls -d "$HOME"/.local/share/android-ndk/android-ndk-* 2>/dev/null | sort -V | tail -1)}"
    host="$(uname -s | tr '[:upper:]' '[:lower:]')-x86_64"
    bin="$ndk/toolchains/llvm/prebuilt/$host/bin"
    [[ -x "$bin/clang" ]] || { echo "Android NDK not found; set ANDROID_NDK_HOME" >&2; exit 1; }
    api=21
    for spec in aarch64-linux-android:arm64-v8a:aarch64-linux-android \
                armv7-linux-androideabi:armeabi-v7a:armv7a-linux-androideabi \
                x86_64-linux-android:x86_64:x86_64-linux-android \
                i686-linux-android:x86:i686-linux-android; do
      IFS=: read -r triple abi clang <<<"$spec"
      rustup target add "$triple" >/dev/null
      echo "==> $triple -> prebuilt/android-$abi/libsuggestedtests_native.so (API $api)"
      var="CARGO_TARGET_$(echo "$triple" | tr '[:lower:]-' '[:upper:]_')_LINKER"
      # 16 KB pages: required by Android 15+ devices and Google Play.
      env "$var=$bin/$clang$api-clang" RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384" \
        cargo build --release --locked -p suggestedtests_native --target "$triple" \
        ${CARGO_FEATURES:+--features "$CARGO_FEATURES"}
      mkdir -p "prebuilt/android-$abi"
      cp "target/$triple/release/libsuggestedtests_native.so" "prebuilt/android-$abi/"
    done
    ;;
  *)
    echo "unknown OS family: $family" >&2
    exit 64
    ;;
esac
