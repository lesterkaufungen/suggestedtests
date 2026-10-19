"""Process metrics read through the OS-agnostic Rust bridge."""

from __future__ import annotations

import ctypes
from dataclasses import dataclass
from typing import ClassVar

from . import _native


def format_bytes(n: int) -> str:
    """Formats a byte count as a human readable size, e.g. `12.5 MiB`."""
    units = ("B", "KiB", "MiB", "GiB", "TiB")
    value, unit = float(abs(n)), 0
    while value >= 1024 and unit < len(units) - 1:
        value /= 1024
        unit += 1
    if unit == 0:
        return f"{n} B"
    return f"{'-' if n < 0 else ''}{value:.1f} {units[unit]}"


def format_ns(ns: int | float) -> str:
    """Formats nanoseconds as `850µs`, `1.25ms` or `2.00s`."""
    us = ns / 1000
    if abs(us) < 1000:
        return f"{round(us)}µs"
    if abs(us) < 1_000_000:
        return f"{us / 1000:.2f}ms"
    return f"{us / 1_000_000:.2f}s"


@dataclass(frozen=True)
class CpuTime:
    """CPU time consumed by the process, split into user and kernel time."""

    user_ns: int
    """Time spent running user-space code."""
    system_ns: int
    """Time spent in the kernel on behalf of the process."""

    @property
    def total_ns(self) -> int:
        """`user_ns + system_ns`."""
        return self.user_ns + self.system_ns

    def __sub__(self, earlier: CpuTime) -> CpuTime:
        """The CPU time spent between `earlier` and this sample."""
        return CpuTime(self.user_ns - earlier.user_ns, self.system_ns - earlier.system_ns)

    def __str__(self) -> str:
        return f"CpuTime(user: {format_ns(self.user_ns)}, system: {format_ns(self.system_ns)})"


@dataclass(frozen=True)
class MemoryUsage:
    """Resident memory (RSS / working set) of the process, in bytes."""

    current_rss_bytes: int
    """Memory currently resident in RAM."""
    peak_rss_bytes: int
    """Highest resident memory since the process started."""

    def __str__(self) -> str:
        return (
            f"MemoryUsage(current: {format_bytes(self.current_rss_bytes)}, "
            f"peak: {format_bytes(self.peak_rss_bytes)})"
        )


class NativeBridgeError(RuntimeError):
    """Raised when the native bridge is missing or an OS call fails."""

    def __init__(self, operation: str, code: int, detail: str | None = None) -> None:
        self.operation = operation
        """The bridge function that failed."""
        self.code = code
        """Negative for bridge errors, positive for the raw OS error code
        (`errno` on Linux/macOS, `GetLastError()` on Windows)."""
        self.detail = detail
        """Extra context, if any."""
        reason = {
            _native.ERR_NULL: "null pointer",
            _native.ERR_UNSUPPORTED: "not supported on this OS",
            _native.ERR_UNKNOWN: "unknown OS error",
        }.get(code, f"OS error {code}")
        super().__init__(f"{operation} failed: {reason}" + (f"\n{detail}" if detail else ""))


class SystemProbe:
    """Process metrics from the native bridge (Windows, Linux and macOS).

    The bridge ships prebuilt in the wheel. Check `is_available()`, or mark
    tests that need it so they are skipped where it isn't::

        @pytest.mark.requires_native_bridge
        def test_no_leak(): ...
    """

    _lib: ClassVar[ctypes.CDLL | None] = None
    _unavailable: ClassVar[str | None] = None
    _probed: ClassVar[bool] = False

    def __init__(self) -> None:
        raise TypeError("SystemProbe only has static methods")

    @classmethod
    def _probe(cls) -> None:
        if cls._probed:
            return
        cls._probed = True
        try:
            lib = _native.load()
        except OSError as e:
            cls._unavailable = (
                "suggestedtests native bridge is not available for this platform "
                f"({e}). Set ${_native.ENV_VAR} to a library built from native/."
            )
            return
        version = lib.st_abi_version()
        if version != _native.ABI_VERSION:
            cls._unavailable = (
                f"suggestedtests native bridge has ABI v{version}, "
                f"expected v{_native.ABI_VERSION}. Rebuild it."
            )
            return
        try:
            # Best-effort and additive (no ABI bump): an older prebuilt that
            # predates this symbol must not make the whole bridge look
            # unavailable over it.
            lib.st_on_load()
        except AttributeError:
            pass
        cls._lib = lib

    @classmethod
    def is_available(cls) -> bool:
        """Whether the bridge is loaded and has the expected ABI version."""
        cls._probe()
        return cls._lib is not None

    @classmethod
    def skip_reason(cls) -> str | None:
        """`None` when available; otherwise why not."""
        return None if cls.is_available() else cls._unavailable

    @classmethod
    def _require(cls, operation: str) -> ctypes.CDLL:
        cls._probe()
        if cls._lib is None:
            raise NativeBridgeError(operation, _native.ERR_UNSUPPORTED, cls._unavailable)
        return cls._lib

    @staticmethod
    def _check(operation: str, status: int) -> None:
        if status != _native.OK:
            raise NativeBridgeError(operation, status)

    @classmethod
    def process_cpu_time(cls) -> CpuTime:
        """CPU time used by the whole process (all threads) so far."""
        out = _native.StCpuTime()
        cls._check("process_cpu_time", cls._require("process_cpu_time").st_process_cpu_time(out))
        return CpuTime(out.user_ns, out.system_ns)

    @classmethod
    def thread_cpu_time_ns(cls) -> int:
        """CPU time used by the calling OS thread so far, in nanoseconds."""
        out = ctypes.c_uint64()
        lib = cls._require("thread_cpu_time_ns")
        cls._check("thread_cpu_time_ns", lib.st_thread_cpu_time_ns(ctypes.byref(out)))
        return out.value

    @classmethod
    def memory_usage(cls) -> MemoryUsage:
        """Current and peak resident memory of the process."""
        out = _native.StMemory()
        cls._check("memory_usage", cls._require("memory_usage").st_memory_usage(out))
        return MemoryUsage(out.current_rss_bytes, out.peak_rss_bytes)

    @classmethod
    def cpu_count(cls) -> int:
        """Number of logical CPUs available to the process."""
        return cls._require("cpu_count").st_cpu_count()

    @classmethod
    def set_verbose(cls, verbose: bool) -> bool:
        """Turns the bridge's startup report on or off; returns the previous setting.

        The report is three ``suggestedtests: ...`` lines on stderr describing
        the platform and environment (OS, arch, libc, container, VM). It is
        printed at most once per process; turning verbose on prints it now if
        it hasn't been printed. Verbose controls nothing else.

        To get the report while the bridge loads, set
        ``SUGGESTEDTESTS_VERBOSE=1`` before the first `SystemProbe` call::

            SystemProbe.set_verbose(True)
        """
        if not isinstance(verbose, bool):
            raise TypeError(f"verbose must be a bool, got {type(verbose).__name__}")
        return bool(cls._require("set_verbose").st_set_verbose(1 if verbose else 0))

    @classmethod
    def verbose(cls) -> bool:
        """Whether the bridge's startup report is on (see `set_verbose`)."""
        return bool(cls._require("verbose").st_verbose())
