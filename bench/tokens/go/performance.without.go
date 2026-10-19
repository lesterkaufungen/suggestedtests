package app

import (
	"sort"
	"testing"
	"time"
)

func TestParsingStaysFast(t *testing.T) {
	for i := 0; i < 3; i++ {
		parse(bigJSON)
	}
	samples := make([]time.Duration, 20)
	for i := range samples {
		start := time.Now()
		parse(bigJSON)
		samples[i] = time.Since(start)
	}
	sort.Slice(samples, func(i, j int) bool { return samples[i] < samples[j] })
	median := (samples[9] + samples[10]) / 2
	if median > 5*time.Millisecond {
		t.Errorf("parse: median %v > budget 5ms (min %v, max %v)", median, samples[0], samples[19])
	}
}
