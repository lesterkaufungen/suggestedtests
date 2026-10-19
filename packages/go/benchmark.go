package suggestedtests

import (
	"errors"
	"fmt"
	"math"
	"runtime"
	"sort"
	"testing"
	"time"
)

// Clock is what a benchmark measures.
type Clock int

const (
	// Wall is elapsed time. It includes waiting, GC and other processes.
	Wall Clock = iota
	// CPU is the CPU time of the benchmarking goroutine's OS thread (locked
	// for the run), via the native bridge. It ignores waiting, other
	// goroutines (including the GC's) and other processes, so it is far less
	// noisy on busy CI machines.
	CPU
)

func (c Clock) String() string {
	if c == CPU {
		return "cpu"
	}
	return "wall"
}

// Statistic selects which statistic of a Result a budget is checked against.
// The zero value is Median.
type Statistic int

const (
	Median Statistic = iota // middle sample; robust against GC pauses
	Min                     // fastest sample
	Mean                    // arithmetic mean
	P95                     // 95th percentile
	Max                     // slowest sample
)

func (s Statistic) String() string {
	switch s {
	case Min:
		return "min"
	case Mean:
		return "mean"
	case P95:
		return "p95"
	case Max:
		return "max"
	}
	return "median"
}

// Result holds the timing statistics of a benchmark.
type Result struct {
	Name    string
	Clock   Clock
	Samples []time.Duration // in run order, warm-up runs excluded
	sorted  []time.Duration
}

// NewResult builds a Result from samples, which must not be empty.
func NewResult(name string, samples []time.Duration, clock Clock) (Result, error) {
	if len(samples) == 0 {
		return Result{}, errors.New("suggestedtests: samples must not be empty")
	}
	s := append([]time.Duration(nil), samples...)
	sorted := append([]time.Duration(nil), samples...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i] < sorted[j] })
	return Result{Name: name, Clock: clock, Samples: s, sorted: sorted}, nil
}

// Min returns the fastest sample.
func (r Result) Min() time.Duration { return r.sorted[0] }

// Max returns the slowest sample.
func (r Result) Max() time.Duration { return r.sorted[len(r.sorted)-1] }

// Mean returns the arithmetic mean.
func (r Result) Mean() time.Duration {
	var total float64
	for _, s := range r.Samples {
		total += float64(s)
	}
	return time.Duration(math.Round(total / float64(len(r.Samples))))
}

// Median returns the 50th percentile.
func (r Result) Median() time.Duration { return r.Percentile(50) }

// P95 returns the 95th percentile.
func (r Result) P95() time.Duration { return r.Percentile(95) }

// StdDev returns the population standard deviation.
func (r Result) StdDev() time.Duration {
	mean := float64(r.Mean())
	var sum float64
	for _, s := range r.Samples {
		sum += (float64(s) - mean) * (float64(s) - mean)
	}
	return time.Duration(math.Round(math.Sqrt(sum / float64(len(r.Samples)))))
}

// Percentile returns the p-th percentile (0-100, clamped) using nearest-rank.
func (r Result) Percentile(p float64) time.Duration {
	if p < 0 {
		p = 0
	}
	if p > 100 {
		p = 100
	}
	rank := int(math.Ceil(p / 100 * float64(len(r.sorted))))
	if rank < 1 {
		rank = 1
	}
	return r.sorted[rank-1]
}

// Get returns the value of s.
func (r Result) Get(s Statistic) time.Duration {
	switch s {
	case Min:
		return r.Min()
	case Mean:
		return r.Mean()
	case P95:
		return r.P95()
	case Max:
		return r.Max()
	}
	return r.Median()
}

func (r Result) String() string {
	cpu := ""
	if r.Clock == CPU {
		cpu = " (cpu)"
	}
	return fmt.Sprintf("%s%s: n=%d min=%s median=%s mean=%s p95=%s max=%s ±%s",
		r.Name, cpu, len(r.Samples), FormatDuration(r.Min()), FormatDuration(r.Median()),
		FormatDuration(r.Mean()), FormatDuration(r.P95()), FormatDuration(r.Max()), FormatDuration(r.StdDev()))
}

type benchConfig struct {
	iterations, warmup int
	clock              Clock
	statistic          Statistic
}

// BenchOption configures Benchmark and ExpectPerformance.
type BenchOption func(*benchConfig)

// Iterations sets the number of timed runs (default 20, at least 1).
func Iterations(n int) BenchOption { return func(c *benchConfig) { c.iterations = n } }

// Warmup sets the number of untimed runs before the timed ones (default 3).
func Warmup(n int) BenchOption { return func(c *benchConfig) { c.warmup = n } }

// WithClock sets what is measured (default Wall).
func WithClock(clock Clock) BenchOption { return func(c *benchConfig) { c.clock = clock } }

// WithStatistic sets the statistic ExpectPerformance checks (default Median).
func WithStatistic(s Statistic) BenchOption { return func(c *benchConfig) { c.statistic = s } }

func configure(opts []BenchOption) (benchConfig, error) {
	c := benchConfig{iterations: 20, warmup: 3}
	for _, o := range opts {
		o(&c)
	}
	switch {
	case c.iterations < 1:
		return c, fmt.Errorf("suggestedtests: iterations must be >= 1, got %d", c.iterations)
	case c.warmup < 0:
		return c, fmt.Errorf("suggestedtests: warmup must be >= 0, got %d", c.warmup)
	case c.clock != Wall && c.clock != CPU:
		return c, fmt.Errorf("suggestedtests: unknown clock %d", c.clock)
	case c.statistic < Median || c.statistic > Max:
		return c, fmt.Errorf("suggestedtests: unknown statistic %d", c.statistic)
	}
	return c, nil
}

// Benchmark runs fn Warmup times untimed, then Iterations times timed, and
// returns the statistics.
//
//	r, err := st.Benchmark("sort", func() { sort.Ints(clone(data)) }, st.Iterations(50))
//	fmt.Println(r) // sort: n=50 min=1.02ms median=1.10ms mean=1.15ms p95=1.40ms max=2.01ms ±120µs
func Benchmark(name string, fn func(), opts ...BenchOption) (Result, error) {
	c, err := configure(opts)
	if err != nil {
		return Result{}, err
	}
	origin := time.Now()
	now := func() time.Duration { return time.Since(origin) } // monotonic clock
	if c.clock == CPU {
		if _, err := bridge("ThreadCPUTime"); err != nil {
			return Result{}, fmt.Errorf("suggestedtests: the CPU clock needs the native bridge: %v", err)
		}
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()
		now = func() time.Duration { d, _ := ThreadCPUTime(); return d }
	}
	for i := 0; i < c.warmup; i++ {
		fn()
	}
	samples := make([]time.Duration, c.iterations)
	for i := range samples {
		start := now()
		fn()
		samples[i] = now() - start
	}
	return NewResult(name, samples, c.clock)
}

// ExpectPerformance benchmarks fn and fails the test if the chosen statistic
// (Median unless WithStatistic is given) exceeds budget.
//
//	st.ExpectPerformance(t, 5*time.Millisecond, func() { parse(bigJSON) })
//	st.ExpectPerformance(t, 20*time.Millisecond, render, st.WithStatistic(st.P95), st.WithClock(st.CPU))
func ExpectPerformance(t testing.TB, budget time.Duration, fn func(), opts ...BenchOption) (Result, bool) {
	t.Helper()
	if budget < 0 {
		t.Fatalf("suggestedtests: budget must be >= 0, got %s", budget)
	}
	c, err := configure(opts)
	if err != nil {
		t.Fatal(err)
	}
	r, err := Benchmark("benchmark", fn, opts...)
	if err != nil {
		t.Fatal(err)
	}
	if actual := r.Get(c.statistic); actual > budget {
		t.Errorf("performance budget exceeded: %s %s > budget %s\n%s",
			c.statistic, FormatDuration(actual), FormatDuration(budget), r)
		return r, false
	}
	return r, true
}
