from suggestedtests import no_leaked_threads


def test_worker_pool_shuts_down():
    with no_leaked_threads():
        with WorkerPool(4) as pool:
            pool.submit(job)
