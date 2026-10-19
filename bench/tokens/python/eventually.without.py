import time


def test_cache_warms_up():
    deadline = time.monotonic() + 5.0
    while True:
        try:
            assert cache.is_warm()
            return
        except AssertionError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.02)
