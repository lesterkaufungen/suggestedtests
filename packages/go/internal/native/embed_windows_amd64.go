//go:build windows && amd64

package native

import "embed"

// Only this platform's libraries are embedded in a test binary.
//
//go:embed prebuilt/windows-x64/suggestedtests_native.dll
var prebuilt embed.FS
