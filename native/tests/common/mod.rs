//! Shared by `tests/prebuilt.rs` (and, on the `local-only` branch, the
//! `download` feature's `tests/published.rs`): the prebuilt targets, what
//! they must export, and a minimal reader for ELF, PE and Mach-O shared
//! libraries (no dependencies, nothing is executed).

#![allow(dead_code)]

use std::collections::BTreeSet;
use std::path::PathBuf;

use suggestedtests_native::platform::*;

/// One `native/prebuilt/<dir>/`.
pub struct Target {
    pub dir: &'static str,
    /// `ST_OS_*`.
    pub os: u32,
    /// `ST_ARCH_*`.
    pub arch: u32,
    /// `ST_LIBC_*`.
    pub libc: u32,
}

const fn t(dir: &'static str, os: u32, arch: u32, libc: u32) -> Target {
    Target {
        dir,
        os,
        arch,
        libc,
    }
}

/// Every shipped target (CLAUDE.md, "19 prebuilt targets").
pub const TARGETS: &[Target] = &[
    t("linux-x64", ST_OS_LINUX, ST_ARCH_X86_64, ST_LIBC_GLIBC),
    t("linux-arm64", ST_OS_LINUX, ST_ARCH_AARCH64, ST_LIBC_GLIBC),
    t("linux-x86", ST_OS_LINUX, ST_ARCH_X86, ST_LIBC_GLIBC),
    t("linux-arm", ST_OS_LINUX, ST_ARCH_ARM, ST_LIBC_GLIBC),
    t("linux-riscv64", ST_OS_LINUX, ST_ARCH_RISCV64, ST_LIBC_GLIBC),
    t("linux-x64-musl", ST_OS_LINUX, ST_ARCH_X86_64, ST_LIBC_MUSL),
    t(
        "linux-arm64-musl",
        ST_OS_LINUX,
        ST_ARCH_AARCH64,
        ST_LIBC_MUSL,
    ),
    t("linux-x86-musl", ST_OS_LINUX, ST_ARCH_X86, ST_LIBC_MUSL),
    t("linux-arm-musl", ST_OS_LINUX, ST_ARCH_ARM, ST_LIBC_MUSL),
    t(
        "linux-riscv64-musl",
        ST_OS_LINUX,
        ST_ARCH_RISCV64,
        ST_LIBC_MUSL,
    ),
    t("macos-x64", ST_OS_MACOS, ST_ARCH_X86_64, ST_LIBC_APPLE),
    t("macos-arm64", ST_OS_MACOS, ST_ARCH_AARCH64, ST_LIBC_APPLE),
    t("windows-x64", ST_OS_WINDOWS, ST_ARCH_X86_64, ST_LIBC_MSVC),
    t(
        "windows-arm64",
        ST_OS_WINDOWS,
        ST_ARCH_AARCH64,
        ST_LIBC_MSVC,
    ),
    t("windows-x86", ST_OS_WINDOWS, ST_ARCH_X86, ST_LIBC_MSVC),
    t(
        "android-arm64-v8a",
        ST_OS_ANDROID,
        ST_ARCH_AARCH64,
        ST_LIBC_BIONIC,
    ),
    t(
        "android-armeabi-v7a",
        ST_OS_ANDROID,
        ST_ARCH_ARM,
        ST_LIBC_BIONIC,
    ),
    t(
        "android-x86_64",
        ST_OS_ANDROID,
        ST_ARCH_X86_64,
        ST_LIBC_BIONIC,
    ),
    t("android-x86", ST_OS_ANDROID, ST_ARCH_X86, ST_LIBC_BIONIC),
];

/// The Node addon's file name (Android has none).
pub const NODE_ADDON: &str = "suggestedtests_native.node";

impl Target {
    /// The C/JNI library's file name.
    pub fn library(&self) -> &'static str {
        match self.os {
            ST_OS_WINDOWS => "suggestedtests_native.dll",
            ST_OS_MACOS => "libsuggestedtests_native.dylib",
            _ => "libsuggestedtests_native.so",
        }
    }

    /// The files shipped in `dir`.
    pub fn files(&self) -> Vec<&'static str> {
        if self.os == ST_OS_ANDROID {
            vec![self.library()]
        } else {
            vec![self.library(), NODE_ADDON]
        }
    }

    fn format(&self) -> Format {
        match self.os {
            ST_OS_WINDOWS => Format::Pe,
            ST_OS_MACOS => Format::MachO,
            _ => Format::Elf,
        }
    }

    fn bits(&self) -> u32 {
        match self.arch {
            ST_ARCH_X86 | ST_ARCH_ARM => 32,
            _ => 64,
        }
    }

    /// The newest glibc symbol version a glibc build may need.
    fn glibc_max(&self) -> (u32, u32) {
        if self.arch == ST_ARCH_RISCV64 {
            (2, 27)
        } else {
            (2, 17)
        }
    }
}

/// The target of the running process, if a prebuilt is shipped for it.
pub fn host() -> Option<&'static Target> {
    let mut p = StPlatform::default();
    // SAFETY: `p` is a live, writable `StPlatform`.
    unsafe { st_platform(&mut p) };
    TARGETS
        .iter()
        .find(|t| t.os == p.os && t.arch == p.arch && t.libc == p.libc)
}

/// `native/`.
pub fn native_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn read_source(path: &str) -> String {
    let path = native_dir().join(path);
    std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
}

/// The `st_*` functions declared in the C header.
pub fn header_functions() -> BTreeSet<String> {
    let header = read_source("include/suggestedtests_native.h");
    header
        .lines()
        .filter(|l| {
            let l = l.trim_start();
            !(l.starts_with('*')
                || l.starts_with("/*")
                || l.starts_with("//")
                || l.starts_with('#'))
        })
        .filter_map(|l| {
            let start = l.find("st_")?;
            let name: String = l[start..]
                .chars()
                .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                .collect();
            l[start + name.len()..].starts_with('(').then_some(name)
        })
        .collect()
}

/// The `Java_*` functions in `src/jni.rs`.
pub fn jni_functions() -> BTreeSet<String> {
    read_source("src/jni.rs")
        .split("fn ")
        .skip(1)
        .filter(|s| s.starts_with("Java_"))
        .map(|s| {
            s.chars()
                .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                .collect()
        })
        .collect()
}

/// What the C/JNI library must export, exactly.
pub fn library_exports() -> BTreeSet<String> {
    let mut all = header_functions();
    all.extend(jni_functions());
    all
}

/// Everything wrong with `bytes` as `file` of target `t`; empty if nothing.
pub fn check(t: &Target, file: &str, bytes: &[u8], exports: &BTreeSet<String>) -> Vec<String> {
    let b = match Binary::parse(bytes) {
        Ok(b) => b,
        Err(e) => return vec![format!("unreadable: {e}")],
    };
    let mut problems = Vec::new();
    if b.format != t.format() || b.arch != t.arch || b.bits != t.bits() {
        problems.push(format!(
            "built for {:?} {}-bit arch {}, expected {:?} {}-bit arch {}",
            b.format,
            b.bits,
            b.arch,
            t.format(),
            t.bits(),
            t.arch
        ));
    }
    if !b.shared {
        problems.push("not a shared library".to_string());
    }

    if file == NODE_ADDON {
        if !b.exports.contains("napi_register_module_v1") {
            problems.push("doesn't export napi_register_module_v1".to_string());
        }
        // The addon resolves napi_* when loaded (CLAUDE.md): nothing for
        // the dynamic linker to bind, and no node.lib / node.exe import.
        let napi: Vec<_> = b
            .undefined
            .iter()
            .filter(|s| s.starts_with("napi_"))
            .collect();
        if !napi.is_empty() {
            problems.push(format!("links napi_* at load time: {napi:?}"));
        }
        if b.needed
            .iter()
            .any(|n| n.to_ascii_lowercase().starts_with("node"))
        {
            problems.push(format!("imports Node itself: {:?}", b.needed));
        }
    } else if &b.exports != exports {
        let missing: Vec<_> = exports.difference(&b.exports).collect();
        let extra: Vec<_> = b.exports.difference(exports).collect();
        problems.push(format!(
            "exports differ from the header and jni.rs: missing {missing:?}, unexpected {extra:?}"
        ));
    }

    let needs = |name: &str| b.needed.iter().any(|n| n == name);
    match t.libc {
        ST_LIBC_GLIBC => {
            if !needs("libc.so.6") {
                problems.push(format!(
                    "glibc build doesn't need libc.so.6: {:?}",
                    b.needed
                ));
            }
            let max = t.glibc_max();
            let too_new: Vec<_> = b.glibc.iter().filter(|v| **v > max).collect();
            if !too_new.is_empty() {
                problems.push(format!("needs glibc newer than {max:?}: {too_new:?}"));
            }
        }
        ST_LIBC_MUSL | ST_LIBC_BIONIC => {
            if !needs("libc.so") || needs("libc.so.6") || !b.glibc.is_empty() {
                problems.push(format!(
                    "not linked against {}'s libc.so: {:?}",
                    if t.libc == ST_LIBC_MUSL {
                        "musl"
                    } else {
                        "bionic"
                    },
                    b.needed
                ));
            }
        }
        ST_LIBC_MSVC => {
            let crt: Vec<_> = b
                .needed
                .iter()
                .filter(|n| {
                    let n = n.to_ascii_lowercase();
                    ["vcruntime", "msvcp", "ucrtbase", "api-ms-win-crt-"]
                        .iter()
                        .any(|p| n.starts_with(p))
                })
                .collect();
            if !crt.is_empty() {
                problems.push(format!("CRT not linked statically: needs {crt:?}"));
            }
        }
        _ => {}
    }
    if t.os == ST_OS_ANDROID && b.min_load_align.map_or(true, |a| a < 16384) {
        problems.push(format!(
            "segments aligned to {:?}, Android needs 16 KB pages",
            b.min_load_align
        ));
    }
    if t.arch == ST_ARCH_ARM && b.format == Format::Elf {
        // Linux ARMv7 prebuilts are armhf; Android's armeabi-v7a is softfp.
        let want_hard = t.os == ST_OS_LINUX;
        if b.arm_hard_float != want_hard {
            problems.push(format!(
                "{} float ABI, expected {}",
                if b.arm_hard_float { "hard" } else { "soft" },
                if want_hard { "hard" } else { "soft" }
            ));
        }
    }
    problems
}

// ---------------------------------------------------------------- reader --

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    Elf,
    Pe,
    MachO,
}

/// What [`check`] needs from a shared library.
#[derive(Debug)]
pub struct Binary {
    pub format: Format,
    /// `ST_ARCH_*`.
    pub arch: u32,
    pub bits: u32,
    /// ELF `ET_DYN`, PE `IMAGE_FILE_DLL`, Mach-O dylib or bundle.
    pub shared: bool,
    /// Defined, exported symbols (Mach-O without the leading `_`).
    pub exports: BTreeSet<String>,
    /// Symbols the dynamic linker must bind (ELF, Mach-O).
    pub undefined: BTreeSet<String>,
    /// ELF `DT_NEEDED`, PE imported DLLs, Mach-O `LC_LOAD_DYLIB`.
    pub needed: Vec<String>,
    /// Required `GLIBC_x.y` symbol versions (ELF).
    pub glibc: Vec<(u32, u32)>,
    /// `EF_ARM_ABI_FLOAT_HARD` (ELF, ARM).
    pub arm_hard_float: bool,
    /// The smallest `PT_LOAD` alignment (ELF).
    pub min_load_align: Option<u64>,
}

/// Little-endian reads that fail instead of panicking on a truncated file.
struct Bytes<'a>(&'a [u8]);

impl Bytes<'_> {
    fn get<const N: usize>(&self, off: u64) -> Result<[u8; N], String> {
        usize::try_from(off)
            .ok()
            .and_then(|o| self.0.get(o..o.checked_add(N)?))
            .map(|s| s.try_into().unwrap())
            .ok_or_else(|| format!("truncated at offset {off:#x}"))
    }
    fn u8(&self, off: u64) -> Result<u8, String> {
        Ok(self.get::<1>(off)?[0])
    }
    fn u16(&self, off: u64) -> Result<u16, String> {
        self.get(off).map(u16::from_le_bytes)
    }
    fn u32(&self, off: u64) -> Result<u32, String> {
        self.get(off).map(u32::from_le_bytes)
    }
    fn u64(&self, off: u64) -> Result<u64, String> {
        self.get(off).map(u64::from_le_bytes)
    }
    /// A 32- or 64-bit word.
    fn word(&self, off: u64, is64: bool) -> Result<u64, String> {
        if is64 {
            self.u64(off)
        } else {
            self.u32(off).map(u64::from)
        }
    }
    fn cstr(&self, off: u64) -> Result<String, String> {
        let start = usize::try_from(off).map_err(|_| "offset overflow".to_string())?;
        let rest = self
            .0
            .get(start..)
            .ok_or_else(|| format!("string out of bounds at {off:#x}"))?;
        let end = rest
            .iter()
            .position(|&b| b == 0)
            .ok_or_else(|| format!("unterminated string at {off:#x}"))?;
        Ok(String::from_utf8_lossy(&rest[..end]).into_owned())
    }
}

impl Binary {
    pub fn parse(bytes: &[u8]) -> Result<Binary, String> {
        let r = Bytes(bytes);
        match r.get::<4>(0)? {
            [0x7f, b'E', b'L', b'F'] => parse_elf(&r),
            [b'M', b'Z', ..] => parse_pe(&r),
            [0xcf, 0xfa, 0xed, 0xfe] => parse_macho(&r, true),
            [0xce, 0xfa, 0xed, 0xfe] => parse_macho(&r, false),
            magic => Err(format!("unknown file type (magic {magic:02x?})")),
        }
    }

    fn new(format: Format, arch: u32, bits: u32, shared: bool) -> Binary {
        Binary {
            format,
            arch,
            bits,
            shared,
            exports: BTreeSet::new(),
            undefined: BTreeSet::new(),
            needed: Vec::new(),
            glibc: Vec::new(),
            arm_hard_float: false,
            min_load_align: None,
        }
    }
}

fn parse_elf(r: &Bytes) -> Result<Binary, String> {
    let is64 = match r.u8(4)? {
        1 => false,
        2 => true,
        c => return Err(format!("bad ELF class {c}")),
    };
    if r.u8(5)? != 1 {
        return Err("big-endian ELF".to_string());
    }
    let machine = r.u16(18)?;
    let arch = match machine {
        62 => ST_ARCH_X86_64,
        183 => ST_ARCH_AARCH64,
        3 => ST_ARCH_X86,
        40 => ST_ARCH_ARM,
        243 => ST_ARCH_RISCV64,
        _ => ST_ARCH_UNKNOWN,
    };
    // ET_DYN
    let mut b = Binary::new(
        Format::Elf,
        arch,
        if is64 { 64 } else { 32 },
        r.u16(16)? == 3,
    );
    let (phoff, shoff, flags, phentsize, phnum, shentsize, shnum) = if is64 {
        (
            r.u64(32)?,
            r.u64(40)?,
            r.u32(48)?,
            r.u16(54)?,
            r.u16(56)?,
            r.u16(58)?,
            r.u16(60)?,
        )
    } else {
        let (phoff, shoff) = (r.u32(28)?.into(), r.u32(32)?.into());
        (
            phoff,
            shoff,
            r.u32(36)?,
            r.u16(42)?,
            r.u16(44)?,
            r.u16(46)?,
            r.u16(48)?,
        )
    };
    b.arm_hard_float = machine == 40 && flags & 0x400 != 0;

    for i in 0..u64::from(phnum) {
        let ph = phoff + i * u64::from(phentsize);
        if r.u32(ph)? == 1 {
            // PT_LOAD
            let align = r.word(ph + if is64 { 48 } else { 28 }, is64)?;
            b.min_load_align = Some(b.min_load_align.map_or(align, |a| a.min(align)));
        }
    }

    struct Section {
        kind: u32,
        offset: u64,
        size: u64,
        link: u32,
        info: u32,
    }
    let section = |i: u64| -> Result<Section, String> {
        let sh = shoff + i * u64::from(shentsize);
        Ok(if is64 {
            Section {
                kind: r.u32(sh + 4)?,
                offset: r.u64(sh + 24)?,
                size: r.u64(sh + 32)?,
                link: r.u32(sh + 40)?,
                info: r.u32(sh + 44)?,
            }
        } else {
            Section {
                kind: r.u32(sh + 4)?,
                offset: r.u32(sh + 16)?.into(),
                size: r.u32(sh + 20)?.into(),
                link: r.u32(sh + 24)?,
                info: r.u32(sh + 28)?,
            }
        })
    };
    let strtab = |link: u32| section(u64::from(link)).map(|s| s.offset);

    for i in 0..u64::from(shnum) {
        let s = section(i)?;
        match s.kind {
            // SHT_DYNSYM
            11 => {
                let (entsize, info_at, shndx_at) = if is64 { (24, 4, 6) } else { (16, 12, 14) };
                let names = strtab(s.link)?;
                for k in 1..s.size / entsize {
                    let sym = s.offset + k * entsize;
                    let name = r.cstr(names + u64::from(r.u32(sym)?))?;
                    let info = r.u8(sym + info_at)?;
                    let (bind, kind) = (info >> 4, info & 0xf);
                    if name.is_empty() || !(bind == 1 || bind == 2) || kind == 3 || kind == 4 {
                        continue; // local, section or file symbol
                    }
                    if r.u16(sym + shndx_at)? == 0 {
                        b.undefined.insert(name);
                    } else if r.u8(sym + info_at + 1)? & 3 == 0 {
                        b.exports.insert(name); // default visibility
                    }
                }
            }
            // SHT_DYNAMIC
            6 => {
                let entsize = if is64 { 16 } else { 8 };
                let names = strtab(s.link)?;
                for k in 0..s.size / entsize {
                    let entry = s.offset + k * entsize;
                    match r.word(entry, is64)? {
                        0 => break,
                        // DT_NEEDED
                        1 => b
                            .needed
                            .push(r.cstr(names + r.word(entry + entsize / 2, is64)?)?),
                        _ => {}
                    }
                }
            }
            // SHT_GNU_verneed
            0x6fff_fffe => {
                let names = strtab(s.link)?;
                let mut need = s.offset;
                for _ in 0..s.info {
                    let mut aux = need + u64::from(r.u32(need + 8)?);
                    for _ in 0..r.u16(need + 2)? {
                        let name = r.cstr(names + u64::from(r.u32(aux + 8)?))?;
                        if let Some(v) = name.strip_prefix("GLIBC_") {
                            let mut parts = v.split('.').map(|p| p.parse::<u32>());
                            if let (Some(Ok(major)), Some(Ok(minor))) = (parts.next(), parts.next())
                            {
                                b.glibc.push((major, minor));
                            }
                        }
                        aux += u64::from(r.u32(aux + 12)?);
                    }
                    let next = r.u32(need + 12)?;
                    if next == 0 {
                        break;
                    }
                    need += u64::from(next);
                }
            }
            _ => {}
        }
    }
    Ok(b)
}

fn parse_pe(r: &Bytes) -> Result<Binary, String> {
    let pe = u64::from(r.u32(0x3c)?);
    if r.get::<4>(pe)? != *b"PE\0\0" {
        return Err("no PE signature".to_string());
    }
    let coff = pe + 4;
    let arch = match r.u16(coff)? {
        0x8664 => ST_ARCH_X86_64,
        0xaa64 => ST_ARCH_AARCH64,
        0x14c => ST_ARCH_X86,
        0x1c4 => ST_ARCH_ARM,
        _ => ST_ARCH_UNKNOWN,
    };
    let sections = u64::from(r.u16(coff + 2)?);
    let opt_size = u64::from(r.u16(coff + 16)?);
    let shared = r.u16(coff + 18)? & 0x2000 != 0; // IMAGE_FILE_DLL
    let opt = coff + 20;
    let (bits, dirs) = match r.u16(opt)? {
        0x10b => (32, opt + 96),
        0x20b => (64, opt + 112),
        m => return Err(format!("bad optional header magic {m:#x}")),
    };
    let mut b = Binary::new(Format::Pe, arch, bits, shared);

    let section_table = opt + opt_size;
    let rva_to_offset = |rva: u32| -> Result<u64, String> {
        for i in 0..sections {
            let s = section_table + i * 40;
            let (vsize, va, raw_size, raw) = (
                r.u32(s + 8)?,
                r.u32(s + 12)?,
                r.u32(s + 16)?,
                r.u32(s + 20)?,
            );
            if rva >= va && rva - va < vsize.max(raw_size) {
                return Ok(u64::from(rva - va) + u64::from(raw));
            }
        }
        Err(format!("RVA {rva:#x} is in no section"))
    };

    let export_rva = r.u32(dirs)?;
    if export_rva != 0 {
        let dir = rva_to_offset(export_rva)?;
        let count = r.u32(dir + 24)?;
        let names = rva_to_offset(r.u32(dir + 32)?)?;
        for i in 0..u64::from(count) {
            b.exports
                .insert(r.cstr(rva_to_offset(r.u32(names + i * 4)?)?)?);
        }
    }
    let import_rva = r.u32(dirs + 8)?;
    if import_rva != 0 {
        let mut desc = rva_to_offset(import_rva)?;
        loop {
            let name = r.u32(desc + 12)?;
            if name == 0 {
                break;
            }
            b.needed.push(r.cstr(rva_to_offset(name)?)?);
            desc += 20;
        }
    }
    Ok(b)
}

fn parse_macho(r: &Bytes, is64: bool) -> Result<Binary, String> {
    let arch = match r.u32(4)? {
        0x0100_0007 => ST_ARCH_X86_64,
        0x0100_000c => ST_ARCH_AARCH64,
        7 => ST_ARCH_X86,
        12 => ST_ARCH_ARM,
        _ => ST_ARCH_UNKNOWN,
    };
    let filetype = r.u32(12)?;
    // MH_DYLIB, MH_BUNDLE
    let mut b = Binary::new(
        Format::MachO,
        arch,
        if is64 { 64 } else { 32 },
        filetype == 6 || filetype == 8,
    );
    let ncmds = r.u32(16)?;
    let mut cmd = if is64 { 32 } else { 28 };
    for _ in 0..ncmds {
        let (kind, size) = (r.u32(cmd)?, r.u32(cmd + 4)?);
        match kind {
            // LC_SYMTAB
            0x2 => {
                let (symoff, nsyms, stroff) = (r.u32(cmd + 8)?, r.u32(cmd + 12)?, r.u32(cmd + 16)?);
                let entsize = if is64 { 16 } else { 12 };
                for k in 0..u64::from(nsyms) {
                    let sym = u64::from(symoff) + k * entsize;
                    let kind = r.u8(sym + 4)?;
                    if kind & 0xe0 != 0 || kind & 1 == 0 {
                        continue; // debug or local
                    }
                    let name = r.cstr(u64::from(stroff) + u64::from(r.u32(sym)?))?;
                    let name = name.strip_prefix('_').unwrap_or(&name).to_string();
                    match kind & 0xe {
                        0x0 => b.undefined.insert(name),
                        0xe => b.exports.insert(name),
                        _ => false,
                    };
                }
            }
            // LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB
            0xc | 0x8000_0018 | 0x8000_001f => {
                b.needed.push(r.cstr(cmd + u64::from(r.u32(cmd + 8)?))?);
            }
            _ => {}
        }
        cmd += u64::from(size);
    }
    Ok(b)
}
