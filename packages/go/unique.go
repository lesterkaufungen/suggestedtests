package suggestedtests

import "testing"

// AssertUnique fails the test if items contains two equal elements, naming
// the duplicate and both indices.
//
//	st.AssertUnique(t, ids) // duplicate "b" at index 1 and 3
func AssertUnique[T comparable](t testing.TB, items []T) bool {
	t.Helper()
	seen := make(map[T]int, len(items))
	for i, item := range items {
		if first, ok := seen[item]; ok {
			t.Errorf("expected unique elements, but %#v appears at index %d and %d", item, first, i)
			return false
		}
		seen[item] = i
	}
	return true
}
