"""Benchmarks and performance budgets."""

from __future__ import annotations

import asyncio
import math
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from datetime import timedelta
from enum import Enum
from typing import TypeVar, Union

from .system_probe import SystemProbe, format_ns

T = TypeVar("T")

Seconds = Union[float, timedelta]
"""A duration: seconds as a number, or a `timedelta`."""


def to_ns(duration: Seconds, name: str = "duration") -> int:
    """Converts seconds or a `timedelta` to integer nanoseconds."""
    if isinstance(duration, timedelta):
        seconds = duration.total_seconds()
    elif isinstance(duration, (int, float)) and not isinstance(duration, bool):
        seconds = float(duration)
    else:
        raise TypeError(f"{name} must be seconds (int/float) or a timedelta, got {duration!r}")
    if seconds < 0 or math.isnan(seconds):
        raise ValueError(f"{name} must be >= 0, got {duration!r}")
    return round(seconds * 1e9)


class Statistic(str, Enum):
    """Which statistic of a `BenchmarkResult` a budget is checked against."""

    MIN = "min"
    """Fastest sample."""
    MEAN = "mean"
    """Arithmetic mean of all samples."""
    MEDIAN = "median"
    """Middle sample. Robust against GC pauses; the default."""
    P95 = "p95"
    """95th percentile sample."""
    MAX = "max"
    """Slowest sample."""


class Clock(str, Enum):
    """What a benchmark measures."""

    WALL = "wall"
    """Elapsed wall-clock time (`time.perf_counter_ns`). Includes waiting and
    time stolen by other processes."""
    CPU = "cpu"
    """CPU time of the calling thread, via the native bridge. Ignores waiting
    and other processes, so it is far less noisy on busy CI machines. In
    `benchmark_async` it includes other tasks that run on the event loop
    while the body awaits."""


@dataclass(frozen=True)
class BenchmarkResult:
    """Timing statistics collected by `benchmark` or `benchmark_async`."""

    name: str
    """Label of the benchmark."""
    samples_ns: tuple[int, ...]
    """Measured durations in run order (warm-up runs excluded)."""
    clock: Clock = Clock.WALL
    """What the samples measure."""
    _sorted: tuple[int, ...] = field(init=False, repr=False, compare=False)

    def __post_init__(self) -> None:
        if not self.samples_ns:
            raise ValueError("samples_ns must not be empty")
        object.__setattr__(self, "samples_ns", tuple(self.samples_ns))
        object.__setattr__(self, "clock", Clock(self.clock))
        object.__setattr__(self, "_sorted", tuple(sorted(self.samples_ns)))

    @property
    def min_ns(self) -> int:
        """Fastest sample."""
        return self._sorted[0]

    @property
    def max_ns(self) -> int:
        """Slowest sample."""
        return self._sorted[-1]

    @property
    def mean_ns(self) -> float:
        """Arithmetic mean."""
        return sum(self.samples_ns) / len(self.samples_ns)

    @property
    def median_ns(self) -> int:
        """Median (50th percentile)."""
        return self.percentile_ns(50)

    @property
    def p95_ns(self) -> int:
        """95th percentile."""
        return self.percentile_ns(95)

    @property
    def stdev_ns(self) -> float:
        """Population standard deviation of the samples."""
        m = self.mean_ns
        return math.sqrt(sum((s - m) ** 2 for s in self.samples_ns) / len(self.samples_ns))

    def percentile_ns(self, p: float) -> int:
        """The `p`th percentile (0-100) using nearest-rank."""
        if not 0 <= p <= 100:
            raise ValueError(f"p must be in [0, 100], got {p}")
        rank = min(max(math.ceil(p / 100 * len(self._sorted)), 1), len(self._sorted))
        return self._sorted[rank - 1]

    def __getitem__(self, statistic: Statistic | str) -> float:
        """The value of `statistic`, in nanoseconds."""
        return {
            Statistic.MIN: self.min_ns,
            Statistic.MEAN: self.mean_ns,
            Statistic.MEDIAN: self.median_ns,
            Statistic.P95: self.p95_ns,
            Statistic.MAX: self.max_ns,
        }[Statistic(statistic)]

    def __str__(self) -> str:
        cpu = " (cpu)" if self.clock is Clock.CPU else ""
        return (
            f"{self.name}{cpu}: n={len(self.samples_ns)} min={format_ns(self.min_ns)} "
            f"median={format_ns(self.median_ns)} mean={format_ns(self.mean_ns)} "
            f"p95={format_ns(self.p95_ns)} max={format_ns(self.max_ns)} "
            f"±{format_ns(self.stdev_ns)}"
        )


def _check_counts(iterations: int, warmup: int) -> None:
    if iterations < 1:
        raise ValueError(f"iterations must be >= 1, got {iterations}")
    if warmup < 0:
        raise ValueError(f"warmup must be >= 0, got {warmup}")


def _reader(clock: Clock | str) -> Callable[[], int]:
    clock = Clock(clock)
    if clock is Clock.WALL:
        return time.perf_counter_ns
    if not SystemProbe.is_available():
        raise RuntimeError(f"Clock.CPU needs the native bridge: {SystemProbe.skip_reason()}")
    return SystemProbe.thread_cpu_time_ns


def benchmark(
    name: str,
    body: Callable[[], object],
    *,
    iterations: int = 20,
    warmup: int = 3,
    clock: Clock | str = Clock.WALL,
) -> BenchmarkResult:
    """Runs `body` `warmup` times untimed, then `iterations` times timed.

    ::

        result = benchmark("parse", lambda: json.loads(payload))
        print(result)  # parse: n=20 min=1.02ms median=1.10ms ...
    """
    _check_counts(iterations, warmup)
    now = _reader(clock)
    for _ in range(warmup):
        body()
    samples = []
    for _ in range(iterations):
        start = now()
        body()
        samples.append(now() - start)
    return BenchmarkResult(name, tuple(samples), Clock(clock))


async def benchmark_async(
    name: str,
    body: Callable[[], Awaitable[object]],
    *,
    iterations: int = 20,
    warmup: int = 3,
    clock: Clock | str = Clock.WALL,
) -> BenchmarkResult:
    """Like `benchmark`, but awaits `body()` on every run."""
    _check_counts(iterations, warmup)
    now = _reader(clock)
    for _ in range(warmup):
        await body()
    samples = []
    for _ in range(iterations):
        start = now()
        await body()
        samples.append(now() - start)
    return BenchmarkResult(name, tuple(samples), Clock(clock))


def _check_budget(result: BenchmarkResult, budget_ns: int, statistic: Statistic | str) -> None:
    statistic = Statistic(statistic)
    actual = result[statistic]
    if actual > budget_ns:
        raise AssertionError(
            f"Performance budget exceeded: {statistic.value} {format_ns(actual)} > "
            f"budget {format_ns(budget_ns)}\n{result}"
        )


def expect_performance(
    body: Callable[[], object],
    *,
    budget: Seconds,
    statistic: Statistic | str = Statistic.MEDIAN,
    iterations: int = 20,
    warmup: int = 3,
    name: str = "benchmark",
    clock: Clock | str = Clock.WALL,
) -> BenchmarkResult:
    """Benchmarks `body` and fails if `statistic` exceeds `budget` (seconds).

    ::

        def test_parsing_stays_fast():
            expect_performance(lambda: parse(big_json), budget=0.005)
    """
    budget_ns = to_ns(budget, "budget")
    Statistic(statistic)
    result = benchmark(name, body, iterations=iterations, warmup=warmup, clock=clock)
    _check_budget(result, budget_ns, statistic)
    return result


async def expect_performance_async(
    body: Callable[[], Awaitable[object]],
    *,
    budget: Seconds,
    statistic: Statistic | str = Statistic.MEDIAN,
    iterations: int = 20,
    warmup: int = 3,
    name: str = "benchmark",
    clock: Clock | str = Clock.WALL,
) -> BenchmarkResult:
    """Like `expect_performance`, but awaits `body()` on every run."""
    budget_ns = to_ns(budget, "budget")
    Statistic(statistic)
    result = await benchmark_async(name, body, iterations=iterations, warmup=warmup, clock=clock)
    _check_budget(result, budget_ns, statistic)
    return result


async def completes_within(awaitable: Awaitable[T], limit: Seconds) -> T:
    """Awaits `awaitable` and fails unless it completes within `limit`.

    ::

        user = await completes_within(repository.load(), 1.0)
    """
    limit_ns = to_ns(limit, "limit")
    try:
        return await asyncio.wait_for(awaitable, limit_ns / 1e9)
    except asyncio.TimeoutError:  # an alias of TimeoutError from 3.11
        raise AssertionError(f"Awaitable did not complete within {format_ns(limit_ns)}") from None
