//! Calls shared by every POSIX system (Linux, macOS, BSDs).

use crate::{SpawnRequest, StCpuTime, ST_ERR_INVALID, ST_ERR_UNKNOWN, ST_SPAWN_DETACHED};
use std::ffi::CString;

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

/// Writes `tag` then `value` as 16 raw bytes, retrying on `EINTR` and on a
/// short write. Used across `fork()`, so no allocation: fixed-size buffer,
/// raw `write(2)` only.
fn write_message(fd: libc::c_int, tag: i64, value: i64) {
    let mut buf = [0u8; 16];
    buf[..8].copy_from_slice(&tag.to_ne_bytes());
    buf[8..].copy_from_slice(&value.to_ne_bytes());
    let mut remaining = &buf[..];
    while !remaining.is_empty() {
        // SAFETY: `remaining` points into `buf`, live for this call.
        let n = unsafe {
            libc::write(
                fd,
                remaining.as_ptr().cast(),
                remaining.len() as libc::size_t,
            )
        };
        if n > 0 {
            remaining = &remaining[n as usize..];
        } else if n < 0 && last_errno() == libc::EINTR {
            continue;
        } else {
            return; // Reader sees a short/absent message as ST_ERR_UNKNOWN.
        }
    }
}

/// Reads back a [`write_message`]; `None` on EOF or a short read (the writer
/// died before finishing).
fn read_message(fd: libc::c_int) -> Option<(i64, i64)> {
    let mut buf = [0u8; 16];
    let mut filled = 0usize;
    while filled < buf.len() {
        // SAFETY: `buf[filled..]` is live, writable memory of the given length.
        let n = unsafe {
            libc::read(
                fd,
                buf[filled..].as_mut_ptr().cast(),
                (buf.len() - filled) as libc::size_t,
            )
        };
        if n > 0 {
            filled += n as usize;
        } else if n < 0 && last_errno() == libc::EINTR {
            continue;
        } else {
            return None;
        }
    }
    let tag = i64::from_ne_bytes(buf[..8].try_into().ok()?);
    let value = i64::from_ne_bytes(buf[8..].try_into().ok()?);
    Some((tag, value))
}

/// Sets `FD_CLOEXEC` so the fd closes itself on a successful `execve` --
/// the only way the reader on the other end can tell exec succeeded, since
/// no code of ours runs afterwards to say so.
fn set_cloexec(fd: libc::c_int) -> Result<(), i32> {
    // SAFETY: `fd` is a just-created, still-open descriptor.
    if unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) } < 0 {
        return Err(last_errno());
    }
    Ok(())
}

/// Spawns `req` as a new process, reparented away from this one via a double
/// `fork()`: the middle child exits as soon as it has forked the grandchild,
/// so `init` (not this process) ends up reaping the grandchild. [`st_spawn`]
/// never waits on anything, so skipping this would leave a zombie behind
/// every single call.
///
/// [`crate::ST_SPAWN_DETACHED`] additionally makes the grandchild a session
/// leader (`setsid`), detached from any controlling terminal.
///
/// A second, `CLOEXEC` pipe reports back whether `execve` itself succeeded:
/// the grandchild writes its errno and exits if `execve` fails, and its copy
/// of the write end closes itself (by `CLOEXEC`) if `execve` succeeds, which
/// is the only way this function learns which happened.
///
/// [`st_spawn`]: crate::st_spawn
pub fn spawn(req: &SpawnRequest) -> Result<u64, i32> {
    // Build every C string up front: fork() only duplicates the calling
    // thread, so the children below must not allocate (another thread could
    // be mid-`malloc`, holding a lock that would never unlock in the child).
    let path = CString::new(req.path.as_bytes()).map_err(|_| ST_ERR_INVALID)?;
    let mut argv_owned = Vec::with_capacity(req.args.len() + 1);
    argv_owned.push(path.clone());
    for arg in &req.args {
        argv_owned.push(CString::new(arg.as_bytes()).map_err(|_| ST_ERR_INVALID)?);
    }
    let mut argv: Vec<*const libc::c_char> = argv_owned.iter().map(|s| s.as_ptr()).collect();
    argv.push(std::ptr::null());

    let cwd = req
        .cwd
        .as_deref()
        .map(|c| CString::new(c.as_bytes()))
        .transpose()
        .map_err(|_| ST_ERR_INVALID)?;

    let mut env_map: Vec<(String, String)> = std::env::vars().collect();
    for (key, value) in &req.env {
        match env_map.iter_mut().find(|(k, _)| k == key) {
            Some(existing) => existing.1 = value.clone(),
            None => env_map.push((key.clone(), value.clone())),
        }
    }
    let envp_owned: Vec<CString> = env_map
        .iter()
        .map(|(k, v)| CString::new(format!("{k}={v}")))
        .collect::<Result<_, _>>()
        .map_err(|_| ST_ERR_INVALID)?;
    let mut envp: Vec<*const libc::c_char> = envp_owned.iter().map(|s| s.as_ptr()).collect();
    envp.push(std::ptr::null());

    let detached = req.flags & ST_SPAWN_DETACHED != 0;
    let path_ptr = path.as_ptr();
    let argv_ptr = argv.as_ptr();
    let envp_ptr = envp.as_ptr();
    let cwd_ptr = cwd.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());

    let mut pid_fds = [0i32; 2];
    // SAFETY: `pid_fds` is a live, writable 2-element array.
    if unsafe { libc::pipe(pid_fds.as_mut_ptr()) } != 0 {
        return Err(last_errno());
    }
    let (pid_read, pid_write) = (pid_fds[0], pid_fds[1]);

    let mut err_fds = [0i32; 2];
    // SAFETY: `err_fds` is a live, writable 2-element array.
    if unsafe { libc::pipe(err_fds.as_mut_ptr()) } != 0 {
        let err = last_errno();
        // SAFETY: both fds were just opened by `pipe` above.
        unsafe {
            libc::close(pid_read);
            libc::close(pid_write);
        }
        return Err(err);
    }
    let (err_read, err_write) = (err_fds[0], err_fds[1]);
    if let Err(err) = set_cloexec(err_write) {
        // SAFETY: all four fds were just opened by `pipe` above.
        unsafe {
            libc::close(pid_read);
            libc::close(pid_write);
            libc::close(err_read);
            libc::close(err_write);
        }
        return Err(err);
    }

    // SAFETY: fork() has no preconditions; it duplicates this thread only.
    let mid_pid = unsafe { libc::fork() };
    if mid_pid < 0 {
        let err = last_errno();
        // SAFETY: all four fds were just opened by `pipe` above.
        unsafe {
            libc::close(pid_read);
            libc::close(pid_write);
            libc::close(err_read);
            libc::close(err_write);
        }
        return Err(err);
    }
    if mid_pid == 0 {
        // Middle (and then grand-) child: from here to `_exit`, only
        // async-signal-safe calls (no allocation, no locks, no panics) --
        // this thread may be holding a lock another thread held at fork time.
        // SAFETY: every fd here is this process' own, just-opened pipe end;
        // `path_ptr`/`argv_ptr`/`envp_ptr`/`cwd_ptr` were built above and
        // outlive this block (the parent is blocked in `waitpid`/`read`).
        unsafe {
            libc::close(pid_read);
            libc::close(err_read);
            if detached {
                libc::setsid();
            }
            let grandchild = libc::fork();
            if grandchild != 0 {
                libc::close(err_write);
                let (tag, value) = if grandchild > 0 {
                    (0i64, i64::from(grandchild))
                } else {
                    (1i64, i64::from(last_errno()))
                };
                write_message(pid_write, tag, value);
                libc::close(pid_write);
                libc::_exit(0);
            }
            libc::close(pid_write);
            let devnull = libc::open(c"/dev/null".as_ptr(), libc::O_RDWR);
            if devnull >= 0 {
                libc::dup2(devnull, 0);
                libc::dup2(devnull, 1);
                libc::dup2(devnull, 2);
                if devnull > 2 {
                    libc::close(devnull);
                }
            }
            if !cwd_ptr.is_null() {
                libc::chdir(cwd_ptr);
            }
            libc::execve(path_ptr, argv_ptr, envp_ptr);
            // execve failed: report it, then give up. `err_write` closes
            // itself (CLOEXEC) on a *successful* execve, which never
            // reaches this line.
            write_message(err_write, 1, i64::from(last_errno()));
            libc::close(err_write);
            libc::_exit(127);
        }
    }

    // Original process: the middle child exits immediately above, so this
    // reaps it without waiting on the (possibly long-lived) grandchild.
    // SAFETY: both fds were opened by `pipe` above and are unused on this
    // side (only a child ever writes to either pipe).
    unsafe {
        libc::close(pid_write);
        libc::close(err_write);
    }
    let mut status = 0i32;
    loop {
        // SAFETY: `mid_pid` is this process' own direct child.
        let rc = unsafe { libc::waitpid(mid_pid, &mut status, 0) };
        if rc >= 0 || last_errno() != libc::EINTR {
            break;
        }
    }
    let pid_message = read_message(pid_read);
    // SAFETY: `pid_read` was opened by `pipe` above.
    unsafe { libc::close(pid_read) };
    let pid = match pid_message {
        Some((0, pid)) if pid > 0 => pid,
        Some((_, code)) => {
            // SAFETY: `err_read` was opened by `pipe` above.
            unsafe { libc::close(err_read) };
            return Err(code as i32);
        }
        None => {
            // SAFETY: `err_read` was opened by `pipe` above.
            unsafe { libc::close(err_read) };
            return Err(ST_ERR_UNKNOWN);
        }
    };

    // Blocks until the grandchild either execs (closing its `CLOEXEC`
    // copy of `err_write`, so this reads EOF) or fails and reports why;
    // either is essentially instant.
    let exec_result = read_message(err_read);
    // SAFETY: `err_read` was opened by `pipe` above.
    unsafe { libc::close(err_read) };
    match exec_result {
        None => Ok(pid as u64),
        Some((_, code)) => Err(code as i32),
    }
}

/// The kernel release from `uname(2)`, e.g. "6.8.0-45-generic".
pub fn kernel_release() -> Option<String> {
    // SAFETY: utsname is plain old data; uname fills it on success.
    let mut u: libc::utsname = unsafe { std::mem::zeroed() };
    if unsafe { libc::uname(&mut u) } != 0 {
        return None;
    }
    // SAFETY: uname NUL-terminates the fields.
    let release = unsafe { std::ffi::CStr::from_ptr(u.release.as_ptr()) };
    Some(release.to_string_lossy().into_owned())
}
