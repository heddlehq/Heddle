// Package paths knows where an install keeps each of its parts.
package paths

import (
	"os"
	"path/filepath"
	"runtime"
)

// Layout is one install. Everything a person creates lives under Home, so removing
// that folder removes Heddle.
type Layout struct {
	Home string
}

func (l Layout) App() string      { return filepath.Join(l.Home, "app") }
func (l Layout) Bin() string      { return filepath.Join(l.Home, "bin") }
func (l Layout) Data() string     { return filepath.Join(l.Home, "data") }
func (l Layout) Backups() string  { return filepath.Join(l.Home, "backups") }
func (l Layout) Logs() string     { return filepath.Join(l.Home, "logs") }
func (l Layout) Log() string      { return filepath.Join(l.Logs(), "heddle.log") }
func (l Layout) DBLog() string    { return filepath.Join(l.Data(), "postgres.log") }
func (l Layout) State() string    { return filepath.Join(l.Home, "run", "heddle.json") }
func (l Layout) Manifest() string { return filepath.Join(l.Home, "heddle.json") }
func (l Layout) Docker() string   { return filepath.Join(l.Home, "docker") }
func (l Layout) Cluster() string  { return filepath.Join(l.Data(), "postgres") }

// EnvFile is where the settings live. It's a file Docker Compose reads as well,
// so an install in Docker keeps it next to the compose file.
func (l Layout) EnvFile(docker bool) string {
	if docker {
		return filepath.Join(l.Docker(), ".env")
	}
	return filepath.Join(l.Home, "heddle.env")
}

// Binary is the name of the command on this system.
func Binary(name string) string {
	if runtime.GOOS == "windows" {
		return name + ".exe"
	}
	return name
}

// Resolve finds the install this command belongs to: HEDDLE_HOME, then the folder
// around the running binary, then the default.
func Resolve() Layout {
	if home := os.Getenv("HEDDLE_HOME"); home != "" {
		return Layout{Home: home}
	}
	if exe, err := os.Executable(); err == nil {
		if real, err := filepath.EvalSymlinks(exe); err == nil {
			home := filepath.Dir(filepath.Dir(real))
			if filepath.Base(filepath.Dir(real)) == "bin" && exists(filepath.Join(home, "app")) {
				return Layout{Home: home}
			}
		}
	}
	return Layout{Home: DefaultHome()}
}

// DefaultHome is where a new install goes when nothing says otherwise.
func DefaultHome() string {
	return defaultHome(runtime.GOOS, os.Getenv("LOCALAPPDATA"), os.Getenv("ProgramData"), userHome())
}

func defaultHome(goos, localAppData, programData, home string) string {
	if goos == "windows" && localAppData != "" {
		preferred := filepath.Join(localAppData, "Heddle")
		// The Postgres installer sends its own path through SQL as UTF-8, but Windows
		// hands it over in the system code page, so a user folder with an accent fails.
		if !Supported(preferred) && programData != "" {
			return filepath.Join(programData, "Heddle")
		}
		return preferred
	}
	return filepath.Join(home, ".heddle")
}

// DefaultTreadleHome is where Treadle goes, on its own so it can be there without
// a Heddle on the same machine.
func DefaultTreadleHome() string {
	if home := os.Getenv("TREADLE_HOME"); home != "" {
		return home
	}
	if runtime.GOOS == "windows" {
		if local := os.Getenv("LOCALAPPDATA"); local != "" {
			return filepath.Join(local, "Treadle")
		}
	}
	return filepath.Join(userHome(), ".treadle")
}

// Supported says whether Postgres and Python can load from this folder. Neither
// does from a path with accents.
func Supported(path string) bool {
	for i := range len(path) {
		if path[i] >= 128 {
			return false
		}
	}
	return true
}

func userHome() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "."
	}
	return home
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
