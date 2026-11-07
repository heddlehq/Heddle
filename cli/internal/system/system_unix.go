//go:build !windows

package system

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"golang.org/x/sys/unix"
)

func root() bool { return os.Geteuid() == 0 }

// FreeDisk returns the bytes free on the disk holding a path, climbing to the
// nearest folder that exists.
func FreeDisk(path string) (uint64, error) {
	for {
		var stat unix.Statfs_t
		err := unix.Statfs(path, &stat)
		if err == nil {
			return uint64(stat.Bavail) * uint64(stat.Bsize), nil
		}
		parent := filepath.Dir(path)
		if parent == path {
			return 0, err
		}
		path = parent
	}
}

// AddToPath makes a folder reachable from new terminals. It returns what it changed,
// or a hint when it can't tell which file to change.
func AddToPath(dir, name string) (string, error) {
	if slices.Contains(filepath.SplitList(os.Getenv("PATH")), dir) {
		return "", nil
	}

	profile, line := shellProfile(os.Getenv("SHELL"), os.Getenv("HOME"), dir)
	if profile == "" {
		return "", fmt.Errorf("add %s to your PATH", dir)
	}

	current, err := os.ReadFile(profile)
	if err != nil && !os.IsNotExist(err) {
		return "", err
	}
	if strings.Contains(string(current), dir) {
		return "", nil
	}

	if err := os.MkdirAll(filepath.Dir(profile), 0o755); err != nil {
		return "", err
	}
	file, err := os.OpenFile(profile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return "", err
	}
	defer file.Close()

	if _, err := fmt.Fprintf(file, "\n# %s\n%s\n", name, line); err != nil {
		return "", err
	}
	return profile, nil
}

// RemoveFromPath takes out what AddToPath wrote, and the line the old install
// script wrote, which has the same shape.
func RemoveFromPath(dirs ...string) error {
	profile, _ := shellProfile(os.Getenv("SHELL"), os.Getenv("HOME"), "")
	if profile == "" {
		return nil
	}

	raw, err := os.ReadFile(profile)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}

	lines := strings.Split(string(raw), "\n")
	kept := make([]string, 0, len(lines))
	for i, line := range lines {
		mentions := slices.ContainsFunc(dirs, func(dir string) bool { return strings.Contains(line, dir) })
		if mentions {
			continue
		}
		next := ""
		if i+1 < len(lines) {
			next = lines[i+1]
		}
		if strings.HasPrefix(strings.TrimSpace(line), "# ") && slices.ContainsFunc(dirs, func(dir string) bool { return strings.Contains(next, dir) }) {
			continue
		}
		kept = append(kept, line)
	}
	return os.WriteFile(profile, []byte(strings.Join(kept, "\n")), 0o644)
}

func shellProfile(shell, home, dir string) (string, string) {
	exported := fmt.Sprintf(`export PATH="%s:$PATH"`, dir)
	switch filepath.Base(shell) {
	case "zsh":
		return filepath.Join(home, ".zshrc"), exported
	case "bash":
		return filepath.Join(home, ".bashrc"), exported
	case "fish":
		return filepath.Join(home, ".config", "fish", "conf.d", "heddle.fish"), fmt.Sprintf("fish_add_path %q", dir)
	}
	return "", ""
}

// Protect is only needed on Windows, where ProgramData is readable by everyone.
func Protect(string) error { return nil }
