//go:build linux && arm && !android

package native

import "embed"

// Only this platform's libraries are embedded in a test binary.
//
//go:embed prebuilt/linux-arm/libsuggestedtests_native.so prebuilt/linux-arm-musl/libsuggestedtests_native.so
var prebuilt embed.FS
