package suggestedtests

import (
	"fmt"
	"runtime/debug"
	"strings"
	"sync"
	"testing"
	"time"
)

type raceConfig struct{ timeout time.Duration }

// RaceOption configures Race.
type RaceOption func(*raceConfig)

// RaceTimeout sets how long all goroutines may take together (default 10s).
func RaceTimeout(d time.Duration) RaceOption { return func(c *raceConfig) { c.timeout = d } }

// Race starts n goroutines, releases them at the same instant and runs fn in
// each with its index, which maximises contention. It fails the test if any
// returns an error or panics, or if they don't finish in time, in which case
// it prints the stuck goroutines' stacks (usually a deadlock). Combine with
// `go test -race`.
//
//	var counter Counter
//	st.Race(t, 8, func(i int) error {
//		for j := 0; j < 1000; j++ {
//			counter.Inc()
//		}
//		return nil
//	})
func Race(t testing.TB, n int, fn func(i int) error, opts ...RaceOption) bool {
	t.Helper()
	c := raceConfig{timeout: 10 * time.Second}
	for _, o := range opts {
		o(&c)
	}
	if n < 1 {
		t.Fatalf("suggestedtests: Race needs n >= 1, got %d", n)
	}
	if c.timeout < 0 {
		t.Fatalf("suggestedtests: RaceTimeout must be >= 0, got %s", c.timeout)
	}
	var ready, done sync.WaitGroup
	start := make(chan struct{})
	errs := make([]error, n)
	ready.Add(n)
	done.Add(n)
	for i := 0; i < n; i++ {
		go func(i int) {
			defer done.Done()
			defer func() {
				if r := recover(); r != nil {
					errs[i] = fmt.Errorf("panic: %v\n%s", r, debug.Stack())
				}
			}()
			ready.Done()
			<-start
			errs[i] = raceWorker(fn, i)
		}(i)
	}
	ready.Wait()
	close(start)
	finished := make(chan struct{})
	go func() { done.Wait(); close(finished) }()
	select {
	case <-finished:
	case <-time.After(c.timeout):
		var stuck strings.Builder
		for _, g := range goroutines() {
			if strings.Contains(g.stack, ".raceWorker(") {
				stuck.WriteString("\n\n" + g.stack)
			}
		}
		t.Errorf("goroutines still running after %s:%s", FormatDuration(c.timeout), stuck.String())
		return false
	}
	var failed []string
	for i, err := range errs {
		if err != nil {
			failed = append(failed, fmt.Sprintf("goroutine %d: %v", i, err))
		}
	}
	if len(failed) > 0 {
		t.Errorf("%d of %d goroutines failed:\n%s", len(failed), n, strings.Join(failed, "\n"))
		return false
	}
	return true
}

// raceWorker is a named frame so stuck goroutines can be found by stack.
//
//go:noinline
func raceWorker(fn func(int) error, i int) error { return fn(i) }
