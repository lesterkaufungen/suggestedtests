//go:build android && arm

package native

import "embed"

// Only this platform's libraries are embedded in a test binary.
//
//go:embed prebuilt/android-armeabi-v7a/libsuggestedtests_native.so
var prebuilt embed.FS
