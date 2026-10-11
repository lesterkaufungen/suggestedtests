//! macOS: current RSS from `proc_pidinfo(PROC_PIDTASKINFO)`, peak from
//! `getrusage`.

use super::unix::{last_errno, rusage_self};
use crate::StMemory;

fn current_rss_bytes() -> Result<u64, i32> {
    // SAFETY: proc_taskinfo is plain old data; proc_pidinfo writes at most
    // `size` bytes into it and returns how many it wrote.
    let mut info: libc::proc_taskinfo = unsafe { std::mem::zeroed() };
    let size = std::mem::size_of::<libc::proc_taskinfo>() as libc::c_int;
    let written = unsafe {
        libc::proc_pidinfo(
            libc::getpid(),
            libc::PROC_PIDTASKINFO,
            0,
            (&mut info as *mut libc::proc_taskinfo).cast(),
            size,
        )
    };
    if written != size {
        return Err(last_errno());
    }
    Ok(info.pti_resident_size)
}

pub fn memory_usage() -> Result<StMemory, i32> {
    let current = current_rss_bytes()?;
    // macOS reports ru_maxrss in bytes.
    let peak = rusage_self()?.ru_maxrss as u64;
    Ok(StMemory {
        current_rss_bytes: current,
        peak_rss_bytes: peak.max(current),
    })
}
