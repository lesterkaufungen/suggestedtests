//go:build linux && 386 && !android

package native

import "embed"

// Only this platform's libraries are embedded in a test binary.
//
//go:embed prebuilt/linux-x86/libsuggestedtests_native.so prebuilt/linux-x86-musl/libsuggestedtests_native.so
var prebuilt embed.FS
