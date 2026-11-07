package install

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"

	"github.com/heddlehq/heddle/cli/internal/paths"
	"github.com/heddlehq/heddle/cli/internal/text"
)

const unitName = "heddle.service"

// AutostartSupported says whether this system can start Heddle at login. It's the
// systemd user service only, for now.
func AutostartSupported() bool {
	if runtime.GOOS != "linux" {
		return false
	}
	_, err := exec.LookPath("systemctl")
	return err == nil
}

func unitPath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "systemd", "user", unitName), nil
}

func unitFile(layout paths.Layout) string {
	binary := filepath.Join(layout.Bin(), paths.Binary("heddle"))
	return fmt.Sprintf(`[Unit]
Description=Heddle
After=network.target

[Service]
Environment=HEDDLE_HOME=%[1]s
ExecStart=%[2]s start --no-browser
ExecStop=%[2]s stop
Restart=on-failure
RestartSec=5
TimeoutStopSec=45

[Install]
WantedBy=default.target
`, layout.Home, binary)
}

// EnableAutostart makes Heddle start at login.
func EnableAutostart(layout paths.Layout) error {
	if !AutostartSupported() {
		return errors.New(text.T("Starting with the computer needs systemd.", "Iniciar com o computador precisa do systemd."))
	}

	path, err := unitPath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(path, []byte(unitFile(layout)), 0o644); err != nil {
		return err
	}
	if err := systemctl("daemon-reload"); err != nil {
		return err
	}
	return systemctl("enable", unitName)
}

// DisableAutostart undoes EnableAutostart, and is fine with nothing to undo.
func DisableAutostart() error {
	path, err := unitPath()
	if err != nil {
		return err
	}
	if _, err := os.Stat(path); errors.Is(err, os.ErrNotExist) {
		return nil
	}
	_ = systemctl("disable", unitName)
	if err := os.Remove(path); err != nil {
		return err
	}
	return systemctl("daemon-reload")
}

// AutostartEnabled says whether Heddle starts at login.
func AutostartEnabled() bool {
	if !AutostartSupported() {
		return false
	}
	return exec.Command("systemctl", "--user", "is-enabled", "--quiet", unitName).Run() == nil
}

func systemctl(args ...string) error {
	output, err := exec.Command("systemctl", append([]string{"--user"}, args...)...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("systemctl %v: %w: %s", args, err, output)
	}
	return nil
}
