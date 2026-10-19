//! `st_platform`: what the library was built for (OS, architecture, C
//! library, pointer width) plus what the running system reports (OS and libc
//! versions, binary translation such as Rosetta 2).
//!
//! The compile-time facts are exact: a library built for one libc can't be
//! loaded into a process using another, so the build target *is* the
//! process' platform.

use crate::write_out;
#[cfg(test)]
use crate::ST_OK;

pub const ST_OS_UNKNOWN: u32 = 0;
pub const ST_OS_LINUX: u32 = 1;
pub const ST_OS_MACOS: u32 = 2;
pub const ST_OS_WINDOWS: u32 = 3;
pub const ST_OS_ANDROID: u32 = 4;
pub const ST_OS_FREEBSD: u32 = 5;
pub const ST_OS_IOS: u32 = 6;

pub const ST_ARCH_UNKNOWN: u32 = 0;
pub const ST_ARCH_X86_64: u32 = 1;
pub const ST_ARCH_AARCH64: u32 = 2;
pub const ST_ARCH_X86: u32 = 3;
pub const ST_ARCH_ARM: u32 = 4;
pub const ST_ARCH_RISCV64: u32 = 5;
pub const ST_ARCH_PPC64LE: u32 = 6;
pub const ST_ARCH_S390X: u32 = 7;
pub const ST_ARCH_LOONGARCH64: u32 = 8;

pub const ST_LIBC_UNKNOWN: u32 = 0;
pub const ST_LIBC_GLIBC: u32 = 1;
pub const ST_LIBC_MUSL: u32 = 2;
pub const ST_LIBC_BIONIC: u32 = 3;
pub const ST_LIBC_MSVC: u32 = 4;
pub const ST_LIBC_APPLE: u32 = 5;
pub const ST_LIBC_BSD: u32 = 6;

/// The process runs translated: Rosetta 2 (x86_64 on Apple Silicon) or
/// Windows' x86/x64 emulation on ARM.
pub const ST_PLATFORM_TRANSLATED: u32 = 1;

/// Result of [`st_platform`].
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StPlatform {
    pub os: u32,
    pub arch: u32,
    pub libc: u32,
    /// 32 or 64.
    pub pointer_bits: u32,
    /// `ST_PLATFORM_*` flags.
    pub flags: u32,
    /// e.g. "6.8.0-45-generic" (Linux kernel), "14.5" (macOS),
    /// "10.0.22631" (Windows), "14" (Android). NUL-terminated UTF-8.
    pub os_version: [u8; 64],
    /// e.g. "2.39" (glibc), "34" (bionic: the API level); empty when the
    /// libc doesn't report one (musl). NUL-terminated UTF-8.
    pub libc_version: [u8; 32],
}

impl Default for StPlatform {
    fn default() -> Self {
        StPlatform {
            os: ST_OS_UNKNOWN,
            arch: ST_ARCH_UNKNOWN,
            libc: ST_LIBC_UNKNOWN,
            pointer_bits: 0,
            flags: 0,
            os_version: [0; 64],
            libc_version: [0; 32],
        }
    }
}

/// Copies `s` into a fixed buffer, truncated at a UTF-8 boundary, always
/// NUL-terminated.
pub(crate) fn copy_str<const N: usize>(dst: &mut [u8; N], s: &str) {
    let mut end = s.len().min(N - 1);
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }
    dst[..end].copy_from_slice(&s.as_bytes()[..end]);
    dst[end..].fill(0);
}

pub(crate) const fn build_os() -> u32 {
    if cfg!(target_os = "android") {
        ST_OS_ANDROID
    } else if cfg!(target_os = "linux") {
        ST_OS_LINUX
    } else if cfg!(target_os = "macos") {
        ST_OS_MACOS
    } else if cfg!(target_os = "ios") {
        ST_OS_IOS
    } else if cfg!(target_os = "windows") {
        ST_OS_WINDOWS
    } else if cfg!(target_os = "freebsd") {
        ST_OS_FREEBSD
    } else {
        ST_OS_UNKNOWN
    }
}

const fn build_arch() -> u32 {
    if cfg!(target_arch = "x86_64") {
        ST_ARCH_X86_64
    } else if cfg!(target_arch = "aarch64") {
        ST_ARCH_AARCH64
    } else if cfg!(target_arch = "x86") {
        ST_ARCH_X86
    } else if cfg!(target_arch = "arm") {
        ST_ARCH_ARM
    } else if cfg!(target_arch = "riscv64") {
        ST_ARCH_RISCV64
    } else if cfg!(all(target_arch = "powerpc64", target_endian = "little")) {
        ST_ARCH_PPC64LE
    } else if cfg!(target_arch = "s390x") {
        ST_ARCH_S390X
    } else if cfg!(target_arch = "loongarch64") {
        ST_ARCH_LOONGARCH64
    } else {
        ST_ARCH_UNKNOWN
    }
}

const fn build_libc() -> u32 {
    if cfg!(target_os = "android") {
        ST_LIBC_BIONIC
    } else if cfg!(target_env = "musl") {
        ST_LIBC_MUSL
    } else if cfg!(all(target_os = "linux", target_env = "gnu")) {
        ST_LIBC_GLIBC
    } else if cfg!(target_os = "windows") {
        ST_LIBC_MSVC
    } else if cfg!(target_vendor = "apple") {
        ST_LIBC_APPLE
    } else if cfg!(target_os = "freebsd") {
        ST_LIBC_BSD
    } else {
        ST_LIBC_UNKNOWN
    }
}

fn platform() -> StPlatform {
    let mut p = StPlatform {
        os: build_os(),
        arch: build_arch(),
        libc: build_libc(),
        pointer_bits: usize::BITS,
        ..StPlatform::default()
    };
    if crate::sys::is_translated() {
        p.flags |= ST_PLATFORM_TRANSLATED;
    }
    copy_str(
        &mut p.os_version,
        &crate::sys::os_version().unwrap_or_default(),
    );
    copy_str(
        &mut p.libc_version,
        &crate::sys::libc_version().unwrap_or_default(),
    );
    p
}

/// Writes the build target and runtime versions to `out`. Always succeeds
/// unless `out` is null; unknown fields are 0 / empty.
///
/// # Safety
/// `out` must be null or point to writable memory for one `StPlatform`.
#[no_mangle]
pub unsafe extern "C" fn st_platform(out: *mut StPlatform) -> i32 {
    write_out(out, Ok(platform()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(buf: &[u8]) -> &str {
        let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
        std::str::from_utf8(&buf[..end]).unwrap()
    }

    #[test]
    fn copy_str_truncates_on_char_boundary() {
        let mut buf = [0xffu8; 6];
        copy_str(&mut buf, "abcdé");
        assert_eq!(text(&buf), "abcd"); // é would not fit with the NUL
        assert_eq!(buf[4], 0);
        copy_str(&mut buf, "ab");
        assert_eq!(&buf, b"ab\0\0\0\0");
    }

    #[test]
    fn describes_this_build() {
        let mut p = StPlatform::default();
        assert_eq!(unsafe { st_platform(&mut p) }, ST_OK);
        assert_eq!(p.pointer_bits as usize, std::mem::size_of::<usize>() * 8);
        assert_ne!(p.os, ST_OS_UNKNOWN);
        assert_ne!(p.arch, ST_ARCH_UNKNOWN);
        assert_ne!(p.libc, ST_LIBC_UNKNOWN);
        assert!(!text(&p.os_version).is_empty(), "os version missing");
        #[cfg(all(target_os = "linux", target_env = "gnu"))]
        assert!(
            text(&p.libc_version).starts_with("2."),
            "{}",
            text(&p.libc_version)
        );
        #[cfg(target_env = "musl")]
        assert_eq!(p.libc, ST_LIBC_MUSL);
    }

    #[test]
    fn null_is_rejected() {
        assert_eq!(
            unsafe { st_platform(std::ptr::null_mut()) },
            crate::ST_ERR_NULL
        );
    }

    #[test]
    fn layout_matches_the_c_header() {
        // sizeof / offsetof as compiled from include/suggestedtests_native.h.
        assert_eq!(std::mem::size_of::<StPlatform>(), 116);
        assert_eq!(std::mem::align_of::<StPlatform>(), 4);
        assert_eq!(std::mem::offset_of!(StPlatform, os_version), 20);
        assert_eq!(std::mem::offset_of!(StPlatform, libc_version), 84);
    }
}
