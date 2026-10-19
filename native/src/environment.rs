//! `st_environment`: is the process in a container, in a virtual machine, on
//! a desktop or a server, in CI?
//!
//! Every answer is a best-effort heuristic from what the OS exposes without
//! privileges (cgroups, mountinfo, DMI, CPUID, sysctl, the registry,
//! environment variables). The decisions are pure functions over those
//! inputs ([`classify_container`], [`vm_from_cpuid_vendor`], [`vm_from_dmi`],
//! [`cloud_from_dmi`], [`kind_from_chassis`]), so they are unit-tested
//! against fixtures for every case, not only the machine running the tests.

use crate::platform::copy_str;
use crate::write_out;

pub const ST_CONTAINER_NONE: u32 = 0;
pub const ST_CONTAINER_DOCKER: u32 = 1;
pub const ST_CONTAINER_PODMAN: u32 = 2;
pub const ST_CONTAINER_CONTAINERD: u32 = 3;
pub const ST_CONTAINER_CRIO: u32 = 4;
pub const ST_CONTAINER_LXC: u32 = 5;
pub const ST_CONTAINER_NSPAWN: u32 = 6;
pub const ST_CONTAINER_OPENVZ: u32 = 7;
pub const ST_CONTAINER_WINDOWS: u32 = 8;
/// In a container whose runtime couldn't be identified.
pub const ST_CONTAINER_UNKNOWN: u32 = 255;

pub const ST_VM_NONE: u32 = 0;
pub const ST_VM_KVM: u32 = 1;
pub const ST_VM_QEMU: u32 = 2;
pub const ST_VM_VMWARE: u32 = 3;
pub const ST_VM_VIRTUALBOX: u32 = 4;
pub const ST_VM_HYPERV: u32 = 5;
pub const ST_VM_XEN: u32 = 6;
pub const ST_VM_PARALLELS: u32 = 7;
pub const ST_VM_BHYVE: u32 = 8;
/// Apple's Virtualization.framework / Hypervisor.framework.
pub const ST_VM_APPLE: u32 = 9;
/// AWS Nitro (KVM-based, reports its own vendor).
pub const ST_VM_NITRO: u32 = 10;
/// A hypervisor is present but couldn't be identified.
pub const ST_VM_UNKNOWN: u32 = 255;

pub const ST_KIND_UNKNOWN: u32 = 0;
pub const ST_KIND_DESKTOP: u32 = 1;
pub const ST_KIND_LAPTOP: u32 = 2;
pub const ST_KIND_SERVER: u32 = 3;
pub const ST_KIND_MOBILE: u32 = 4;

/// Running in a Kubernetes pod.
pub const ST_ENV_KUBERNETES: u32 = 1;
/// Running under Windows Subsystem for Linux.
pub const ST_ENV_WSL: u32 = 2;
/// A CI system's environment variables are set.
pub const ST_ENV_CI: u32 = 4;
/// No graphical session (no DISPLAY / WAYLAND_DISPLAY on Unix).
pub const ST_ENV_HEADLESS: u32 = 8;
/// A cloud provider was identified (see `cloud`).
pub const ST_ENV_CLOUD: u32 = 16;

/// Result of [`st_environment`].
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StEnvironment {
    /// `ST_CONTAINER_*`.
    pub container: u32,
    /// `ST_VM_*`.
    pub vm: u32,
    /// `ST_KIND_*`.
    pub kind: u32,
    /// `ST_ENV_*` flags.
    pub flags: u32,
    /// What identified the hypervisor, e.g. "KVMKVMKVM" (CPUID) or
    /// "VMware, Inc." (DMI). NUL-terminated UTF-8, empty if none.
    pub vm_vendor: [u8; 48],
    /// "aws", "gcp", "azure", "digitalocean", "hetzner", "oracle",
    /// "alibaba", "openstack" or empty. NUL-terminated.
    pub cloud: [u8; 16],
}

impl Default for StEnvironment {
    fn default() -> Self {
        StEnvironment {
            container: ST_CONTAINER_NONE,
            vm: ST_VM_NONE,
            kind: ST_KIND_UNKNOWN,
            flags: 0,
            vm_vendor: [0; 48],
            cloud: [0; 16],
        }
    }
}

// ----------------------------------------------------------- classifiers --

/// Linux container evidence, gathered by [`linux::container_inputs`].
#[derive(Debug, Default, Clone)]
pub struct ContainerInputs {
    /// `/.dockerenv` exists.
    pub dockerenv: bool,
    /// `/run/.containerenv` exists (Podman, also some Buildah/CRI-O setups).
    pub containerenv: bool,
    /// `$container` (set by systemd-nspawn, podman, lxc, flatpak...).
    pub env_container: Option<String>,
    /// Contents of `/proc/self/cgroup`.
    pub cgroup: String,
    /// Contents of `/proc/self/mountinfo` (only the first lines matter).
    pub mountinfo: String,
    /// `/proc/vz` exists but `/proc/bc` doesn't (inside an OpenVZ container).
    pub openvz: bool,
}

/// Decides the container runtime from Linux evidence.
pub fn classify_container(i: &ContainerInputs) -> u32 {
    if let Some(env) = i.env_container.as_deref() {
        match env {
            "docker" => return ST_CONTAINER_DOCKER,
            "podman" => return ST_CONTAINER_PODMAN,
            "lxc" | "lxc-libvirt" => return ST_CONTAINER_LXC,
            "systemd-nspawn" => return ST_CONTAINER_NSPAWN,
            "oci" | "crio" => return ST_CONTAINER_CRIO,
            _ => {}
        }
    }
    if i.containerenv {
        return ST_CONTAINER_PODMAN;
    }
    let evidence = format!("{}\n{}", i.cgroup, i.mountinfo);
    let has = |needle: &str| evidence.contains(needle);
    // Most specific first: Kubernetes nodes run containerd or CRI-O, and
    // their paths also mention "kubepods".
    if has("crio-") || has("/crio/") {
        return ST_CONTAINER_CRIO;
    }
    if has("libpod") || has("/containers/storage/overlay") {
        return ST_CONTAINER_PODMAN;
    }
    if i.dockerenv || has("/docker/") || has("docker-") || has("/docker/containers/") {
        return ST_CONTAINER_DOCKER;
    }
    if has("containerd") || has("cri-containerd") || has("/k8s.io/") {
        return ST_CONTAINER_CONTAINERD;
    }
    if has("/lxc/") || has("lxc.payload") {
        return ST_CONTAINER_LXC;
    }
    if has("/machine.slice/machine-") {
        return ST_CONTAINER_NSPAWN;
    }
    if i.openvz {
        return ST_CONTAINER_OPENVZ;
    }
    if has("kubepods") {
        return ST_CONTAINER_UNKNOWN;
    }
    ST_CONTAINER_NONE
}

/// Maps the CPUID hypervisor vendor (leaf 0x40000000) to `ST_VM_*`.
pub fn vm_from_cpuid_vendor(vendor: &str) -> u32 {
    match vendor.trim_end_matches(['\0', ' ']) {
        "KVMKVMKVM" | "Linux KVM Hv" => ST_VM_KVM,
        "TCGTCGTCGTCG" => ST_VM_QEMU,
        "VMwareVMware" => ST_VM_VMWARE,
        "VBoxVBoxVBox" => ST_VM_VIRTUALBOX,
        "Microsoft Hv" => ST_VM_HYPERV,
        "XenVMMXenVMM" => ST_VM_XEN,
        "prl hyperv" | " lrpepyh  vr" => ST_VM_PARALLELS,
        "bhyve bhyve" | "BHyVE BHyVE" => ST_VM_BHYVE,
        "Apple VZ" | "AppleVZ" => ST_VM_APPLE,
        "" => ST_VM_NONE,
        _ => ST_VM_UNKNOWN,
    }
}

/// Maps DMI / SMBIOS strings (`sys_vendor`, `product_name`, `bios_vendor`,
/// lowercased or not) to `ST_VM_*`. `ST_VM_NONE` for physical hardware.
pub fn vm_from_dmi(sys_vendor: &str, product: &str, bios_vendor: &str) -> u32 {
    let all = format!("{sys_vendor}\n{product}\n{bios_vendor}").to_ascii_lowercase();
    let has = |needle: &str| all.contains(needle);
    if has("amazon ec2") || (has("amazon") && has("nitro")) {
        ST_VM_NITRO
    } else if has("vmware") {
        ST_VM_VMWARE
    } else if has("virtualbox") || has("innotek") {
        ST_VM_VIRTUALBOX
    } else if has("microsoft corporation") && has("virtual machine") {
        ST_VM_HYPERV
    } else if has("parallels") {
        ST_VM_PARALLELS
    } else if has("xen") {
        ST_VM_XEN
    } else if has("bhyve") {
        ST_VM_BHYVE
    } else if has("apple virtualization") {
        ST_VM_APPLE
    } else if has("kvm")
        || has("google compute engine")
        || has("openstack")
        || has("digitalocean")
        || has("hetzner")
    {
        ST_VM_KVM
    } else if has("qemu") || has("seabios") || has("bochs") {
        ST_VM_QEMU
    } else {
        ST_VM_NONE
    }
}

/// Identifies a cloud provider from DMI / SMBIOS strings.
pub fn cloud_from_dmi(
    sys_vendor: &str,
    product: &str,
    bios_vendor: &str,
    asset_tag: &str,
) -> &'static str {
    let all = format!("{sys_vendor}\n{product}\n{bios_vendor}\n{asset_tag}").to_ascii_lowercase();
    let has = |needle: &str| all.contains(needle);
    if has("amazon") {
        "aws"
    } else if has("google") {
        "gcp"
    } else if has("7783-7084-3265-9085-8269-3286-77")
        || (has("microsoft corporation") && has("virtual machine") && has("090008"))
    {
        "azure" // Azure's chassis asset tag / Hyper-V BIOS of Azure
    } else if has("digitalocean") {
        "digitalocean"
    } else if has("hetzner") {
        "hetzner"
    } else if has("oraclecloud") || has("oracle cloud") {
        "oracle"
    } else if has("alibaba") {
        "alibaba"
    } else if has("openstack") {
        "openstack"
    } else {
        ""
    }
}

/// Maps the SMBIOS chassis type (`/sys/class/dmi/id/chassis_type`) to
/// `ST_KIND_*`.
pub fn kind_from_chassis(chassis: u32) -> u32 {
    match chassis {
        3 | 4 | 5 | 6 | 7 | 13 | 15 | 16 | 24 | 35 | 36 => ST_KIND_DESKTOP,
        8 | 9 | 10 | 14 | 30 | 31 | 32 => ST_KIND_LAPTOP,
        17 | 23 | 25 | 28 | 29 => ST_KIND_SERVER,
        11 => ST_KIND_MOBILE, // hand held
        _ => ST_KIND_UNKNOWN,
    }
}

/// Whether a known CI system's variables are set.
pub fn is_ci(var: impl Fn(&str) -> Option<String>) -> bool {
    const VARS: &[&str] = &[
        "GITHUB_ACTIONS",
        "GITLAB_CI",
        "JENKINS_URL",
        "BUILDKITE",
        "CIRCLECI",
        "TF_BUILD",
        "TEAMCITY_VERSION",
        "TRAVIS",
        "BITBUCKET_BUILD_NUMBER",
        "APPVEYOR",
        "DRONE",
        "CODEBUILD_BUILD_ID",
        "BUILD_ID",
    ];
    if let Some(ci) = var("CI") {
        if !ci.is_empty() && ci != "false" && ci != "0" {
            return true;
        }
    }
    VARS.iter().any(|v| var(v).is_some())
}

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok()
}

// ------------------------------------------------------------- CPUID (x86) --

/// The hypervisor vendor from CPUID, if the "hypervisor present" bit is set.
/// `None` on non-x86, on bare metal, and in Hyper-V's root partition (a
/// Windows host with Hyper-V/VBS enabled), which is not a guest.
#[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
fn cpuid_hypervisor() -> Option<String> {
    #[cfg(target_arch = "x86")]
    use std::arch::x86::__cpuid;
    #[cfg(target_arch = "x86_64")]
    use std::arch::x86_64::__cpuid;
    // SAFETY: CPUID exists on every x86_64 CPU and every i686-class CPU Rust
    // targets; leaves above the maximum return zeros, not faults.
    let leaf1 = unsafe { __cpuid(1) };
    if leaf1.ecx & (1 << 31) == 0 {
        return None;
    }
    let base = unsafe { __cpuid(0x4000_0000) };
    let mut vendor = Vec::with_capacity(12);
    for reg in [base.ebx, base.ecx, base.edx] {
        vendor.extend_from_slice(&reg.to_le_bytes());
    }
    let vendor = String::from_utf8_lossy(&vendor)
        .trim_end_matches('\0')
        .to_string();
    if vendor == "Microsoft Hv" && base.eax >= 0x4000_0003 {
        // EBX bit 0 of leaf 0x40000003: CreatePartitions, only the root has it.
        let features = unsafe { __cpuid(0x4000_0003) };
        if features.ebx & 1 != 0 {
            return None;
        }
    }
    Some(vendor)
}

#[cfg(not(any(target_arch = "x86", target_arch = "x86_64")))]
fn cpuid_hypervisor() -> Option<String> {
    None
}

// ------------------------------------------------------------- per OS ------

#[cfg(any(target_os = "linux", target_os = "android"))]
mod linux {
    use super::*;
    use std::fs;
    use std::path::Path;

    fn read(path: &str) -> String {
        fs::read_to_string(path)
            .map(|s| s.trim().to_string())
            .unwrap_or_default()
    }

    pub(super) fn container_inputs() -> ContainerInputs {
        let mut mountinfo = fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
        mountinfo.truncate(
            mountinfo
                .char_indices()
                .nth(16 * 1024)
                .map_or(mountinfo.len(), |(i, _)| i),
        );
        ContainerInputs {
            dockerenv: Path::new("/.dockerenv").exists(),
            containerenv: Path::new("/run/.containerenv").exists(),
            env_container: env("container"),
            cgroup: fs::read_to_string("/proc/self/cgroup").unwrap_or_default(),
            mountinfo,
            openvz: Path::new("/proc/vz").exists() && !Path::new("/proc/bc").exists(),
        }
    }

    pub(super) fn kubernetes() -> bool {
        env("KUBERNETES_SERVICE_HOST").is_some()
            || Path::new("/var/run/secrets/kubernetes.io/serviceaccount").exists()
    }

    pub(super) fn wsl() -> bool {
        env("WSL_DISTRO_NAME").is_some()
            || env("WSL_INTEROP").is_some()
            || read("/proc/sys/kernel/osrelease")
                .to_ascii_lowercase()
                .contains("microsoft")
    }

    pub(super) struct Dmi {
        pub sys_vendor: String,
        pub product: String,
        pub bios_vendor: String,
        pub asset_tag: String,
        pub chassis: u32,
    }

    pub(super) fn dmi() -> Dmi {
        let base = "/sys/class/dmi/id/";
        Dmi {
            sys_vendor: read(&format!("{base}sys_vendor")),
            product: read(&format!("{base}product_name")),
            bios_vendor: read(&format!("{base}bios_vendor")),
            asset_tag: read(&format!("{base}chassis_asset_tag")),
            chassis: read(&format!("{base}chassis_type")).parse().unwrap_or(0),
        }
    }

    /// Hypervisor hints that work on every architecture (DMI is missing on
    /// many ARM boards).
    pub(super) fn other_vm_hints() -> Option<(u32, String)> {
        let hv = read("/sys/hypervisor/type");
        if hv == "xen" {
            return Some((ST_VM_XEN, "xen".into()));
        }
        let compatible = fs::read("/proc/device-tree/hypervisor/compatible").unwrap_or_default();
        let compatible = String::from_utf8_lossy(&compatible).to_ascii_lowercase();
        if compatible.contains("xen") {
            return Some((ST_VM_XEN, "xen".into()));
        }
        if compatible.contains("kvm") {
            return Some((ST_VM_KVM, "kvm".into()));
        }
        let cpuinfo = fs::read_to_string("/proc/cpuinfo").unwrap_or_default();
        if cpuinfo
            .lines()
            .any(|l| l.starts_with("flags") && l.split_whitespace().any(|f| f == "hypervisor"))
        {
            return Some((ST_VM_UNKNOWN, String::new()));
        }
        None
    }

    #[cfg(target_os = "android")]
    pub(super) fn android_emulator() -> bool {
        let prop = |name: &str| crate::sys::android_property(name).unwrap_or_default();
        prop("ro.kernel.qemu") == "1"
            || prop("ro.boot.qemu") == "1"
            || matches!(
                prop("ro.hardware").as_str(),
                "goldfish" | "ranchu" | "cutf_cvm"
            )
    }
}

fn detect() -> StEnvironment {
    let mut e = StEnvironment::default();
    let mut vendor = String::new();
    if is_ci(env) {
        e.flags |= ST_ENV_CI;
    }

    // CPUID first: it is exact on x86 for every OS.
    if let Some(v) = cpuid_hypervisor() {
        e.vm = vm_from_cpuid_vendor(&v);
        vendor = v;
    }

    #[cfg(any(target_os = "linux", target_os = "android"))]
    {
        e.container = classify_container(&linux::container_inputs());
        if linux::kubernetes() {
            e.flags |= ST_ENV_KUBERNETES;
            if e.container == ST_CONTAINER_NONE {
                e.container = ST_CONTAINER_UNKNOWN;
            }
        }
        if linux::wsl() {
            e.flags |= ST_ENV_WSL;
            if e.vm == ST_VM_NONE {
                e.vm = ST_VM_HYPERV;
            }
        }
        let dmi = linux::dmi();
        let dmi_vm = vm_from_dmi(&dmi.sys_vendor, &dmi.product, &dmi.bios_vendor);
        let replace = e.vm == ST_VM_NONE
            || e.vm == ST_VM_UNKNOWN
            || (e.vm == ST_VM_KVM && dmi_vm == ST_VM_NITRO);
        if replace && dmi_vm != ST_VM_NONE {
            e.vm = dmi_vm;
            vendor = dmi.sys_vendor.clone();
        }
        if e.vm == ST_VM_NONE {
            if let Some((vm, v)) = linux::other_vm_hints() {
                e.vm = vm;
                vendor = v;
            }
        }
        let cloud = cloud_from_dmi(
            &dmi.sys_vendor,
            &dmi.product,
            &dmi.bios_vendor,
            &dmi.asset_tag,
        );
        if !cloud.is_empty() {
            e.flags |= ST_ENV_CLOUD;
            copy_str(&mut e.cloud, cloud);
        }
        e.kind = kind_from_chassis(dmi.chassis);
        if env("DISPLAY").is_none() && env("WAYLAND_DISPLAY").is_none() {
            e.flags |= ST_ENV_HEADLESS;
        }
        if e.kind == ST_KIND_UNKNOWN {
            // No usable chassis (VMs, containers, ARM boards): a graphical
            // session suggests a desktop, otherwise assume a server.
            e.kind = if e.flags & ST_ENV_HEADLESS == 0 && e.container == ST_CONTAINER_NONE {
                ST_KIND_DESKTOP
            } else {
                ST_KIND_SERVER
            };
        }
        #[cfg(target_os = "android")]
        {
            e.kind = ST_KIND_MOBILE;
            e.flags &= !ST_ENV_HEADLESS;
            if linux::android_emulator() && e.vm == ST_VM_NONE {
                e.vm = ST_VM_QEMU;
                vendor = "android emulator".into();
            }
        }
    }

    #[cfg(target_os = "macos")]
    {
        if crate::sys::sysctl_int("kern.hv_vmm_present") == Some(1) && e.vm == ST_VM_NONE {
            e.vm = ST_VM_APPLE;
            vendor = "kern.hv_vmm_present".into();
        }
        let model = crate::sys::sysctl_string("hw.model").unwrap_or_default();
        e.kind = if model.contains("Book") {
            ST_KIND_LAPTOP
        } else {
            ST_KIND_DESKTOP
        };
        if model.starts_with("VirtualMac") && e.vm == ST_VM_NONE {
            e.vm = ST_VM_APPLE;
            vendor = model;
        }
    }

    #[cfg(windows)]
    {
        let info = crate::sys::windows_environment();
        if info.container {
            e.container = ST_CONTAINER_WINDOWS;
        }
        e.kind = info.kind;
        let dmi_vm = vm_from_dmi(&info.manufacturer, &info.product, &info.bios_vendor);
        if (e.vm == ST_VM_NONE || e.vm == ST_VM_UNKNOWN) && dmi_vm != ST_VM_NONE {
            e.vm = dmi_vm;
            vendor = info.manufacturer.clone();
        }
        let cloud = cloud_from_dmi(&info.manufacturer, &info.product, &info.bios_vendor, "");
        if !cloud.is_empty() {
            e.flags |= ST_ENV_CLOUD;
            copy_str(&mut e.cloud, cloud);
        }
    }

    copy_str(&mut e.vm_vendor, &vendor);
    e
}

/// Writes what is known about the process' environment to `out`. Always
/// succeeds unless `out` is null; unknown fields are 0 / empty.
///
/// # Safety
/// `out` must be null or point to writable memory for one `StEnvironment`.
#[no_mangle]
pub unsafe extern "C" fn st_environment(out: *mut StEnvironment) -> i32 {
    write_out(out, Ok(detect()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn inputs() -> ContainerInputs {
        ContainerInputs::default()
    }

    #[test]
    fn bare_host_is_not_a_container() {
        let mut i = inputs();
        i.cgroup = "0::/user.slice/user-1000.slice/session-2.scope\n".into();
        i.mountinfo = "22 1 259:2 / / rw,relatime shared:1 - ext4 /dev/nvme0n1p2 rw\n".into();
        assert_eq!(classify_container(&i), ST_CONTAINER_NONE);
    }

    #[test]
    fn docker() {
        let mut i = inputs();
        i.dockerenv = true;
        assert_eq!(classify_container(&i), ST_CONTAINER_DOCKER);
        let mut i = inputs();
        i.cgroup = "12:memory:/docker/3f2e8a1c9b\n".into();
        assert_eq!(classify_container(&i), ST_CONTAINER_DOCKER);
        let mut i = inputs(); // cgroup v2: only mountinfo shows it
        i.cgroup = "0::/\n".into();
        i.mountinfo = "511 480 0:121 / / rw - overlay overlay rw,lowerdir=/var/lib/docker/overlay2/l/X\n530 511 259:2 /var/lib/docker/containers/3f2e/hostname /etc/hostname rw - ext4 /dev/sda1 rw\n".into();
        assert_eq!(classify_container(&i), ST_CONTAINER_DOCKER);
    }

    #[test]
    fn podman() {
        let mut i = inputs();
        i.containerenv = true;
        assert_eq!(classify_container(&i), ST_CONTAINER_PODMAN);
        let mut i = inputs();
        i.env_container = Some("podman".into());
        assert_eq!(classify_container(&i), ST_CONTAINER_PODMAN);
        let mut i = inputs();
        i.cgroup = "0::/machine.slice/libpod-8a1c.scope/container\n".into();
        assert_eq!(classify_container(&i), ST_CONTAINER_PODMAN);
    }

    #[test]
    fn kubernetes_runtimes() {
        let mut i = inputs();
        i.cgroup = "0::/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod1.slice/cri-containerd-9b.scope\n".into();
        assert_eq!(classify_container(&i), ST_CONTAINER_CONTAINERD);
        let mut i = inputs();
        i.cgroup = "0::/kubepods.slice/kubepods-pod1.slice/crio-4e2c.scope\n".into();
        assert_eq!(classify_container(&i), ST_CONTAINER_CRIO);
        let mut i = inputs();
        i.mountinfo = "1 0 0:1 / / rw - overlay overlay rw,lowerdir=/run/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/1/fs\n".into();
        assert_eq!(classify_container(&i), ST_CONTAINER_CONTAINERD);
        let mut i = inputs();
        i.cgroup = "0::/kubepods/besteffort/pod1/abc\n".into();
        assert_eq!(classify_container(&i), ST_CONTAINER_UNKNOWN);
    }

    #[test]
    fn lxc_nspawn_openvz() {
        let mut i = inputs();
        i.env_container = Some("lxc".into());
        assert_eq!(classify_container(&i), ST_CONTAINER_LXC);
        let mut i = inputs();
        i.cgroup = "0::/lxc.payload.web/init.scope\n".into();
        assert_eq!(classify_container(&i), ST_CONTAINER_LXC);
        let mut i = inputs();
        i.env_container = Some("systemd-nspawn".into());
        assert_eq!(classify_container(&i), ST_CONTAINER_NSPAWN);
        let mut i = inputs();
        i.openvz = true;
        assert_eq!(classify_container(&i), ST_CONTAINER_OPENVZ);
    }

    #[test]
    fn cpuid_vendors() {
        assert_eq!(vm_from_cpuid_vendor("KVMKVMKVM\0\0\0"), ST_VM_KVM);
        assert_eq!(vm_from_cpuid_vendor("VMwareVMware"), ST_VM_VMWARE);
        assert_eq!(vm_from_cpuid_vendor("Microsoft Hv"), ST_VM_HYPERV);
        assert_eq!(vm_from_cpuid_vendor("VBoxVBoxVBox"), ST_VM_VIRTUALBOX);
        assert_eq!(vm_from_cpuid_vendor("XenVMMXenVMM"), ST_VM_XEN);
        assert_eq!(vm_from_cpuid_vendor("TCGTCGTCGTCG"), ST_VM_QEMU);
        assert_eq!(vm_from_cpuid_vendor(" lrpepyh  vr"), ST_VM_PARALLELS);
        assert_eq!(vm_from_cpuid_vendor("bhyve bhyve "), ST_VM_BHYVE);
        assert_eq!(vm_from_cpuid_vendor("SomethingNew"), ST_VM_UNKNOWN);
        assert_eq!(vm_from_cpuid_vendor(""), ST_VM_NONE);
    }

    #[test]
    fn dmi_strings() {
        assert_eq!(
            vm_from_dmi("QEMU", "Standard PC (Q35 + ICH9, 2009)", "SeaBIOS"),
            ST_VM_QEMU
        );
        assert_eq!(
            vm_from_dmi("VMware, Inc.", "VMware Virtual Platform", "Phoenix"),
            ST_VM_VMWARE
        );
        assert_eq!(
            vm_from_dmi("innotek GmbH", "VirtualBox", "innotek GmbH"),
            ST_VM_VIRTUALBOX
        );
        assert_eq!(
            vm_from_dmi(
                "Microsoft Corporation",
                "Virtual Machine",
                "Microsoft Corporation"
            ),
            ST_VM_HYPERV
        );
        assert_eq!(
            vm_from_dmi("Amazon EC2", "m6i.large", "Amazon EC2"),
            ST_VM_NITRO
        );
        assert_eq!(
            vm_from_dmi("Google", "Google Compute Engine", "Google"),
            ST_VM_KVM
        );
        assert_eq!(vm_from_dmi("Xen", "HVM domU", "Xen"), ST_VM_XEN);
        assert_eq!(
            vm_from_dmi(
                "Parallels Software International Inc.",
                "Parallels Virtual Platform",
                ""
            ),
            ST_VM_PARALLELS
        );
        assert_eq!(
            vm_from_dmi("Dell Inc.", "PowerEdge R750", "Dell Inc."),
            ST_VM_NONE
        );
        assert_eq!(vm_from_dmi("LENOVO", "20XW0026GE", "LENOVO"), ST_VM_NONE);
        assert_eq!(vm_from_dmi("", "", ""), ST_VM_NONE);
    }

    #[test]
    fn clouds() {
        assert_eq!(
            cloud_from_dmi("Amazon EC2", "t3.micro", "Amazon EC2", "i-0abc"),
            "aws"
        );
        assert_eq!(
            cloud_from_dmi("Google", "Google Compute Engine", "Google", ""),
            "gcp"
        );
        assert_eq!(
            cloud_from_dmi(
                "Microsoft Corporation",
                "Virtual Machine",
                "Microsoft Corporation",
                "7783-7084-3265-9085-8269-3286-77"
            ),
            "azure"
        );
        assert_eq!(
            cloud_from_dmi("DigitalOcean", "Droplet", "DigitalOcean", ""),
            "digitalocean"
        );
        assert_eq!(
            cloud_from_dmi("Hetzner", "vServer", "Hetzner", ""),
            "hetzner"
        );
        assert_eq!(cloud_from_dmi("QEMU", "Standard PC", "SeaBIOS", ""), "");
        assert_eq!(
            cloud_from_dmi(
                "Microsoft Corporation",
                "Virtual Machine",
                "Microsoft Corporation",
                ""
            ),
            ""
        );
    }

    #[test]
    fn chassis() {
        assert_eq!(kind_from_chassis(3), ST_KIND_DESKTOP);
        assert_eq!(kind_from_chassis(10), ST_KIND_LAPTOP);
        assert_eq!(kind_from_chassis(23), ST_KIND_SERVER);
        assert_eq!(kind_from_chassis(17), ST_KIND_SERVER);
        assert_eq!(kind_from_chassis(1), ST_KIND_UNKNOWN); // "Other": most VMs
        assert_eq!(kind_from_chassis(0), ST_KIND_UNKNOWN);
    }

    #[test]
    fn ci_variables() {
        let none = |_: &str| None;
        assert!(!is_ci(none));
        assert!(is_ci(
            |v: &str| (v == "GITHUB_ACTIONS").then(|| "true".to_string())
        ));
        assert!(is_ci(|v: &str| (v == "CI").then(|| "true".to_string())));
        assert!(!is_ci(|v: &str| (v == "CI").then(|| "false".to_string())));
    }

    #[test]
    fn detects_something_plausible_here() {
        let mut e = StEnvironment::default();
        assert_eq!(unsafe { st_environment(&mut e) }, crate::ST_OK);
        assert!(e.vm == ST_VM_NONE || e.vm <= ST_VM_NITRO || e.vm == ST_VM_UNKNOWN);
        assert!(e.kind <= ST_KIND_MOBILE);
        assert_eq!(e.vm_vendor[47], 0);
        assert_eq!(e.cloud[15], 0);
        if std::env::var("GITHUB_ACTIONS").is_ok() {
            assert_ne!(e.flags & ST_ENV_CI, 0);
        }
    }

    #[test]
    fn null_is_rejected() {
        assert_eq!(
            unsafe { st_environment(std::ptr::null_mut()) },
            crate::ST_ERR_NULL
        );
    }

    #[test]
    fn layout_matches_the_c_header() {
        assert_eq!(std::mem::size_of::<StEnvironment>(), 80);
        assert_eq!(std::mem::offset_of!(StEnvironment, vm_vendor), 16);
        assert_eq!(std::mem::offset_of!(StEnvironment, cloud), 64);
    }
}
