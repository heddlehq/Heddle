// Package system answers what the installer and `heddle doctor` need to know about
// this machine, and changes the little of it they have to: the PATH.
package system

import (
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// Facts is what decides which installs can work on this machine.
type Facts struct {
	OS     string
	Arch   string
	Target string // Empty when there's no Heddle build for this machine.
	Musl   bool
	Root   bool
	Docker bool
	Claude string // Path of the claude binary, when it's installed.
}

// Detect looks at this machine.
func Detect() Facts {
	facts := Facts{
		OS:     runtime.GOOS,
		Arch:   runtime.GOARCH,
		Target: Target(runtime.GOOS, runtime.GOARCH),
		Musl:   musl(),
		Root:   root(),
		Docker: dockerRuns(),
	}
	if path, err := exec.LookPath("claude"); err == nil {
		facts.Claude = path
	}
	return facts
}

// Target is the name a release gives this platform, or "" when it has no build.
func Target(goos, goarch string) string {
	switch goos + "/" + goarch {
	case "linux/amd64":
		return "linux-x64"
	case "linux/arm64":
		return "linux-arm64"
	case "darwin/arm64":
		return "macos-arm64"
	case "windows/amd64":
		return "windows-x64"
	}
	return ""
}

// NativeProblem says why the install with its own Postgres can't work here, or ""
// when it can. Docker and Treadle still can: this is a choice to take away, not
// the end of the install.
func (f Facts) NativeProblem(tr func(en, pt string) string) string {
	switch {
	case f.Target == "":
		return tr("There's no Heddle build for "+f.OS+" on "+f.Arch+".", "Não existe build do Heddle para "+f.OS+" em "+f.Arch+".")
	case f.Root:
		return tr("The bundled Postgres refuses to run as root.", "O Postgres embutido não roda como root.")
	case f.Musl:
		return tr("Heddle's builds need glibc, and this system uses musl.", "Os builds do Heddle precisam de glibc, e este sistema usa musl.")
	}
	return ""
}

func musl() bool {
	if runtime.GOOS != "linux" {
		return false
	}
	output, _ := exec.Command("ldd", "--version").CombinedOutput()
	return strings.Contains(strings.ToLower(string(output)), "musl")
}

// dockerRuns checks the daemon answers, not only that the command exists: a Docker
// that's installed and stopped can't install anything.
func dockerRuns() bool {
	if _, err := exec.LookPath("docker"); err != nil {
		return false
	}
	command := exec.Command("docker", "compose", "version")
	if command.Run() != nil {
		return false
	}
	done := make(chan error, 1)
	info := exec.Command("docker", "info")
	if err := info.Start(); err != nil {
		return false
	}
	go func() { done <- info.Wait() }()
	select {
	case err := <-done:
		return err == nil
	case <-time.After(3 * time.Second):
		_ = info.Process.Kill()
		return false
	}
}

// PortFree says whether something on this machine could listen on a port.
func PortFree(port int) bool {
	listener, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return false
	}
	_ = listener.Close()
	return true
}

// DirSize adds up the files under a folder.
func DirSize(path string) int64 {
	var total int64
	_ = filepath.WalkDir(path, func(_ string, entry os.DirEntry, err error) error {
		if err == nil && !entry.IsDir() {
			if info, err := entry.Info(); err == nil {
				total += info.Size()
			}
		}
		return nil
	})
	return total
}

// HumanSize prints bytes the way people read them.
func HumanSize(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

// OpenBrowser opens an address, and does nothing where there's no browser.
func OpenBrowser(url string) error {
	switch runtime.GOOS {
	case "windows":
		return exec.Command("cmd", "/c", "start", "", url).Start()
	case "darwin":
		return exec.Command("open", url).Start()
	default:
		return exec.Command("xdg-open", url).Start()
	}
}
