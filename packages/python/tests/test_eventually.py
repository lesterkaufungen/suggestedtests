import asyncio
import time

import pytest

from suggestedtests import eventually, eventually_async


def test_returns_once_condition_holds():
    start = time.monotonic()

    def ready():
        assert time.monotonic() - start > 0.05
        return "ok"

    assert eventually(ready, timeout=2) == "ok"


def test_fails_with_last_error():
    def boom():
        raise ValueError("boom")

    with pytest.raises(AssertionError, match=r"(?s)within 50.00ms \(\d+ attempts\).*boom"):
        eventually(boom, timeout=0.05)


def test_rejects_coroutines():
    async def coro():
        pass

    with pytest.raises(TypeError, match="eventually_async"):
        eventually(coro)


def test_validates_durations():
    with pytest.raises(ValueError):
        eventually(lambda: None, timeout=-1)


def test_async_variant():
    state = {"n": 0}

    async def body():
        state["n"] += 1
        assert state["n"] >= 3
        return state["n"]

    assert asyncio.run(eventually_async(body, interval=0.001)) == 3


def test_async_variant_accepts_sync_body():
    assert asyncio.run(eventually_async(lambda: 7)) == 7


def test_async_variant_times_out():
    async def never():
        raise AssertionError("not yet")

    with pytest.raises(AssertionError, match="not yet"):
        asyncio.run(eventually_async(never, timeout=0.02))
