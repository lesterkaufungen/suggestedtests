//go:build android && 386

package native

import "embed"

// Only this platform's libraries are embedded in a test binary.
//
//go:embed prebuilt/android-x86/libsuggestedtests_native.so
var prebuilt embed.FS
