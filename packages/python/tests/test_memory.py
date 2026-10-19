import importlib.util

import pytest

from suggestedtests import KiB, MiB, expect_allocations, expect_memory, measure_memory


@pytest.mark.requires_native_bridge
def test_measure_memory_reports_growth():
    with measure_memory() as report:
        block = bytearray(64 * MiB)
        block[::4096] = b"x" * len(block[::4096])  # touch every page
    assert report.peak_growth_bytes >= 0
    assert report.after is not None
    assert "MemoryReport(rss: " in str(report)
    del block


def test_report_is_incomplete_inside_block():
    from suggestedtests import MemoryReport, MemoryUsage

    with pytest.raises(RuntimeError, match="after the `with` block"):
        _ = MemoryReport(MemoryUsage(1, 1)).rss_growth_bytes


@pytest.mark.requires_native_bridge
def test_expect_memory_fails_over_budget():
    with pytest.raises(AssertionError, match="peak RSS grew"):
        with expect_memory(max_peak_growth=0):
            block = bytearray(256 * MiB)
            block[::4096] = b"x" * len(block[::4096])
            del block


def test_expect_memory_validates():
    with pytest.raises(ValueError, match="Provide"):
        with expect_memory():
            pass
    with pytest.raises(ValueError, match=">= 0"):
        with expect_memory(max_rss_growth=-1):
            pass


needs_tracemalloc = pytest.mark.skipif(
    importlib.util.find_spec("_tracemalloc") is None, reason="tracemalloc is CPython-only"
)


@needs_tracemalloc
def test_expect_allocations_passes():
    with expect_allocations(max_net=64 * KiB) as report:
        _ = [str(i) for i in range(1000)]
    assert report.peak_bytes > 0


@needs_tracemalloc
def test_expect_allocations_names_the_line():
    kept = []
    with pytest.raises(AssertionError) as info:
        with expect_allocations(max_net=1 * KiB):
            kept.extend("x" * 100 + str(i) for i in range(1000))
    message = str(info.value)
    assert "still allocated" in message
    assert "test_memory.py:" in message


@needs_tracemalloc
def test_expect_allocations_peak():
    with pytest.raises(AssertionError, match="peak"):
        with expect_allocations(max_peak=1 * KiB):
            _ = bytearray(1 * MiB)


@needs_tracemalloc
def test_expect_allocations_validates():
    with pytest.raises(ValueError):
        with expect_allocations():
            pass


@pytest.mark.skipif(
    importlib.util.find_spec("_tracemalloc") is not None,
    reason="needs a Python without tracemalloc",
)
def test_expect_allocations_explains_missing_tracemalloc():
    with pytest.raises(RuntimeError, match="CPython-only"):
        with expect_allocations(max_net=1):
            pass
