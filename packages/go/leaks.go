package suggestedtests

import (
	"bytes"
	"runtime"
	"strconv"
	"strings"
	"testing"
	"time"
)

type goroutine struct {
	id    uint64
	stack string
}

// goroutines parses runtime.Stack(all) into goroutines, excluding the caller.
func goroutines() []goroutine {
	buf := make([]byte, 1<<16)
	for {
		n := runtime.Stack(buf, true)
		if n < len(buf) {
			buf = buf[:n]
			break
		}
		buf = make([]byte, 2*len(buf))
	}
	var out []goroutine
	for i, block := range bytes.Split(buf, []byte("\n\n")) {
		if i == 0 {
			continue // the calling goroutine
		}
		header := string(block)
		if !strings.HasPrefix(header, "goroutine ") {
			continue
		}
		fields := strings.Fields(header)
		id, err := strconv.ParseUint(fields[1], 10, 64)
		if err != nil {
			continue
		}
		out = append(out, goroutine{id: id, stack: string(block)})
	}
	return out
}

type leakConfig struct {
	grace  time.Duration
	ignore []string
}

// LeakOption configures NoGoroutineLeaks.
type LeakOption func(*leakConfig)

// Grace sets how long goroutines may take to exit after the test (default 1s).
func Grace(d time.Duration) LeakOption { return func(c *leakConfig) { c.grace = d } }

// IgnoreFunction ignores goroutines whose stack contains function, e.g.
// "go.opencensus.io/stats/view.(*worker).start".
func IgnoreFunction(function string) LeakOption {
	return func(c *leakConfig) { c.ignore = append(c.ignore, function) }
}

// NoGoroutineLeaks fails the test if goroutines started during it are still
// running when it ends (after its other cleanups and a grace period). The
// failure prints their stacks. Call it first in the test:
//
//	func TestServer(t *testing.T) {
//		st.NoGoroutineLeaks(t)
//		srv := startServer(t) // registers t.Cleanup(srv.Close)
//		...
//	}
func NoGoroutineLeaks(t testing.TB, opts ...LeakOption) {
	t.Helper()
	c := leakConfig{grace: time.Second}
	for _, o := range opts {
		o(&c)
	}
	before := map[uint64]bool{}
	for _, g := range goroutines() {
		before[g.id] = true
	}
	// Cleanups run last-registered first, so this runs after the test's own.
	t.Cleanup(func() {
		t.Helper()
		deadline := time.Now().Add(c.grace)
		for {
			leaked := leakedGoroutines(before, c.ignore)
			if len(leaked) == 0 {
				return
			}
			if time.Now().After(deadline) {
				var b strings.Builder
				for _, g := range leaked {
					b.WriteString("\n\n")
					b.WriteString(g.stack)
				}
				t.Errorf("%d goroutine(s) still running %s after the test:%s", len(leaked), FormatDuration(c.grace), b.String())
				return
			}
			time.Sleep(10 * time.Millisecond)
		}
	})
}

func leakedGoroutines(before map[uint64]bool, ignore []string) []goroutine {
	var leaked []goroutine
outer:
	for _, g := range goroutines() {
		if before[g.id] {
			continue
		}
		for _, f := range ignore {
			if strings.Contains(g.stack, f) {
				continue outer
			}
		}
		leaked = append(leaked, g)
	}
	return leaked
}
