package suggestedtests

import "testing"

func TestAssertUnique(t *testing.T) {
	wantPass(t, runFake(t, func(tb testing.TB) { AssertUnique(tb, []int{1, 2, 3}) }))
	wantFailure(t, runFake(t, func(tb testing.TB) { AssertUnique(tb, []string{"a", "b", "c", "b"}) }),
		`expected unique elements, but "b" appears at index 1 and 3`)
	type id struct{ n int }
	wantFailure(t, runFake(t, func(tb testing.TB) { AssertUnique(tb, []id{{1}, {1}}) }), "appears at index 0 and 1")
}
