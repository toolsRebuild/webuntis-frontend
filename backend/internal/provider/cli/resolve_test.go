package cli

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func fakeExecutable(t *testing.T, dir string) {
	t.Helper()
	old := executable
	executable = func() (string, error) { return filepath.Join(dir, "untisd"), nil }
	t.Cleanup(func() { executable = old })
}

func TestResolvePrefersTheBundledCLI(t *testing.T) {
	dir := t.TempDir()
	fakeExecutable(t, dir)
	name := "untis"
	if runtime.GOOS == "windows" {
		name = "untis.exe"
	}
	bundled := filepath.Join(dir, name)
	if err := os.WriteFile(bundled, []byte("cli"), 0o755); err != nil {
		t.Fatal(err)
	}
	for _, in := range []string{"", "untis"} {
		if got := Resolve(in); got != bundled {
			t.Errorf("Resolve(%q) = %q, want %q", in, got, bundled)
		}
	}
	if got := New(Config{}, nil).cfg.Binary; got != bundled {
		t.Errorf("New uses %q, want %q", got, bundled)
	}
}

func TestResolveFallsBackToPATH(t *testing.T) {
	fakeExecutable(t, t.TempDir())
	if got := Resolve(""); got != "untis" {
		t.Errorf("Resolve(\"\") = %q, want untis", got)
	}
	// a folder of that name is not a program
	dir := t.TempDir()
	fakeExecutable(t, dir)
	if err := os.Mkdir(filepath.Join(dir, "untis"), 0o755); err != nil {
		t.Fatal(err)
	}
	if got := Resolve("untis"); got != "untis" {
		t.Errorf("Resolve(untis) = %q next to a folder", got)
	}
}

func TestResolveKeepsPaths(t *testing.T) {
	fakeExecutable(t, t.TempDir())
	for _, p := range []string{"/opt/untis/bin/untis", "./untis", `C:\tools\untis.exe`} {
		if got := Resolve(p); got != p {
			t.Errorf("Resolve(%q) = %q", p, got)
		}
	}
}
