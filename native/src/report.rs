//! The startup report: what `st_platform` and `st_environment` say about this
//! process, printed once to stderr when the library is loaded, but only if
//! verbose is on. The verbose flag controls nothing else.
//!
//! Verbose is set by the caller:
//!
//! * before the library is loaded, with `SUGGESTEDTESTS_VERBOSE=1` (also
//!   `true`, `yes`, `on`); the loader hook in [`crate::load`] reads it, which
//!   is the only way to affect what happens *during* loading;
//! * after loading, with `st_set_verbose(1)` / `st_set_verbose(0)`. Turning it
//!   on prints the report then if it hasn't been printed yet; it is never
//!   printed twice.
//!
//! On ELF and Mach-O systems the report is printed from the loader hook. On
//! Windows it waits for the first `st_abi_version` call, which every binding
//! makes right after loading: gathering the environment reads the registry,
//! which must not be done under the loader lock.

use std::io::Write;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::environment::*;
use crate::platform::*;

/// Environment variable that turns verbose on before the library loads.
pub const VERBOSE_ENV_VAR: &str = "SUGGESTEDTESTS_VERBOSE";

static VERBOSE: AtomicBool = AtomicBool::new(false);
/// The report was printed (or claimed by a thread printing it).
static PRINTED: AtomicBool = AtomicBool::new(false);
/// The loader hook ran with verbose on, but printing had to wait (Windows).
static PENDING: AtomicBool = AtomicBool::new(false);

/// Whether an environment variable value means "on".
pub fn is_truthy(value: &str) -> bool {
    matches!(
        value.trim().to_ascii_lowercase().as_str(),
        "1" | "true" | "yes" | "on"
    )
}

/// Turns verbose on if [`VERBOSE_ENV_VAR`] says so. Called by the loader
/// hook; never turns it off, so an earlier `st_set_verbose(1)` (possible where
/// initializers run lazily) is kept.
pub(crate) fn init_from_env() {
    if std::env::var(VERBOSE_ENV_VAR).is_ok_and(|v| is_truthy(&v)) {
        VERBOSE.store(true, Ordering::Release);
    }
}

/// Called once by [`crate::load`] after the initializers. `from_loader` is
/// true when the OS loader hook is running.
pub(crate) fn at_startup(from_loader: bool) {
    if !VERBOSE.load(Ordering::Acquire) {
        return;
    }
    if from_loader && cfg!(windows) {
        PENDING.store(true, Ordering::Release);
        return;
    }
    print_once();
}

/// Prints a report deferred by [`at_startup`]. Called by `st_abi_version`.
#[inline]
pub(crate) fn flush_pending() {
    if PENDING.load(Ordering::Acquire) && PENDING.swap(false, Ordering::AcqRel) {
        print_once();
    }
}

fn print_once() {
    if PRINTED.swap(true, Ordering::AcqRel) {
        return;
    }
    // One write, so lines from several processes don't interleave; errors
    // (a closed stderr) are ignored: the report is best effort.
    let _ = std::io::stderr().write_all(report().as_bytes());
}

fn c_str(buf: &[u8]) -> &str {
    let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    std::str::from_utf8(&buf[..end]).unwrap_or("?")
}

/// `ST_OS_*` as a word.
pub fn os_name(os: u32) -> &'static str {
    match os {
        ST_OS_LINUX => "linux",
        ST_OS_MACOS => "macos",
        ST_OS_WINDOWS => "windows",
        ST_OS_ANDROID => "android",
        ST_OS_FREEBSD => "freebsd",
        ST_OS_IOS => "ios",
        _ => "unknown",
    }
}

/// `ST_ARCH_*` as a word.
pub fn arch_name(arch: u32) -> &'static str {
    match arch {
        ST_ARCH_X86_64 => "x86_64",
        ST_ARCH_AARCH64 => "aarch64",
        ST_ARCH_X86 => "x86",
        ST_ARCH_ARM => "arm",
        ST_ARCH_RISCV64 => "riscv64",
        ST_ARCH_PPC64LE => "ppc64le",
        ST_ARCH_S390X => "s390x",
        ST_ARCH_LOONGARCH64 => "loongarch64",
        _ => "unknown",
    }
}

/// `ST_LIBC_*` as a word.
pub fn libc_name(libc: u32) -> &'static str {
    match libc {
        ST_LIBC_GLIBC => "glibc",
        ST_LIBC_MUSL => "musl",
        ST_LIBC_BIONIC => "bionic",
        ST_LIBC_MSVC => "msvc",
        ST_LIBC_APPLE => "libSystem",
        ST_LIBC_BSD => "bsd libc",
        _ => "unknown",
    }
}

/// `ST_CONTAINER_*` as a word.
pub fn container_name(container: u32) -> &'static str {
    match container {
        ST_CONTAINER_NONE => "none",
        ST_CONTAINER_DOCKER => "docker",
        ST_CONTAINER_PODMAN => "podman",
        ST_CONTAINER_CONTAINERD => "containerd",
        ST_CONTAINER_CRIO => "cri-o",
        ST_CONTAINER_LXC => "lxc",
        ST_CONTAINER_NSPAWN => "systemd-nspawn",
        ST_CONTAINER_OPENVZ => "openvz",
        ST_CONTAINER_WINDOWS => "windows container",
        _ => "unknown runtime",
    }
}

/// `ST_VM_*` as a word.
pub fn vm_name(vm: u32) -> &'static str {
    match vm {
        ST_VM_NONE => "none",
        ST_VM_KVM => "kvm",
        ST_VM_QEMU => "qemu",
        ST_VM_VMWARE => "vmware",
        ST_VM_VIRTUALBOX => "virtualbox",
        ST_VM_HYPERV => "hyper-v",
        ST_VM_XEN => "xen",
        ST_VM_PARALLELS => "parallels",
        ST_VM_BHYVE => "bhyve",
        ST_VM_APPLE => "apple virtualization",
        ST_VM_NITRO => "aws nitro",
        _ => "unknown hypervisor",
    }
}

/// `ST_KIND_*` as a word.
pub fn kind_name(kind: u32) -> &'static str {
    match kind {
        ST_KIND_DESKTOP => "desktop",
        ST_KIND_LAPTOP => "laptop",
        ST_KIND_SERVER => "server",
        ST_KIND_MOBILE => "mobile",
        _ => "unknown",
    }
}

/// The report for `p` and `e`, one `suggestedtests: ...` line each.
pub fn format_report(p: &StPlatform, e: &StEnvironment) -> String {
    let libc_version = c_str(&p.libc_version);
    let mut platform = format!(
        "{} {} {}{}, {}-bit, os {}",
        os_name(p.os),
        arch_name(p.arch),
        libc_name(p.libc),
        if libc_version.is_empty() {
            String::new()
        } else {
            format!(" {libc_version}")
        },
        p.pointer_bits,
        c_str(&p.os_version),
    );
    if p.flags & ST_PLATFORM_TRANSLATED != 0 {
        platform.push_str(", translated (emulated)");
    }
    let vendor = c_str(&e.vm_vendor);
    let cloud = c_str(&e.cloud);
    let flags: Vec<&str> = [
        (ST_ENV_KUBERNETES, "kubernetes"),
        (ST_ENV_WSL, "wsl"),
        (ST_ENV_CI, "ci"),
        (ST_ENV_HEADLESS, "headless"),
        (ST_ENV_CLOUD, "cloud"),
    ]
    .iter()
    .filter(|(bit, _)| e.flags & bit != 0)
    .map(|&(_, name)| name)
    .collect();
    format!(
        "suggestedtests: native bridge loaded (ABI v{})\n\
         suggestedtests: platform: {platform}\n\
         suggestedtests: environment: {}, container {}, vm {}{}{}{}\n",
        crate::ST_ABI_VERSION,
        kind_name(e.kind),
        container_name(e.container),
        vm_name(e.vm),
        if vendor.is_empty() {
            String::new()
        } else {
            format!(" ({vendor})")
        },
        if cloud.is_empty() {
            String::new()
        } else {
            format!(", cloud {cloud}")
        },
        if flags.is_empty() {
            String::new()
        } else {
            format!(", flags: {}", flags.join(" "))
        },
    )
}

/// The report for this process.
pub fn report() -> String {
    let (mut p, mut e) = (StPlatform::default(), StEnvironment::default());
    // SAFETY: both point to live, writable structs.
    unsafe {
        st_platform(&mut p);
        st_environment(&mut e);
    }
    format_report(&p, &e)
}

/// Sets the verbose flag (0 = off, anything else = on) and returns the
/// previous value. Turning it on prints the startup report now if it hasn't
/// been printed yet.
#[no_mangle]
pub extern "C" fn st_set_verbose(verbose: u32) -> u32 {
    let previous = VERBOSE.swap(verbose != 0, Ordering::AcqRel);
    if verbose != 0 {
        PENDING.store(false, Ordering::Release);
        print_once();
    }
    previous as u32
}

/// The verbose flag: 1 on, 0 off.
#[no_mangle]
pub extern "C" fn st_verbose() -> u32 {
    VERBOSE.load(Ordering::Acquire) as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn truthy_values() {
        for v in ["1", "true", "TRUE", " yes ", "on"] {
            assert!(is_truthy(v), "{v}");
        }
        for v in ["", "0", "false", "no", "off", "2"] {
            assert!(!is_truthy(v), "{v}");
        }
    }

    #[test]
    fn formats_every_field() {
        let mut p = StPlatform {
            os: ST_OS_LINUX,
            arch: ST_ARCH_X86_64,
            libc: ST_LIBC_GLIBC,
            pointer_bits: 64,
            flags: ST_PLATFORM_TRANSLATED,
            ..StPlatform::default()
        };
        copy_str(&mut p.os_version, "6.8.0-45-generic");
        copy_str(&mut p.libc_version, "2.39");
        let mut e = StEnvironment {
            container: ST_CONTAINER_DOCKER,
            vm: ST_VM_KVM,
            kind: ST_KIND_SERVER,
            flags: ST_ENV_KUBERNETES | ST_ENV_CI | ST_ENV_CLOUD,
            ..StEnvironment::default()
        };
        copy_str(&mut e.vm_vendor, "KVMKVMKVM");
        copy_str(&mut e.cloud, "aws");
        assert_eq!(
            format_report(&p, &e),
            "suggestedtests: native bridge loaded (ABI v1)\n\
             suggestedtests: platform: linux x86_64 glibc 2.39, 64-bit, os 6.8.0-45-generic, translated (emulated)\n\
             suggestedtests: environment: server, container docker, vm kvm (KVMKVMKVM), cloud aws, flags: kubernetes ci cloud\n"
        );
    }

    #[test]
    fn formats_unknown_and_empty_fields() {
        let r = format_report(&StPlatform::default(), &StEnvironment::default());
        assert!(
            r.contains("platform: unknown unknown unknown, 0-bit, os \n"),
            "{r}"
        );
        assert!(
            r.contains("environment: unknown, container none, vm none\n"),
            "{r}"
        );
    }

    #[test]
    fn names_cover_every_constant() {
        for os in 1..=ST_OS_IOS {
            assert_ne!(os_name(os), "unknown");
        }
        for arch in 1..=ST_ARCH_LOONGARCH64 {
            assert_ne!(arch_name(arch), "unknown");
        }
        for libc in 1..=ST_LIBC_BSD {
            assert_ne!(libc_name(libc), "unknown");
        }
        for c in 1..=ST_CONTAINER_WINDOWS {
            assert_ne!(container_name(c), "unknown runtime");
        }
        for vm in 1..=ST_VM_NITRO {
            assert_ne!(vm_name(vm), "unknown hypervisor");
        }
        for kind in 1..=ST_KIND_MOBILE {
            assert_ne!(kind_name(kind), "unknown");
        }
    }

    #[test]
    fn report_describes_this_process() {
        let r = report();
        assert_eq!(r.lines().count(), 3);
        assert!(r.contains(arch_name(match std::env::consts::ARCH {
            "x86_64" => ST_ARCH_X86_64,
            "aarch64" => ST_ARCH_AARCH64,
            "x86" => ST_ARCH_X86,
            "arm" => ST_ARCH_ARM,
            "riscv64" => ST_ARCH_RISCV64,
            _ => ST_ARCH_UNKNOWN,
        })));
    }

    /// Runs this test binary again with only `test` and `env`, returning its
    /// stderr; `None` where the binary can't be re-run (e.g. under qemu-user
    /// without binfmt).
    fn child_stderr(test: &str, env: &[(&str, &str)]) -> Option<String> {
        let mut cmd = std::process::Command::new(std::env::current_exe().ok()?);
        cmd.args(["--exact", test, "--test-threads=1", "--nocapture"])
            .env_remove(VERBOSE_ENV_VAR)
            .env("SUGGESTEDTESTS_REPORT_CHILD", "1");
        for (k, v) in env {
            cmd.env(k, v);
        }
        let out = cmd.output().ok()?;
        assert!(out.status.success(), "{out:?}");
        Some(String::from_utf8_lossy(&out.stderr).into_owned())
    }

    fn is_child() -> bool {
        std::env::var_os("SUGGESTEDTESTS_REPORT_CHILD").is_some()
    }

    #[test]
    fn child_does_nothing() {}

    #[test]
    fn child_sets_verbose_twice() {
        if is_child() {
            assert_eq!(st_verbose(), 0);
            assert_eq!(st_set_verbose(1), 0);
            assert_eq!(st_set_verbose(7), 1);
            assert_eq!(st_verbose(), 1);
            assert_eq!(st_set_verbose(0), 1);
            assert_eq!(st_verbose(), 0);
        }
    }

    const CHILD_NOOP: &str = "report::tests::child_does_nothing";

    #[test]
    fn silent_by_default() {
        for env in [&[][..], &[(VERBOSE_ENV_VAR, "0")][..]] {
            if let Some(err) = child_stderr(CHILD_NOOP, env) {
                assert!(!err.contains("suggestedtests:"), "{err}");
            }
        }
    }

    #[test]
    fn env_var_prints_the_report_at_load() {
        if let Some(err) = child_stderr(CHILD_NOOP, &[(VERBOSE_ENV_VAR, "1")]) {
            // On Windows the hook defers to st_abi_version, which this child
            // never calls; the other platforms print from the loader.
            if cfg!(windows) {
                assert!(!err.contains("suggestedtests:"), "{err}");
            } else {
                assert_eq!(err.matches("native bridge loaded").count(), 1, "{err}");
                assert!(err.contains("suggestedtests: platform: "), "{err}");
                assert!(err.contains("suggestedtests: environment: "), "{err}");
            }
        }
    }

    #[test]
    fn setter_prints_the_report_once() {
        if let Some(err) = child_stderr("report::tests::child_sets_verbose_twice", &[]) {
            assert_eq!(err.matches("native bridge loaded").count(), 1, "{err}");
        }
    }
}
