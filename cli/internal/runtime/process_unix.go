//go:build !windows

package runtime

import (
	"os/exec"
	"strconv"
	"strings"
	"syscall"

	"github.com/heddlehq/heddle/cli/internal/paths"
)

// detach gives the VM its own session: Ctrl+C in this terminal, or closing it,
// reaches only this process, which then stops the VM in order.
func detach(command *exec.Cmd) {
	command.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
}

// terminate is what makes the VM shut down in order.
func terminate(pid int, _ paths.Layout) {
	_ = syscall.Kill(pid, syscall.SIGTERM)
}

func forceKill(pid int) {
	_ = syscall.Kill(pid, syscall.SIGKILL)
}

// ownsProcess checks the PID is still a VM from this install, and not one the system
// handed to something else after a reboot.
func ownsProcess(pid int, app string) bool {
	if syscall.Kill(pid, 0) != nil {
		return false
	}
	output, err := exec.Command("ps", "-o", "command=", "-p", strconv.Itoa(pid)).Output()
	return err == nil && strings.Contains(string(output), app)
}

// findProcess looks for a VM of this install with no state file: the old launcher
// left none.
func findProcess(app string) int {
	output, err := exec.Command("pgrep", "-f", app+"/erts-").Output()
	if err != nil {
		return 0
	}
	for _, field := range strings.Fields(string(output)) {
		if pid, err := strconv.Atoi(field); err == nil {
			return pid
		}
	}
	return 0
}
