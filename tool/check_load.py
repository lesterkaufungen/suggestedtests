# Loads a prebuilt bridge library with ctypes and calls every export.
# Used by CI to prove the musl build loads on Alpine and the glibc build loads
# on glibc 2.17 (CentOS 7). Python 2 and 3 compatible.
#
#   python3 tool/check_load.py native/prebuilt/linux-x64-musl/libsuggestedtests_native.so
from __future__ import print_function

import ctypes
import sys


class CpuTime(ctypes.Structure):
    _fields_ = [("user_ns", ctypes.c_uint64), ("system_ns", ctypes.c_uint64)]


class Memory(ctypes.Structure):
    _fields_ = [("current", ctypes.c_uint64), ("peak", ctypes.c_uint64)]


lib = ctypes.CDLL(sys.argv[1])
cpu, mem, thread = CpuTime(), Memory(), ctypes.c_uint64()

assert lib.st_abi_version() == 1, "unexpected ABI version"
assert lib.st_cpu_count() >= 1
assert lib.st_process_cpu_time(ctypes.byref(cpu)) == 0
assert lib.st_thread_cpu_time_ns(ctypes.byref(thread)) == 0
assert lib.st_memory_usage(ctypes.byref(mem)) == 0
assert mem.current > 0 and mem.peak >= mem.current
print("OK", sys.argv[1], "rss=%d cpus=%d" % (mem.current, lib.st_cpu_count()))
