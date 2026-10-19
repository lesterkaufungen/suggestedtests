//! Node-API addon for the `suggestedtests` npm package.
//!
//! Exposes the C ABI of `suggestedtests_native` to JavaScript with the same
//! status codes. Struct results go into a caller-allocated `BigUint64Array`:
//!
//! ```js
//! const out = new BigUint64Array(2);
//! if (addon.processCpuTime(out) === 0) console.log(out[0], out[1]);
//! ```
//!
//! The `napi_*` functions are looked up in the host process when the module
//! is registered (`dlsym(RTLD_DEFAULT)` / `GetProcAddress` on the executable)
//! instead of being linked. The addon therefore needs no `node.lib` import
//! library on Windows nor `-undefined dynamic_lookup` on macOS, and builds
//! with the same cross toolchains as the core library.
//!
//! Keep in sync with `packages/js/src/native.ts`.

use std::ffi::{c_char, c_void};
use std::sync::OnceLock;

use suggestedtests_native::report::{st_set_verbose, st_verbose};
use suggestedtests_native::{
    st_abi_version, st_cpu_count, st_memory_usage, st_on_load, st_process_cpu_time,
    st_thread_cpu_time_ns, StCpuTime, StMemory, ST_ERR_NULL, ST_OK,
};

type Env = *mut c_void;
type Value = *mut c_void;
type CallbackInfo = *mut c_void;
type Status = i32;
type Callback = unsafe extern "C" fn(Env, CallbackInfo) -> Value;

const NAPI_OK: Status = 0;
const NAPI_BIGUINT64_ARRAY: i32 = 10;

type CreateUint32 = unsafe extern "C" fn(Env, u32, *mut Value) -> Status;
type CreateInt32 = unsafe extern "C" fn(Env, i32, *mut Value) -> Status;
type GetValueUint32 = unsafe extern "C" fn(Env, Value, *mut u32) -> Status;
type CreateFunction =
    unsafe extern "C" fn(Env, *const c_char, usize, Callback, *mut c_void, *mut Value) -> Status;
type SetNamedProperty = unsafe extern "C" fn(Env, Value, *const c_char, Value) -> Status;
type GetCbInfo = unsafe extern "C" fn(
    Env,
    CallbackInfo,
    *mut usize,
    *mut Value,
    *mut Value,
    *mut *mut c_void,
) -> Status;
type GetTypedarrayInfo = unsafe extern "C" fn(
    Env,
    Value,
    *mut i32,
    *mut usize,
    *mut *mut c_void,
    *mut Value,
    *mut usize,
) -> Status;

/// The subset of Node-API this addon uses.
struct Napi {
    create_uint32: CreateUint32,
    create_int32: CreateInt32,
    get_value_uint32: GetValueUint32,
    create_function: CreateFunction,
    set_named_property: SetNamedProperty,
    get_cb_info: GetCbInfo,
    get_typedarray_info: GetTypedarrayInfo,
}

static NAPI: OnceLock<Option<Napi>> = OnceLock::new();

#[cfg(unix)]
fn lookup(name: &[u8]) -> *mut c_void {
    debug_assert_eq!(name.last(), Some(&0));
    // SAFETY: `name` is NUL-terminated; RTLD_DEFAULT searches the process.
    unsafe { libc::dlsym(libc::RTLD_DEFAULT, name.as_ptr().cast()) }
}

#[cfg(windows)]
fn lookup(name: &[u8]) -> *mut c_void {
    use windows_sys::Win32::System::LibraryLoader::{GetModuleHandleW, GetProcAddress};
    debug_assert_eq!(name.last(), Some(&0));
    // SAFETY: a null module name returns the executable (node.exe), which
    // exports Node-API; `name` is NUL-terminated.
    unsafe {
        let host = GetModuleHandleW(std::ptr::null());
        if host.is_null() {
            return std::ptr::null_mut();
        }
        GetProcAddress(host, name.as_ptr()).map_or(std::ptr::null_mut(), |f| f as *mut c_void)
    }
}

macro_rules! resolve {
    ($name:literal as $ty:ty) => {{
        let f = lookup(concat!($name, "\0").as_bytes());
        if f.is_null() {
            return None;
        }
        // SAFETY: the symbol is the Node-API function of that name, whose C
        // signature matches the field it is assigned to.
        unsafe { std::mem::transmute::<*mut c_void, $ty>(f) }
    }};
}

fn load_napi() -> Option<Napi> {
    Some(Napi {
        create_uint32: resolve!("napi_create_uint32" as CreateUint32),
        create_int32: resolve!("napi_create_int32" as CreateInt32),
        get_value_uint32: resolve!("napi_get_value_uint32" as GetValueUint32),
        create_function: resolve!("napi_create_function" as CreateFunction),
        set_named_property: resolve!("napi_set_named_property" as SetNamedProperty),
        get_cb_info: resolve!("napi_get_cb_info" as GetCbInfo),
        get_typedarray_info: resolve!("napi_get_typedarray_info" as GetTypedarrayInfo),
    })
}

fn napi() -> &'static Napi {
    // Only reachable from callbacks registered after a successful load.
    NAPI.get()
        .and_then(Option::as_ref)
        .unwrap_or_else(|| std::process::abort())
}

/// Returns `status` as a JS number.
unsafe fn int32(env: Env, status: i32) -> Value {
    let mut result = std::ptr::null_mut();
    (napi().create_int32)(env, status, &mut result);
    result
}

/// Copies `values` into the `BigUint64Array` passed as the first argument.
unsafe fn write_out(env: Env, info: CallbackInfo, values: &[u64]) -> i32 {
    let n = napi();
    let mut argc = 1usize;
    let mut arg = std::ptr::null_mut();
    if (n.get_cb_info)(
        env,
        info,
        &mut argc,
        &mut arg,
        std::ptr::null_mut(),
        std::ptr::null_mut(),
    ) != NAPI_OK
        || argc < 1
    {
        return ST_ERR_NULL;
    }
    let (mut kind, mut length, mut data) = (0i32, 0usize, std::ptr::null_mut());
    if (n.get_typedarray_info)(
        env,
        arg,
        &mut kind,
        &mut length,
        &mut data,
        std::ptr::null_mut(),
        std::ptr::null_mut(),
    ) != NAPI_OK
        || kind != NAPI_BIGUINT64_ARRAY
        || length < values.len()
        || data.is_null()
    {
        return ST_ERR_NULL;
    }
    let out = data.cast::<u64>();
    for (i, &v) in values.iter().enumerate() {
        out.add(i).write_unaligned(v);
    }
    ST_OK
}

unsafe extern "C" fn abi_version(env: Env, _info: CallbackInfo) -> Value {
    let mut result = std::ptr::null_mut();
    (napi().create_uint32)(env, st_abi_version(), &mut result);
    result
}

/// `onLoad(): number`: `st_on_load`, returning `ST_OK` (there's no failure
/// mode to report).
unsafe extern "C" fn on_load(env: Env, _info: CallbackInfo) -> Value {
    st_on_load();
    int32(env, ST_OK)
}

unsafe extern "C" fn process_cpu_time(env: Env, info: CallbackInfo) -> Value {
    let mut t = StCpuTime::default();
    let status = match st_process_cpu_time(&mut t) {
        ST_OK => write_out(env, info, &[t.user_ns, t.system_ns]),
        status => status,
    };
    int32(env, status)
}

unsafe extern "C" fn thread_cpu_time_ns(env: Env, info: CallbackInfo) -> Value {
    let mut ns = 0u64;
    let status = match st_thread_cpu_time_ns(&mut ns) {
        ST_OK => write_out(env, info, &[ns]),
        status => status,
    };
    int32(env, status)
}

unsafe extern "C" fn memory_usage(env: Env, info: CallbackInfo) -> Value {
    let mut m = StMemory::default();
    let status = match st_memory_usage(&mut m) {
        ST_OK => write_out(env, info, &[m.current_rss_bytes, m.peak_rss_bytes]),
        status => status,
    };
    int32(env, status)
}

unsafe extern "C" fn cpu_count(env: Env, _info: CallbackInfo) -> Value {
    let mut result = std::ptr::null_mut();
    (napi().create_uint32)(env, st_cpu_count(), &mut result);
    result
}

unsafe fn uint32(env: Env, value: u32) -> Value {
    let mut result = std::ptr::null_mut();
    (napi().create_uint32)(env, value, &mut result);
    result
}

/// `setVerbose(verbose: number): number`: `st_set_verbose`. A missing or
/// non-number argument counts as 0.
unsafe extern "C" fn set_verbose(env: Env, info: CallbackInfo) -> Value {
    let n = napi();
    let (mut argc, mut arg, mut verbose) = (1usize, std::ptr::null_mut(), 0u32);
    if (n.get_cb_info)(
        env,
        info,
        &mut argc,
        &mut arg,
        std::ptr::null_mut(),
        std::ptr::null_mut(),
    ) != NAPI_OK
        || argc < 1
        || (n.get_value_uint32)(env, arg, &mut verbose) != NAPI_OK
    {
        verbose = 0;
    }
    uint32(env, st_set_verbose(verbose))
}

unsafe extern "C" fn verbose(env: Env, _info: CallbackInfo) -> Value {
    uint32(env, st_verbose())
}

/// Called by Node.js when the addon is loaded. Leaves `exports` empty if
/// Node-API cannot be found; the JS side reports that as unavailable.
///
/// # Safety
/// Called by Node.js with a valid `env` and `exports` object.
#[no_mangle]
pub unsafe extern "C" fn napi_register_module_v1(env: Env, exports: Value) -> Value {
    let Some(n) = NAPI.get_or_init(load_napi) else {
        return exports;
    };
    let functions: [(&[u8], Callback); 8] = [
        (b"abiVersion\0", abi_version),
        (b"onLoad\0", on_load),
        (b"processCpuTime\0", process_cpu_time),
        (b"threadCpuTimeNs\0", thread_cpu_time_ns),
        (b"memoryUsage\0", memory_usage),
        (b"cpuCount\0", cpu_count),
        (b"setVerbose\0", set_verbose),
        (b"verbose\0", verbose),
    ];
    for (name, callback) in functions {
        let mut function = std::ptr::null_mut();
        let name = name.as_ptr().cast::<c_char>();
        // NAPI_AUTO_LENGTH: the name is NUL-terminated.
        if (n.create_function)(
            env,
            name,
            usize::MAX,
            callback,
            std::ptr::null_mut(),
            &mut function,
        ) == NAPI_OK
        {
            (n.set_named_property)(env, exports, name, function);
        }
    }
    exports
}
