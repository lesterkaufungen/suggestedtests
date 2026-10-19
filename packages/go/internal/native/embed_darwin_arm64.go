//go:build darwin && arm64

package native

import "embed"

// Only this platform's libraries are embedded in a test binary.
//
//go:embed prebuilt/macos-arm64/libsuggestedtests_native.dylib
var prebuilt embed.FS
