package suggestedtests

import (
	"errors"
	"testing"
	"time"
)

func TestEventuallyPassesOnceConditionHolds(t *testing.T) {
	n := 0
	ok := Eventually(t, func() error {
		n++
		if n < 3 {
			return errors.New("not yet")
		}
		return nil
	}, Every(time.Millisecond))
	if !ok || n != 3 {
		t.Errorf("ok=%v n=%d", ok, n)
	}
}

func TestEventuallyFailsWithLastError(t *testing.T) {
	f := runFake(t, func(tb testing.TB) {
		Eventually(tb, func() error { return errors.New("boom") }, Within(30*time.Millisecond), Every(5*time.Millisecond))
	})
	wantFailure(t, f, "condition not met within 30.00ms (", "attempts). Last error:\nboom")
}

func TestEventuallyValidates(t *testing.T) {
	wantFailure(t, runFake(t, func(tb testing.TB) { Eventually(tb, func() error { return nil }, Within(-1)) }), "must be >= 0")
}
