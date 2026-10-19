package native

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestPlatformDirAndEmbeddedLibrary(t *testing.T) {
	dir := PlatformDir()
	if dir == "" {
		t.Skipf("no prebuilt for %s/%s", runtime.GOOS, runtime.GOARCH)
	}
	if _, err := prebuilt.ReadFile("prebuilt/" + dir + "/" + LibraryFileName()); err != nil {
		t.Fatalf("library for %s is not embedded: %v", dir, err)
	}
}

func TestLoadAndCall(t *testing.T) {
	if PlatformDir() == "" {
		t.Skip("no prebuilt for this platform")
	}
	lib, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	// Before anything else calls into it: the loader hook must have run.
	if st := lib.LoadState(); st != LoadAtLoad {
		t.Errorf("st_load_state() = %d, want %d (initializers ran from the loader)", st, LoadAtLoad)
	}
	if v := lib.AbiVersion(); v != ABIVersion {
		t.Fatalf("ABI v%d", v)
	}
	if lib.ProcessCPUTime(nil) != ErrNull || lib.MemoryUsage(nil) != ErrNull || lib.ThreadCPUTimeNs(nil) != ErrNull {
		t.Error("null pointers must be rejected")
	}
	var m Memory
	if lib.MemoryUsage(&m) != OK || m.CurrentRSSBytes == 0 || m.PeakRSSBytes < m.CurrentRSSBytes {
		t.Errorf("memory %+v", m)
	}
	if _, err := os.Stat(lib.Path); err != nil {
		t.Errorf("extracted library missing: %v", err)
	}
}

func TestOnLoadIsOptional(t *testing.T) {
	if PlatformDir() == "" {
		t.Skip("no prebuilt for this platform")
	}
	lib, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	// nil on an older prebuilt that predates this additive (no ABI bump)
	// symbol; callable without panicking otherwise.
	if lib.OnLoad != nil {
		lib.OnLoad()
	}
}

func TestExtractIsIdempotent(t *testing.T) {
	if PlatformDir() == "" {
		t.Skip("no prebuilt for this platform")
	}
	a, err := extract()
	if err != nil {
		t.Fatal(err)
	}
	b, err := extract()
	if err != nil || a != b {
		t.Fatalf("%s != %s (%v)", a, b, err)
	}
}

func TestELFInterpreter(t *testing.T) {
	if _, err := ELFInterpreter(filepath.Join("native.go")); err == nil {
		t.Error("a Go source file is not ELF")
	}
	if _, err := ELFInterpreter("/does/not/exist"); err == nil {
		t.Error("missing file must fail")
	}
	if runtime.GOOS != "linux" || (runtime.GOARCH != "amd64" && runtime.GOARCH != "arm64") {
		return // only 64-bit ELF is read; every shipped Linux platform is 64-bit
	}
	exe, _ := os.Executable()
	if _, err := ELFInterpreter(exe); err != nil {
		t.Errorf("test binary: %v", err)
	}
}
