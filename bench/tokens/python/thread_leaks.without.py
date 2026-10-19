import threading
import time


def test_worker_pool_shuts_down():
    before = set(threading.enumerate())
    with WorkerPool(4) as pool:
        pool.submit(job)
    deadline = time.monotonic() + 1.0
    leaked = set(threading.enumerate()) - before
    while leaked and time.monotonic() < deadline:
        time.sleep(0.02)
        leaked = {t for t in leaked if t.is_alive()}
    assert not leaked, f"threads still running: {sorted(t.name for t in leaked)}"
