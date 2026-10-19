package suggestedtests

import (
	"testing"
	"time"
)

func TestNoGoroutineLeaksPassesWhenGoroutinesExit(t *testing.T) {
	wantPass(t, runFake(t, func(tb testing.TB) {
		NoGoroutineLeaks(tb)
		done := make(chan struct{})
		go func() { time.Sleep(10 * time.Millisecond); close(done) }()
		<-done
	}))
}

func TestNoGoroutineLeaksRunsAfterOtherCleanups(t *testing.T) {
	wantPass(t, runFake(t, func(tb testing.TB) {
		NoGoroutineLeaks(tb)
		stop := make(chan struct{})
		go func() { <-stop }()
		tb.Cleanup(func() { close(stop) })
	}))
}

func TestNoGoroutineLeaksReportsStacks(t *testing.T) {
	stop := make(chan struct{})
	defer close(stop)
	f := runFake(t, func(tb testing.TB) {
		NoGoroutineLeaks(tb, Grace(50*time.Millisecond))
		go leakyWorker(stop)
	})
	wantFailure(t, f, "1 goroutine(s) still running 50.00ms after the test", "leakyWorker")
}

func TestNoGoroutineLeaksIgnore(t *testing.T) {
	stop := make(chan struct{})
	defer close(stop)
	wantPass(t, runFake(t, func(tb testing.TB) {
		NoGoroutineLeaks(tb, Grace(20*time.Millisecond), IgnoreFunction("leakyWorker"))
		go leakyWorker(stop)
	}))
}

func leakyWorker(stop chan struct{}) { <-stop }
