package suggestedtests

import (
	"strings"
	"testing"
)

func TestScenarioRunsStepsInOrder(t *testing.T) {
	var log []string
	s := NewScenario(t).
		Given("a", func(t testing.TB) { log = append(log, "a") }).
		When("b", func(t testing.TB) { log = append(log, "b") }).
		Then("c", func(t testing.TB) {
			if strings.Join(log, "") != "ab" {
				t.Errorf("log = %v", log)
			}
		}).
		And("d", func(t testing.TB) {})
	if got := strings.Join(s.Passed(), "|"); got != "Given: a|When: b|Then: c|And: d" {
		t.Error(got)
	}
}

func TestScenarioNamesTheFailingStepAndStops(t *testing.T) {
	ran := false
	f := runFake(t, func(tb testing.TB) {
		NewScenario(tb).
			Given("an empty cart", func(t testing.TB) {}).
			Then("the total is 30", func(t testing.TB) { t.Errorf("total = %d, want 30", 20) }).
			And("never", func(t testing.TB) { ran = true })
	})
	wantFailure(t, f, "Then: the total is 30: total = 20, want 30", "passed steps:\n  ✓ Given: an empty cart")
	if ran || !f.fatal {
		t.Errorf("ran=%v fatal=%v", ran, f.fatal)
	}
}

func TestScenarioFatalStillLogsPassedSteps(t *testing.T) {
	f := runFake(t, func(tb testing.TB) {
		NewScenario(tb).
			Given("setup", func(t testing.TB) {}).
			When("it breaks", func(t testing.TB) { t.Fatalf("boom") })
	})
	wantFailure(t, f, "When: it breaks: boom", "✓ Given: setup")
}

func TestScenarioReportsPanics(t *testing.T) {
	f := runFake(t, func(tb testing.TB) {
		NewScenario(tb).When("it panics", func(t testing.TB) { panic("kaboom") })
	})
	wantFailure(t, f, "When: it panics: panic: kaboom")
}

func TestScenarioValidates(t *testing.T) {
	wantFailure(t, runFake(t, func(tb testing.TB) { NewScenario(tb).Given("", func(testing.TB) {}) }), "needs a description")
}
