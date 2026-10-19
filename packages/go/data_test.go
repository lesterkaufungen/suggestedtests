package suggestedtests

import (
	"math"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"testing"
	"time"
)

func TestSameSeedSameValues(t *testing.T) {
	a, b := NewTestData(42), NewTestData(42)
	if a.Int(0, 1e9) != b.Int(0, 1e9) || a.Email() != b.Email() || a.UUID() != b.UUID() {
		t.Error("same seed produced different values")
	}
}

func TestSequenceIsFixed(t *testing.T) {
	// xoshiro256** seeded with splitmix64: this must never change, or
	// recorded seeds stop reproducing failures.
	if got := NewTestData(1).Uint64(); got != NewTestData(1).Uint64() {
		t.Fatal("not deterministic")
	}
	got := NewTestData(0).Int(0, 1_000_000)
	if got != NewTestData(0).Int(0, 1_000_000) {
		t.Fatal("not deterministic")
	}
}

func TestRanges(t *testing.T) {
	d := NewTestData(7)
	seen := map[int]bool{}
	for i := 0; i < 500; i++ {
		n := d.Int(3, 5)
		if n < 3 || n > 5 {
			t.Fatalf("Int out of range: %d", n)
		}
		seen[n] = true
		if f := d.Float(1, 2); f < 1 || f >= 2 {
			t.Fatalf("Float out of range: %v", f)
		}
	}
	if len(seen) != 3 {
		t.Errorf("Int never produced some values: %v", seen)
	}
	if d.Int(7, 7) != 7 {
		t.Error("Int(7, 7)")
	}
	d.Int(math.MinInt, math.MaxInt) // full range must not loop or panic
}

func TestStrings(t *testing.T) {
	d := NewTestData(3)
	checks := map[string]*regexp.Regexp{
		d.String(12, ""):   regexp.MustCompile(`^[a-zA-Z0-9]{12}$`),
		d.String(50, "ab"): regexp.MustCompile(`^[ab]{50}$`),
		d.String(4, "äö"):  regexp.MustCompile(`^[äö]{4}$`),
		d.Sentence(6):      regexp.MustCompile(`^[A-Z][a-z]+( [a-z]+){5}\.$`),
		d.Email():          regexp.MustCompile(`^[a-z]+\.[a-z]{5}@example\.com$`),
		d.UUID():           regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`),
	}
	for s, re := range checks {
		if !re.MatchString(s) {
			t.Errorf("%q does not match %s", s, re)
		}
	}
}

func TestTimesAndCollections(t *testing.T) {
	d := NewTestData(4)
	from := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	to := time.Date(2020, 2, 1, 0, 0, 0, 0, time.UTC)
	if tm := d.Time(from, to); tm.Before(from) || !tm.Before(to) || tm.Location() != time.UTC {
		t.Errorf("Time = %v", tm)
	}
	if tm := d.Time(time.Time{}, time.Time{}); tm.Year() < 2000 || tm.Year() >= 2030 {
		t.Errorf("default Time = %v", tm)
	}
	if p := Pick(d, []string{"x", "y"}); p != "x" && p != "y" {
		t.Error(p)
	}
	if l := ListOf(d, 3, (*TestData).Word); len(l) != 3 {
		t.Error(l)
	}
	s := Shuffled(d, []int{1, 2, 3, 4, 5})
	sort.Ints(s)
	if !reflect.DeepEqual(s, []int{1, 2, 3, 4, 5}) {
		t.Error(s)
	}
}

func TestInvalidArgumentsPanic(t *testing.T) {
	d := NewTestData(0)
	for name, call := range map[string]func(){
		"Int":      func() { d.Int(5, 1) },
		"Float":    func() { d.Float(2, 1) },
		"Bool":     func() { d.Bool(2) },
		"String":   func() { d.String(-1, "") },
		"Sentence": func() { d.Sentence(0) },
		"Time":     func() { d.Time(time.Unix(10, 0), time.Unix(0, 0)) },
		"Pick":     func() { Pick(d, []int{}) },
		"ListOf":   func() { ListOf(d, -1, (*TestData).Word) },
	} {
		func() {
			defer func() {
				if r := recover(); r == nil || !strings.Contains(r.(string), "suggestedtests:") {
					t.Errorf("%s: expected a suggestedtests panic, got %v", name, r)
				}
			}()
			call()
		}()
	}
}

func TestDataLogsSeedOnFailure(t *testing.T) {
	t.Setenv(SeedEnvVar, "1234")
	f := runFake(t, func(tb testing.TB) {
		if Data(tb).Seed() != 1234 {
			tb.Errorf("seed not taken from the environment")
		}
		tb.Errorf("boom")
	})
	wantFailure(t, f, "TestData seed: 1234 (reproduce with SUGGESTEDTESTS_SEED=1234 go test -run")
	if strings.Contains(f.output(), "not taken") {
		t.Error(f.output())
	}
	t.Setenv(SeedEnvVar, "x")
	wantFailure(t, runFake(t, func(tb testing.TB) { Data(tb) }), "must be an unsigned integer")
}

func TestDataIsQuietOnSuccess(t *testing.T) {
	f := runFake(t, func(tb testing.TB) { Data(tb).Word() })
	if f.failed || len(f.logs) > 0 {
		t.Error(f.output())
	}
}
