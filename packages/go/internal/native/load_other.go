//go:build !(((darwin || linux) && (amd64 || arm64 || 386 || arm || (riscv64 && go1.25))) || (windows && (amd64 || arm64 || 386)))

package native

import (
	"embed"
	"errors"
)

// No prebuilt bridge for this platform (or a Go too old for purego on it,
// e.g. riscv64 before Go 1.25), so purego isn't imported either:
// the package builds anywhere and reports the bridge as unavailable.
var prebuilt embed.FS

func open(string) (uintptr, error) {
	return 0, errors.New("no prebuilt bridge for this platform")
}

func register(interface{}, uintptr, string) {}
