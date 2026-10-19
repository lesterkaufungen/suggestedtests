//! Runs code when the library is loaded, before any export is called.
//!
//! Every binding loads this library at runtime (`dlopen`, `LoadLibrary`,
//! `System.loadLibrary`, `FFI::cdef`, ctypes, Dart's native assets, purego),
//! and each OS calls the library's initializers while doing so:
//!
//! | Platform                                   | Mechanism                                        |
//! | ------------------------------------------ | ------------------------------------------------ |
//! | Linux, Android, FreeBSD (ELF; glibc, musl, bionic) | function pointer in `.init_array`        |
//! | macOS, iOS (Mach-O)                        | function pointer in `__DATA,__mod_init_func`     |
//! | Windows (PE, MSVC CRT)                     | function pointer in `.CRT$XCU`, run by the CRT's `_DllMainCRTStartup` |
//! | anything else                              | none: [`ensure`] runs them on first use instead  |
//!
//! [`ensure`] is also called by `st_abi_version`, which every binding calls
//! first, so initializers run exactly once on every platform even where the
//! loader hook is missing; [`state`] (exported as `st_load_state`) tells
//! which way they ran, so tests can check the hook works on each target.
//!
//! # Rules for initializers
//!
//! They run inside the OS loader, under its lock (Windows' loader lock, glibc's
//! `dl_load_lock`), possibly before the host language's runtime is ready:
//!
//! * **never panic**: release builds abort on panic, which kills the host
//!   process while it is loading the library;
//! * don't start, join or wait for threads, and don't load other libraries
//!   (deadlocks on the loader lock);
//! * don't call back into the host language, don't read its state;
//! * keep them short: they delay every test run's first call into the bridge.
//!
//! Add an initializer by appending it to [`INITIALIZERS`].
//!
//! After the initializers, the hook prints the startup report
//! ([`crate::report`]) if the caller turned verbose on with
//! `SUGGESTEDTESTS_VERBOSE=1` before loading the library. With verbose off
//! (the default) nothing is printed.

use std::sync::atomic::{AtomicU32, Ordering};

/// Initializers not run (yet).
pub const ST_LOAD_NOT_RUN: u32 = 0;
/// Initializers ran from the OS loader hook while the library was loaded.
pub const ST_LOAD_AT_LOAD: u32 = 1;
/// No loader hook ran (unsupported platform, or the hook was stripped);
/// initializers ran on the first call to `st_abi_version` instead.
pub const ST_LOAD_LAZY: u32 = 2;

/// The functions run once, in order, when the library is loaded. See the
/// module docs for what they may do.
const INITIALIZERS: &[fn()] = &[];

/// 0 = not started, 1 = running, 2 = done. A plain atomic rather than
/// `std::sync::Once`: it works before anything else in the library and never
/// blocks inside the loader.
static PROGRESS: AtomicU32 = AtomicU32::new(0);
static STATE: AtomicU32 = AtomicU32::new(ST_LOAD_NOT_RUN);

fn run(how: u32) {
    if PROGRESS
        .compare_exchange(0, 1, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        // Already done, or another thread is running them. The loader hook
        // runs before any other thread can call into the library, so only a
        // lazy call can race with another lazy call; it may return early and
        // see initializers still running, which they tolerate.
        return;
    }
    crate::report::init_from_env();
    for init in INITIALIZERS {
        init();
    }
    STATE.store(how, Ordering::Release);
    PROGRESS.store(2, Ordering::Release);
    crate::report::at_startup(how == ST_LOAD_AT_LOAD);
}

/// Runs the initializers if no loader hook did. Cheap after the first call.
#[inline]
pub fn ensure() {
    if PROGRESS.load(Ordering::Acquire) == 0 {
        run(ST_LOAD_LAZY);
    }
}

/// How the initializers ran: `ST_LOAD_*`.
pub fn state() -> u32 {
    STATE.load(Ordering::Acquire)
}

/// The loader hook. `extern "C"` with no parameters: ELF and Mach-O pass
/// `(argc, argv, envp, ...)` on some systems, which the C calling convention
/// lets a function ignore.
extern "C" fn on_load() {
    run(ST_LOAD_AT_LOAD);
}

#[cfg(any(
    target_os = "linux",
    target_os = "android",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd",
    target_os = "dragonfly",
    target_os = "illumos",
    target_os = "solaris"
))]
#[used]
#[link_section = ".init_array"]
static ON_LOAD: extern "C" fn() = on_load;

#[cfg(target_vendor = "apple")]
#[used]
#[link_section = "__DATA,__mod_init_func"]
static ON_LOAD: extern "C" fn() = on_load;

// `.CRT$XCU`: the MSVC CRT's C++ dynamic initializers, which its DLL entry
// point (`_DllMainCRTStartup`, linked statically with +crt-static) runs on
// DLL_PROCESS_ATTACH. The `$XCU` suffix sorts after the CRT's own `$XCA`.
#[cfg(all(windows, target_env = "msvc"))]
#[used]
#[link_section = ".CRT$XCU"]
static ON_LOAD: extern "C" fn() = on_load;

/// How the initializers ran: `ST_LOAD_NOT_RUN` (0), `ST_LOAD_AT_LOAD` (1)
/// or `ST_LOAD_LAZY` (2). Doesn't run them itself.
#[no_mangle]
pub extern "C" fn st_load_state() -> u32 {
    state()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ran_from_the_loader_hook() {
        // The test binary links this crate statically, so its own
        // `.init_array` / `__mod_init_func` / `.CRT$XCU` entry ran at start-up.
        let supported = cfg!(any(
            target_os = "linux",
            target_os = "android",
            target_os = "freebsd",
            target_vendor = "apple",
            all(windows, target_env = "msvc")
        ));
        if supported {
            assert_eq!(st_load_state(), ST_LOAD_AT_LOAD);
        }
    }

    #[test]
    fn ensure_is_idempotent() {
        ensure();
        let before = state();
        ensure();
        assert_eq!(state(), before);
        assert_ne!(state(), ST_LOAD_NOT_RUN);
        assert_eq!(PROGRESS.load(Ordering::Acquire), 2);
    }
}
