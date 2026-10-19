"""Checks the macOS prebuilts the way dyld would, without a Mac.

For each native/prebuilt/macos-*/ file (the C library and the Node addon):

* on arm64, a code signature (ad-hoc is enough) whose page hashes match the
  file: macOS refuses unsigned arm64 libraries in every host ("Trying to load
  an unsigned library"). x86_64 needs none: tested on macOS 26.5, an unsigned
  x86_64 library loads wherever an ad-hoc signed one does (plain hosts, and
  hardened ones with disable-library-validation), so a signature there is
  only checked when present;
* a minimum macOS no newer than the packages promise (10.13 on x86_64, 11.0,
  the first Apple Silicon release, on arm64);
* only system libraries (libSystem, libiconv) linked;
* the load-time initializer (native/src/load.rs) in __mod_init_func or
  __init_offsets: it prints the startup report.

Used by tool/release_build.sh after the prebuilts are built.

    python3 tool/check_macho.py native/prebuilt/macos-*/*
"""

from __future__ import annotations

import hashlib
import struct
import sys
from pathlib import Path

LC_SEGMENT_64, LC_BUILD_VERSION, LC_VERSION_MIN_MACOSX = 0x19, 0x32, 0x24
LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_CODE_SIGNATURE = 0xC, 0x80000018, 0x8000001F, 0x1D
MAX_MINOS = {"x86_64": (10, 13), "arm64": (11, 0)}
SYSTEM_LIBRARIES = {"/usr/lib/libSystem.B.dylib", "/usr/lib/libiconv.2.dylib"}


def check(path: str) -> list[str]:
    data = Path(path).read_bytes()
    magic, cpu, _, _, ncmds, _, _ = struct.unpack_from("<IiiIIII", data)
    if magic != 0xFEEDFACF:
        return ["not a 64-bit little-endian Mach-O"]
    arch = {0x01000007: "x86_64", 0x0100000C: "arm64"}.get(cpu, hex(cpu))
    problems, minos, initializers, signature = [], None, 0, None
    offset = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, offset)
        if cmd == LC_BUILD_VERSION:
            minos = struct.unpack_from("<I", data, offset + 12)[0]
        elif cmd == LC_VERSION_MIN_MACOSX:
            minos = struct.unpack_from("<I", data, offset + 8)[0]
        elif cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB):
            name_offset = struct.unpack_from("<I", data, offset + 8)[0]
            library = data[offset + name_offset : offset + size].split(b"\0")[0].decode()
            if library not in SYSTEM_LIBRARIES:
                problems.append(f"links {library}, which isn't a system library on every Mac")
        elif cmd == LC_SEGMENT_64:
            for i in range(struct.unpack_from("<I", data, offset + 64)[0]):
                section = offset + 72 + i * 80
                section_type = struct.unpack_from("<I", data, section + 64)[0] & 0xFF
                if section_type in (0x9, 0x16):  # S_MOD_INIT_FUNC_POINTERS, S_INIT_FUNC_OFFSETS
                    initializers += struct.unpack_from("<Q", data, section + 40)[0]
        elif cmd == LC_CODE_SIGNATURE:
            signature = struct.unpack_from("<II", data, offset + 8)
        offset += size

    if minos is None:
        problems.append("no minimum macOS version")
    elif ((minos >> 16), (minos >> 8) & 0xFF) > MAX_MINOS.get(arch, (0, 0)):
        problems.append(f"needs macOS {minos >> 16}.{(minos >> 8) & 0xFF}, newer than {MAX_MINOS.get(arch)}")
    if not initializers:
        problems.append("no load-time initializer (__mod_init_func / __init_offsets)")
    if signature is None:
        if arch == "arm64":
            problems.append("no code signature: macOS refuses unsigned arm64 libraries")
    else:
        problems += _check_signature(data, *signature)
    return problems


def _check_signature(data: bytes, offset: int, size: int) -> list[str]:
    blob = data[offset : offset + size]
    magic, _, count = struct.unpack_from(">III", blob)
    if magic != 0xFADE0CC0:
        return ["code signature isn't a SuperBlob"]
    for i in range(count):
        _, blob_offset = struct.unpack_from(">II", blob, 12 + 8 * i)
        if struct.unpack_from(">I", blob, blob_offset)[0] != 0xFADE0C02:
            continue  # requirements, entitlements, …: only the CodeDirectory has the hashes
        (_, _, _, _, hash_offset, _, _, pages, code_limit, hash_size, hash_type, _, page_log) = (
            struct.unpack_from(">IIIIIIIIIBBBB", blob, blob_offset)
        )
        if code_limit != offset:
            return [f"signature covers {code_limit} bytes, not the {offset} before it"]
        algorithm = {1: hashlib.sha1, 2: hashlib.sha256}.get(hash_type)
        if algorithm is None:
            return [f"unknown signature hash type {hash_type}"]
        page = 1 << page_log
        start = blob_offset + hash_offset
        bad = [
            n
            for n in range(pages)
            if algorithm(data[n * page : min((n + 1) * page, code_limit)]).digest()[:hash_size]
            != blob[start + n * hash_size : start + (n + 1) * hash_size]
        ]
        return (
            [f"code signature doesn't match pages {bad[:5]}: the file changed after signing"] if bad else []
        )
    return ["code signature has no CodeDirectory"]


def main() -> None:
    failed = False
    for path in sys.argv[1:]:
        problems = check(path)
        failed |= bool(problems)
        print(("FAIL " if problems else "OK   ") + path + "".join(f"\n     {p}" for p in problems))
    if not sys.argv[1:]:
        sys.exit("usage: check_macho.py <macOS dylib or .node>...")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
