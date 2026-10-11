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
