package app

import (
	"syscall"
	"testing"
)

// Unix only; Maxrss is in KiB on Linux.
func peakRSSKiB(t *testing.T) int64 {
	var usage syscall.Rusage
	if err := syscall.Getrusage(syscall.RUSAGE_SELF, &usage); err != nil {
		t.Fatal(err)
	}
	return int64(usage.Maxrss)
}

func TestImportStaysSmall(t *testing.T) {
	before := peakRSSKiB(t)
	importer.Run(bigFile)
	if growth := peakRSSKiB(t) - before; growth > 50*1024 {
		t.Errorf("peak RSS grew by %.1f MiB > 50 MiB", float64(growth)/1024)
	}
}
