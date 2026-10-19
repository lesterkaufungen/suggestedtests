<p align="center">
  <img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/packages/dart/assets/logo.png" alt="suggestedtests logo" width="140">
</p>

<h1 align="center">suggestedtests for Python</h1>

<p align="center">
  pytest helpers that make tests faster to write, and keep your code fast.
</p>

<p align="center">
  <a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md"><img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/bench/tokens/banner.png" alt="Tokens an AI coding agent spends per test, hand-written vs with suggestedtests, projected to larger test suites (estimate)" width="900"></a>
</p>

<p align="center">
  <a href="https://pypi.org/project/suggestedtests/"><img src="https://img.shields.io/pypi/v/suggestedtests?logo=pypi&logoColor=white&label=PyPI&color=3775A9" alt="PyPI"></a>
  <img src="https://img.shields.io/badge/Python-3.8%2B%20%7C%20PyPy-3776AB?logo=python&logoColor=white" alt="Python 3.8+ and PyPy">
  <img src="https://img.shields.io/badge/pytest-7%2B-0A9EDC?logo=pytest&logoColor=white" alt="pytest 7+">
  <img src="https://img.shields.io/badge/dependencies-none-brightgreen" alt="no dependencies">
  <!-- tokens:badge -->
<!-- prettier-ignore-start -->
<a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md"><img src="https://img.shields.io/badge/AI%20agents-~67%25%20fewer%20tokens-8A2BE2" alt="~67% fewer tokens for AI agents (estimate)"></a>
<!-- prettier-ignore-end -->
<!-- /tokens:badge -->
  <a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/packages/python/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <sub>The same helpers in <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/dart">Flutter & Dart</a> · <b>Python</b> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/js">JS & TS</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/php">PHP</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/java">Java</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/go">Go</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/swift">Swift</a> · <a href="https://github.com/lesterkaufungen/suggestedtests">one repo, one native bridge</a></sub>
</p>

---

| Helper | What it's for |
| --- | --- |
| `expect_performance`, `benchmark`, `completes_within` | Timing statistics and performance budgets, on wall-clock or CPU time. |
| `SystemProbe`, `expect_memory` | Process CPU time and resident memory via a native bridge for Windows, Linux and macOS. |
| `expect_allocations` | Python heap budgets via `tracemalloc`. Failures list the lines that allocated. |
| `eventually`, `eventually_async` | Polling assertions. Use them instead of `time.sleep`. |
| `steps` fixture / `Steps` | Given/when/then blocks. A failure names the failing step. |
| `test_data` fixture / `TestData` | Seeded, reproducible fake data. A failure prints the seed. |
| `assert_unique`, `no_leaked_threads` | Duplicate check that names positions; thread-leak check. |
| `@pytest.mark.requires_native_bridge` | Skips a test, with the reason, where the bridge is unavailable. |

For table-driven tests use `pytest.mark.parametrize`, and for spies use
`unittest.mock`. They already do the job well, so this package doesn't
duplicate them.

## Built for AI coding agents

<!-- tokens:section -->
<!-- prettier-ignore-start -->
An agent that knows these helpers writes one call where it would otherwise
write the loop, the timer, the statistics and the failure message, and then
read all of it again on every later change. For the tests in the
[benchmark](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md), that is **453 → 149 tokens
(67% fewer)**:

| Test | Hand-written | With suggestedtests | Saved |
| --- | ---: | ---: | ---: |
| Performance budget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/python/performance.without.py), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/python/performance.with.py)) | 141 | 32 | 77% |
| Wait for a condition ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/python/eventually.without.py), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/python/eventually.with.py)) | 67 | 29 | 57% |
| Peak-RSS budget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/python/memory.without.py), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/python/memory.with.py)) | 126 | 49 | 61% |
| Thread-leak check ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/python/thread_leaks.without.py), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/python/thread_leaks.with.py)) | 119 | 39 | 67% |

Estimated with the public `o200k_base` tokenizer: other models count
differently, so compare the ratios, not the numbers. Reasoning and retries
aren't counted, and the hand-written versions are often weaker (Linux-only
memory reads, no seed in the failure).

Tell your agent the helpers exist. Paste this into `CLAUDE.md`, `AGENTS.md`
or your editor's rules (179 tokens of context, paid back after about
3 tests):

````markdown
## Tests: use `suggestedtests` (pytest plugin, loads automatically)

- Timing budgets: `expect_performance(fn, budget=0.005)` (seconds); statistics: `benchmark("name", fn)`.
- Never `time.sleep`: `eventually(fn)` retries until `fn` stops raising `AssertionError`.
- Memory: `with expect_memory(max_peak_growth=50 * MiB):` plus `@pytest.mark.requires_native_bridge`; Python heap: `with expect_allocations(max_net=64 * KiB):`.
- Leaks: `with no_leaked_threads():`.
- Given/when/then: the `steps` fixture (`with steps.given("..."):`); seeded data: the `test_data` fixture.
- Duplicates: `assert_unique(items)`. For parametrize and mocks, use pytest and `unittest.mock`.
````
<!-- prettier-ignore-end -->
<!-- /tokens:section -->

## Install

```sh
pip install suggestedtests
```

Requires Python 3.8+ (CPython or PyPy) and has no dependencies; the pytest
plugin (pytest 7+) loads automatically. On PyPy everything works except
`expect_allocations`, which needs CPython's `tracemalloc`.

## Performance budgets

```python
from suggestedtests import expect_performance, benchmark, Statistic


def test_parsing_stays_fast():
    expect_performance(lambda: parse(big_json), budget=0.005)  # seconds, or a timedelta


def test_report():
    result = benchmark("sort", lambda: sorted(data), iterations=50)
    print(result)  # sort: n=50 min=1.02ms median=1.10ms mean=1.15ms p95=1.40ms max=2.01ms ±0.12ms
```

The budget is checked against the median by default, which is robust against
GC pauses. Pass `statistic="p95"` (or `"min"`, `"mean"`, `"max"`) to check
something else.

Pass `clock="cpu"` to measure CPU time instead of wall-clock time. CPU time
ignores sleeping, I/O waits and other processes, so it is far less noisy on
busy CI machines.

`benchmark_async` and `expect_performance_async` take a coroutine function.
`await completes_within(coro, 1.0)` fails if an awaitable takes too long.

## Memory budgets

```python
from suggestedtests import MiB, KiB, expect_memory, expect_allocations


@pytest.mark.requires_native_bridge
def test_import_does_not_blow_up():
    with expect_memory(max_peak_growth=50 * MiB):
        importer.run(big_file)


def test_cache_is_bounded():
    with expect_allocations(max_net=64 * KiB):
        for i in range(10_000):
            cache.put(i, str(i))
```

`expect_memory` measures process RSS through the native bridge. RSS covers
everything the process holds, including C extensions, so it catches leaks
and blow-ups measured in megabytes. `expect_allocations` uses `tracemalloc`
and counts Python objects exactly. When it fails, it lists the source lines
that allocated the most:

```
AssertionError: Allocation budget exceeded: 412.3 KiB still allocated > budget 64.0 KiB
AllocationReport(net: +412.3 KiB, peak: +420.1 KiB)
  app/cache.py:41: +398.0 KiB  self._items[key] = value
```

## Native bridge (Windows / Linux / macOS)

```python
from suggestedtests import SystemProbe

SystemProbe.process_cpu_time()  # CpuTime(user: 1.25s, system: 80.00ms)
SystemProbe.thread_cpu_time_ns()  # this thread only
SystemProbe.memory_usage()  # MemoryUsage(current: 40.1 MiB, peak: 52.3 MiB)
SystemProbe.cpu_count()
```

**You don't need Rust.** The wheel contains the bridge prebuilt for
Linux (glibc ≥ 2.17 and musl; x64, arm64, x86, ARMv7 and RISC-V 64), macOS (Intel and Apple Silicon) and Windows (x64, arm64, x86), and Android (Termux; all four ABIs). It is loaded with `ctypes`; a
32-bit Python on a 64-bit OS gets the 32-bit build. On Linux it picks the glibc or musl build, matching
the running interpreter. To use your own build, point
`$SUGGESTEDTESTS_NATIVE_LIB` at it. Tests marked
`@pytest.mark.requires_native_bridge` are skipped, with the reason, on
platforms without a build.

### Startup report

The bridge can describe the machine the tests run on: OS, architecture, C
library, container, VM and machine kind, as three `suggestedtests: ...` lines on
stderr. It is off by default, so nothing is printed. Turn it on for the whole
run, which prints it as the bridge loads:

```sh
SUGGESTEDTESTS_VERBOSE=1 pytest
```

Importing `suggestedtests` loads the bridge, and pytest's plugin imports it, so the report appears in every run, even one that never calls a native helper. Or turn it on from code, which prints it then (at most once per process):

```python
SystemProbe.set_verbose(True)
```

```
suggestedtests: native bridge loaded (ABI v1)
suggestedtests: platform: linux x86_64 glibc 2.39, 64-bit, os 6.8.0-45-generic
suggestedtests: environment: server, container docker, vm kvm (KVMKVMKVM), flags: ci
```

This flag controls nothing else.

## `eventually`: no more fixed sleeps

```python
eventually(lambda: client.get("/health").raise_for_status())
eventually(check_queue_is_empty, timeout=10, interval=0.1)
await eventually_async(lambda: assert_job_done(job_id))
```

The test continues as soon as the condition holds, and fails with the last
error after the timeout.

## Given / when / then

```python
def test_adding_items_updates_the_total(steps):
    with steps.given("an empty cart"):
        cart = Cart()
    with steps.when("two items are added"):
        cart.add(10)
        cart.add(20)
    with steps.then("the total is 30"):
        assert cart.total == 30
```

The original exception propagates unchanged, so pytest's assertion
introspection still works. A note is added that names the failing step and
the steps that passed:

```
E       assert 20 == 30
Failed step: Then: the total is 30
Passed steps:
  ✓ Given: an empty cart
  ✓ When: two items are added
```

## Reproducible test data

```python
def test_signup(test_data):
    user = User(name=test_data.word(), email=test_data.email(), age=test_data.integer(18, 90))
    assert signup(user).ok
```

Each test gets a fresh seed. When a test fails, the report shows how to rerun
it with the same data:

```
----- suggestedtests -----
test_data seed: 1804289383
reproduce with: pytest 'tests/test_signup.py::test_signup' --st-seed=1804289383
```

Use `TestData(42)` directly outside of fixtures. It offers `integer`,
`decimal`, `boolean`, `string`, `word`, `sentence`, `email`, `uuid`, `date`,
`pick`, `list_of` and `shuffled`.

## Other checks

```python
assert_unique(u.id for u in users)  # 'b' appears at index 1 and 3

with no_leaked_threads():  # fails if threads outlive the block
    with WorkerPool(4) as pool:
        pool.submit(job)
```

## Example

See [`examples/test_example.py`](examples/test_example.py). Run it with
`pytest examples/`.

## License

MIT
