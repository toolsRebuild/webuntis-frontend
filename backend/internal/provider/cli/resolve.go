package cli

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// DefaultBinary is the name of the untis CLI.
const DefaultBinary = "untis"

// executable is os.Executable, replaceable in tests.
var executable = os.Executable

// Resolve picks the untis program to run. The releases ship untis next to
// untisd (the Tauri sidecars, the portable folders and the web archives),
// so a bare program name is looked up there first; that copy is the CLI
// version the release was built and tested with. Without one, the name
// is left to the PATH lookup. A path is used as given.
func Resolve(binary string) string {
	if binary == "" {
		binary = DefaultBinary
	}
	if strings.ContainsAny(binary, `/\`) {
		return binary
	}
	exe, err := executable()
	if err != nil {
		return binary
	}
	if real, err := filepath.EvalSymlinks(exe); err == nil {
		exe = real
	}
	name := binary
	if runtime.GOOS == "windows" && !strings.EqualFold(filepath.Ext(name), ".exe") {
		name += ".exe"
	}
	bundled := filepath.Join(filepath.Dir(exe), name)
	if st, err := os.Stat(bundled); err == nil && st.Mode().IsRegular() {
		return bundled
	}
	return binary
}
