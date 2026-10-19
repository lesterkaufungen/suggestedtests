//go:build linux && amd64 && !android

package native

import "embed"

// Only this platform's libraries are embedded in a test binary.
//
//go:embed prebuilt/linux-x64/libsuggestedtests_native.so prebuilt/linux-x64-musl/libsuggestedtests_native.so
var prebuilt embed.FS
