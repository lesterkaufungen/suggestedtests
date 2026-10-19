package suggestedtests

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGoldenCreatesMatchesAndUpdates(t *testing.T) {
	dir := t.TempDir()
	wd, _ := os.Getwd()
	if err := os.Chdir(dir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(wd)
	t.Setenv("CI", "")
	os.Unsetenv("CI")
	t.Setenv(UpdateGoldenEnvVar, "")

	wantPass(t, runFake(t, func(tb testing.TB) { Golden(tb, "report", []byte("a\nb\n")) }))
	if data, err := os.ReadFile(filepath.Join("testdata", "report.golden")); err != nil || string(data) != "a\nb\n" {
		t.Fatalf("golden file not written: %q %v", data, err)
	}
	wantPass(t, runFake(t, func(tb testing.TB) { Golden(tb, "report", []byte("a\nb\n")) }))
	wantFailure(t, runFake(t, func(tb testing.TB) { Golden(tb, "report", []byte("a\nc\n")) }),
		"output differs from testdata", "line 2:\n  want: \"b\"\n  got:  \"c\"")

	t.Setenv(UpdateGoldenEnvVar, "1")
	wantPass(t, runFake(t, func(tb testing.TB) { Golden(tb, "report", []byte("a\nc\n")) }))
	if data, _ := os.ReadFile(filepath.Join("testdata", "report.golden")); string(data) != "a\nc\n" {
		t.Errorf("not updated: %q", data)
	}
}

func TestGoldenMissingFailsInCI(t *testing.T) {
	dir := t.TempDir()
	wd, _ := os.Getwd()
	if err := os.Chdir(dir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(wd)
	t.Setenv("CI", "true")
	t.Setenv(UpdateGoldenEnvVar, "")
	wantFailure(t, runFake(t, func(tb testing.TB) { Golden(tb, "missing", []byte("x")) }), "does not exist")
	wantFailure(t, runFake(t, func(tb testing.TB) { Golden(tb, "../escape", []byte("x")) }), "invalid golden file name")
}
