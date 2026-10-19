//go:build (darwin || linux) && (amd64 || arm64 || 386 || arm || (riscv64 && go1.25))

package native

import "github.com/ebitengine/purego"

func open(path string) (uintptr, error) {
	return purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_LOCAL)
}

func register(fn interface{}, handle uintptr, name string) {
	purego.RegisterLibFunc(fn, handle, name)
}
