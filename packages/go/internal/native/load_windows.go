//go:build windows && (amd64 || arm64 || 386)

package native

import (
	"syscall"

	"github.com/ebitengine/purego"
)

func open(path string) (uintptr, error) {
	h, err := syscall.LoadLibrary(path)
	return uintptr(h), err
}

func register(fn interface{}, handle uintptr, name string) {
	purego.RegisterLibFunc(fn, handle, name)
}
