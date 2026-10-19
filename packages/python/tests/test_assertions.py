import threading
import time

import pytest

from suggestedtests import assert_unique, no_leaked_threads


def test_unique_passes():
    assert_unique([1, 2, 3])
    assert_unique(x for x in "abc")
    assert_unique([[1], [2]])


def test_duplicate_is_named_with_positions():
    with pytest.raises(AssertionError, match=r"'b' appears at index 1 and 3"):
        assert_unique(["a", "b", "c", "b"])


def test_unhashable_duplicates():
    with pytest.raises(AssertionError, match=r"\[1\] appears at index 0 and 2"):
        assert_unique([[1], [2], [1]])


def test_no_leaked_threads_passes_for_joined_threads():
    with no_leaked_threads():
        t = threading.Thread(target=lambda: time.sleep(0.01))
        t.start()


def test_no_leaked_threads_fails():
    stop = threading.Event()
    try:
        with pytest.raises(AssertionError, match=r"1 thread\(s\) still running.*'leaky'"):
            with no_leaked_threads(timeout=0.05):
                threading.Thread(target=stop.wait, name="leaky", daemon=True).start()
    finally:
        stop.set()
