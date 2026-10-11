//! Calls shared by every POSIX system (Linux, macOS, BSDs).

use crate::{StCpuTime, ST_ERR_UNKNOWN};

const NS_PER_SEC: u64 = 1_000_000_000;

/// Last `errno` as a positive status code.
pub(super) fn last_errno() -> i32 {
    std::io::Error::last_os_error()
        .raw_os_error()
        .filter(|&e| e > 0)
        .unwrap_or(ST_ERR_UNKNOWN)
}

fn timeval_ns(tv: libc::timeval) -> u64 {
    (tv.tv_sec as u64) * NS_PER_SEC + (tv.tv_usec as u64) * 1_000
}

/// `getrusage(RUSAGE_SELF)`. Shared with the OS modules for `ru_maxrss`.
pub(super) fn rusage_self() -> Result<libc::rusage, i32> {
    // SAFETY: rusage is plain old data; getrusage fully initialises it.
    let mut ru: libc::rusage = unsafe { std::mem::zeroed() };
    if unsafe { libc::getrusage(libc::RUSAGE_SELF, &mut ru) } != 0 {
        return Err(last_errno());
    }
    Ok(ru)
}

pub fn process_cpu_time() -> Result<StCpuTime, i32> {
    let ru = rusage_self()?;
    Ok(StCpuTime {
        user_ns: timeval_ns(ru.ru_utime),
        system_ns: timeval_ns(ru.ru_stime),
    })
}

pub fn thread_cpu_time_ns() -> Result<u64, i32> {
    // SAFETY: timespec is plain old data; clock_gettime fills it on success.
    let mut ts: libc::timespec = unsafe { std::mem::zeroed() };
    if unsafe { libc::clock_gettime(libc::CLOCK_THREAD_CPUTIME_ID, &mut ts) } != 0 {
        return Err(last_errno());
    }
    Ok((ts.tv_sec as u64) * NS_PER_SEC + ts.tv_nsec as u64)
}
