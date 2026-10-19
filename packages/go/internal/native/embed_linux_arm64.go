//go:build linux && arm64 && !android

package native

import "embed"

// Only this platform's libraries are embedded in a test binary.
//
//go:embed prebuilt/linux-arm64/libsuggestedtests_native.so prebuilt/linux-arm64-musl/libsuggestedtests_native.so
var prebuilt embed.FS
