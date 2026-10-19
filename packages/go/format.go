package suggestedtests

import (
	"fmt"
	"time"
)

// Byte sizes for budgets.
const (
	KiB int64 = 1 << 10
	MiB int64 = 1 << 20
	GiB int64 = 1 << 30
)

// FormatBytes formats a byte count as a human readable size, e.g. "12.5 MiB".
func FormatBytes(bytes int64) string {
	units := []string{"B", "KiB", "MiB", "GiB", "TiB"}
	value := float64(bytes)
	if value < 0 {
		value = -value
	}
	unit := 0
	for value >= 1024 && unit < len(units)-1 {
		value /= 1024
		unit++
	}
	if unit == 0 {
		return fmt.Sprintf("%d B", bytes)
	}
	sign := ""
	if bytes < 0 {
		sign = "-"
	}
	return fmt.Sprintf("%s%.1f %s", sign, value, units[unit])
}

// FormatDuration formats a duration as "850µs", "1.25ms" or "2.00s".
func FormatDuration(d time.Duration) string {
	us := float64(d) / float64(time.Microsecond)
	abs := us
	if abs < 0 {
		abs = -abs
	}
	switch {
	case abs < 1000:
		return fmt.Sprintf("%.0fµs", us)
	case abs < 1e6:
		return fmt.Sprintf("%.2fms", us/1e3)
	default:
		return fmt.Sprintf("%.2fs", us/1e6)
	}
}

func signedBytes(n int64) string {
	if n >= 0 {
		return "+" + FormatBytes(n)
	}
	return FormatBytes(n)
}
