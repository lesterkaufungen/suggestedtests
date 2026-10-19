package app

import (
	"testing"

	st "github.com/lesterkaufungen/suggestedtests/packages/go"
)

func TestImportStaysSmall(t *testing.T) {
	st.RequireNativeBridge(t)
	st.ExpectMemory(t, func() { importer.Run(bigFile) }, st.MaxPeakGrowth(50*st.MiB))
}
