package suggestedtests

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"testing"

	"github.com/lesterkaufungen/suggestedtests/packages/go/internal/native"
)

func burn() int {
	x := 0
	for i := 0; i < 1_000_000; i++ {
		x = (x*31 + i) % 1_000_003
	}
	return x
}

func TestNativeBridgeErrorMessage(t *testing.T) {
	if got := (&NativeBridgeError{Op: "x", Code: native.ErrUnsupported}).Error(); !strings.Contains(got, "not supported on this OS") {
		t.Error(got)
	}
	if got := (&NativeBridgeError{Op: "x", Code: 13}).Error(); !strings.Contains(got, "OS error 13") {
		t.Error(got)
	}
}

func TestCPUTimeArithmetic(t *testing.T) {
	d := CPUTime{User: 30, System: 7}.Sub(CPUTime{User: 10, System: 2})
	if d != (CPUTime{User: 20, System: 5}) || d.Total() != 25 {
		t.Errorf("got %+v", d)
	}
}

func TestBridgeIsAvailableWhereShipped(t *testing.T) {
	if native.PlatformDir() == "" {
		if NativeBridgeAvailable() || !strings.Contains(NativeBridgeSkipReason(), "native bridge is not available") {
			t.Fatalf("expected unavailable with a reason, got %q", NativeBridgeSkipReason())
		}
		return
	}
	if !NativeBridgeAvailable() {
		t.Fatalf("bridge unavailable on %s: %s", native.PlatformDir(), NativeBridgeSkipReason())
	}
	if NativeBridgeSkipReason() != "" {
		t.Error("skip reason should be empty")
	}
}

func TestProcessCPUTimeAdvances(t *testing.T) {
	RequireNativeBridge(t)
	before, err := ProcessCPUTime()
	if err != nil {
		t.Fatal(err)
	}
	for {
		now, _ := ProcessCPUTime()
		if now.Sub(before).Total() > 0 {
			return
		}
		burn()
	}
}

func TestThreadCPUTimeAdvances(t *testing.T) {
	RequireNativeBridge(t)
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	before, err := ThreadCPUTime()
	if err != nil {
		t.Fatal(err)
	}
	for {
		if now, _ := ThreadCPUTime(); now > before {
			return
		}
		burn()
	}
}

func TestMemoryUsageIsPlausible(t *testing.T) {
	RequireNativeBridge(t)
	m, err := ReadMemoryUsage()
	if err != nil {
		t.Fatal(err)
	}
	if m.CurrentRSSBytes < MiB || m.PeakRSSBytes < m.CurrentRSSBytes {
		t.Errorf("implausible %v", m)
	}
	if n, err := CPUCount(); err != nil || n < 1 {
		t.Errorf("CPUCount() = %d, %v", n, err)
	}
}

func TestRequireNativeBridgeSkips(t *testing.T) {
	if NativeBridgeAvailable() {
		f := runFake(t, func(tb testing.TB) { RequireNativeBridge(tb) })
		if f.skipped {
			t.Error("skipped although the bridge is available")
		}
	}
}

// TestVerboseChild is run by runVerboseChild in a fresh process.
func TestVerboseChild(t *testing.T) {
	switch os.Getenv("SUGGESTEDTESTS_VERBOSE_CHILD") {
	case "nothing": // the package's init loads the bridge
	case "load":
		if !NativeBridgeAvailable() {
			t.Fatal(NativeBridgeSkipReason())
		}
		v, _ := NativeBridgeVerbose()
		fmt.Println("verbose", v)
	case "set":
		before, _ := NativeBridgeVerbose()
		first, _ := SetNativeBridgeVerbose(true)
		second, _ := SetNativeBridgeVerbose(true)
		third, _ := SetNativeBridgeVerbose(false)
		after, _ := NativeBridgeVerbose()
		fmt.Println("verbose", before, first, second, third, after)
	}
}

func runVerboseChild(t *testing.T, mode string, env ...string) (stdout, stderr string) {
	t.Helper()
	RequireNativeBridge(t)
	cmd := exec.Command(os.Args[0], "-test.run=^TestVerboseChild$")
	for _, kv := range os.Environ() {
		if !strings.HasPrefix(kv, native.VerboseEnvVar+"=") {
			cmd.Env = append(cmd.Env, kv)
		}
	}
	cmd.Env = append(cmd.Env, append(env, "SUGGESTEDTESTS_VERBOSE_CHILD="+mode)...)
	var out, errOut strings.Builder
	cmd.Stdout, cmd.Stderr = &out, &errOut
	if err := cmd.Run(); err != nil {
		t.Fatalf("child: %v\n%s%s", err, out.String(), errOut.String())
	}
	return out.String(), errOut.String()
}

func TestNativeBridgeIsSilentByDefault(t *testing.T) {
	out, errOut := runVerboseChild(t, "load")
	if !strings.Contains(out, "verbose false") || strings.Contains(errOut, "suggestedtests:") {
		t.Errorf("stdout %q, stderr %q", out, errOut)
	}
}

func TestVerboseEnvVarPrintsTheReportOnLoad(t *testing.T) {
	out, errOut := runVerboseChild(t, "load", native.VerboseEnvVar+"=1")
	if !strings.Contains(out, "verbose true") {
		t.Errorf("stdout %q", out)
	}
	if n := strings.Count(errOut, "suggestedtests: platform: "); n != 1 {
		t.Errorf("report printed %d times: %q", n, errOut)
	}
}

func TestSetNativeBridgeVerbosePrintsTheReportOnce(t *testing.T) {
	out, errOut := runVerboseChild(t, "set")
	if !strings.Contains(out, "verbose false false true true false") {
		t.Errorf("stdout %q", out)
	}
	if n := strings.Count(errOut, "suggestedtests: platform: "); n != 1 {
		t.Errorf("report printed %d times: %q", n, errOut)
	}
}

func TestImportingThePackageLoadsTheBridge(t *testing.T) {
	_, errOut := runVerboseChild(t, "nothing", native.VerboseEnvVar+"=1")
	if n := strings.Count(errOut, "suggestedtests: platform: "); n != 1 {
		t.Errorf("report printed %d times: %q", n, errOut)
	}
}
