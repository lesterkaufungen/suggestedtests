//! Windows: `GetProcessTimes`, `GetThreadTimes` and `K32GetProcessMemoryInfo`.

use crate::{
    SpawnRequest, StCpuTime, StMemory, ST_ERR_INVALID, ST_ERR_UNKNOWN, ST_SPAWN_DETACHED,
    ST_SPAWN_NO_WINDOW,
};
use windows_sys::Win32::Foundation::{
    CloseHandle, GetLastError, FILETIME, GENERIC_READ, GENERIC_WRITE, INVALID_HANDLE_VALUE,
};
use windows_sys::Win32::Security::SECURITY_ATTRIBUTES;
use windows_sys::Win32::Storage::FileSystem::{
    CreateFileW, FILE_SHARE_READ, FILE_SHARE_WRITE, OPEN_EXISTING,
};
use windows_sys::Win32::System::ProcessStatus::{K32GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS};
use windows_sys::Win32::System::Threading::{
    CreateProcessW, GetCurrentProcess, GetCurrentThread, GetProcessTimes, GetThreadTimes,
    CREATE_NEW_PROCESS_GROUP, CREATE_NO_WINDOW, CREATE_UNICODE_ENVIRONMENT, DETACHED_PROCESS,
    PROCESS_INFORMATION, STARTF_USESTDHANDLES, STARTUPINFOW,
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

fn wide(s: &str) -> Result<Vec<u16>, i32> {
    if s.contains('\0') {
        return Err(ST_ERR_INVALID);
    }
    Ok(s.encode_utf16().chain(std::iter::once(0)).collect())
}

/// Windows' argv-quoting rules (as `CommandLineToArgvW` expects): wrap in
/// quotes when the argument has a space, tab or quote, doubling any
/// backslashes that immediately precede a literal or closing quote.
fn quote_arg(arg: &str) -> String {
    if !arg.is_empty() && !arg.chars().any(|c| matches!(c, ' ' | '\t' | '"')) {
        return arg.to_string();
    }
    let mut out = String::with_capacity(arg.len() + 2);
    out.push('"');
    let mut chars = arg.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\\' {
            let mut backslashes = 1usize;
            while chars.peek() == Some(&'\\') {
                backslashes += 1;
                chars.next();
            }
            let doubled = matches!(chars.peek(), Some('"') | None);
            let count = if doubled {
                backslashes * 2
            } else {
                backslashes
            };
            out.extend(std::iter::repeat('\\').take(count));
        } else if c == '"' {
            out.push('\\');
            out.push('"');
        } else {
            out.push(c);
        }
    }
    out.push('"');
    out
}

/// Spawns `req` with `CreateProcessW`. Unlike Unix, a Windows child is never
/// reparented onto this process in a way that needs reaping: once
/// `CreateProcessW` returns, closing its handles (so nothing here can wait
/// on or kill it later) leaves the child running fully on its own.
pub fn spawn(req: &SpawnRequest) -> Result<u64, i32> {
    let app_name = wide(&req.path)?;
    let mut cmdline = quote_arg(&req.path);
    for arg in &req.args {
        cmdline.push(' ');
        cmdline.push_str(&quote_arg(arg));
    }
    let mut cmdline_w = wide(&cmdline)?;

    let cwd_w = req.cwd.as_deref().map(wide).transpose()?;

    // Windows takes one flat, double-NUL-terminated block of "KEY=VALUE\0"
    // strings; `BTreeMap` both de-duplicates overridden keys and gives the
    // sorted order `CreateProcessW` expects for `CREATE_UNICODE_ENVIRONMENT`.
    let mut env_map: std::collections::BTreeMap<String, String> = std::env::vars().collect();
    for (key, value) in &req.env {
        env_map.insert(key.clone(), value.clone());
    }
    let mut env_block: Vec<u16> = Vec::new();
    for (key, value) in &env_map {
        if key.is_empty() {
            continue;
        }
        env_block.extend(wide(&format!("{key}={value}"))?);
    }
    env_block.push(0);

    // One inheritable handle to the NUL device for all three standard
    // handles, so a detached child doesn't hold this process' own stdio
    // open. `CreateProcessW`'s `bInheritHandles` only propagates handles
    // marked inheritable, so this is the only one the child receives.
    let inheritable = SECURITY_ATTRIBUTES {
        nLength: std::mem::size_of::<SECURITY_ATTRIBUTES>() as u32,
        lpSecurityDescriptor: std::ptr::null_mut(),
        bInheritHandle: 1,
    };
    let nul_name = wide("NUL")?;
    // SAFETY: `nul_name` is NUL-terminated; `inheritable` is live for the call.
    let nul = unsafe {
        CreateFileW(
            nul_name.as_ptr(),
            GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            &inheritable,
            OPEN_EXISTING,
            0,
            std::ptr::null_mut(),
        )
    };
    if nul == INVALID_HANDLE_VALUE {
        return Err(last_error());
    }

    // SAFETY: STARTUPINFOW is plain old data; zeroed is a valid value before
    // we fill the fields CreateProcessW reads.
    let mut startup_info: STARTUPINFOW = unsafe { std::mem::zeroed() };
    startup_info.cb = std::mem::size_of::<STARTUPINFOW>() as u32;
    startup_info.dwFlags = STARTF_USESTDHANDLES;
    startup_info.hStdInput = nul;
    startup_info.hStdOutput = nul;
    startup_info.hStdError = nul;

    let mut creation_flags = CREATE_UNICODE_ENVIRONMENT;
    if req.flags & ST_SPAWN_NO_WINDOW != 0 {
        creation_flags |= CREATE_NO_WINDOW;
    }
    if req.flags & ST_SPAWN_DETACHED != 0 {
        creation_flags |= CREATE_NEW_PROCESS_GROUP;
        // DETACHED_PROCESS and CREATE_NO_WINDOW can't be combined; when no
        // console is created in the first place there's nothing to detach.
        if req.flags & ST_SPAWN_NO_WINDOW == 0 {
            creation_flags |= DETACHED_PROCESS;
        }
    }

    // SAFETY: STARTUPINFOW/PROCESS_INFORMATION are plain old data.
    let mut process_info: PROCESS_INFORMATION = unsafe { std::mem::zeroed() };
    // SAFETY: `app_name`/`cmdline_w`/`cwd_w` are NUL-terminated and live for
    // the call; `cmdline_w` is the only one `CreateProcessW` may write
    // through (never past its length); `env_block` is a double-NUL-terminated
    // buffer matching `CREATE_UNICODE_ENVIRONMENT`; `startup_info` and
    // `process_info` are valid, sized structures.
    let ok = unsafe {
        CreateProcessW(
            app_name.as_ptr(),
            cmdline_w.as_mut_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            1, // bInheritHandles: only the NUL handle above is inheritable.
            creation_flags,
            env_block.as_ptr().cast(),
            cwd_w.as_ref().map_or(std::ptr::null(), |w| w.as_ptr()),
            &startup_info,
            &mut process_info,
        )
    };
    let create_err = (ok == 0).then(last_error);
    // SAFETY: `nul` is a valid handle opened above, not needed any further.
    unsafe { CloseHandle(nul) };
    if let Some(err) = create_err {
        return Err(err);
    }
    // SAFETY: both handles were just filled in by `CreateProcessW`; nothing
    // here ever waits on or kills this process, so neither is kept open.
    unsafe {
        CloseHandle(process_info.hProcess);
        CloseHandle(process_info.hThread);
    }
    Ok(u64::from(process_info.dwProcessId))
}

fn rtl_version() -> Option<windows_sys::Win32::System::SystemInformation::OSVERSIONINFOEXW> {
    use windows_sys::Win32::System::SystemInformation::OSVERSIONINFOEXW;
    // SAFETY: plain old data; RtlGetVersion fills it (unlike GetVersionEx it
    // isn't capped by the application manifest).
    let mut v: OSVERSIONINFOEXW = unsafe { std::mem::zeroed() };
    v.dwOSVersionInfoSize = std::mem::size_of::<OSVERSIONINFOEXW>() as u32;
    let status = unsafe {
        windows_sys::Wdk::System::SystemServices::RtlGetVersion(
            (&mut v as *mut OSVERSIONINFOEXW).cast(),
        )
    };
    (status == 0).then_some(v)
}

/// "major.minor.build", e.g. "10.0.22631".
pub fn os_version() -> Option<String> {
    let v = rtl_version()?;
    Some(format!(
        "{}.{}.{}",
        v.dwMajorVersion, v.dwMinorVersion, v.dwBuildNumber
    ))
}

pub fn libc_version() -> Option<String> {
    None
}

/// Whether this process runs under x86/x64 emulation on ARM64 Windows.
pub fn is_translated() -> bool {
    use windows_sys::Win32::System::SystemInformation::IMAGE_FILE_MACHINE_ARM64;
    use windows_sys::Win32::System::Threading::IsWow64Process2;
    let (mut process, mut native) = (0u16, 0u16);
    // SAFETY: the pseudo-handle is always valid; both out-pointers are live.
    if unsafe { IsWow64Process2(GetCurrentProcess(), &mut process, &mut native) } == 0 {
        return false;
    }
    native == IMAGE_FILE_MACHINE_ARM64 && !cfg!(target_arch = "aarch64")
}

fn registry_string(key: &str, value: &str) -> Option<String> {
    use windows_sys::Win32::System::Registry::{RegGetValueW, HKEY_LOCAL_MACHINE, RRF_RT_REG_SZ};
    let wide = |s: &str| {
        s.encode_utf16()
            .chain(std::iter::once(0))
            .collect::<Vec<u16>>()
    };
    let (key, value) = (wide(key), wide(value));
    let mut buf = [0u16; 256];
    let mut size = std::mem::size_of_val(&buf) as u32;
    // SAFETY: `buf` is `size` bytes; strings are NUL-terminated.
    let rc = unsafe {
        RegGetValueW(
            HKEY_LOCAL_MACHINE,
            key.as_ptr(),
            value.as_ptr(),
            RRF_RT_REG_SZ,
            std::ptr::null_mut(),
            buf.as_mut_ptr().cast(),
            &mut size,
        )
    };
    if rc != 0 {
        return None;
    }
    let len = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
    Some(String::from_utf16_lossy(&buf[..len]))
}

fn registry_exists(key: &str, value: &str) -> bool {
    use windows_sys::Win32::System::Registry::{RegGetValueW, HKEY_LOCAL_MACHINE, RRF_RT_ANY};
    let wide = |s: &str| {
        s.encode_utf16()
            .chain(std::iter::once(0))
            .collect::<Vec<u16>>()
    };
    let (key, value) = (wide(key), wide(value));
    // SAFETY: a null buffer only checks for existence.
    unsafe {
        RegGetValueW(
            HKEY_LOCAL_MACHINE,
            key.as_ptr(),
            value.as_ptr(),
            RRF_RT_ANY,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        ) == 0
    }
}

/// What `st_environment` needs from Windows.
pub struct WindowsEnvironment {
    pub kind: u32,
    pub container: bool,
    pub manufacturer: String,
    pub product: String,
    pub bios_vendor: String,
}

pub fn windows_environment() -> WindowsEnvironment {
    const BIOS: &str = "HARDWARE\\DESCRIPTION\\System\\BIOS";
    // wProductType: 1 workstation, 2 domain controller, 3 server.
    let kind = match rtl_version().map(|v| v.wProductType) {
        Some(1) => crate::environment::ST_KIND_DESKTOP,
        Some(2) | Some(3) => crate::environment::ST_KIND_SERVER,
        _ => crate::environment::ST_KIND_UNKNOWN,
    };
    WindowsEnvironment {
        kind,
        // Set for Windows Server containers and Hyper-V isolated containers.
        container: registry_exists("SYSTEM\\CurrentControlSet\\Control", "ContainerType"),
        manufacturer: registry_string(BIOS, "SystemManufacturer").unwrap_or_default(),
        product: registry_string(BIOS, "SystemProductName").unwrap_or_default(),
        bios_vendor: registry_string(BIOS, "BIOSVendor").unwrap_or_default(),
    }
}
