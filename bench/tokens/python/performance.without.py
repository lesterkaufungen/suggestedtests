import statistics
import time


def test_parsing_stays_fast():
    for _ in range(3):
        parse(big_json)
    samples = []
    for _ in range(20):
        start = time.perf_counter()
        parse(big_json)
        samples.append(time.perf_counter() - start)
    median = statistics.median(samples)
    assert median <= 0.005, (
        f"parse: median {median * 1000:.2f}ms > budget 5.00ms "
        f"(min {min(samples) * 1000:.2f}ms, max {max(samples) * 1000:.2f}ms)"
    )
