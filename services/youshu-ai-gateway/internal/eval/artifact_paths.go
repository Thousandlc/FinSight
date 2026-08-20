package eval

import (
	"fmt"
	"os"
	"path/filepath"
)

// ResolveOutputDir returns the canonical module-root .eval-output directory unless
// requestedDir is a non-default explicit path (e.g. t.TempDir() in tests).
func ResolveOutputDir(requestedDir string) (string, error) {
	if requestedDir != "" && requestedDir != DefaultOutputDir {
		return requestedDir, nil
	}
	root, err := findModuleRootFromWD()
	if err != nil {
		return filepath.Join(".", DefaultOutputDir), nil
	}
	return filepath.Join(root, DefaultOutputDir), nil
}

func findModuleRootFromWD() (string, error) {
	wd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	dir := wd
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("go.mod not found from %s", wd)
		}
		dir = parent
	}
}
