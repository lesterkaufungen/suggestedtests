package app

import (
	"runtime"
	"testing"
	"time"
)

func TestServerShutsDown(t *testing.T) {
	before := runtime.NumGoroutine()
	t.Cleanup(func() {
		deadline := time.Now().Add(time.Second)
		for runtime.NumGoroutine() > before && time.Now().Before(deadline) {
			time.Sleep(20 * time.Millisecond)
		}
		if n := runtime.NumGoroutine() - before; n > 0 {
			buf := make([]byte, 1<<20)
			t.Errorf("%d goroutine(s) still running after the test:\n%s", n, buf[:runtime.Stack(buf, true)])
		}
	})
	srv := startServer(t)
	srv.Handle(request)
}
