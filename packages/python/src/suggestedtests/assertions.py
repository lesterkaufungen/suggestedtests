"""Assertions pytest doesn't have built in."""

from __future__ import annotations

import threading
import time
from collections.abc import Iterable, Iterator
from contextlib import contextmanager

from .performance import Seconds, to_ns


def assert_unique(items: Iterable[object]) -> None:
    """Fails if `items` contains two equal elements, naming the first duplicate
    and both of its positions. Unhashable elements are compared with `==`. ::

        assert_unique(user.id for user in users)
    """
    seen: dict[object, int] = {}
    unhashable: list[tuple[int, object]] = []
    for index, item in enumerate(items):
        try:
            first = seen.setdefault(item, index)
        except TypeError:
            first = next((i for i, other in unhashable if other == item), index)
            unhashable.append((index, item))
        if first != index:
            raise AssertionError(
                f"Expected unique elements, but {item!r} appears at index {first} and {index}"
            )


@contextmanager
def no_leaked_threads(*, timeout: Seconds = 1.0) -> Iterator[None]:
    """Fails if the block starts threads that are still alive `timeout`
    seconds after it ends, listing them by name. ::

        def test_worker_pool_shuts_down():
            with no_leaked_threads():
                with WorkerPool(4) as pool:
                    pool.submit(job)
    """
    timeout_ns = to_ns(timeout, "timeout")
    before = set(threading.enumerate())
    yield
    deadline = time.monotonic_ns() + timeout_ns
    while True:
        leaked = [t for t in threading.enumerate() if t not in before and t.is_alive()]
        if not leaked:
            return
        remaining = deadline - time.monotonic_ns()
        if remaining <= 0:
            names = ", ".join(f"{t.name!r} (daemon={t.daemon})" for t in leaked)
            raise AssertionError(f"{len(leaked)} thread(s) still running after the block: {names}")
        leaked[0].join(min(remaining / 1e9, 0.05))
