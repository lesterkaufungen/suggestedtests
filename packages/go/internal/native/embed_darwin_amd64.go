//go:build darwin && amd64

package native

import "embed"

// Only this platform's libraries are embedded in a test binary.
//
//go:embed prebuilt/macos-x64/libsuggestedtests_native.dylib
var prebuilt embed.FS
