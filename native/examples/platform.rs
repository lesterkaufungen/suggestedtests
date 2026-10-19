//! Using `st_platform` and `st_environment` from Rust.
//!
//! Rust code links the crate as an rlib and calls the same `extern "C"`
//! functions the other languages load from the cdylib:
//!
//! ```sh
//! cargo run --example platform
//! ```

use suggestedtests_native::environment::*;
use suggestedtests_native::platform::*;
use suggestedtests_native::report::{
    arch_name, container_name, kind_name, libc_name, os_name, vm_name,
};
use suggestedtests_native::{st_abi_version, ST_OK};

/// The text of a fixed, NUL-terminated `char[N]` field, "-" if empty.
fn text(buf: &[u8]) -> &str {
    let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    match std::str::from_utf8(&buf[..end]) {
        Ok("") => "-",
        Ok(s) => s,
        Err(_) => "?",
    }
}

fn platform() -> StPlatform {
    let mut p = StPlatform::default();
    // SAFETY: `p` is a live, writable `StPlatform`.
    let status = unsafe { st_platform(&mut p) };
    assert_eq!(status, ST_OK, "st_platform failed with {status}");
    p
}

fn environment() -> StEnvironment {
    let mut e = StEnvironment::default();
    // SAFETY: `e` is a live, writable `StEnvironment`.
    let status = unsafe { st_environment(&mut e) };
    assert_eq!(status, ST_OK, "st_environment failed with {status}");
    e
}

/// The `native/prebuilt/<os>-<arch>[-musl]` directory name for `p`, e.g.
/// "linux-x64", "linux-arm64-musl", "macos-arm64", "android-arm64-v8a";
/// `None` where no prebuilt is shipped.
fn prebuilt_dir(p: &StPlatform) -> Option<String> {
    let os = match p.os {
        ST_OS_LINUX => "linux",
        ST_OS_MACOS => "macos",
        ST_OS_WINDOWS => "windows",
        ST_OS_ANDROID => "android",
        _ => return None,
    };
    let arch = match (p.os, p.arch) {
        (ST_OS_ANDROID, ST_ARCH_AARCH64) => "arm64-v8a",
        (ST_OS_ANDROID, ST_ARCH_ARM) => "armeabi-v7a",
        (ST_OS_ANDROID, ST_ARCH_X86_64) => "x86_64",
        (_, ST_ARCH_X86_64) => "x64",
        (_, ST_ARCH_AARCH64) => "arm64",
        (_, ST_ARCH_X86) => "x86",
        (ST_OS_LINUX, ST_ARCH_ARM) => "arm",
        (ST_OS_LINUX, ST_ARCH_RISCV64) => "riscv64",
        _ => return None,
    };
    let musl = if p.libc == ST_LIBC_MUSL { "-musl" } else { "" };
    Some(format!("{os}-{arch}{musl}"))
}

/// The C library's file name on `os`.
fn library_file(os: u32) -> &'static str {
    match os {
        ST_OS_WINDOWS => "suggestedtests_native.dll",
        ST_OS_MACOS => "libsuggestedtests_native.dylib",
        _ => "libsuggestedtests_native.so",
    }
}

/// Where to download the prebuilt for `p` from: the copy committed on `main`.
fn download_url(p: &StPlatform) -> Option<String> {
    Some(format!(
        "https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/native/prebuilt/{}/{}",
        prebuilt_dir(p)?,
        library_file(p.os),
    ))
}

fn main() {
    // Like every binding, call this first: it runs the load-time
    // initializers where no loader hook did.
    println!("ABI v{}", st_abi_version());

    let p = platform();
    println!(
        "platform: {} {} {} {} ({}-bit), os {}",
        os_name(p.os),
        arch_name(p.arch),
        libc_name(p.libc),
        text(&p.libc_version),
        p.pointer_bits,
        text(&p.os_version),
    );
    if p.flags & ST_PLATFORM_TRANSLATED != 0 {
        println!("  running translated (Rosetta 2 / Windows on ARM emulation)");
    }

    let e = environment();
    println!(
        "environment: {}, container {}, vm {} ({}), cloud {}",
        kind_name(e.kind),
        container_name(e.container),
        vm_name(e.vm),
        text(&e.vm_vendor),
        text(&e.cloud),
    );
    for (bit, name) in [
        (ST_ENV_KUBERNETES, "kubernetes"),
        (ST_ENV_WSL, "wsl"),
        (ST_ENV_CI, "ci"),
        (ST_ENV_HEADLESS, "headless"),
        (ST_ENV_CLOUD, "cloud"),
    ] {
        if e.flags & bit != 0 {
            println!("  flag: {name}");
        }
    }

    // What a test would do with it: skip or relax checks that depend on
    // the machine.
    let shared_machine =
        e.container != ST_CONTAINER_NONE || e.vm != ST_VM_NONE || e.flags & ST_ENV_CI != 0;
    if shared_machine {
        println!("timing budgets: relaxed (container, VM or CI)");
    } else {
        println!("timing budgets: strict");
    }
    if p.os == ST_OS_LINUX && p.libc == ST_LIBC_MUSL {
        println!("musl: skipping glibc-only checks");
    }

    // Pick the right file to download for this machine.
    let Some(url) = download_url(&p) else {
        println!("download: no prebuilt for this platform");
        return;
    };
    println!("download: {url}");
}
