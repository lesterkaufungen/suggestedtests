package app

import (
	"testing"
	"time"

	st "github.com/lesterkaufungen/suggestedtests/packages/go"
)

func TestParsingStaysFast(t *testing.T) {
	st.ExpectPerformance(t, 5*time.Millisecond, func() { parse(bigJSON) })
}
