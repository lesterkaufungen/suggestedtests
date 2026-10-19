package app

import (
	"testing"

	st "github.com/lesterkaufungen/suggestedtests/packages/go"
)

func TestServerShutsDown(t *testing.T) {
	st.NoGoroutineLeaks(t)
	srv := startServer(t)
	srv.Handle(request)
}
