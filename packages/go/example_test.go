// A tour of suggestedtests. Run it with: go test -run Example -v .
package suggestedtests_test

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"sort"
	"sync"
	"testing"
	"time"

	st "github.com/lesterkaufungen/suggestedtests/packages/go"
)

type cart struct{ items []int }

func (c *cart) Add(price int) { c.items = append(c.items, price) }

func (c *cart) Total() int {
	sum := 0
	for _, p := range c.items {
		sum += p
	}
	return sum
}

func TestExampleScenario(t *testing.T) {
	var c *cart
	st.NewScenario(t).
		Given("an empty cart", func(t testing.TB) { c = &cart{} }).
		When("two items are added", func(t testing.TB) { c.Add(10); c.Add(20) }).
		Then("the total is 30", func(t testing.TB) {
			if got := c.Total(); got != 30 {
				t.Errorf("total = %d, want 30", got)
			}
		})
}

func TestExamplePerformanceBudget(t *testing.T) {
	payload, _ := json.Marshal(map[string][]int{"items": make([]int, 1000)})
	var v map[string][]int
	st.ExpectPerformance(t, 50*time.Millisecond, func() { _ = json.Unmarshal(payload, &v) })
}

func TestExampleCPUClock(t *testing.T) {
	st.RequireNativeBridge(t)
	data := st.ListOf(st.NewTestData(1), 10_000, func(d *st.TestData) int { return d.Int(0, 1e6) })
	st.ExpectPerformance(t, 50*time.Millisecond, func() {
		s := append([]int(nil), data...)
		sort.Ints(s)
	}, st.WithClock(st.CPU), st.WithStatistic(st.P95))
}

func TestExampleMemoryBudget(t *testing.T) {
	buf := make([]byte, 0, 64)
	st.ExpectMemory(t, func() { buf = append(buf[:0], "hello"...) }, st.MaxAllocs(0))
}

func TestExampleSeededData(t *testing.T) {
	d := st.Data(t) // the seed is logged if this test fails
	st.AssertUnique(t, st.ListOf(d, 100, (*st.TestData).UUID))
}

func TestExampleEventually(t *testing.T) {
	var mu sync.Mutex
	ready := false
	go func() { time.Sleep(10 * time.Millisecond); mu.Lock(); ready = true; mu.Unlock() }()
	st.Eventually(t, func() error {
		mu.Lock()
		defer mu.Unlock()
		if !ready {
			return errors.New("not ready")
		}
		return nil
	})
}

func TestExampleNoLeaks(t *testing.T) {
	st.NoGoroutineLeaks(t)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Skip(err)
	}
	done := make(chan struct{})
	go func() { defer close(done); _, _ = ln.Accept() }()
	t.Cleanup(func() { ln.Close(); <-done }) // runs before the leak check
}

func TestExampleRace(t *testing.T) {
	var mu sync.Mutex
	counter := 0
	st.Race(t, 8, func(i int) error {
		for j := 0; j < 1000; j++ {
			mu.Lock()
			counter++
			mu.Unlock()
		}
		return nil
	})
	if counter != 8000 {
		t.Errorf("counter = %d", counter)
	}
}

func ExampleNewTestData() {
	d := st.NewTestData(42)
	fmt.Println(d.Seed(), len(d.UUID()), d.Int(7, 7))
	// Output: 42 36 7
}

func ExampleFormatBytes() {
	fmt.Println(st.FormatBytes(1536), st.FormatBytes(5*st.MiB))
	// Output: 1.5 KiB 5.0 MiB
}

func ExampleNewResult() {
	r, _ := st.NewResult("parse", []time.Duration{3 * time.Millisecond, time.Millisecond, 2 * time.Millisecond}, st.Wall)
	fmt.Println(r.Median(), r.Get(st.Max))
	// Output: 2ms 3ms
}
