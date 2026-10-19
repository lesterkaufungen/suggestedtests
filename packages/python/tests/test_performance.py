import asyncio
from datetime import timedelta

import pytest

from suggestedtests import (
    BenchmarkResult,
    Clock,
    Statistic,
    benchmark,
    benchmark_async,
    completes_within,
    expect_performance,
    expect_performance_async,
)


def result(*samples):
    return BenchmarkResult("r", tuple(samples))


def test_statistics():
    r = result(5, 1, 3, 2, 4)
    assert (r.min_ns, r.max_ns, r.mean_ns, r.median_ns, r.p95_ns) == (1, 5, 3, 3, 5)
    assert r[Statistic.MEDIAN] == 3 and r["max"] == 5
    assert r.percentile_ns(0) == 1 and r.percentile_ns(100) == 5
    assert r.stdev_ns == pytest.approx(2**0.5)
    assert r.samples_ns == (5, 1, 3, 2, 4)


def test_result_validates():
    with pytest.raises(ValueError, match="empty"):
        result()
    with pytest.raises(ValueError, match=r"\[0, 100\]"):
        result(1).percentile_ns(101)
    with pytest.raises(ValueError):
        result(1)["p99"]


def test_str_formats_units():
    assert str(result(500, 2_500_000, 3_000_000_000)).startswith(
        "r: n=3 min=0µs median=2.50ms mean=1.00s"
    )


def test_benchmark_counts_runs():
    calls = []
    r = benchmark("b", lambda: calls.append(1), iterations=5, warmup=2)
    assert len(calls) == 7 and len(r.samples_ns) == 5 and r.clock is Clock.WALL


@pytest.mark.parametrize(("iterations", "warmup"), [(0, 0), (1, -1)])
def test_benchmark_validates_counts(iterations, warmup):
    with pytest.raises(ValueError):
        benchmark("b", lambda: None, iterations=iterations, warmup=warmup)


def test_benchmark_validates_clock():
    with pytest.raises(ValueError):
        benchmark("b", lambda: None, clock="sundial")


@pytest.mark.requires_native_bridge
def test_cpu_clock_ignores_sleep():
    import time

    r = benchmark("sleep", lambda: time.sleep(0.01), iterations=3, warmup=0, clock="cpu")
    assert r.clock is Clock.CPU and r.median_ns < 5_000_000


def test_benchmark_async():
    async def body():
        await asyncio.sleep(0)

    r = asyncio.run(benchmark_async("a", body, iterations=4, warmup=1))
    assert len(r.samples_ns) == 4


def test_expect_performance_passes_and_fails():
    assert expect_performance(lambda: None, budget=1.0).name == "benchmark"
    with pytest.raises(AssertionError, match="Performance budget exceeded: max"):
        expect_performance(
            lambda: sum(range(10_000)), budget=timedelta(0), statistic="max", iterations=2
        )


def test_expect_performance_validates_eagerly():
    calls = []
    with pytest.raises(ValueError):
        expect_performance(lambda: calls.append(1), budget=-1)
    with pytest.raises(ValueError):
        expect_performance(lambda: calls.append(1), budget=1, statistic="p42")
    with pytest.raises(TypeError):
        expect_performance(lambda: calls.append(1), budget="1s")
    assert calls == []


def test_expect_performance_async():
    async def body():
        pass

    asyncio.run(expect_performance_async(body, budget=1.0))


def test_completes_within():
    async def fast():
        return 42

    async def slow():
        await asyncio.sleep(1)

    assert asyncio.run(completes_within(fast(), 1)) == 42
    with pytest.raises(AssertionError, match="did not complete within 10.00ms"):
        asyncio.run(completes_within(slow(), 0.01))
