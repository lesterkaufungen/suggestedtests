package suggestedtests

import (
	"testing"
	"time"
)

func TestFormatBytes(t *testing.T) {
	cases := map[int64]string{0: "0 B", 1023: "1023 B", 1536: "1.5 KiB", 5 * MiB: "5.0 MiB", -2048: "-2.0 KiB"}
	for in, want := range cases {
		if got := FormatBytes(in); got != want {
			t.Errorf("FormatBytes(%d) = %q, want %q", in, got, want)
		}
	}
}

func TestFormatDuration(t *testing.T) {
	cases := map[time.Duration]string{850 * time.Microsecond: "850µs", 1250 * time.Microsecond: "1.25ms", 2 * time.Second: "2.00s"}
	for in, want := range cases {
		if got := FormatDuration(in); got != want {
			t.Errorf("FormatDuration(%v) = %q, want %q", in, got, want)
		}
	}
}
