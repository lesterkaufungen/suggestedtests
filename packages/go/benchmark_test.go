package suggestedtests

import (
	"strings"
	"testing"
	"time"
)

func ns(values ...int64) []time.Duration {
	out := make([]time.Duration, len(values))
	for i, v := range values {
		out[i] = time.Duration(v)
	}
	return out
}

func TestResultStatistics(t *testing.T) {
	r, err := NewResult("r", ns(5, 1, 3, 2, 4), Wall)
	if err != nil {
		t.Fatal(err)
	}
	got := []time.Duration{r.Min(), r.Max(), r.Mean(), r.Median(), r.P95(), r.Percentile(0), r.StdDev()}
	want := ns(1, 5, 3, 3, 5, 1, 1)
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("stat %d = %v, want %v", i, got[i], want[i])
		}
	}
	if r.Get(Max) != 5 || r.Get(Median) != 3 {
		t.Error("Get")
	}
	if r.Samples[0] != 5 {
		t.Error("samples must keep run order")
	}
	if _, err := NewResult("r", nil, Wall); err == nil {
		t.Error("empty samples must fail")
	}
}

func TestResultString(t *testing.T) {
	r, _ := NewResult("x", ns(500_000, 2_500_000, 3_000_000_000), CPU)
	if s := r.String(); !strings.HasPrefix(s, "x (cpu): n=3 min=500µs median=2.50ms mean=1.00s") {
		t.Error(s)
	}
}

func TestBenchmarkCountsRuns(t *testing.T) {
	calls := 0
	r, err := Benchmark("b", func() { calls++ }, Iterations(5), Warmup(2))
	if err != nil {
		t.Fatal(err)
	}
	if calls != 7 || len(r.Samples) != 5 {
		t.Errorf("calls=%d samples=%d", calls, len(r.Samples))
	}
}

func TestBenchmarkValidatesOptions(t *testing.T) {
	for name, opt := range map[string]BenchOption{
		"iterations": Iterations(0), "warmup": Warmup(-1), "clock": WithClock(Clock(9)), "statistic": WithStatistic(Statistic(9)),
	} {
		if _, err := Benchmark("b", func() {}, opt); err == nil {
			t.Errorf("%s: expected an error", name)
		}
	}
}

func TestCPUClockIgnoresSleep(t *testing.T) {
	RequireNativeBridge(t)
	r, err := Benchmark("sleep", func() { time.Sleep(10 * time.Millisecond) }, Iterations(3), Warmup(0), WithClock(CPU))
	if err != nil {
		t.Fatal(err)
	}
	if r.Clock != CPU || r.Median() > 5*time.Millisecond {
		t.Errorf("CPU clock counted sleeping: %s", r)
	}
}

func TestExpectPerformance(t *testing.T) {
	wantPass(t, runFake(t, func(tb testing.TB) { ExpectPerformance(tb, time.Second, func() {}) }))
	f := runFake(t, func(tb testing.TB) {
		ExpectPerformance(tb, 0, func() { _ = strings.Repeat("x", 100_000) }, WithStatistic(Max), Iterations(2))
	})
	wantFailure(t, f, "performance budget exceeded: max", "> budget 0µs", "benchmark: n=2")
}

func TestExpectPerformanceValidatesBeforeRunning(t *testing.T) {
	calls := 0
	f := runFake(t, func(tb testing.TB) { ExpectPerformance(tb, -1, func() { calls++ }) })
	wantFailure(t, f, "budget must be >= 0")
	f = runFake(t, func(tb testing.TB) { ExpectPerformance(tb, time.Second, func() { calls++ }, Iterations(0)) })
	wantFailure(t, f, "iterations must be >= 1")
	if calls != 0 || !f.fatal {
		t.Errorf("calls=%d fatal=%v", calls, f.fatal)
	}
}
