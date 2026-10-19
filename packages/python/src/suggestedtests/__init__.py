"""Test helpers for pytest, backed by an OS-native bridge.

::

    from suggestedtests import expect_performance, eventually, MiB, expect_memory

The pytest plugin (fixtures `test_data` and `steps`, marker
`requires_native_bridge`, option `--st-seed`) loads automatically.
"""

from .assertions import assert_unique, no_leaked_threads
from .eventually import eventually, eventually_async
from .memory import (
    AllocationReport,
    GiB,
    KiB,
    MemoryReport,
    MiB,
    expect_allocations,
    expect_memory,
    measure_memory,
)
from .performance import (
    BenchmarkResult,
    Clock,
    Statistic,
    benchmark,
    benchmark_async,
    completes_within,
    expect_performance,
    expect_performance_async,
)
from .scenario import Steps
from .system_probe import (
    CpuTime,
    MemoryUsage,
    NativeBridgeError,
    SystemProbe,
    format_bytes,
    format_ns,
)
from .test_data import TestData

__all__ = [
    "AllocationReport",
    "BenchmarkResult",
    "Clock",
    "CpuTime",
    "GiB",
    "KiB",
    "MemoryReport",
    "MemoryUsage",
    "MiB",
    "NativeBridgeError",
    "Statistic",
    "Steps",
    "SystemProbe",
    "TestData",
    "assert_unique",
    "benchmark",
    "benchmark_async",
    "completes_within",
    "eventually",
    "eventually_async",
    "expect_allocations",
    "expect_memory",
    "expect_performance",
    "expect_performance_async",
    "format_bytes",
    "format_ns",
    "measure_memory",
    "no_leaked_threads",
]

# Load the native bridge now, at import (pytest imports this package through
# the plugin), so the bridge's startup report (SUGGESTEDTESTS_VERBOSE=1) is
# printed even in runs that never call a native helper. It never raises: where
# the bridge is missing, SystemProbe says why when it is used.
SystemProbe._probe()
