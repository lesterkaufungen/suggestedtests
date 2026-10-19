<p align="center">
  <img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/packages/dart/assets/logo.png" alt="suggestedtests logo" width="140">
</p>

<h1 align="center">suggestedtests for Go</h1>

<p align="center">
  Helpers for Go's <code>testing</code> package that make tests faster to write, and keep your code fast.
</p>

<p align="center">
  <a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md"><img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/bench/tokens/banner.png" alt="Tokens an AI coding agent spends per test, hand-written vs with suggestedtests, projected to larger test suites (estimate)" width="900"></a>
</p>

<p align="center">
  <a href="https://pkg.go.dev/github.com/lesterkaufungen/suggestedtests/packages/go"><img src="https://pkg.go.dev/badge/github.com/lesterkaufungen/suggestedtests/packages/go.svg" alt="Go Reference"></a>
  <img src="https://img.shields.io/badge/Go-1.18%2B-00ADD8?logo=go&logoColor=white" alt="Go 1.18+">
  <img src="https://img.shields.io/badge/cgo-not%20needed-00ADD8" alt="no cgo needed">
  <!-- tokens:badge -->
<!-- prettier-ignore-start -->
<a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md"><img src="https://img.shields.io/badge/AI%20agents-~54%25%20fewer%20tokens-8A2BE2" alt="~54% fewer tokens for AI agents (estimate)"></a>
<!-- prettier-ignore-end -->
<!-- /tokens:badge -->
  <a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/packages/go/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <sub>The same helpers in <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/dart">Flutter & Dart</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/python">Python</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/js">JS & TS</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/php">PHP</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/java">Java</a> · <b>Go</b> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/swift">Swift</a> · <a href="https://github.com/lesterkaufungen/suggestedtests">one repo, one native bridge</a></sub>
</p>

---

| Helper | What it's for |
| --- | --- |
| `ExpectPerformance`, `Benchmark` | Performance budgets in ordinary tests, on wall-clock or CPU time. |
| `ExpectMemory` | Budgets for RSS (native bridge), live Go heap, bytes allocated and allocation count. |
| `ProcessCPUTime`, `ThreadCPUTime`, `ReadMemoryUsage`, `CPUCount` | Process metrics via a native bridge for Windows, Linux and macOS. |
| `NoGoroutineLeaks` | Fails a test that leaves goroutines running, and prints their stacks. |
| `Race` | Releases N goroutines at once to expose races; reports stuck ones with stacks. |
| `Eventually` | Polling instead of `time.Sleep`. |
| `NewScenario` | Given/when/then steps whose failure names the failing step. |
| `Golden` | `testdata/*.golden` files, updated with one environment variable. |
| `Data`, `NewTestData` | Seeded, reproducible fake data. A failure logs the seed. |
| `AssertUnique`, `RequireNativeBridge` | Duplicate check that names indices; skip where the bridge is unavailable. |

Use subtests for table-driven tests and `testing.B` for microbenchmarks; Go
already does those well. These helpers fail with `t.Errorf` and return
whether they passed.

## Built for AI coding agents

<!-- tokens:section -->
<!-- prettier-ignore-start -->
An agent that knows these helpers writes one call where it would otherwise
write the loop, the timer, the statistics and the failure message, and then
read all of it again on every later change. For the tests in the
[benchmark](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md), that is **575 → 263 tokens
(54% fewer)**:

| Test | Hand-written | With suggestedtests | Saved |
| --- | ---: | ---: | ---: |
| Performance budget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/go/performance.without.go), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/go/performance.with.go)) | 173 | 59 | 66% |
| Wait for a condition ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/go/eventually.without.go), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/go/eventually.with.go)) | 83 | 76 | 8% |
| Peak-RSS budget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/go/memory.without.go), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/go/memory.with.go)) | 158 | 70 | 56% |
| Goroutine-leak check ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/go/goroutine_leaks.without.go), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/go/goroutine_leaks.with.go)) | 161 | 58 | 64% |

Estimated with the public `o200k_base` tokenizer: other models count
differently, so compare the ratios, not the numbers. Reasoning and retries
aren't counted, and the hand-written versions are often weaker (Linux-only
memory reads, no seed in the failure).

Tell your agent the helpers exist. Paste this into `CLAUDE.md`, `AGENTS.md`
or your editor's rules (201 tokens of context, paid back after about
3 tests):

````markdown
## Tests: use suggestedtests (`st "github.com/lesterkaufungen/suggestedtests/packages/go"`)

- Timing budgets: `st.ExpectPerformance(t, 5*time.Millisecond, fn)`.
- Never `time.Sleep`: `st.Eventually(t, func() error {...})`.
- Memory: `st.ExpectMemory(t, fn, st.MaxPeakGrowth(50*st.MiB))` after `st.RequireNativeBridge(t)`; allocations: `st.MaxAllocs(0)`.
- Leaks and races: `st.NoGoroutineLeaks(t)` as the first line; `st.Race(t, n, func(i int) error {...})`.
- Given/when/then: `st.NewScenario(t).Given(...).When(...).Then(...)`; golden files: `st.Golden(t, "name", got)`.
- Seeded data: `d := st.Data(t)`; duplicates: `st.AssertUnique(t, items)`.
````
<!-- prettier-ignore-end -->
<!-- /tokens:section -->

## Install

```sh
go get github.com/lesterkaufungen/suggestedtests/packages/go
```

```go
import st "github.com/lesterkaufungen/suggestedtests/packages/go"
```

Requires Go 1.18+. Its only dependency is
[purego](https://github.com/ebitengine/purego), used to load the bridge
without cgo.

## Performance budgets

```go
func TestParsingStaysFast(t *testing.T) {
	st.ExpectPerformance(t, 5*time.Millisecond, func() { parse(bigJSON) })
}

func TestRenderP95(t *testing.T) {
	st.ExpectPerformance(t, 20*time.Millisecond, render,
		st.WithStatistic(st.P95), st.WithClock(st.CPU), st.Iterations(50))
}
```

On failure:

```
performance budget exceeded: median 7.31ms > budget 5.00ms
benchmark: n=20 min=6.90ms median=7.31ms mean=7.40ms p95=8.02ms max=8.30ms ±310µs
```

`st.WithClock(st.CPU)` measures the CPU time of the benchmarking goroutine,
which is locked to its OS thread for the run. It ignores waiting, other
goroutines (including the GC's) and other processes, so it is far less noisy
on busy CI machines. `st.Benchmark` returns the `Result` without asserting.

## Memory budgets

```go
func TestCacheHitDoesNotAllocate(t *testing.T) {
	st.ExpectMemory(t, func() { cache.Get("key") }, st.MaxAllocs(0))
}

func TestImportStaysSmall(t *testing.T) {
	st.RequireNativeBridge(t)
	st.ExpectMemory(t, func() { importer.Run(bigFile) }, st.MaxPeakGrowth(64*st.MiB))
}
```

| Limit | Measures |
| --- | --- |
| `MaxAllocs`, `MaxAllocatedBytes` | every allocation made while the function ran, even if freed (`MemStats.Mallocs`/`TotalAlloc`) |
| `MaxHeapGrowth` | live Go heap still referenced afterwards |
| `MaxRSSGrowth`, `MaxPeakGrowth` | resident memory of the whole process, including cgo and mmap (native bridge) |

Allocation counts are taken with `GOMAXPROCS(1)`, like
`testing.AllocsPerRun`, so other goroutines rarely interfere.

## Native bridge (Windows / Linux / macOS)

```go
cpu, _ := st.ProcessCPUTime()  // CPUTime(user: 1.25s, system: 80.00ms)
mem, _ := st.ReadMemoryUsage() // MemoryUsage(current: 40.1 MiB, peak: 52.3 MiB)
n, _ := st.CPUCount()
```

**You don't need Rust, cgo or a C compiler.** The module embeds the bridge
prebuilt for Linux (glibc ≥ 2.17 and musl; amd64, arm64, 386, arm and
riscv64), macOS (Intel and Apple Silicon), Windows (amd64, arm64, 386) and
Android (with cgo, as Go requires there). RISC-V needs Go 1.25+ (purego's
assembly); everything else works from Go 1.18. A test binary only contains
its own platform's library. On first use
it is written to the temp directory and loaded with purego, with
`CGO_ENABLED=0` or `1`. On Linux it picks the glibc or musl build, matching
the test binary's interpreter. To use your own build, point
`$SUGGESTEDTESTS_NATIVE_LIB` at it. Elsewhere, the package still builds,
the bridge functions return a `*NativeBridgeError`, and `RequireNativeBridge`
skips the test with the reason.

`ThreadCPUTime` measures the current OS thread. Goroutines move between
threads, so wrap the measured code in `runtime.LockOSThread()`.

### Startup report

The bridge can describe the machine the tests run on: OS, architecture, C
library, container, VM and machine kind, as three `suggestedtests: ...` lines on
stderr. It is off by default, so nothing is printed. Turn it on for the whole
run, which prints it as the bridge loads:

```sh
SUGGESTEDTESTS_VERBOSE=1 go test ./...
```

Importing the package loads the bridge when the test binary starts, so the report appears even in runs that never call a native helper. Or turn it on from code, which prints it then (at most once per process):

```go
st.SetNativeBridgeVerbose(true)
```

```
suggestedtests: native bridge loaded (ABI v1)
suggestedtests: platform: linux x86_64 glibc 2.39, 64-bit, os 6.8.0-45-generic
suggestedtests: environment: server, container docker, vm kvm (KVMKVMKVM), flags: ci
```

This flag controls nothing else.

## Goroutine leaks

```go
func TestServerShutsDown(t *testing.T) {
	st.NoGoroutineLeaks(t) // first, so it runs after the other cleanups
	srv := startServer(t) // registers t.Cleanup(srv.Close)
	...
}
// 1 goroutine(s) still running 1.00s after the test:
//
// goroutine 34 [chan receive]:
// example.com/app.(*Server).loop(...)
```

Use `st.Grace(d)` to wait longer, and `st.IgnoreFunction(name)` to ignore
goroutines you expect to stay.

## Races

```go
st.Race(t, 8, func(i int) error {
	for j := 0; j < 1000; j++ {
		counter.Inc()
	}
	return nil
})
```

Run it with `go test -race`. All goroutines start at once, which maximises
contention. Errors and panics are reported per goroutine. If they don't
finish within 10 seconds (`st.RaceTimeout(d)`), the stuck goroutines' stacks
are printed.

## `Eventually`: no more fixed sleeps

```go
st.Eventually(t, func() error {
	if !cache.Warm() {
		return errors.New("cache is cold")
	}
	return nil
}, st.Within(10*time.Second), st.Every(100*time.Millisecond))
```

## Given / when / then

```go
var c *Cart
st.NewScenario(t).
	Given("an empty cart", func(t testing.TB) { c = NewCart() }).
	When("two items are added", func(t testing.TB) { c.Add(10); c.Add(20) }).
	Then("the total is 30", func(t testing.TB) {
		if got := c.Total(); got != 30 {
			t.Errorf("total = %d, want 30", got)
		}
	})
// Then: the total is 30: total = 20, want 30
// passed steps:
//   ✓ Given: an empty cart
//   ✓ When: two items are added
```

A failing step stops the scenario; panics are reported with the step's name.

## Golden files

```go
st.Golden(t, "invoice", renderInvoice(order)) // testdata/invoice.golden
```

A missing file is written on the first run, except in CI (`$CI` set), where
it fails. Run with `SUGGESTEDTESTS_UPDATE_GOLDEN=1` to accept intended
changes. A mismatch shows the first differing line.

## Reproducible test data

```go
func TestSignup(t *testing.T) {
	d := st.Data(t)
	if err := signup(d.Email(), d.Int(18, 90)); err != nil {
		t.Fatal(err)
	}
}
// on failure: TestData seed: 1804289383 (reproduce with SUGGESTEDTESTS_SEED=1804289383 go test -run '^TestSignup$')
```

`TestData` offers `Int`, `Float`, `Bool`, `String`, `Word`, `Sentence`,
`Email`, `UUID` and `Time`, plus the generic functions `Pick`, `ListOf` and
`Shuffled`. It uses its own xoshiro256** generator, so a seed produces the
same values on every platform and Go version. `st.NewTestData(42)` works
outside tests.

## Example

See [`example_test.go`](example_test.go). Run it with `go test -run Example -v .`

## License

MIT
