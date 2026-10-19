"""ctypes bindings to the Rust bridge in the monorepo's `native/`.

Mirrors `native/include/suggestedtests_native.h`; keep the two in sync.

The library is looked up, in order, at:

1. `$SUGGESTEDTESTS_NATIVE_LIB` (an explicit path, e.g. a local cargo build),
2. `suggestedtests/_prebuilt/<platform>/` (installed wheels),
3. `native/prebuilt/<platform>/` of the monorepo (development checkout).
"""

from __future__ import annotations

import ctypes
import os
import platform
import struct
import sys
from pathlib import Path

ABI_VERSION = 1

OK = 0
ERR_NULL = -1
LOAD_AT_LOAD = 1  # st_load_state(): initializers ran from the OS loader hook
ERR_UNSUPPORTED = -2
ERR_UNKNOWN = -3

ENV_VAR = "SUGGESTEDTESTS_NATIVE_LIB"
VERBOSE_ENV_VAR = "SUGGESTEDTESTS_VERBOSE"  # read by the bridge when it loads


class StCpuTime(ctypes.Structure):
    """`StCpuTime` from the C header."""

    _fields_ = [("user_ns", ctypes.c_uint64), ("system_ns", ctypes.c_uint64)]


class StMemory(ctypes.Structure):
    """`StMemory` from the C header."""

    _fields_ = [
        ("current_rss_bytes", ctypes.c_uint64),
        ("peak_rss_bytes", ctypes.c_uint64),
    ]


def elf_interpreter(path: str) -> str | None:
    """The program interpreter (`PT_INTERP`) of a little-endian ELF file (32 or 64-bit)."""
    try:
        with open(path, "rb") as f:
            header = f.read(64)
            is_elf = len(header) >= 52 and header[:4] == b"\x7fELF"
            if not is_elf or header[4] not in (1, 2) or header[5] != 1:
                return None
            if header[4] == 2:  # ELFCLASS64
                (ph_offset,) = struct.unpack_from("<Q", header, 0x20)
                ph_size, ph_count = struct.unpack_from("<HH", header, 0x36)
            else:  # ELFCLASS32
                (ph_offset,) = struct.unpack_from("<I", header, 0x1C)
                ph_size, ph_count = struct.unpack_from("<HH", header, 0x2A)
            for i in range(ph_count):
                f.seek(ph_offset + i * ph_size)
                ph = f.read(ph_size)
                if len(ph) < 32 or struct.unpack_from("<I", ph, 0)[0] != 3:  # PT_INTERP
                    continue
                if header[4] == 2:
                    (offset,) = struct.unpack_from("<Q", ph, 8)
                    (size,) = struct.unpack_from("<Q", ph, 32)
                else:
                    (offset,) = struct.unpack_from("<I", ph, 4)
                    (size,) = struct.unpack_from("<I", ph, 16)
                f.seek(offset)
                return f.read(min(size, 4096)).split(b"\0", 1)[0].decode()
    except OSError:
        return None
    return None


def _uses_musl() -> bool:
    # A library built for one libc can't be loaded into a process using the
    # other, so ask the running interpreter rather than the system.
    interpreter = elf_interpreter(sys.executable)
    if interpreter is not None:
        return "musl" in interpreter
    libc, _ = platform.libc_ver()
    return libc != "glibc" and any(Path("/lib").glob("ld-musl-*"))


_ARCHES = {
    "x86_64": "x64",
    "amd64": "x64",
    "aarch64": "arm64",
    "arm64": "arm64",
    "i386": "x86",
    "i486": "x86",
    "i586": "x86",
    "i686": "x86",
    "x86": "x86",
    "armv7l": "arm",
    "armv7": "arm",
    "armv8l": "arm",
    "arm": "arm",
    "riscv64": "riscv64",
}

_ANDROID_ABIS = {"arm64": "arm64-v8a", "arm": "armeabi-v7a", "x64": "x86_64", "x86": "x86"}


def _is_android() -> bool:
    return sys.platform == "android" or hasattr(sys, "getandroidapilevel")


def platform_dir() -> str | None:
    """`<os>-<arch>[-musl]`, the prebuilt directory for this process, or None."""
    arch = _ARCHES.get(platform.machine().lower())
    if arch is None:
        return None
    if sys.maxsize <= 2**32:  # a 32-bit interpreter on a 64-bit OS
        arch = {"x64": "x86", "arm64": "arm"}.get(arch, arch)
    if _is_android():
        abi = _ANDROID_ABIS.get(arch)
        return f"android-{abi}" if abi else None
    if sys.platform.startswith("linux"):
        return f"linux-{arch}{'-musl' if _uses_musl() else ''}"
    if sys.platform == "darwin":
        return f"macos-{arch}"
    if sys.platform == "win32":
        return f"windows-{arch}"
    return None


def library_file_name() -> str:
    """The bridge's file name on this OS."""
    if sys.platform == "win32":
        return "suggestedtests_native.dll"
    if sys.platform == "darwin":
        return "libsuggestedtests_native.dylib"
    return "libsuggestedtests_native.so"


def candidates() -> list[Path]:
    """Paths the library is looked up at, in order."""
    if explicit := os.environ.get(ENV_VAR):
        return [Path(explicit)]
    pdir = platform_dir()
    if pdir is None:
        return []
    name = library_file_name()
    here = Path(__file__).resolve().parent
    # packages/python/src/suggestedtests/_native.py -> repository root
    repo = here.parents[3] if len(here.parents) > 3 else here
    return [
        here / "_prebuilt" / pdir / name,
        repo / "native" / "prebuilt" / pdir / name,
    ]


def load() -> ctypes.CDLL:
    """Loads the bridge and declares its signatures. Raises OSError if missing."""
    paths = candidates()
    if not paths:
        raise OSError(f"no prebuilt bridge for {sys.platform}/{platform.machine()}")
    found = next((p for p in paths if p.is_file()), None)
    if found is None:
        raise OSError("bridge library not found at: " + ", ".join(str(p) for p in paths))
    lib = ctypes.CDLL(str(found))
    lib.st_abi_version.restype = ctypes.c_uint32
    lib.st_abi_version.argtypes = []
    lib.st_process_cpu_time.restype = ctypes.c_int32
    lib.st_process_cpu_time.argtypes = [ctypes.POINTER(StCpuTime)]
    lib.st_thread_cpu_time_ns.restype = ctypes.c_int32
    lib.st_thread_cpu_time_ns.argtypes = [ctypes.POINTER(ctypes.c_uint64)]
    lib.st_memory_usage.restype = ctypes.c_int32
    lib.st_memory_usage.argtypes = [ctypes.POINTER(StMemory)]
    lib.st_cpu_count.restype = ctypes.c_uint32
    lib.st_cpu_count.argtypes = []
    lib.st_load_state.restype = ctypes.c_uint32
    lib.st_load_state.argtypes = []
    lib.st_set_verbose.restype = ctypes.c_uint32
    lib.st_set_verbose.argtypes = [ctypes.c_uint32]
    lib.st_verbose.restype = ctypes.c_uint32
    lib.st_verbose.argtypes = []
    try:
        # Additive, no ABI bump: an older prebuilt may predate this symbol.
        lib.st_on_load.restype = None
        lib.st_on_load.argtypes = []
    except AttributeError:
        pass
    return lib
