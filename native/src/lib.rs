//! OS-agnostic C ABI bridge shared by every `suggestedtests` package.
//!
//! Every exported function has the same signature and semantics on Windows,
//! Linux and macOS; the per-OS system calls live in `sys/`. The matching C
//! declarations are in `include/suggestedtests_native.h`. Its consumers:
//!
//! * Dart: `packages/dart/lib/src/native/bindings.dart` (`@Native` FFI)
//! * Python: `packages/python/src/suggestedtests/_native.py` (ctypes)
//! * PHP: `packages/php/src/Native/Bridge.php` (ext-ffi)
//! * Java: the JNI exports in [`jni`]
//! * Node.js: the Node-API addon in `node/`, which links this crate
//!
//! Keep all of them in sync and bump [`ST_ABI_VERSION`] on any breaking change.
//!
//! Status codes returned by fallible functions:
//! * `0` ([`ST_OK`]) — success, `*out` written.
//! * `< 0` — bridge error ([`ST_ERR_NULL`], [`ST_ERR_UNSUPPORTED`]).
//! * `> 0` — raw OS error code (`errno` on Unix, `GetLastError()` on Windows).

pub mod environment;
pub mod jni;
pub mod load;
pub mod platform;
pub mod report;
pub(crate) mod sys;

/// Version of the C ABI. Every binding refuses a library with a different one.
pub const ST_ABI_VERSION: u32 = 1;

/// Success.
pub const ST_OK: i32 = 0;
/// A required out-pointer was null.
pub const ST_ERR_NULL: i32 = -1;
/// The operation is not available on this OS.
pub const ST_ERR_UNSUPPORTED: i32 = -2;
/// The OS reported an error but no error code could be retrieved.
pub const ST_ERR_UNKNOWN: i32 = -3;
/// A required C string argument was null or not valid UTF-8.
pub const ST_ERR_INVALID: i32 = -4;

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

/// Detach the spawned process from this one: on Unix it becomes a session
/// leader in a new session (`setsid`), detached from any controlling
/// terminal; on Windows it gets its own process group
/// (`CREATE_NEW_PROCESS_GROUP`) and, unless [`ST_SPAWN_NO_WINDOW`] is also
/// set, no console (`DETACHED_PROCESS`). Ignored nowhere: even without this
/// flag, [`st_spawn`] never leaves a zombie or an open handle behind, since
/// nothing can wait on the child afterwards.
pub const ST_SPAWN_DETACHED: u32 = 1;
/// Windows only: `CREATE_NO_WINDOW`, so a console child doesn't flash a
/// window. Ignored elsewhere.
pub const ST_SPAWN_NO_WINDOW: u32 = 2;

/// One additional or overriding environment variable for [`st_spawn`].
#[repr(C)]
pub struct StSpawnEnvVar {
    pub key: *const std::os::raw::c_char,
    pub value: *const std::os::raw::c_char,
}

/// A validated, owned [`st_spawn`] request: everything below this point is
/// safe Rust, no raw pointers.
pub(crate) struct SpawnRequest {
    pub path: String,
    pub args: Vec<String>,
    pub cwd: Option<String>,
    pub env: Vec<(String, String)>,
    pub flags: u32,
}

/// # Safety
/// `ptr` must be null or a NUL-terminated, valid-UTF-8 C string with a
/// lifetime covering this call.
unsafe fn required_str(ptr: *const std::os::raw::c_char) -> Result<String, i32> {
    if ptr.is_null() {
        return Err(ST_ERR_NULL);
    }
    std::ffi::CStr::from_ptr(ptr)
        .to_str()
        .map(str::to_owned)
        .map_err(|_| ST_ERR_INVALID)
}

impl SpawnRequest {
    /// # Safety
    /// See [`st_spawn`].
    unsafe fn from_raw(
        path: *const std::os::raw::c_char,
        args: *const *const std::os::raw::c_char,
        args_len: u32,
        cwd: *const std::os::raw::c_char,
        env: *const StSpawnEnvVar,
        env_len: u32,
        flags: u32,
    ) -> Result<Self, i32> {
        let path = required_str(path)?;

        if args.is_null() && args_len != 0 {
            return Err(ST_ERR_NULL);
        }
        let mut owned_args = Vec::with_capacity(args_len as usize);
        for i in 0..args_len as isize {
            owned_args.push(required_str(*args.offset(i))?);
        }

        let cwd = if cwd.is_null() {
            None
        } else {
            Some(required_str(cwd)?)
        };

        if env.is_null() && env_len != 0 {
            return Err(ST_ERR_NULL);
        }
        let mut owned_env = Vec::with_capacity(env_len as usize);
        for i in 0..env_len as isize {
            let var = &*env.offset(i);
            owned_env.push((required_str(var.key)?, required_str(var.value)?));
        }

        Ok(SpawnRequest {
            path,
            args: owned_args,
            cwd,
            env: owned_env,
            flags,
        })
    }
}

pub(crate) fn write_out<T>(out: *mut T, result: Result<T, i32>) -> i32 {
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

/// Returns [`ST_ABI_VERSION`]. Every binding calls this first, so it also
/// runs the load-time initializers ([`load`]) where no loader hook did.
#[no_mangle]
pub extern "C" fn st_abi_version() -> u32 {
    load::ensure();
    report::flush_pending();
    ST_ABI_VERSION
}

/// Called once, as early as each binding's own load path allows (see each
/// package's loader/native-bridge file), for side effects that don't belong
/// in the pure version query [`st_abi_version`] does. Safe to call more than
/// once (only the first call does anything) and safe to call without ever
/// calling `st_abi_version` at all.
///
/// A no-op beyond `st_abi_version`'s own `load::ensure`/`report::flush_pending`
/// right now: every binding already gets both from its first call to
/// `st_abi_version`, so nothing here is reachable through the published
/// prebuilts either way.
#[no_mangle]
pub extern "C" fn st_on_load() {
    load::ensure();
    report::flush_pending();
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

/// Spawns `path` as a new, unmonitored process and writes its PID to
/// `out_pid`. No handle is kept open and nothing is ever waited on: this is
/// fire-and-forget, so there is no `st_process_wait`/`st_process_kill`.
///
/// `path` is the executable file, not resolved against `PATH` (like
/// `execve`, unlike `execvp`). `args` is its argv *excluding* `path`
/// (`path` is always argv\[0\]); pass null with `args_len` 0 for none. `cwd`
/// may be null to inherit this process' working directory. `env` adds to,
/// or overrides, this process' inherited environment; pass null with
/// `env_len` 0 to inherit it unchanged. `flags` is a bitmask of
/// [`ST_SPAWN_DETACHED`] and [`ST_SPAWN_NO_WINDOW`].
///
/// Returns [`ST_ERR_NULL`] for a null `path`/`out_pid`, or a null `args`/`env`
/// element or array (when its `_len` is nonzero); [`ST_ERR_INVALID`] for a
/// string that isn't valid UTF-8; otherwise the OS error from spawning.
///
/// # Safety
/// `path` and `cwd` must be null or NUL-terminated UTF-8 C strings. `args`
/// must be null (with `args_len` 0) or point to `args_len` readable
/// pointers, each null or a NUL-terminated UTF-8 C string. `env` must be
/// null (with `env_len` 0) or point to `env_len` readable [`StSpawnEnvVar`]s
/// whose `key`/`value` are null or NUL-terminated UTF-8 C strings. `out_pid`
/// must be null or point to writable memory for one `u64`. Every pointer
/// need only be valid for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn st_spawn(
    path: *const std::os::raw::c_char,
    args: *const *const std::os::raw::c_char,
    args_len: u32,
    cwd: *const std::os::raw::c_char,
    env: *const StSpawnEnvVar,
    env_len: u32,
    flags: u32,
    out_pid: *mut u64,
) -> i32 {
    if out_pid.is_null() {
        return ST_ERR_NULL;
    }
    let request = match SpawnRequest::from_raw(path, args, args_len, cwd, env, env_len, flags) {
        Ok(request) => request,
        Err(code) => return code,
    };
    write_out(out_pid, sys::spawn(&request))
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

    /// Spins until `read()` returns a larger value. CPU clocks tick coarsely on
    /// some systems (~15.6ms on Windows), so a fixed amount of work may not
    /// register. Panics after 5s of wall time.
    fn burn_until_advances(read: impl Fn() -> u64) -> (u64, u64) {
        let before = read();
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let mut x = 0u64;
        loop {
            for i in 0..100_000u64 {
                x = std::hint::black_box(x.wrapping_mul(31).wrapping_add(i));
            }
            let after = read();
            if after > before {
                return (before, after);
            }
            assert!(
                std::time::Instant::now() < deadline,
                "CPU clock never advanced"
            );
        }
    }

    #[test]
    fn abi_version() {
        assert_eq!(st_abi_version(), ST_ABI_VERSION);
    }

    #[test]
    fn on_load_runs_more_than_once_without_issue() {
        st_on_load();
        st_on_load();
        assert_ne!(load::state(), load::ST_LOAD_NOT_RUN);
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
        let (before, after) = burn_until_advances(|| {
            let mut t = StCpuTime::default();
            assert_eq!(unsafe { st_process_cpu_time(&mut t) }, ST_OK);
            t.user_ns + t.system_ns
        });
        assert!(after > before);
    }

    #[test]
    fn thread_cpu_time_increases() {
        let (before, after) = burn_until_advances(|| {
            let mut t = 0u64;
            assert_eq!(unsafe { st_thread_cpu_time_ns(&mut t) }, ST_OK);
            t
        });
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

    #[test]
    fn spawn_rejects_null_path_and_out_pid() {
        let path = std::ffi::CString::new("/bin/true").unwrap();
        let mut pid = 0u64;
        unsafe {
            assert_eq!(
                st_spawn(
                    std::ptr::null(),
                    std::ptr::null(),
                    0,
                    std::ptr::null(),
                    std::ptr::null(),
                    0,
                    0,
                    &mut pid
                ),
                ST_ERR_NULL
            );
            assert_eq!(
                st_spawn(
                    path.as_ptr(),
                    std::ptr::null(),
                    0,
                    std::ptr::null(),
                    std::ptr::null(),
                    0,
                    0,
                    std::ptr::null_mut()
                ),
                ST_ERR_NULL
            );
        }
    }

    #[test]
    fn spawn_rejects_a_null_arg_when_args_len_is_nonzero() {
        let path = std::ffi::CString::new("/bin/true").unwrap();
        let mut pid = 0u64;
        unsafe {
            assert_eq!(
                st_spawn(
                    path.as_ptr(),
                    std::ptr::null(),
                    1,
                    std::ptr::null(),
                    std::ptr::null(),
                    0,
                    0,
                    &mut pid
                ),
                ST_ERR_NULL
            );
        }
    }

    #[cfg(unix)]
    #[test]
    fn spawn_runs_cwd_env_and_args() {
        let dir = std::env::temp_dir().join(format!(
            "st_spawn_test_{}_{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let marker = dir.join("marker");

        let path = std::ffi::CString::new("/bin/sh").unwrap();
        let arg0 = std::ffi::CString::new("-c").unwrap();
        // Proves args, cwd and env all reached the child: it writes its own
        // cwd, the env var we passed, and an arg we passed, into `marker`.
        let script = std::ffi::CString::new(
            "pwd > \"$1\"; echo \"$ST_SPAWN_TEST_VAR\" >> \"$1\"; echo \"$2\" >> \"$1\"",
        )
        .unwrap();
        let script_name = std::ffi::CString::new("script").unwrap();
        let marker_arg = std::ffi::CString::new(marker.to_str().unwrap()).unwrap();
        let extra_arg = std::ffi::CString::new("hello-from-args").unwrap();
        let args = [
            arg0.as_ptr(),
            script.as_ptr(),
            script_name.as_ptr(),
            marker_arg.as_ptr(),
            extra_arg.as_ptr(),
        ];
        let cwd = std::ffi::CString::new(dir.to_str().unwrap()).unwrap();
        let env_key = std::ffi::CString::new("ST_SPAWN_TEST_VAR").unwrap();
        let env_value = std::ffi::CString::new("hello-from-env").unwrap();
        let env = [StSpawnEnvVar {
            key: env_key.as_ptr(),
            value: env_value.as_ptr(),
        }];

        let mut pid = 0u64;
        let rc = unsafe {
            st_spawn(
                path.as_ptr(),
                args.as_ptr(),
                args.len() as u32,
                cwd.as_ptr(),
                env.as_ptr(),
                1,
                ST_SPAWN_DETACHED,
                &mut pid,
            )
        };
        assert_eq!(rc, ST_OK, "st_spawn failed: {rc}");
        assert!(pid > 0);

        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
        while !marker.exists() {
            assert!(
                std::time::Instant::now() < deadline,
                "spawned process never ran"
            );
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        // Give the child a moment past the marker's creation to finish its
        // last two writes (it's created by the first `>`, before the two
        // `>>` appends).
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        let mut lines: Vec<String>;
        loop {
            lines = std::fs::read_to_string(&marker)
                .unwrap()
                .lines()
                .map(str::to_owned)
                .collect();
            if lines.len() >= 3 || std::time::Instant::now() >= deadline {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        assert_eq!(lines.len(), 3, "{lines:?}");
        // `/bin/sh` may resolve a symlinked temp dir (e.g. macOS's /tmp ->
        // /private/tmp), so compare canonicalized paths.
        assert_eq!(
            std::fs::canonicalize(&lines[0]).unwrap(),
            std::fs::canonicalize(&dir).unwrap()
        );
        assert_eq!(lines[1], "hello-from-env");
        assert_eq!(lines[2], "hello-from-args");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[cfg(unix)]
    #[test]
    fn spawn_reports_exec_failure() {
        let path = std::ffi::CString::new("/no/such/executable-st-spawn-test").unwrap();
        let mut pid = 0u64;
        let rc = unsafe {
            st_spawn(
                path.as_ptr(),
                std::ptr::null(),
                0,
                std::ptr::null(),
                std::ptr::null(),
                0,
                0,
                &mut pid,
            )
        };
        // ENOENT: the self-pipe/CLOEXEC trick in sys::unix::spawn lets this
        // observe the grandchild's execve failing, not just that fork()
        // itself succeeded.
        assert_eq!(rc, libc::ENOENT, "st_spawn returned: {rc}");
    }
}
