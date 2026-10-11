//! Windows: `GetProcessTimes`, `GetThreadTimes` and `K32GetProcessMemoryInfo`.

use crate::{StCpuTime, StMemory, ST_ERR_UNKNOWN};
use windows_sys::Win32::Foundation::{GetLastError, FILETIME};
use windows_sys::Win32::System::ProcessStatus::{
    K32GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS,
};
use windows_sys::Win32::System::Threading::{
    GetCurrentProcess, GetCurrentThread, GetProcessTimes, GetThreadTimes,
};

fn last_error() -> i32 {
    // SAFETY: GetLastError has no preconditions.
    match unsafe { GetLastError() } {
        0 => ST_ERR_UNKNOWN,
        code => code as i32,
    }
}

/// FILETIME durations are in 100-nanosecond units.
fn filetime_ns(ft: FILETIME) -> u64 {
    ((u64::from(ft.dwHighDateTime) << 32) | u64::from(ft.dwLowDateTime)) * 100
}

const ZERO: FILETIME = FILETIME {
    dwLowDateTime: 0,
    dwHighDateTime: 0,
};

pub fn process_cpu_time() -> Result<StCpuTime, i32> {
    let (mut creation, mut exit, mut kernel, mut user) = (ZERO, ZERO, ZERO, ZERO);
    // SAFETY: the pseudo-handle is always valid; all out-pointers are live.
    let ok = unsafe {
        GetProcessTimes(
            GetCurrentProcess(),
            &mut creation,
            &mut exit,
            &mut kernel,
            &mut user,
        )
    };
    if ok == 0 {
        return Err(last_error());
    }
    Ok(StCpuTime {
        user_ns: filetime_ns(user),
        system_ns: filetime_ns(kernel),
    })
}

pub fn thread_cpu_time_ns() -> Result<u64, i32> {
    let (mut creation, mut exit, mut kernel, mut user) = (ZERO, ZERO, ZERO, ZERO);
    // SAFETY: the pseudo-handle is always valid; all out-pointers are live.
    let ok = unsafe {
        GetThreadTimes(
            GetCurrentThread(),
            &mut creation,
            &mut exit,
            &mut kernel,
            &mut user,
        )
    };
    if ok == 0 {
        return Err(last_error());
    }
    Ok(filetime_ns(user) + filetime_ns(kernel))
}

pub fn memory_usage() -> Result<StMemory, i32> {
    // SAFETY: PROCESS_MEMORY_COUNTERS is plain old data.
    let mut counters: PROCESS_MEMORY_COUNTERS = unsafe { std::mem::zeroed() };
    let size = std::mem::size_of::<PROCESS_MEMORY_COUNTERS>() as u32;
    counters.cb = size;
    // SAFETY: the pseudo-handle is always valid; `counters` is `size` bytes.
    if unsafe { K32GetProcessMemoryInfo(GetCurrentProcess(), &mut counters, size) } == 0 {
        return Err(last_error());
    }
    Ok(StMemory {
        current_rss_bytes: counters.WorkingSetSize as u64,
        peak_rss_bytes: counters.PeakWorkingSetSize as u64,
    })
}
