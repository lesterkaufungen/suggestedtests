//! Linux / Android: current RSS from `/proc/self/statm`, peak from `getrusage`.

use super::unix::{last_errno, rusage_self};
use crate::{StMemory, ST_ERR_UNKNOWN};

fn page_size() -> Result<u64, i32> {
    // SAFETY: sysconf has no preconditions.
    let size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    if size <= 0 {
        return Err(last_errno());
    }
    Ok(size as u64)
}

fn current_rss_bytes() -> Result<u64, i32> {
    let statm = std::fs::read_to_string("/proc/self/statm")
        .map_err(|e| e.raw_os_error().unwrap_or(ST_ERR_UNKNOWN))?;
    // Format: "size resident shared text lib data dt", in pages.
    let resident_pages: u64 = statm
        .split_ascii_whitespace()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .ok_or(ST_ERR_UNKNOWN)?;
    Ok(resident_pages * page_size()?)
}

pub fn memory_usage() -> Result<StMemory, i32> {
    let current = current_rss_bytes()?;
    // Linux reports ru_maxrss in kilobytes.
    let peak = rusage_self()?.ru_maxrss as u64 * 1024;
    Ok(StMemory {
        current_rss_bytes: current,
        // statm is page-accurate while maxrss may lag; never report peak < current.
        peak_rss_bytes: peak.max(current),
    })
}

/// The OS version: the kernel release, or Android's release ("14").
pub fn os_version() -> Option<String> {
    #[cfg(target_os = "android")]
    if let Some(release) = android_property("ro.build.version.release") {
        return Some(release);
    }
    super::unix::kernel_release()
}

/// glibc's version ("2.39"), Android's API level ("34"), or None (musl).
pub fn libc_version() -> Option<String> {
    #[cfg(all(target_os = "linux", target_env = "gnu"))]
    {
        // SAFETY: returns a static NUL-terminated string.
        let v = unsafe { std::ffi::CStr::from_ptr(libc::gnu_get_libc_version()) };
        return Some(v.to_string_lossy().into_owned());
    }
    #[cfg(target_os = "android")]
    {
        return android_property("ro.build.version.sdk");
    }
    #[allow(unreachable_code)]
    None
}

pub fn is_translated() -> bool {
    false
}

/// An Android system property, e.g. `ro.build.version.sdk`.
#[cfg(target_os = "android")]
pub fn android_property(name: &str) -> Option<String> {
    let name = std::ffi::CString::new(name).ok()?;
    let mut value = [0 as libc::c_char; 92]; // PROP_VALUE_MAX
                                             // SAFETY: `value` has PROP_VALUE_MAX bytes, as the API requires.
    let len = unsafe { libc::__system_property_get(name.as_ptr(), value.as_mut_ptr()) };
    if len <= 0 {
        return None;
    }
    // SAFETY: the property is NUL-terminated within the buffer.
    let v = unsafe { std::ffi::CStr::from_ptr(value.as_ptr()) };
    Some(v.to_string_lossy().into_owned())
}
