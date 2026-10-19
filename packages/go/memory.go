package suggestedtests

import (
	"fmt"
	"runtime"
	"testing"
)

// MemoryReport describes how memory changed while a function ran.
type MemoryReport struct {
	// Before and After are native RSS samples; nil without the bridge.
	Before, After *MemoryUsage
	// HeapGrowth is the change of live Go heap (HeapAlloc after a GC).
	HeapGrowth int64
	// AllocatedBytes and Allocs count every allocation made while the
	// function ran (MemStats.TotalAlloc and Mallocs), even if it was freed.
	// They are process-wide; GOMAXPROCS is 1 while measuring (as in
	// testing.AllocsPerRun) so other goroutines rarely interfere.
	AllocatedBytes, Allocs int64
}

// RSSGrowth is the change in resident memory; ok is false without the bridge.
func (r MemoryReport) RSSGrowth() (bytes int64, ok bool) {
	if r.Before == nil || r.After == nil {
		return 0, false
	}
	return r.After.CurrentRSSBytes - r.Before.CurrentRSSBytes, true
}

// PeakGrowth is how far the function pushed the process' peak RSS up; ok is
// false without the bridge.
func (r MemoryReport) PeakGrowth() (bytes int64, ok bool) {
	if r.Before == nil || r.After == nil {
		return 0, false
	}
	return r.After.PeakRSSBytes - r.Before.PeakRSSBytes, true
}

func (r MemoryReport) String() string {
	rss, peak := "n/a", "n/a"
	if b, ok := r.RSSGrowth(); ok {
		rss = signedBytes(b)
	}
	if b, ok := r.PeakGrowth(); ok {
		peak = signedBytes(b)
	}
	return fmt.Sprintf("MemoryReport(heap: %s, allocated: %s in %d allocs, rss: %s, rss peak: %s)",
		signedBytes(r.HeapGrowth), FormatBytes(r.AllocatedBytes), r.Allocs, rss, peak)
}

// MeasureMemory runs fn and reports how memory changed. Go heap and
// allocation figures are always filled in; RSS needs the native bridge.
func MeasureMemory(fn func()) MemoryReport {
	var before *MemoryUsage
	if m, err := ReadMemoryUsage(); err == nil {
		before = &m
	}
	// The MemStats (~5 KiB each) are allocated before the window opens so
	// they aren't counted. Like testing.AllocsPerRun, one P keeps other
	// goroutines from allocating in parallel, and the allocation counters
	// are read before the final GC, which is only needed for the live heap.
	var start, end, heap runtime.MemStats
	defer runtime.GOMAXPROCS(runtime.GOMAXPROCS(1))
	runtime.GC()
	runtime.ReadMemStats(&start)
	fn()
	runtime.ReadMemStats(&end)
	runtime.GC()
	runtime.ReadMemStats(&heap)
	r := MemoryReport{
		Before:         before,
		HeapGrowth:     int64(heap.HeapAlloc) - int64(start.HeapAlloc),
		AllocatedBytes: int64(end.TotalAlloc - start.TotalAlloc),
		Allocs:         int64(end.Mallocs - start.Mallocs),
	}
	if before != nil {
		if m, err := ReadMemoryUsage(); err == nil {
			r.After = &m
		}
	}
	return r
}

type memoryBudget struct {
	rss, peak, heap, allocated, allocs int64
	set                                []string
}

// MemoryLimit is a budget for ExpectMemory. Values are bytes, except MaxAllocs.
type MemoryLimit func(*memoryBudget)

// MaxRSSGrowth limits the growth of resident memory (needs the native bridge).
func MaxRSSGrowth(bytes int64) MemoryLimit {
	return func(b *memoryBudget) { b.rss = bytes; b.set = append(b.set, "MaxRSSGrowth") }
}

// MaxPeakGrowth limits how far the process' peak RSS may rise (needs the
// native bridge). It catches temporary spikes that RSS growth misses.
func MaxPeakGrowth(bytes int64) MemoryLimit {
	return func(b *memoryBudget) { b.peak = bytes; b.set = append(b.set, "MaxPeakGrowth") }
}

// MaxHeapGrowth limits the growth of the live Go heap: memory still
// referenced after the function returned.
func MaxHeapGrowth(bytes int64) MemoryLimit {
	return func(b *memoryBudget) { b.heap = bytes; b.set = append(b.set, "MaxHeapGrowth") }
}

// MaxAllocatedBytes limits the bytes allocated while the function ran,
// freed or not.
func MaxAllocatedBytes(bytes int64) MemoryLimit {
	return func(b *memoryBudget) { b.allocated = bytes; b.set = append(b.set, "MaxAllocatedBytes") }
}

// MaxAllocs limits the number of heap allocations while the function ran.
func MaxAllocs(n int64) MemoryLimit {
	return func(b *memoryBudget) { b.allocs = n; b.set = append(b.set, "MaxAllocs") }
}

func (b *memoryBudget) has(name string) bool {
	for _, s := range b.set {
		if s == name {
			return true
		}
	}
	return false
}

// ExpectMemory runs fn and fails the test if memory grew beyond any of the
// limits. At least one limit is required.
//
//	st.ExpectMemory(t, func() { importer.Run(bigFile) }, st.MaxPeakGrowth(64*st.MiB))
//	st.ExpectMemory(t, func() { cache.Get(key) }, st.MaxAllocs(0))
func ExpectMemory(t testing.TB, fn func(), limits ...MemoryLimit) (MemoryReport, bool) {
	t.Helper()
	b := &memoryBudget{}
	for _, l := range limits {
		l(b)
	}
	if len(b.set) == 0 {
		t.Fatal("suggestedtests: ExpectMemory needs at least one limit, e.g. st.MaxHeapGrowth(st.MiB)")
	}
	for name, v := range map[string]int64{"MaxRSSGrowth": b.rss, "MaxPeakGrowth": b.peak, "MaxHeapGrowth": b.heap, "MaxAllocatedBytes": b.allocated, "MaxAllocs": b.allocs} {
		if b.has(name) && v < 0 {
			t.Fatalf("suggestedtests: %s must be >= 0, got %d", name, v)
		}
	}
	if (b.has("MaxRSSGrowth") || b.has("MaxPeakGrowth")) && !NativeBridgeAvailable() {
		t.Fatalf("suggestedtests: RSS limits need the native bridge: %s", NativeBridgeSkipReason())
	}
	r := MeasureMemory(fn)
	ok := true
	fail := func(what string, actual, limit int64, format func(int64) string) {
		t.Helper()
		t.Errorf("memory budget exceeded: %s %s > budget %s\n%s", what, format(actual), format(limit), r)
		ok = false
	}
	count := func(n int64) string { return fmt.Sprint(n) }
	if b.has("MaxHeapGrowth") && r.HeapGrowth > b.heap {
		fail("Go heap grew", r.HeapGrowth, b.heap, FormatBytes)
	}
	if b.has("MaxAllocatedBytes") && r.AllocatedBytes > b.allocated {
		fail("allocated", r.AllocatedBytes, b.allocated, FormatBytes)
	}
	if b.has("MaxAllocs") && r.Allocs > b.allocs {
		fail("allocations", r.Allocs, b.allocs, count)
	}
	if g, has := r.RSSGrowth(); has && b.has("MaxRSSGrowth") && g > b.rss {
		fail("RSS grew", g, b.rss, FormatBytes)
	}
	if g, has := r.PeakGrowth(); has && b.has("MaxPeakGrowth") && g > b.peak {
		fail("peak RSS grew", g, b.peak, FormatBytes)
	}
	return r, ok
}
