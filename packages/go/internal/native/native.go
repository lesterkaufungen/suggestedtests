// Package native loads the Rust bridge from the monorepo's native/ with purego
// (no cgo) and exposes its C ABI. Mirrors native/include/suggestedtests_native.h;
// keep the two in sync.
//
// The library is taken from, in order:
//  1. $SUGGESTEDTESTS_NATIVE_LIB (an explicit path, e.g. a local cargo build);
//  2. the copy embedded for this GOOS/GOARCH (prebuilt/, staged by
//     tool/stage.sh go), written to a temporary file first.
package native

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
)

// ABI version and status codes from the C header.
const (
	ABIVersion     = 1
	OK             = 0
	ErrNull        = -1
	ErrUnsupported = -2
	ErrUnknown     = -3
	// LoadAtLoad is st_load_state() when the OS loader ran the initializers.
	LoadAtLoad = 1
)

// EnvVar names an explicit library path.
const EnvVar = "SUGGESTEDTESTS_NATIVE_LIB"

// VerboseEnvVar turns on the bridge's startup report. The bridge reads it
// from the C environment while loading; Load also passes os.Getenv's value
// on, since os.Setenv doesn't reach the C environment without cgo.
const VerboseEnvVar = "SUGGESTEDTESTS_VERBOSE"

// CPUTime is StCpuTime.
type CPUTime struct {
	UserNs   uint64
	SystemNs uint64
}

// Memory is StMemory.
type Memory struct {
	CurrentRSSBytes uint64
	PeakRSSBytes    uint64
}

// Lib holds the bridge's functions.
type Lib struct {
	AbiVersion func() uint32
	// OnLoad is st_on_load, called once per process for side effects
	// distinct from the version query AbiVersion does. nil on an older
	// prebuilt that predates this additive (no ABI bump) symbol.
	OnLoad          func()
	ProcessCPUTime  func(out *CPUTime) int32
	ThreadCPUTimeNs func(out *uint64) int32
	MemoryUsage     func(out *Memory) int32
	CPUCount        func() uint32
	// LoadState is st_load_state: how the load-time initializers ran.
	LoadState func() uint32
	// SetVerbose is st_set_verbose: turns the startup report on (non-zero)
	// or off and returns the previous value.
	SetVerbose func(verbose uint32) uint32
	// Verbose is st_verbose: 1 if the startup report is on.
	Verbose func() uint32
	// Path is the file the library was loaded from.
	Path string
}

var (
	once    sync.Once
	lib     *Lib
	loadErr error
)

// Load returns the bridge, loading it on first use.
func Load() (*Lib, error) {
	once.Do(func() { lib, loadErr = load() })
	return lib, loadErr
}

func load() (*Lib, error) {
	path := os.Getenv(EnvVar)
	if path == "" {
		var err error
		if path, err = extract(); err != nil {
			return nil, err
		}
	} else if _, err := os.Stat(path); err != nil {
		return nil, fmt.Errorf("bridge library not found at: %s", path)
	}
	handle, err := open(path)
	if err != nil {
		return nil, fmt.Errorf("cannot load %s: %v", path, err)
	}
	l := &Lib{Path: path}
	register(&l.AbiVersion, handle, "st_abi_version")
	register(&l.ProcessCPUTime, handle, "st_process_cpu_time")
	register(&l.ThreadCPUTimeNs, handle, "st_thread_cpu_time_ns")
	register(&l.MemoryUsage, handle, "st_memory_usage")
	register(&l.CPUCount, handle, "st_cpu_count")
	register(&l.LoadState, handle, "st_load_state")
	register(&l.SetVerbose, handle, "st_set_verbose")
	register(&l.Verbose, handle, "st_verbose")
	registerOptional(&l.OnLoad, handle, "st_on_load")
	if l.OnLoad != nil {
		l.OnLoad()
	}
	if truthy(os.Getenv(VerboseEnvVar)) {
		l.SetVerbose(1)
	}
	return l, nil
}

// registerOptional is register, but leaves fn unset (nil) instead of
// panicking (purego.RegisterLibFunc's behavior for a missing symbol) if the
// library predates this additive (no ABI bump) symbol.
func registerOptional(fn interface{}, handle uintptr, name string) {
	defer func() { recover() }()
	register(fn, handle, name)
}

// PlatformDir is "<os>-<arch>[-musl]", the prebuilt directory for this
// process, or "" if there is none.
func PlatformDir() string {
	if runtime.GOOS == "android" {
		return map[string]string{"arm64": "android-arm64-v8a", "arm": "android-armeabi-v7a", "amd64": "android-x86_64", "386": "android-x86"}[runtime.GOARCH]
	}
	arch := map[string]string{"amd64": "x64", "arm64": "arm64", "386": "x86", "arm": "arm", "riscv64": "riscv64"}[runtime.GOARCH]
	if arch == "" {
		return ""
	}
	switch runtime.GOOS {
	case "linux":
		if usesMusl() {
			return "linux-" + arch + "-musl"
		}
		return "linux-" + arch
	case "darwin":
		return "macos-" + arch
	case "windows":
		return "windows-" + arch
	}
	return ""
}

// LibraryFileName is the bridge's file name on this OS.
func LibraryFileName() string {
	switch runtime.GOOS {
	case "windows":
		return "suggestedtests_native.dll"
	case "darwin":
		return "libsuggestedtests_native.dylib"
	}
	return "libsuggestedtests_native.so"
}

// extract writes the embedded library to a content-addressed temporary file,
// so concurrent test binaries share it.
func extract() (string, error) {
	dir := PlatformDir()
	if dir == "" {
		return "", fmt.Errorf("no prebuilt bridge for %s/%s", runtime.GOOS, runtime.GOARCH)
	}
	data, err := prebuilt.ReadFile("prebuilt/" + dir + "/" + LibraryFileName())
	if err != nil {
		return "", fmt.Errorf("no prebuilt bridge embedded for %s (%s/%s)", dir, runtime.GOOS, runtime.GOARCH)
	}
	sum := sha256.Sum256(data)
	path := filepath.Join(os.TempDir(), "suggestedtests-"+hex.EncodeToString(sum[:8]), LibraryFileName())
	if existing, err := os.ReadFile(path); err == nil && bytes.Equal(existing, data) {
		return path, nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return "", err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), "lib-*")
	if err != nil {
		return "", err
	}
	_, err = tmp.Write(data)
	if closeErr := tmp.Close(); err == nil {
		err = closeErr
	}
	if err == nil {
		err = os.Rename(tmp.Name(), path)
	}
	if err != nil {
		os.Remove(tmp.Name())
		// Another process may have won the rename (or holds the file open on Windows).
		if existing, readErr := os.ReadFile(path); readErr == nil && bytes.Equal(existing, data) {
			return path, nil
		}
		return "", err
	}
	return path, nil
}

// ELFInterpreter returns the program interpreter (PT_INTERP) of a
// little-endian ELF file (32- or 64-bit), or "" for a statically linked one.
func ELFInterpreter(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	header := make([]byte, 64)
	if _, err := io.ReadFull(f, header); err != nil {
		return "", err
	}
	if !bytes.Equal(header[:4], []byte("\x7fELF")) || (header[4] != 1 && header[4] != 2) || header[5] != 1 {
		return "", errors.New("not a little-endian ELF file")
	}
	le := binary.LittleEndian
	is64 := header[4] == 2
	var phOffset int64
	var phSize int64
	var phCount int
	if is64 {
		phOffset, phSize, phCount = int64(le.Uint64(header[0x20:])), int64(le.Uint16(header[0x36:])), int(le.Uint16(header[0x38:]))
	} else {
		phOffset, phSize, phCount = int64(le.Uint32(header[0x1c:])), int64(le.Uint16(header[0x2a:])), int(le.Uint16(header[0x2c:]))
	}
	ph := make([]byte, phSize)
	for i := 0; i < phCount; i++ {
		if _, err := f.ReadAt(ph, phOffset+int64(i)*phSize); err != nil {
			return "", err
		}
		if le.Uint32(ph) != 3 { // PT_INTERP
			continue
		}
		var offset, size uint64
		if is64 {
			offset, size = le.Uint64(ph[8:]), le.Uint64(ph[32:])
		} else {
			offset, size = uint64(le.Uint32(ph[4:])), uint64(le.Uint32(ph[16:]))
		}
		if size > 4096 {
			size = 4096
		}
		buf := make([]byte, size)
		if _, err := f.ReadAt(buf, int64(offset)); err != nil && err != io.EOF {
			return "", err
		}
		return strings.TrimRight(string(buf), "\x00"), nil
	}
	return "", nil
}

func usesMusl() bool {
	// A library built for one libc can't be loaded into a process using the
	// other, so ask the running test binary.
	if exe, err := os.Executable(); err == nil {
		if interp, err := ELFInterpreter(exe); err == nil && interp != "" {
			return strings.Contains(interp, "musl")
		}
	}
	matches, _ := filepath.Glob("/lib/ld-musl-*")
	return len(matches) > 0
}

// truthy matches the bridge's reading of VerboseEnvVar: 1, true, yes or on.
func truthy(v string) bool {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "1", "true", "yes", "on":
		return true
	}
	return false
}
