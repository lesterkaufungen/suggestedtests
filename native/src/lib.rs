//! OS-agnostic C ABI bridge for the `suggestedtests` Dart package.
//!
//! Every exported function has the same signature and semantics on Windows,
//! Linux and macOS; the per-OS system calls live in `sys/`. The matching C
//! declarations are in `include/suggestedtests_native.h` and the Dart
//! bindings in `lib/src/native/bindings.dart`. Keep all three in sync and bump
//! [`ST_ABI_VERSION`] on any breaking change.
//!
//! Status codes returned by fallible functions:
//! * `0` ([`ST_OK`]) — success, `*out` written.
//! * `< 0` — bridge error ([`ST_ERR_NULL`], [`ST_ERR_UNSUPPORTED`]).
//! * `> 0` — raw OS error code (`errno` on Unix, `GetLastError()` on Windows).

mod sys;

/// Version of the C ABI. Dart refuses to use a library with a different one.
pub const ST_ABI_VERSION: u32 = 1;

/// Success.
pub const ST_OK: i32 = 0;
/// A required out-pointer was null.
pub const ST_ERR_NULL: i32 = -1;
/// The operation is not available on this OS.
pub const ST_ERR_UNSUPPORTED: i32 = -2;
/// The OS reported an error but no error code could be retrieved.
pub const ST_ERR_UNKNOWN: i32 = -3;

/// CPU time consumed by the whole process, in nanoseconds.
#[repr(C)]
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct StCpuTime {
    pub user_ns: u64,
    pub system_ns: u64,
}

/// Resident memory of the process, in bytes.
#[repr(C)]
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct StMemory {
    pub current_rss_bytes: u64,
    pub peak_rss_bytes: u64,
}

fn write_out<T>(out: *mut T, result: Result<T, i32>) -> i32 {
    if out.is_null() {
        return ST_ERR_NULL;
    }
    match result {
        Ok(value) => {
            // SAFETY: caller guarantees `out` points to writable memory for a `T`.
            unsafe { out.write(value) };
            ST_OK
        }
        Err(code) => code,
    }
}

/// Returns [`ST_ABI_VERSION`].
#[no_mangle]
pub extern "C" fn st_abi_version() -> u32 {
    ST_ABI_VERSION
}

/// Writes the process' user and kernel CPU time to `out`.
///
/// # Safety
/// `out` must be null or point to writable memory for one `StCpuTime`.
#[no_mangle]
pub unsafe extern "C" fn st_process_cpu_time(out: *mut StCpuTime) -> i32 {
    write_out(out, sys::process_cpu_time())
}

/// Writes the calling thread's CPU time (user + kernel) in nanoseconds to `out`.
///
/// # Safety
/// `out` must be null or point to writable memory for one `u64`.
#[no_mangle]
pub unsafe extern "C" fn st_thread_cpu_time_ns(out: *mut u64) -> i32 {
    write_out(out, sys::thread_cpu_time_ns())
}

/// Writes the process' current and peak resident set size to `out`.
///
/// # Safety
/// `out` must be null or point to writable memory for one `StMemory`.
#[no_mangle]
pub unsafe extern "C" fn st_memory_usage(out: *mut StMemory) -> i32 {
    write_out(out, sys::memory_usage())
}

/// Number of logical CPUs available to the process (at least 1).
#[no_mangle]
pub extern "C" fn st_cpu_count() -> u32 {
    std::thread::available_parallelism()
        .map(|n| u32::try_from(n.get()).unwrap_or(u32::MAX))
        .unwrap_or(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn burn() -> u64 {
        // Enough work to register on a ~1ms-resolution clock.
        let mut x = 0u64;
        for i in 0..20_000_000u64 {
            x = x.wrapping_mul(31).wrapping_add(i);
        }
        std::hint::black_box(x)
    }

    #[test]
    fn abi_version() {
        assert_eq!(st_abi_version(), ST_ABI_VERSION);
    }

    #[test]
    fn null_pointers_are_rejected() {
        unsafe {
            assert_eq!(st_process_cpu_time(std::ptr::null_mut()), ST_ERR_NULL);
            assert_eq!(st_thread_cpu_time_ns(std::ptr::null_mut()), ST_ERR_NULL);
            assert_eq!(st_memory_usage(std::ptr::null_mut()), ST_ERR_NULL);
        }
    }

    #[test]
    fn process_cpu_time_increases() {
        let mut before = StCpuTime::default();
        let mut after = StCpuTime::default();
        unsafe {
            assert_eq!(st_process_cpu_time(&mut before), ST_OK);
            burn();
            assert_eq!(st_process_cpu_time(&mut after), ST_OK);
        }
        assert!(after.user_ns + after.system_ns > before.user_ns + before.system_ns);
    }

    #[test]
    fn thread_cpu_time_increases() {
        let (mut before, mut after) = (0u64, 0u64);
        unsafe {
            assert_eq!(st_thread_cpu_time_ns(&mut before), ST_OK);
            burn();
            assert_eq!(st_thread_cpu_time_ns(&mut after), ST_OK);
        }
        assert!(after > before);
    }

    #[test]
    fn memory_usage_is_plausible() {
        let mut m = StMemory::default();
        assert_eq!(unsafe { st_memory_usage(&mut m) }, ST_OK);
        assert!(m.current_rss_bytes > 0);
        assert!(m.peak_rss_bytes >= m.current_rss_bytes);
    }

    #[test]
    fn cpu_count_is_positive() {
        assert!(st_cpu_count() >= 1);
    }
}
