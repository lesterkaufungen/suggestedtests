"""A tour of suggestedtests. Run it with: pytest examples/"""

import asyncio
import json
import threading

import pytest

from suggestedtests import (
    KiB,
    MiB,
    SystemProbe,
    assert_unique,
    benchmark,
    completes_within,
    eventually,
    expect_allocations,
    expect_memory,
    expect_performance,
    no_leaked_threads,
)


class Cart:
    def __init__(self):
        self.items = []

    @property
    def total(self):
        return sum(self.items)


def test_given_when_then(steps):
    with steps.given("an empty cart"):
        cart = Cart()
    with steps.when("two items are added"):
        cart.items += [10, 20]
    with steps.then("the total is 30"):
        assert cart.total == 30


def test_seeded_data(test_data):
    # On failure the report prints the seed; rerun with --st-seed=<seed>.
    emails = test_data.list_of(20, lambda d: d.email())
    assert all(e.endswith("@example.com") for e in emails)


def test_ids_are_unique(test_data):
    assert_unique(test_data.uuid() for _ in range(100))


def test_parsing_stays_fast():
    payload = json.dumps({"items": list(range(1000))})
    result = expect_performance(lambda: json.loads(payload), budget=0.05)
    print(result)


@pytest.mark.requires_native_bridge
def test_cpu_time_ignores_noisy_neighbours():
    result = benchmark("sum", lambda: sum(range(10_000)), clock="cpu")
    assert result.median_ns > 0


@pytest.mark.requires_native_bridge
def test_loading_stays_under_budget():
    with expect_memory(max_peak_growth=512 * MiB):
        data = [bytes(1024) for _ in range(1000)]
    del data
    assert SystemProbe.cpu_count() >= 1


@pytest.mark.skipif(
    __import__("importlib.util").util.find_spec("_tracemalloc") is None,
    reason="tracemalloc is CPython-only",
)
def test_cache_does_not_keep_garbage():
    with expect_allocations(max_net=64 * KiB):
        for i in range(1000):
            _ = str(i) * 10


def test_background_work_finishes():
    done = threading.Event()
    with no_leaked_threads():
        threading.Thread(target=done.set).start()

    def finished():
        assert done.is_set()

    eventually(finished, timeout=1.0)


def test_async_call_is_quick():
    async def fetch():
        await asyncio.sleep(0.001)
        return "ok"

    assert asyncio.run(completes_within(fetch(), 1.0)) == "ok"
