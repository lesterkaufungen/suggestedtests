package suggestedtests

import (
	"errors"
	"sync/atomic"
	"testing"
	"time"
)

func TestRaceRunsEveryGoroutine(t *testing.T) {
	var counter int64
	ok := Race(t, 8, func(i int) error {
		for j := 0; j < 1000; j++ {
			atomic.AddInt64(&counter, 1)
		}
		return nil
	})
	if !ok || counter != 8000 {
		t.Errorf("ok=%v counter=%d", ok, counter)
	}
}

func TestRaceReportsErrorsAndPanics(t *testing.T) {
	f := runFake(t, func(tb testing.TB) {
		Race(tb, 3, func(i int) error {
			switch i {
			case 0:
				return errors.New("bad state")
			case 1:
				panic("kaboom")
			}
			return nil
		})
	})
	wantFailure(t, f, "2 of 3 goroutines failed", "goroutine 0: bad state", "goroutine 1: panic: kaboom")
}

func TestRaceReportsStuckGoroutines(t *testing.T) {
	never := make(chan struct{})
	defer close(never)
	f := runFake(t, func(tb testing.TB) {
		Race(tb, 2, func(i int) error { <-never; return nil }, RaceTimeout(50*time.Millisecond))
	})
	wantFailure(t, f, "goroutines still running after 50.00ms", "raceWorker")
}

func TestRaceValidates(t *testing.T) {
	wantFailure(t, runFake(t, func(tb testing.TB) { Race(tb, 0, func(int) error { return nil }) }), "n >= 1")
}
