//! Using `st_spawn` from Rust: the same patterns every other binding's FFI
//! layer (ctypes, JNI, Node-API, `dlopen`, `@Native`...) follows to call the
//! same `extern "C"` function from the cdylib.
//!
//! ```sh
//! cargo run --example process
//! ```
//!
//! Two snippets: the thinnest possible call, and a call using every
//! parameter (args, cwd, env, flags). `st_spawn` never resolves `path`
//! against `PATH` (like `execve`, not `execvp`) and never waits on the
//! child -- see `native/src/lib.rs` and `native/src/sys/unix.rs`/`windows.rs`
//! for the full contract and why.

use std::ffi::CString;
use std::os::raw::c_char;
#[cfg(windows)]
use suggestedtests_native::ST_SPAWN_NO_WINDOW;
use suggestedtests_native::{st_abi_version, st_spawn, StSpawnEnvVar, ST_OK, ST_SPAWN_DETACHED};

/// Snippet 1: the thinnest possible call -- no args, no cwd override, no
/// extra env, no flags. Every binding's simplest wrapper looks like this:
/// one C string in, one status code and one PID out.
fn spawn_plain(path: &str) -> Result<u64, i32> {
    let path = CString::new(path).expect("path has no interior NUL");
    let mut pid = 0u64;
    // SAFETY: `path` is NUL-terminated; every other pointer is null with a
    // matching zero length (meaning "none"); `out_pid` is a live `u64`.
    let status = unsafe {
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
    if status == ST_OK {
        Ok(pid)
    } else {
        Err(status)
    }
}

/// Snippet 2: every parameter. `args` excludes `path` itself (`path` is
/// always argv[0], like `execve`). The pattern here -- build owned
/// `CString`s first, then collect their `.as_ptr()`s into the arrays the C
/// ABI wants -- is exactly what a ctypes/JNI/Node-API layer does too; the
/// only rule is that the owned strings must outlive the `st_spawn` call.
fn spawn_with_args_cwd_env(
    path: &str,
    args: &[&str],
    cwd: Option<&str>,
    env: &[(&str, &str)],
    flags: u32,
) -> Result<u64, i32> {
    let path_c = CString::new(path).expect("path has no interior NUL");
    let args_c: Vec<CString> = args
        .iter()
        .map(|a| CString::new(*a).expect("arg has no interior NUL"))
        .collect();
    let arg_ptrs: Vec<*const c_char> = args_c.iter().map(|a| a.as_ptr()).collect();

    let cwd_c = cwd.map(|c| CString::new(c).expect("cwd has no interior NUL"));

    // StSpawnEnvVar only borrows; the CStrings it points into must live
    // until the st_spawn call below, hence two separate Vecs.
    let env_c: Vec<(CString, CString)> = env
        .iter()
        .map(|(k, v)| {
            (
                CString::new(*k).expect("env key has no interior NUL"),
                CString::new(*v).expect("env value has no interior NUL"),
            )
        })
        .collect();
    let env_vars: Vec<StSpawnEnvVar> = env_c
        .iter()
        .map(|(k, v)| StSpawnEnvVar {
            key: k.as_ptr(),
            value: v.as_ptr(),
        })
        .collect();

    let mut pid = 0u64;
    // SAFETY: `arg_ptrs`/`env_vars` point to `arg_ptrs.len()`/`env_vars.len()`
    // elements, each a NUL-terminated C string kept alive (via `args_c`/
    // `env_c`) until this call returns; `cwd_c` is null only when `cwd` was
    // `None`; `out_pid` is a live `u64`.
    let status = unsafe {
        st_spawn(
            path_c.as_ptr(),
            arg_ptrs.as_ptr(),
            arg_ptrs.len() as u32,
            cwd_c.as_ref().map_or(std::ptr::null(), |c| c.as_ptr()),
            env_vars.as_ptr(),
            env_vars.len() as u32,
            flags,
            &mut pid,
        )
    };
    if status == ST_OK {
        Ok(pid)
    } else {
        Err(status)
    }
}

fn main() {
    // Like every binding, call this first: it runs the load-time
    // initializers where no loader hook did.
    println!("ABI v{}", st_abi_version());

    #[cfg(unix)]
    {
        println!("\n-- snippet 1: spawn_plain --");
        match spawn_plain("/bin/true") {
            Ok(pid) => println!("pid {pid}"),
            Err(code) => println!("failed: {code}"),
        }

        println!("\n-- snippet 2: spawn_with_args_cwd_env --");
        let dir = std::env::temp_dir().join("st_spawn_example");
        std::fs::create_dir_all(&dir).expect("create example dir");
        let marker = dir.join("marker");
        let result = spawn_with_args_cwd_env(
            "/bin/sh",
            &[
                "-c",
                "pwd > \"$1\"; echo \"$GREETING\" >> \"$1\"",
                "sh",                     // sh's $0
                marker.to_str().unwrap(), // sh's $1
            ],
            Some(dir.to_str().unwrap()),
            &[("GREETING", "hello from st_spawn")],
            // ST_SPAWN_NO_WINDOW is a no-op here (Windows only); passing it
            // on every platform, rather than `cfg`-gating it, is the point.
            ST_SPAWN_DETACHED,
        );
        match result {
            Ok(pid) => {
                println!("pid {pid}, writing to {}", marker.display());
                // Detached means this never waits on it; give the shell a
                // moment before reading the marker back for this demo.
                std::thread::sleep(std::time::Duration::from_millis(200));
                print!("{}", std::fs::read_to_string(&marker).unwrap_or_default());
            }
            Err(code) => println!("failed: {code}"),
        }
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[cfg(windows)]
    {
        println!("\n-- snippet 1: spawn_plain --");
        // st_spawn never resolves against PATH, so this needs the full path
        // even for a well-known system binary.
        match spawn_plain(r"C:\Windows\System32\cmd.exe") {
            Ok(pid) => println!("pid {pid}"),
            Err(code) => println!("failed: {code}"),
        }

        println!("\n-- snippet 2: spawn_with_args_cwd_env --");
        match spawn_with_args_cwd_env(
            r"C:\Windows\System32\cmd.exe",
            &["/C", "echo hello from st_spawn"],
            None,
            &[("GREETING", "hello from st_spawn")],
            // Detached + no console window: the common combination for a
            // helper process a GUI-less test run launches in the background.
            ST_SPAWN_DETACHED | ST_SPAWN_NO_WINDOW,
        ) {
            Ok(pid) => println!("pid {pid}"),
            Err(code) => println!("failed: {code}"),
        }
    }
}
