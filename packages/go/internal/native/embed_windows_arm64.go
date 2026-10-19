//go:build windows && arm64

package native

import "embed"

// Only this platform's libraries are embedded in a test binary.
//
//go:embed prebuilt/windows-arm64/suggestedtests_native.dll
var prebuilt embed.FS
