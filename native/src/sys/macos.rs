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

/// `sysctlbyname` returning a string, e.g. `kern.osproductversion`.
pub fn sysctl_string(name: &str) -> Option<String> {
    let cname = std::ffi::CString::new(name).ok()?;
    let mut len: libc::size_t = 0;
    // SAFETY: a null buffer asks for the size.
    if unsafe {
        libc::sysctlbyname(
            cname.as_ptr(),
            std::ptr::null_mut(),
            &mut len,
            std::ptr::null_mut(),
            0,
        )
    } != 0
        || len == 0
    {
        return None;
    }
    let mut buf = vec![0u8; len];
    // SAFETY: `buf` has `len` bytes.
    if unsafe {
        libc::sysctlbyname(
            cname.as_ptr(),
            buf.as_mut_ptr().cast(),
            &mut len,
            std::ptr::null_mut(),
            0,
        )
    } != 0
    {
        return None;
    }
    buf.truncate(len);
    let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    Some(String::from_utf8_lossy(&buf[..end]).into_owned())
}

/// `sysctlbyname` returning an int, e.g. `kern.hv_vmm_present`.
pub fn sysctl_int(name: &str) -> Option<i32> {
    let cname = std::ffi::CString::new(name).ok()?;
    let mut value: i32 = 0;
    let mut len = std::mem::size_of::<i32>() as libc::size_t;
    // SAFETY: `value` is `len` bytes.
    let rc = unsafe {
        libc::sysctlbyname(
            cname.as_ptr(),
            (&mut value as *mut i32).cast(),
            &mut len,
            std::ptr::null_mut(),
            0,
        )
    };
    (rc == 0).then_some(value)
}

/// macOS' product version ("14.5").
pub fn os_version() -> Option<String> {
    sysctl_string("kern.osproductversion").or_else(super::unix::kernel_release)
}

pub fn libc_version() -> Option<String> {
    None
}

/// Whether this process runs under Rosetta 2.
pub fn is_translated() -> bool {
    sysctl_int("sysctl.proc_translated") == Some(1)
}
