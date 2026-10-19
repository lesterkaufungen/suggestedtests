// Package suggestedtests adds helpers to Go's testing package: performance
// and memory budgets backed by an OS-native bridge (CPU time and resident
// memory on Windows, Linux and macOS), Eventually, given/when/then
// scenarios, goroutine-leak checks, race tests, golden files and seeded test
// data.
//
//	import st "github.com/lesterkaufungen/suggestedtests/packages/go"
//
//	func TestParsingStaysFast(t *testing.T) {
//		st.ExpectPerformance(t, 5*time.Millisecond, func() { parse(bigJSON) })
//	}
//
// The bridge is a prebuilt Rust library embedded in the module and loaded
// with purego, so it needs neither cgo nor a C compiler. Tests that need it
// call RequireNativeBridge to be skipped where it is unavailable.
//
// Helpers report failures with t.Errorf and return whether they passed, like
// assertions; stop the test with `if !ok { t.FailNow() }` where needed.
// Invalid arguments are programmer errors: helpers that take a testing.TB
// call t.Fatalf, others return an error or panic.
package suggestedtests
