"""Polling assertions that replace fixed sleeps."""

from __future__ import annotations

import asyncio
import inspect
import time
from collections.abc import Awaitable, Callable
from typing import TypeVar

from .performance import Seconds, to_ns
from .system_probe import format_ns

T = TypeVar("T")


def _timed_out(attempts: int, timeout_ns: int, error: BaseException) -> AssertionError:
    return AssertionError(
        f"Condition not met within {format_ns(timeout_ns)} ({attempts} attempts). "
        f"Last error:\n{type(error).__name__}: {error}"
    )


def eventually(body: Callable[[], T], *, timeout: Seconds = 5.0, interval: Seconds = 0.02) -> T:
    """Re-runs `body` every `interval` until it returns without raising, then
    returns its result. Fails with the last error after `timeout` (seconds).

    The test continues as soon as the condition holds instead of always
    sleeping for the worst case. ::

        eventually(lambda: client.get("/health").raise_for_status())

    For coroutines, use `eventually_async`.
    """
    __tracebackhide__ = True
    timeout_ns, interval_ns = to_ns(timeout, "timeout"), to_ns(interval, "interval")
    start = time.monotonic_ns()
    attempts = 0
    while True:
        attempts += 1
        try:
            result = body()
        except Exception as error:
            if time.monotonic_ns() - start >= timeout_ns:
                raise _timed_out(attempts, timeout_ns, error) from error
        else:
            if inspect.isawaitable(result):
                if inspect.iscoroutine(result):
                    result.close()
                raise TypeError("body returned an awaitable; use eventually_async")
            return result
        time.sleep(interval_ns / 1e9)


async def eventually_async(
    body: Callable[[], T | Awaitable[T]],
    *,
    timeout: Seconds = 5.0,
    interval: Seconds = 0.02,
) -> T:
    """Like `eventually`, but awaits `body()` if it returns an awaitable and
    sleeps with `asyncio.sleep`, so the event loop keeps running. ::

        await eventually_async(lambda: queue.assert_empty())
    """
    __tracebackhide__ = True
    timeout_ns, interval_ns = to_ns(timeout, "timeout"), to_ns(interval, "interval")
    start = time.monotonic_ns()
    attempts = 0
    while True:
        attempts += 1
        try:
            result = body()
            if inspect.isawaitable(result):
                result = await result
            return result  # type: ignore[return-value]
        except Exception as error:
            if time.monotonic_ns() - start >= timeout_ns:
                raise _timed_out(attempts, timeout_ns, error) from error
        await asyncio.sleep(interval_ns / 1e9)
