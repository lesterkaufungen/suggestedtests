package suggestedtests

import (
	"runtime/debug"
	"strings"
	"testing"
)

var sink [][]byte

func TestMeasureMemoryCountsAllocations(t *testing.T) {
	r := MeasureMemory(func() {
		for i := 0; i < 100; i++ {
			sink = append(sink, make([]byte, 1024))
		}
	})
	// Allocation counters are exact; the live-heap delta also moves when
	// earlier garbage is collected, so it is covered by the 32 MiB test below.
	if r.Allocs < 100 || r.AllocatedBytes < 100*1024 {
		t.Errorf("implausible %s", r)
	}
	sink = nil
	if NativeBridgeAvailable() && (r.Before == nil || r.After == nil) {
		t.Error("RSS samples missing although the bridge is available")
	}
}

func TestExpectMemoryAllocationBudget(t *testing.T) {
	buf := make([]int, 0, 16)
	wantPass(t, runFake(t, func(tb testing.TB) {
		ExpectMemory(tb, func() { buf = append(buf[:0], 1, 2, 3) }, MaxAllocs(0))
	}))
	f := runFake(t, func(tb testing.TB) {
		ExpectMemory(tb, func() { sink = append(sink, make([]byte, 64*1024)) }, MaxAllocatedBytes(1024))
	})
	sink = nil
	wantFailure(t, f, "memory budget exceeded: allocated", "> budget 1.0 KiB")
}

func TestExpectMemoryHeapBudget(t *testing.T) {
	f := runFake(t, func(tb testing.TB) {
		ExpectMemory(tb, func() {
			for i := 0; i < 32; i++ {
				sink = append(sink, make([]byte, MiB))
			}
		}, MaxHeapGrowth(MiB))
	})
	sink = nil
	wantFailure(t, f, "Go heap grew")
}

func TestExpectMemoryPeakBudget(t *testing.T) {
	RequireNativeBridge(t)
	// Return memory freed by earlier tests to the OS; otherwise the
	// allocation below reuses resident pages and RSS doesn't rise.
	debug.FreeOSMemory()
	m, err := ReadMemoryUsage()
	if err != nil {
		t.Fatal(err)
	}
	// The peak is a lifetime high-water mark: allocate past it, whatever
	// earlier tests (or -count runs) pushed it to.
	size := m.PeakRSSBytes - m.CurrentRSSBytes + 64*MiB
	f := runFake(t, func(tb testing.TB) {
		ExpectMemory(tb, func() {
			b := make([]byte, size)
			for i := 0; i < len(b); i += 4096 {
				b[i] = 1
			}
			sink = append(sink, b)
		}, MaxPeakGrowth(0))
	})
	sink = nil
	wantFailure(t, f, "peak RSS grew")
}

func TestExpectMemoryValidates(t *testing.T) {
	wantFailure(t, runFake(t, func(tb testing.TB) { ExpectMemory(tb, func() {}) }), "at least one limit")
	wantFailure(t, runFake(t, func(tb testing.TB) { ExpectMemory(tb, func() {}, MaxAllocs(-1)) }), "MaxAllocs must be >= 0")
}

func TestMemoryReportString(t *testing.T) {
	r := MemoryReport{Before: &MemoryUsage{10, 20}, After: &MemoryUsage{15, 30}, HeapGrowth: -50, AllocatedBytes: 2048, Allocs: 3}
	if s := r.String(); !strings.HasPrefix(s, "MemoryReport(heap: -50 B, allocated: 2.0 KiB in 3 allocs, rss: +5 B, rss peak: +10 B)") {
		t.Error(s)
	}
}
