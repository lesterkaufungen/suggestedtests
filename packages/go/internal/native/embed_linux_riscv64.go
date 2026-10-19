//go:build linux && riscv64 && go1.25

package native

import "embed"

// Only this platform's libraries are embedded in a test binary.
//
//go:embed prebuilt/linux-riscv64/libsuggestedtests_native.so prebuilt/linux-riscv64-musl/libsuggestedtests_native.so
var prebuilt embed.FS
