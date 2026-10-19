package suggestedtests

import (
	"fmt"
	"runtime"
	"strings"
	"sync"
	"testing"
)

// fakeTB records failures so tests can check that helpers fail correctly.
type fakeTB struct {
	testing.TB
	mu       sync.Mutex
	errors   []string
	logs     []string
	failed   bool
	fatal    bool
	skipped  bool
	cleanups []func()
}

func (f *fakeTB) record(msg string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.errors = append(f.errors, msg)
	f.failed = true
}

func (f *fakeTB) Helper()                           {}
func (f *fakeTB) Error(args ...interface{})         { f.record(fmt.Sprint(args...)) }
func (f *fakeTB) Errorf(s string, a ...interface{}) { f.record(fmt.Sprintf(s, a...)) }
func (f *fakeTB) Fail()                             { f.mu.Lock(); f.failed = true; f.mu.Unlock() }
func (f *fakeTB) Fatal(args ...interface{})         { f.record(fmt.Sprint(args...)); f.FailNow() }
func (f *fakeTB) Fatalf(s string, a ...interface{}) { f.record(fmt.Sprintf(s, a...)); f.FailNow() }
func (f *fakeTB) FailNow() {
	f.mu.Lock()
	f.failed, f.fatal = true, true
	f.mu.Unlock()
	runtime.Goexit()
}
func (f *fakeTB) Skip(args ...interface{}) {
	f.mu.Lock()
	f.skipped = true
	f.mu.Unlock()
	runtime.Goexit()
}
func (f *fakeTB) Logf(s string, a ...interface{}) {
	f.mu.Lock()
	f.logs = append(f.logs, fmt.Sprintf(s, a...))
	f.mu.Unlock()
}
func (f *fakeTB) Failed() bool      { f.mu.Lock(); defer f.mu.Unlock(); return f.failed }
func (f *fakeTB) Cleanup(fn func()) { f.mu.Lock(); f.cleanups = append(f.cleanups, fn); f.mu.Unlock() }
func (f *fakeTB) output() string {
	return strings.Join(append(append([]string{}, f.errors...), f.logs...), "\n")
}

// runFake runs body against a fakeTB the way the testing package runs a test.
func runFake(t *testing.T, body func(tb testing.TB)) *fakeTB {
	f := &fakeTB{TB: t}
	run := func(fn func()) {
		done := make(chan struct{})
		go func() { defer close(done); fn() }()
		<-done
	}
	run(func() { body(f) })
	for i := len(f.cleanups) - 1; i >= 0; i-- {
		run(f.cleanups[i])
	}
	return f
}

func wantFailure(t *testing.T, f *fakeTB, contains ...string) {
	t.Helper()
	if !f.failed {
		t.Fatalf("expected a failure, got none")
	}
	out := f.output()
	for _, c := range contains {
		if !strings.Contains(out, c) {
			t.Errorf("failure output does not contain %q:\n%s", c, out)
		}
	}
}

func wantPass(t *testing.T, f *fakeTB) {
	t.Helper()
	if f.failed {
		t.Fatalf("expected no failure, got:\n%s", f.output())
	}
}
