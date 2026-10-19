//! Per-OS implementations. Each module exposes the same three functions:
//!
//! * `process_cpu_time() -> Result<StCpuTime, i32>`
//! * `thread_cpu_time_ns() -> Result<u64, i32>`
//! * `memory_usage() -> Result<StMemory, i32>`
//!
//! `Err` carries a status code as documented in `lib.rs`.

#[cfg(unix)]
mod unix;

#[cfg(any(target_os = "linux", target_os = "android"))]
mod linux;
#[cfg(target_os = "android")]
pub use linux::android_property;
#[cfg(any(target_os = "linux", target_os = "android"))]
pub use linux::{is_translated, libc_version, memory_usage, os_version};

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
pub use macos::{is_translated, libc_version, memory_usage, os_version, sysctl_int, sysctl_string};

#[cfg(unix)]
pub use unix::{process_cpu_time, spawn, thread_cpu_time_ns};

#[cfg(windows)]
mod windows;
#[cfg(windows)]
pub use windows::{
    is_translated, libc_version, memory_usage, os_version, process_cpu_time, spawn,
    thread_cpu_time_ns, windows_environment,
};

// Other Unix flavours compile, but report memory as unsupported.
#[cfg(all(
    unix,
    not(any(target_os = "linux", target_os = "android", target_os = "macos"))
))]
pub fn memory_usage() -> Result<crate::StMemory, i32> {
    Err(crate::ST_ERR_UNSUPPORTED)
}

#[cfg(all(
    unix,
    not(any(target_os = "linux", target_os = "android", target_os = "macos"))
))]
pub use unix::kernel_release as os_version;

#[cfg(all(
    unix,
    not(any(target_os = "linux", target_os = "android", target_os = "macos"))
))]
pub fn libc_version() -> Option<String> {
    None
}

#[cfg(all(
    unix,
    not(any(target_os = "linux", target_os = "android", target_os = "macos"))
))]
pub fn is_translated() -> bool {
    false
}
