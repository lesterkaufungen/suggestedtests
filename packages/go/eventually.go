package suggestedtests

import (
	"testing"
	"time"
)

type eventuallyConfig struct{ timeout, interval time.Duration }

// EventuallyOption configures Eventually.
type EventuallyOption func(*eventuallyConfig)

// Within sets how long Eventually keeps trying (default 5s).
func Within(d time.Duration) EventuallyOption { return func(c *eventuallyConfig) { c.timeout = d } }

// Every sets the pause between attempts (default 20ms).
func Every(d time.Duration) EventuallyOption { return func(c *eventuallyConfig) { c.interval = d } }

// Eventually calls cond until it returns nil, then returns true. If it still
// returns an error after the timeout, the test fails with the last error.
// It replaces fixed time.Sleep calls: the test continues as soon as the
// condition holds.
//
//	st.Eventually(t, func() error {
//		if !cache.Warm() {
//			return errors.New("cache is cold")
//		}
//		return nil
//	}, st.Within(10*time.Second))
func Eventually(t testing.TB, cond func() error, opts ...EventuallyOption) bool {
	t.Helper()
	c := eventuallyConfig{timeout: 5 * time.Second, interval: 20 * time.Millisecond}
	for _, o := range opts {
		o(&c)
	}
	if c.timeout < 0 || c.interval < 0 {
		t.Fatalf("suggestedtests: Within and Every must be >= 0, got %s and %s", c.timeout, c.interval)
	}
	start := time.Now()
	for attempts := 1; ; attempts++ {
		err := cond()
		if err == nil {
			return true
		}
		if time.Since(start) >= c.timeout {
			t.Errorf("condition not met within %s (%d attempts). Last error:\n%v",
				FormatDuration(c.timeout), attempts, err)
			return false
		}
		time.Sleep(c.interval)
	}
}
