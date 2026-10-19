package suggestedtests

import (
	"fmt"
	"runtime/debug"
	"strings"
	"testing"
)

// Scenario runs a test as given/when/then steps. Each step runs immediately,
// receives a testing.TB that prefixes its failures with the step, and stops
// the scenario if it fails:
//
//	s := st.NewScenario(t)
//	var cart *Cart
//	s.Given("an empty cart", func(t testing.TB) { cart = NewCart() })
//	s.When("two items are added", func(t testing.TB) { cart.Add(10); cart.Add(20) })
//	s.Then("the total is 30", func(t testing.TB) {
//		if got := cart.Total(); got != 30 {
//			t.Errorf("total = %d, want 30", got)
//		}
//	})
//
// fails with "Then: the total is 30: total = 20, want 30" and lists the
// steps that passed.
type Scenario struct {
	t      testing.TB
	passed []string
}

// NewScenario starts a scenario in t.
func NewScenario(t testing.TB) *Scenario { return &Scenario{t: t} }

// Given runs a setup step.
func (s *Scenario) Given(description string, step func(t testing.TB)) *Scenario {
	s.t.Helper()
	return s.run("Given", description, step)
}

// When runs the action under test.
func (s *Scenario) When(description string, step func(t testing.TB)) *Scenario {
	s.t.Helper()
	return s.run("When", description, step)
}

// Then runs an expectation.
func (s *Scenario) Then(description string, step func(t testing.TB)) *Scenario {
	s.t.Helper()
	return s.run("Then", description, step)
}

// And continues the previous step kind (e.g. a second Then).
func (s *Scenario) And(description string, step func(t testing.TB)) *Scenario {
	s.t.Helper()
	return s.run("And", description, step)
}

// Passed returns the steps that completed, as "Keyword: description".
func (s *Scenario) Passed() []string { return append([]string(nil), s.passed...) }

func (s *Scenario) run(keyword, description string, step func(t testing.TB)) *Scenario {
	s.t.Helper()
	if description == "" || step == nil {
		s.t.Fatalf("suggestedtests: %s needs a description and a step function", keyword)
	}
	label := keyword + ": " + description
	st := &stepTB{TB: s.t, label: label}
	failedBefore := s.t.Failed()
	completed := false
	logPassed := func() {
		if len(s.passed) > 0 {
			s.t.Logf("passed steps:\n  ✓ %s", strings.Join(s.passed, "\n  ✓ "))
		}
	}
	func() {
		defer func() {
			if r := recover(); r != nil {
				s.t.Errorf("%s: panic: %v\n%s", label, r, debug.Stack())
				st.failed = true
				return
			}
			if !completed {
				// The step called FailNow / Fatal / SkipNow (runtime.Goexit);
				// log before the test goroutine exits.
				if s.t.Failed() {
					logPassed()
				}
			}
		}()
		step(st)
		completed = true
	}()
	if st.failed || (!failedBefore && s.t.Failed()) {
		logPassed()
		s.t.FailNow()
	}
	s.passed = append(s.passed, label)
	return s
}

// stepTB prefixes failures with the step.
type stepTB struct {
	testing.TB
	label  string
	failed bool
}

func (s *stepTB) Error(args ...interface{}) {
	s.TB.Helper()
	s.failed = true
	s.TB.Error(s.label + ": " + fmt.Sprint(args...))
}

func (s *stepTB) Errorf(format string, args ...interface{}) {
	s.TB.Helper()
	s.failed = true
	s.TB.Errorf("%s: %s", s.label, fmt.Sprintf(format, args...))
}

func (s *stepTB) Fatal(args ...interface{}) {
	s.TB.Helper()
	s.failed = true
	s.TB.Fatal(s.label + ": " + fmt.Sprint(args...))
}

func (s *stepTB) Fatalf(format string, args ...interface{}) {
	s.TB.Helper()
	s.failed = true
	s.TB.Fatalf("%s: %s", s.label, fmt.Sprintf(format, args...))
}

func (s *stepTB) Fail() {
	s.failed = true
	s.TB.Fail()
}

func (s *stepTB) FailNow() {
	s.failed = true
	s.TB.FailNow()
}
