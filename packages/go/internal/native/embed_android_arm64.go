//go:build android && arm64

package native

import "embed"

// Only this platform's libraries are embedded in a test binary.
//
//go:embed prebuilt/android-arm64-v8a/libsuggestedtests_native.so
var prebuilt embed.FS
