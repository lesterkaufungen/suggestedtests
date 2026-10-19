package app

import (
	"testing"
	"time"
)

func TestCacheWarmsUp(t *testing.T) {
	deadline := time.Now().Add(5 * time.Second)
	for !cache.Warm() {
		if time.Now().After(deadline) {
			t.Fatal("cache is still cold after 5s")
		}
		time.Sleep(20 * time.Millisecond)
	}
}
