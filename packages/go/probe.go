package suggestedtests

import (
	"fmt"
	"testing"
	"time"

	"github.com/lesterkaufungen/suggestedtests/packages/go/internal/native"
)

// CPUTime is the CPU time consumed by the process, split into user and
// kernel time.
type CPUTime struct {
	User   time.Duration // time spent running user-space code
	System time.Duration // time spent in the kernel on behalf of the process
}

// Total returns User + System.
func (c CPUTime) Total() time.Duration { return c.User + c.System }

// Sub returns the CPU time spent between earlier and c.
func (c CPUTime) Sub(earlier CPUTime) CPUTime {
	return CPUTime{User: c.User - earlier.User, System: c.System - earlier.System}
}

func (c CPUTime) String() string {
	return fmt.Sprintf("CPUTime(user: %s, system: %s)", FormatDuration(c.User), FormatDuration(c.System))
}

// MemoryUsage is the resident memory (RSS / working set) of the process.
type MemoryUsage struct {
	CurrentRSSBytes int64 // memory currently resident in RAM
	PeakRSSBytes    int64 // highest resident memory since the process started
}

func (m MemoryUsage) String() string {
	return fmt.Sprintf("MemoryUsage(current: %s, peak: %s)", FormatBytes(m.CurrentRSSBytes), FormatBytes(m.PeakRSSBytes))
}

// NativeBridgeError is returned when the native bridge is missing or an OS
// call fails.
type NativeBridgeError struct {
	Op string // the bridge function that failed
	// Code is negative for bridge errors and positive for the raw OS error
	// (errno on Linux/macOS, GetLastError() on Windows).
	Code   int
	Detail string // extra context, if any
}

func (e *NativeBridgeError) Error() string {
	var reason string
	switch e.Code {
	case native.ErrNull:
		reason = "null pointer"
	case native.ErrUnsupported:
		reason = "not supported on this OS"
	case native.ErrUnknown:
		reason = "unknown OS error"
	default:
		reason = fmt.Sprintf("OS error %d", e.Code)
	}
	if e.Detail != "" {
		return e.Op + " failed: " + reason + "\n" + e.Detail
	}
	return e.Op + " failed: " + reason
}

// init loads the native bridge when a test binary that imports this package
// starts, so its startup report (SUGGESTEDTESTS_VERBOSE=1) is printed even in
// runs that never call a native helper. A load error is kept for the first use.
func init() {
	_, _ = native.Load()
}

func bridge(op string) (*native.Lib, error) {
	lib, err := native.Load()
	if err != nil {
		return nil, &NativeBridgeError{Op: op, Code: native.ErrUnsupported, Detail: unavailable(err)}
	}
	if v := lib.AbiVersion(); v != native.ABIVersion {
		return nil, &NativeBridgeError{Op: op, Code: native.ErrUnsupported, Detail: fmt.Sprintf(
			"suggestedtests native bridge has ABI v%d, expected v%d. Rebuild it.", v, native.ABIVersion)}
	}
	return lib, nil
}

func unavailable(err error) string {
	return fmt.Sprintf("suggestedtests native bridge is not available for this platform (%v). "+
		"Set $%s to a library built from native/.", err, native.EnvVar)
}

// NativeBridgeAvailable reports whether the bridge is loaded and has the
// expected ABI version.
func NativeBridgeAvailable() bool {
	_, err := bridge("probe")
	return err == nil
}

// NativeBridgeSkipReason is "" when the bridge is available and otherwise
// explains why it isn't.
func NativeBridgeSkipReason() string {
	if _, err := bridge("probe"); err != nil {
		return err.(*NativeBridgeError).Detail
	}
	return ""
}

// RequireNativeBridge skips the test, with the reason, where the native
// bridge is unavailable.
func RequireNativeBridge(t testing.TB) {
	t.Helper()
	if reason := NativeBridgeSkipReason(); reason != "" {
		t.Skip(reason)
	}
}

func check(op string, status int32) error {
	if status != native.OK {
		return &NativeBridgeError{Op: op, Code: int(status)}
	}
	return nil
}

// ProcessCPUTime returns the CPU time used by the whole process (all
// threads) so far.
func ProcessCPUTime() (CPUTime, error) {
	lib, err := bridge("ProcessCPUTime")
	if err != nil {
		return CPUTime{}, err
	}
	var out native.CPUTime
	if err := check("ProcessCPUTime", lib.ProcessCPUTime(&out)); err != nil {
		return CPUTime{}, err
	}
	return CPUTime{User: time.Duration(out.UserNs), System: time.Duration(out.SystemNs)}, nil
}

// ThreadCPUTime returns the CPU time used by the calling OS thread so far.
//
// Goroutines move between OS threads, so only compare two samples taken
// with runtime.LockOSThread in effect.
func ThreadCPUTime() (time.Duration, error) {
	lib, err := bridge("ThreadCPUTime")
	if err != nil {
		return 0, err
	}
	var out uint64
	if err := check("ThreadCPUTime", lib.ThreadCPUTimeNs(&out)); err != nil {
		return 0, err
	}
	return time.Duration(out), nil
}

// ReadMemoryUsage returns the current and peak resident memory of the process.
func ReadMemoryUsage() (MemoryUsage, error) {
	lib, err := bridge("ReadMemoryUsage")
	if err != nil {
		return MemoryUsage{}, err
	}
	var out native.Memory
	if err := check("ReadMemoryUsage", lib.MemoryUsage(&out)); err != nil {
		return MemoryUsage{}, err
	}
	return MemoryUsage{CurrentRSSBytes: int64(out.CurrentRSSBytes), PeakRSSBytes: int64(out.PeakRSSBytes)}, nil
}

// CPUCount returns the number of logical CPUs available to the process.
func CPUCount() (int, error) {
	lib, err := bridge("CPUCount")
	if err != nil {
		return 0, err
	}
	return int(lib.CPUCount()), nil
}

// SetNativeBridgeVerbose turns the native bridge's startup report on or off
// and returns the previous setting.
//
// The report is three "suggestedtests: ..." lines on stderr describing the
// platform and environment (OS, arch, libc, container, VM). It is printed at
// most once per process; turning verbose on prints it now if it hasn't been
// printed. Verbose controls nothing else. To get it while the bridge loads,
// run the tests with SUGGESTEDTESTS_VERBOSE=1:
//
//	SUGGESTEDTESTS_VERBOSE=1 go test ./...
func SetNativeBridgeVerbose(verbose bool) (bool, error) {
	lib, err := bridge("SetNativeBridgeVerbose")
	if err != nil {
		return false, err
	}
	var v uint32
	if verbose {
		v = 1
	}
	return lib.SetVerbose(v) != 0, nil
}

// NativeBridgeVerbose reports whether the native bridge's startup report is
// on (see SetNativeBridgeVerbose).
func NativeBridgeVerbose() (bool, error) {
	lib, err := bridge("NativeBridgeVerbose")
	if err != nil {
		return false, err
	}
	return lib.Verbose() != 0, nil
}
