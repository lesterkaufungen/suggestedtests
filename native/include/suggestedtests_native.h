/*
 * C ABI of the suggestedtests native bridge (native/src/lib.rs).
 * Identical on Windows, Linux and macOS.
 *
 * Status codes: 0 = ok, <0 = bridge error, >0 = OS error code
 * (errno on Unix, GetLastError() on Windows).
 */
#ifndef SUGGESTEDTESTS_NATIVE_H
#define SUGGESTEDTESTS_NATIVE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ST_ABI_VERSION 1u

#define ST_OK 0
#define ST_ERR_NULL (-1)
#define ST_ERR_UNSUPPORTED (-2)
#define ST_ERR_UNKNOWN (-3)
#define ST_ERR_INVALID (-4) /* a required string argument was null or not valid UTF-8 */

typedef struct StCpuTime {
  uint64_t user_ns;
  uint64_t system_ns;
} StCpuTime;

typedef struct StMemory {
  uint64_t current_rss_bytes;
  uint64_t peak_rss_bytes;
} StMemory;

uint32_t st_abi_version(void);
/* Each binding's own loader calls this once, as early as that language
 * allows, in addition to st_abi_version(): a dedicated hook for load-time
 * side effects, separate from the version query. Safe to call more than
 * once, and safe even without ever calling st_abi_version(). */
void st_on_load(void);
int32_t st_process_cpu_time(StCpuTime *out);
int32_t st_thread_cpu_time_ns(uint64_t *out);
int32_t st_memory_usage(StMemory *out);
uint32_t st_cpu_count(void);

/* ---------------------------------------------------------------- load --
 * Initializers run when the library is loaded (native/src/load.rs): from
 * .init_array (ELF), __mod_init_func (Mach-O) or .CRT$XCU (Windows), or on
 * the first st_abi_version() call where no loader hook ran. */

#define ST_LOAD_NOT_RUN 0u
#define ST_LOAD_AT_LOAD 1u /* ran from the OS loader while loading the library */
#define ST_LOAD_LAZY 2u    /* ran on the first st_abi_version() call instead */

uint32_t st_load_state(void);

/* ------------------------------------------------------------- verbose --
 * The startup report (native/src/report.rs): st_platform and st_environment
 * in words, three "suggestedtests: ..." lines printed once to stderr when the
 * library loads, only if verbose is on. Verbose controls nothing else; it is
 * off by default, so nothing is printed.
 *
 * Turn it on before loading with SUGGESTEDTESTS_VERBOSE=1 (or true/yes/on),
 * or after loading with st_set_verbose(1), which prints the report then if it
 * hasn't been printed. On Windows the load-time report is printed by the first
 * st_abi_version() call rather than under the loader lock. */

/* Sets verbose (0 off, anything else on); returns the previous value. */
uint32_t st_set_verbose(uint32_t verbose);
/* 1 if verbose is on, else 0. */
uint32_t st_verbose(void);

/* ------------------------------------------------------------ platform --
 * st_platform: the build target (exact, since a library only loads into a
 * matching process) and the running OS's versions. Added in ABI v1; not yet
 * used by the language packages. */

#define ST_OS_UNKNOWN 0u
#define ST_OS_LINUX 1u
#define ST_OS_MACOS 2u
#define ST_OS_WINDOWS 3u
#define ST_OS_ANDROID 4u
#define ST_OS_FREEBSD 5u
#define ST_OS_IOS 6u

#define ST_ARCH_UNKNOWN 0u
#define ST_ARCH_X86_64 1u
#define ST_ARCH_AARCH64 2u
#define ST_ARCH_X86 3u
#define ST_ARCH_ARM 4u
#define ST_ARCH_RISCV64 5u
#define ST_ARCH_PPC64LE 6u
#define ST_ARCH_S390X 7u
#define ST_ARCH_LOONGARCH64 8u

#define ST_LIBC_UNKNOWN 0u
#define ST_LIBC_GLIBC 1u
#define ST_LIBC_MUSL 2u
#define ST_LIBC_BIONIC 3u
#define ST_LIBC_MSVC 4u
#define ST_LIBC_APPLE 5u
#define ST_LIBC_BSD 6u

/* Rosetta 2, or x86/x64 emulation on ARM64 Windows. */
#define ST_PLATFORM_TRANSLATED 1u

typedef struct StPlatform {
  uint32_t os;            /* ST_OS_* */
  uint32_t arch;          /* ST_ARCH_* */
  uint32_t libc;          /* ST_LIBC_* */
  uint32_t pointer_bits;  /* 32 or 64 */
  uint32_t flags;         /* ST_PLATFORM_* */
  char os_version[64];    /* "6.8.0-45-generic", "14.5", "10.0.22631", "14"; NUL-terminated UTF-8 */
  char libc_version[32];  /* "2.39" (glibc), "34" (bionic API level), "" if unknown (musl) */
} StPlatform;

int32_t st_platform(StPlatform *out);

/* --------------------------------------------------------- environment --
 * st_environment: container, hypervisor, machine kind, CI. Best-effort
 * heuristics without privileges: cgroups, mountinfo, DMI, CPUID, sysctl,
 * the registry, environment variables. Added in ABI v1. */

#define ST_CONTAINER_NONE 0u
#define ST_CONTAINER_DOCKER 1u
#define ST_CONTAINER_PODMAN 2u
#define ST_CONTAINER_CONTAINERD 3u
#define ST_CONTAINER_CRIO 4u
#define ST_CONTAINER_LXC 5u
#define ST_CONTAINER_NSPAWN 6u
#define ST_CONTAINER_OPENVZ 7u
#define ST_CONTAINER_WINDOWS 8u
#define ST_CONTAINER_UNKNOWN 255u /* a container, runtime unidentified */

#define ST_VM_NONE 0u
#define ST_VM_KVM 1u
#define ST_VM_QEMU 2u
#define ST_VM_VMWARE 3u
#define ST_VM_VIRTUALBOX 4u
#define ST_VM_HYPERV 5u
#define ST_VM_XEN 6u
#define ST_VM_PARALLELS 7u
#define ST_VM_BHYVE 8u
#define ST_VM_APPLE 9u  /* Apple Virtualization.framework */
#define ST_VM_NITRO 10u /* AWS Nitro */
#define ST_VM_UNKNOWN 255u /* a hypervisor, vendor unidentified */

#define ST_KIND_UNKNOWN 0u
#define ST_KIND_DESKTOP 1u
#define ST_KIND_LAPTOP 2u
#define ST_KIND_SERVER 3u
#define ST_KIND_MOBILE 4u

#define ST_ENV_KUBERNETES 1u
#define ST_ENV_WSL 2u
#define ST_ENV_CI 4u
#define ST_ENV_HEADLESS 8u /* no graphical session (no DISPLAY / WAYLAND_DISPLAY) */
#define ST_ENV_CLOUD 16u   /* cloud provider identified, see `cloud` */

typedef struct StEnvironment {
  uint32_t container;  /* ST_CONTAINER_* */
  uint32_t vm;         /* ST_VM_* */
  uint32_t kind;       /* ST_KIND_* */
  uint32_t flags;      /* ST_ENV_* */
  char vm_vendor[48];  /* what identified the hypervisor: "KVMKVMKVM", "VMware, Inc."; NUL-terminated */
  char cloud[16];      /* "aws", "gcp", "azure", "digitalocean", "hetzner", "oracle", "alibaba", "openstack" or "" */
} StEnvironment;

int32_t st_environment(StEnvironment *out);

/* ------------------------------------------------------------------ spawn --
 * st_spawn: fire-and-forget process launch, no PATH lookup (like execve, not
 * execvp), no handle kept open and nothing ever waited on -- so there is no
 * st_process_wait/st_process_kill. Added in ABI v1; not yet used by the
 * language packages. */

#define ST_SPAWN_DETACHED 1u  /* Unix: setsid(); Windows: CREATE_NEW_PROCESS_GROUP (+ DETACHED_PROCESS unless ST_SPAWN_NO_WINDOW) */
#define ST_SPAWN_NO_WINDOW 2u /* Windows only: CREATE_NO_WINDOW; ignored elsewhere */

typedef struct StSpawnEnvVar {
  const char *key;
  const char *value;
} StSpawnEnvVar;

/*
 * path:     the executable file, not resolved against PATH; always argv[0].
 * args:     argv *excluding* path; NULL with args_len 0 for none.
 * cwd:      the child's working directory; NULL to inherit this process'.
 * env:      added to / overriding this process' inherited environment;
 *           NULL with env_len 0 to inherit it unchanged.
 * flags:    ST_SPAWN_* bitmask.
 * out_pid:  the child's PID.
 *
 * Returns ST_ERR_NULL for a null path/out_pid, or a null args/env array or
 * element (when its _len is nonzero); ST_ERR_INVALID for a string that isn't
 * valid UTF-8; otherwise the OS error encountered while spawning.
 */
int32_t st_spawn(const char *path, const char *const *args, uint32_t args_len,
                  const char *cwd, const StSpawnEnvVar *env, uint32_t env_len,
                  uint32_t flags, uint64_t *out_pid);

#ifdef __cplusplus
}
#endif

#endif /* SUGGESTEDTESTS_NATIVE_H */
