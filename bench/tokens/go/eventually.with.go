package app

import (
	"errors"
	"testing"

	st "github.com/lesterkaufungen/suggestedtests/packages/go"
)

func TestCacheWarmsUp(t *testing.T) {
	st.Eventually(t, func() error {
		if !cache.Warm() {
			return errors.New("cache is cold")
		}
		return nil
	})
}
