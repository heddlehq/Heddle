package config

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/heddlehq/heddle/cli/internal/paths"
)

const (
	ModeLocal  = "local"
	ModeDocker = "docker"
)

// Manifest records how an install was made, so later commands don't have to guess.
type Manifest struct {
	Mode        string    `json:"mode"`
	InstalledAt time.Time `json:"installed_at"`
	Treadle     string    `json:"treadle_home,omitempty"`
}

// LoadManifest reads the manifest. Installs from the old script have none, and
// those are always local.
func LoadManifest(layout paths.Layout) (Manifest, error) {
	raw, err := os.ReadFile(layout.Manifest())
	if errors.Is(err, os.ErrNotExist) {
		return Manifest{Mode: ModeLocal}, nil
	}
	if err != nil {
		return Manifest{}, err
	}

	var manifest Manifest
	if err := json.Unmarshal(raw, &manifest); err != nil {
		return Manifest{}, err
	}
	if manifest.Mode == "" {
		manifest.Mode = ModeLocal
	}
	return manifest, nil
}

// SaveManifest writes the manifest.
func SaveManifest(layout paths.Layout, manifest Manifest) error {
	raw, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(layout.Manifest()), 0o755); err != nil {
		return err
	}
	return os.WriteFile(layout.Manifest(), append(raw, '\n'), 0o644)
}

// Installed says whether this folder holds an install of either kind.
func Installed(layout paths.Layout) bool {
	if _, err := os.Stat(filepath.Join(layout.App(), "VERSION")); err == nil {
		return true
	}
	_, err := os.Stat(layout.Manifest())
	return err == nil
}

// Version reads the version of the program in this install.
func Version(layout paths.Layout) string {
	for _, path := range []string{
		filepath.Join(layout.App(), "VERSION"),
		filepath.Join(layout.Docker(), "src", "VERSION"),
	} {
		if raw, err := os.ReadFile(path); err == nil {
			return strings.TrimSpace(string(raw))
		}
	}
	return ""
}
