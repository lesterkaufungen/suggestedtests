"""Memory budgets: process RSS via the native bridge, Python heap via tracemalloc."""

from __future__ import annotations

import linecache
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field

from .system_probe import MemoryUsage, SystemProbe, format_bytes

KiB = 1024
"""Bytes in a kibibyte."""
MiB = 1024 * KiB
"""Bytes in a mebibyte."""
GiB = 1024 * MiB
"""Bytes in a gibibyte."""


def _signed(n: int) -> str:
    return ("+" if n >= 0 else "") + format_bytes(n)


@dataclass
class MemoryReport:
    """Resident memory before and after the body of `measure_memory`."""

    before: MemoryUsage
    """Sample taken before the body ran."""
    after: MemoryUsage | None = None
    """Sample taken after the body completed; `None` while it runs."""

    def _after(self) -> MemoryUsage:
        if self.after is None:
            raise RuntimeError("MemoryReport is only complete after the `with` block")
        return self.after

    @property
    def rss_growth_bytes(self) -> int:
        """Change in resident memory. Can be negative."""
        return self._after().current_rss_bytes - self.before.current_rss_bytes

    @property
    def peak_growth_bytes(self) -> int:
        """How far the body pushed the process' peak RSS above its previous peak."""
        return self._after().peak_rss_bytes - self.before.peak_rss_bytes

    def __str__(self) -> str:
        return (
            f"MemoryReport(rss: {_signed(self.rss_growth_bytes)}, "
            f"peak: {_signed(self.peak_growth_bytes)}, now: {self.after})"
        )


@contextmanager
def measure_memory() -> Iterator[MemoryReport]:
    """Reports how the process' resident memory changed across the block.

    RSS is a coarse, process-wide signal: allocators keep freed memory and
    other threads share the process. Use it to catch leaks and blow-ups of
    megabytes. For Python objects, `expect_allocations` is exact. ::

        with measure_memory() as report:
            load_everything()
        print(report.peak_growth_bytes)
    """
    report = MemoryReport(SystemProbe.memory_usage())
    yield report
    report.after = SystemProbe.memory_usage()


@contextmanager
def expect_memory(
    *, max_rss_growth: int | None = None, max_peak_growth: int | None = None
) -> Iterator[MemoryReport]:
    """Fails if resident memory grew by more than `max_rss_growth` bytes, or the
    peak rose by more than `max_peak_growth`. At least one budget is required. ::

        @pytest.mark.requires_native_bridge
        def test_loading_stays_under_50_mib():
            with expect_memory(max_peak_growth=50 * MiB):
                repository.load_all()
    """
    __tracebackhide__ = True
    if max_rss_growth is None and max_peak_growth is None:
        raise ValueError("Provide max_rss_growth and/or max_peak_growth.")
    for name, value in (("max_rss_growth", max_rss_growth), ("max_peak_growth", max_peak_growth)):
        if value is not None and value < 0:
            raise ValueError(f"{name} must be >= 0, got {value}")
    with measure_memory() as report:
        yield report
    if max_rss_growth is not None and report.rss_growth_bytes > max_rss_growth:
        raise AssertionError(
            f"Memory budget exceeded: RSS grew {format_bytes(report.rss_growth_bytes)} > "
            f"budget {format_bytes(max_rss_growth)}\n{report}"
        )
    if max_peak_growth is not None and report.peak_growth_bytes > max_peak_growth:
        raise AssertionError(
            f"Memory budget exceeded: peak RSS grew {format_bytes(report.peak_growth_bytes)} > "
            f"budget {format_bytes(max_peak_growth)}\n{report}"
        )


@dataclass
class AllocationReport:
    """Python heap allocations made inside `expect_allocations`."""

    net_bytes: int = 0
    """Bytes still allocated at the end of the block (can be negative)."""
    peak_bytes: int = 0
    """Highest extra allocation at any point during the block."""
    top: list[str] = field(default_factory=list)
    """The largest net allocations, as `file:line: size` strings."""

    def __str__(self) -> str:
        sites = "".join(f"\n  {line}" for line in self.top)
        return (
            f"AllocationReport(net: {_signed(self.net_bytes)}, "
            f"peak: +{format_bytes(self.peak_bytes)}){sites}"
        )


def _tracemalloc():  # noqa: ANN202
    """`tracemalloc`, which only CPython has (not PyPy)."""
    try:
        import tracemalloc
    except ImportError as e:
        raise RuntimeError(
            "expect_allocations needs tracemalloc, which this Python implementation lacks "
            "(it is CPython-only); use expect_memory instead"
        ) from e
    return tracemalloc


def _top_sites(before: object, after: object, limit: int) -> list[str]:
    tracemalloc = _tracemalloc()
    ignore = [tracemalloc.Filter(False, tracemalloc.__file__), tracemalloc.Filter(False, __file__)]
    diff = after.filter_traces(ignore).compare_to(before.filter_traces(ignore), "lineno")
    lines = []
    for stat in diff[:limit]:
        if stat.size_diff <= 0:
            break
        frame = stat.traceback[0]
        code = linecache.getline(frame.filename, frame.lineno).strip()
        lines.append(f"{frame.filename}:{frame.lineno}: {_signed(stat.size_diff)}  {code}")
    return lines


@contextmanager
def expect_allocations(
    *, max_net: int | None = None, max_peak: int | None = None, top: int = 5
) -> Iterator[AllocationReport]:
    """Fails if Python code in the block left more than `max_net` bytes
    allocated, or allocated more than `max_peak` at once.

    Uses `tracemalloc`, so it counts Python objects exactly (unlike RSS) and
    the failure lists the lines that allocated the most. Works without the
    native bridge; needs CPython (PyPy has no tracemalloc). ::

        def test_cache_is_bounded():
            cache = LruCache(100)
            with expect_allocations(max_net=64 * KiB):
                for i in range(10_000):
                    cache.put(i, str(i))
    """
    __tracebackhide__ = True
    if max_net is None and max_peak is None:
        raise ValueError("Provide max_net and/or max_peak.")
    if top < 0:
        raise ValueError(f"top must be >= 0, got {top}")
    tracemalloc = _tracemalloc()
    started = not tracemalloc.is_tracing()
    if started:
        tracemalloc.start()
    report = AllocationReport()
    try:
        before = tracemalloc.take_snapshot()
        start, _ = tracemalloc.get_traced_memory()
        # Python 3.8 has no reset_peak: if someone else started tracing, the
        # peak may then include allocations from before the block.
        if hasattr(tracemalloc, "reset_peak"):
            tracemalloc.reset_peak()
        yield report
        current, peak = tracemalloc.get_traced_memory()
        report.net_bytes = current - start
        report.peak_bytes = max(peak - start, 0)
        over_net = max_net is not None and report.net_bytes > max_net
        over_peak = max_peak is not None and report.peak_bytes > max_peak
        if over_net or over_peak:
            report.top = _top_sites(before, tracemalloc.take_snapshot(), top)
        if over_net:
            raise AssertionError(
                f"Allocation budget exceeded: {format_bytes(report.net_bytes)} still allocated "
                f"> budget {format_bytes(max_net)}\n{report}"
            )
        if over_peak:
            raise AssertionError(
                f"Allocation budget exceeded: peak {format_bytes(report.peak_bytes)} > "
                f"budget {format_bytes(max_peak)}\n{report}"
            )
    finally:
        if started:
            tracemalloc.stop()
