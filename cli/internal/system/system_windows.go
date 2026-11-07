//go:build windows

package system

import (
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"slices"
	"strings"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

func root() bool { return false }

// FreeDisk returns the bytes free on the disk holding a path, climbing to the
// nearest folder that exists.
func FreeDisk(path string) (uint64, error) {
	for {
		pointer, err := windows.UTF16PtrFromString(path)
		if err != nil {
			return 0, err
		}
		var free uint64
		err = windows.GetDiskFreeSpaceEx(pointer, &free, nil, nil)
		if err == nil {
			return free, nil
		}
		parent := filepath.Dir(path)
		if parent == path {
			return 0, err
		}
		path = parent
	}
}

func userPath() (registry.Key, string, error) {
	key, err := registry.OpenKey(registry.CURRENT_USER, "Environment", registry.QUERY_VALUE|registry.SET_VALUE)
	if err != nil {
		return 0, "", err
	}
	value, _, err := key.GetStringValue("Path")
	if err != nil && err != registry.ErrNotExist {
		key.Close()
		return 0, "", err
	}
	return key, value, nil
}

// AddToPath puts a folder in the user's PATH.
func AddToPath(dir, _ string) (string, error) {
	key, value, err := userPath()
	if err != nil {
		return "", err
	}
	defer key.Close()

	parts := strings.Split(value, ";")
	if slices.Contains(parts, dir) {
		return "", nil
	}
	updated := strings.Trim(value+";"+dir, ";")
	if err := key.SetExpandStringValue("Path", updated); err != nil {
		return "", err
	}
	return "PATH", nil
}

// RemoveFromPath takes folders out of the user's PATH.
func RemoveFromPath(dirs ...string) error {
	key, value, err := userPath()
	if err != nil {
		return err
	}
	defer key.Close()

	parts := slices.DeleteFunc(strings.Split(value, ";"), func(part string) bool {
		return slices.Contains(dirs, part)
	})
	return key.SetExpandStringValue("Path", strings.Join(parts, ";"))
}

// Protect keeps a folder in ProgramData to this user: it's readable by every
// account, and this one holds passwords.
func Protect(path string) error {
	if !strings.HasPrefix(strings.ToLower(path), strings.ToLower(os.Getenv("ProgramData"))) {
		return nil
	}
	current, err := user.Current()
	if err != nil {
		return err
	}
	grant := fmt.Sprintf("*%s:(OI)(CI)F", current.Uid)
	return exec.Command("icacls", path, "/inheritance:r", "/grant:r", grant, "*S-1-5-18:(OI)(CI)F").Run()
}
