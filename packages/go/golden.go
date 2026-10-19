package suggestedtests

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// UpdateGoldenEnvVar rewrites golden files that differ when set to 1.
const UpdateGoldenEnvVar = "SUGGESTEDTESTS_UPDATE_GOLDEN"

// Golden compares got with testdata/<name>.golden, relative to the package
// being tested. A missing file is written and the comparison passes, except
// in CI ($CI set), where it fails. Run with SUGGESTEDTESTS_UPDATE_GOLDEN=1 to
// accept intended changes.
//
//	st.Golden(t, "invoice", renderInvoice(order))
func Golden(t testing.TB, name string, got []byte) bool {
	t.Helper()
	if name == "" || strings.Contains(name, "..") {
		t.Fatalf("suggestedtests: invalid golden file name %q", name)
	}
	path := filepath.Join("testdata", filepath.FromSlash(name)+".golden")
	want, err := os.ReadFile(path)
	update := os.Getenv(UpdateGoldenEnvVar) == "1"
	if os.IsNotExist(err) && (update || os.Getenv("CI") == "") {
		writeGolden(t, path, got)
		t.Logf("wrote golden file %s", path)
		return true
	}
	if err != nil {
		if os.IsNotExist(err) {
			t.Errorf("golden file %s does not exist. Run the test locally to create it, then commit it.", path)
			return false
		}
		t.Fatalf("suggestedtests: reading %s: %v", path, err)
	}
	if bytes.Equal(want, got) {
		return true
	}
	if update {
		writeGolden(t, path, got)
		t.Logf("updated golden file %s", path)
		return true
	}
	t.Errorf("output differs from %s (set %s=1 to update it):\n%s", path, UpdateGoldenEnvVar, firstDifference(want, got))
	return false
}

func writeGolden(t testing.TB, path string, data []byte) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("suggestedtests: %v", err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatalf("suggestedtests: %v", err)
	}
}

// firstDifference describes the first line where want and got differ.
func firstDifference(want, got []byte) string {
	w := strings.Split(string(want), "\n")
	g := strings.Split(string(got), "\n")
	for i := 0; i < len(w) || i < len(g); i++ {
		var wl, gl string
		if i < len(w) {
			wl = w[i]
		}
		if i < len(g) {
			gl = g[i]
		}
		if wl != gl || i >= len(w) || i >= len(g) {
			return fmt.Sprintf("line %d:\n  want: %q\n  got:  %q", i+1, wl, gl)
		}
	}
	return "files differ"
}
