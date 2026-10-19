//! JNI entry points for the Java package
//! (`io.github.lesterkaufungen.suggestedtests.internal.NativeBridge`).
//!
//! Same functions and status codes as the C ABI. Struct results are written to
//! a caller-allocated `long[]`, so no Java objects are created here. JNI
//! functions are reached through the `JNIEnv` table, not by symbol, so these
//! exports add no link-time dependency: Dart, Python and PHP can still load
//! the library without a JVM.
//!
//! Keep in sync with `packages/java/src/main/java/.../internal/NativeBridge.java`.

use crate::{
    st_abi_version, st_cpu_count, st_memory_usage, st_on_load, st_process_cpu_time,
    st_thread_cpu_time_ns, StCpuTime, StMemory, ST_ERR_NULL, ST_ERR_UNKNOWN, ST_OK,
};
use jni_sys::{jclass, jint, jlong, jlongArray, JNIEnv};

/// Writes `values` to the start of `array`. Returns a status code.
///
/// # Safety
/// `env` must be the `JNIEnv` of the calling thread; `array` a local reference
/// or null.
unsafe fn write_longs<const N: usize>(
    env: *mut JNIEnv,
    array: jlongArray,
    values: [u64; N],
) -> jint {
    if env.is_null() || (*env).is_null() || array.is_null() {
        return ST_ERR_NULL;
    }
    let table = &**env;
    let (Some(length), Some(set_region)) = (table.GetArrayLength, table.SetLongArrayRegion) else {
        return ST_ERR_UNKNOWN;
    };
    if (length(env, array) as usize) < N {
        return ST_ERR_NULL;
    }
    // Every value is a duration in ns or a byte count: far below i64::MAX.
    let longs = values.map(|v| v as jlong);
    set_region(env, array, 0, N as jint, longs.as_ptr());
    ST_OK
}

/// `static native int abiVersion()`
#[no_mangle]
pub extern "system" fn Java_io_github_lesterkaufungen_suggestedtests_internal_NativeBridge_abiVersion(
    _env: *mut JNIEnv,
    _class: jclass,
) -> jint {
    st_abi_version() as jint
}

/// `static native void onLoad()`: `st_on_load`.
#[no_mangle]
pub extern "system" fn Java_io_github_lesterkaufungen_suggestedtests_internal_NativeBridge_onLoad(
    _env: *mut JNIEnv,
    _class: jclass,
) {
    st_on_load();
}

/// `static native int processCpuTime(long[] out)`: `out = {userNs, systemNs}`.
///
/// # Safety
/// Called by the JVM with a valid `env`.
#[no_mangle]
pub unsafe extern "system" fn Java_io_github_lesterkaufungen_suggestedtests_internal_NativeBridge_processCpuTime(
    env: *mut JNIEnv,
    _class: jclass,
    out: jlongArray,
) -> jint {
    let mut t = StCpuTime::default();
    match st_process_cpu_time(&mut t) {
        ST_OK => write_longs(env, out, [t.user_ns, t.system_ns]),
        status => status,
    }
}

/// `static native int threadCpuTimeNs(long[] out)`: `out = {ns}`.
///
/// # Safety
/// Called by the JVM with a valid `env`.
#[no_mangle]
pub unsafe extern "system" fn Java_io_github_lesterkaufungen_suggestedtests_internal_NativeBridge_threadCpuTimeNs(
    env: *mut JNIEnv,
    _class: jclass,
    out: jlongArray,
) -> jint {
    let mut ns = 0u64;
    match st_thread_cpu_time_ns(&mut ns) {
        ST_OK => write_longs(env, out, [ns]),
        status => status,
    }
}

/// `static native int memoryUsage(long[] out)`: `out = {currentRss, peakRss}`.
///
/// # Safety
/// Called by the JVM with a valid `env`.
#[no_mangle]
pub unsafe extern "system" fn Java_io_github_lesterkaufungen_suggestedtests_internal_NativeBridge_memoryUsage(
    env: *mut JNIEnv,
    _class: jclass,
    out: jlongArray,
) -> jint {
    let mut m = StMemory::default();
    match st_memory_usage(&mut m) {
        ST_OK => write_longs(env, out, [m.current_rss_bytes, m.peak_rss_bytes]),
        status => status,
    }
}

/// `static native int cpuCount()`
#[no_mangle]
pub extern "system" fn Java_io_github_lesterkaufungen_suggestedtests_internal_NativeBridge_cpuCount(
    _env: *mut JNIEnv,
    _class: jclass,
) -> jint {
    st_cpu_count().min(i32::MAX as u32) as jint
}

/// `static native int setVerbose(int verbose)`: `st_set_verbose`.
#[no_mangle]
pub extern "system" fn Java_io_github_lesterkaufungen_suggestedtests_internal_NativeBridge_setVerbose(
    _env: *mut JNIEnv,
    _class: jclass,
    verbose: jint,
) -> jint {
    crate::report::st_set_verbose(verbose as u32) as jint
}

/// `static native int verbose()`: `st_verbose`.
#[no_mangle]
pub extern "system" fn Java_io_github_lesterkaufungen_suggestedtests_internal_NativeBridge_verbose(
    _env: *mut JNIEnv,
    _class: jclass,
) -> jint {
    crate::report::st_verbose() as jint
}
