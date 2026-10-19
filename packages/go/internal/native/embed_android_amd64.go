//go:build android && amd64

package native

import "embed"

// Only this platform's libraries are embedded in a test binary.
//
//go:embed prebuilt/android-x86_64/libsuggestedtests_native.so
var prebuilt embed.FS
