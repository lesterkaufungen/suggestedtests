# Loads a prebuilt bridge library with ctypes and calls every export.
# Used by tool/release_build.sh; also runs on old systems (Alpine for musl,
# CentOS 7 for glibc 2.17). Python 2 and 3 compatible.
#
#   python3 tool/check_load.py native/prebuilt/linux-x64-musl/libsuggestedtests_native.so
from __future__ import print_function

import ctypes
import os
import sys


class CpuTime(ctypes.Structure):
    _fields_ = [("user_ns", ctypes.c_uint64), ("system_ns", ctypes.c_uint64)]


class Memory(ctypes.Structure):
    _fields_ = [("current", ctypes.c_uint64), ("peak", ctypes.c_uint64)]


class Platform(ctypes.Structure):
    _fields_ = [("os", ctypes.c_uint32), ("arch", ctypes.c_uint32), ("libc", ctypes.c_uint32),
                ("pointer_bits", ctypes.c_uint32), ("flags", ctypes.c_uint32),
                ("os_version", ctypes.c_char * 64), ("libc_version", ctypes.c_char * 32)]


class Environment(ctypes.Structure):
    _fields_ = [("container", ctypes.c_uint32), ("vm", ctypes.c_uint32), ("kind", ctypes.c_uint32),
                ("flags", ctypes.c_uint32), ("vm_vendor", ctypes.c_char * 48), ("cloud", ctypes.c_char * 16)]


assert ctypes.sizeof(Platform) == 116 and ctypes.sizeof(Environment) == 80, "struct layout changed"


lib = ctypes.CDLL(sys.argv[1])
cpu, mem, thread = CpuTime(), Memory(), ctypes.c_uint64()

# Before any other call: native/src/load.rs's loader hook must have run.
load_state = lib.st_load_state()
assert load_state == 1, "load-time initializers didn't run from the loader (state %d)" % load_state

assert lib.st_abi_version() == 1, "unexpected ABI version"
# The startup report (native/src/report.rs) is on only with SUGGESTEDTESTS_VERBOSE.
want_verbose = os.environ.get("SUGGESTEDTESTS_VERBOSE", "").strip().lower() in ("1", "true", "yes", "on")
assert lib.st_verbose() == int(want_verbose), "verbose flag doesn't match SUGGESTEDTESTS_VERBOSE"
assert lib.st_set_verbose(int(want_verbose)) == int(want_verbose)
assert lib.st_cpu_count() >= 1
assert lib.st_process_cpu_time(ctypes.byref(cpu)) == 0
assert lib.st_thread_cpu_time_ns(ctypes.byref(thread)) == 0
assert lib.st_memory_usage(ctypes.byref(mem)) == 0
assert mem.current > 0 and mem.peak >= mem.current
plat, env = Platform(), Environment()
assert lib.st_platform(ctypes.byref(plat)) == 0
assert lib.st_environment(ctypes.byref(env)) == 0
assert plat.os != 0 and plat.arch != 0 and plat.libc != 0, "unknown build target"
assert plat.pointer_bits == ctypes.sizeof(ctypes.c_void_p) * 8
print("OK", sys.argv[1], "load=%d rss=%d cpus=%d os=%d arch=%d libc=%d (%s, libc %s) container=%d vm=%d (%s) kind=%d" % (
    load_state, mem.current, lib.st_cpu_count(), plat.os, plat.arch, plat.libc, plat.os_version.decode(),
    plat.libc_version.decode() or "?", env.container, env.vm, env.vm_vendor.decode(), env.kind))
