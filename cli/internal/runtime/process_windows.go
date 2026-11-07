//go:build windows

package runtime

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"syscall"

	"github.com/heddlehq/heddle/cli/internal/paths"
)

const createNewProcessGroup = 0x00000200

func detach(command *exec.Cmd) {
	command.SysProcAttr = &syscall.SysProcAttr{CreationFlags: createNewProcessGroup}
}

// terminate kills the VM's tree and stops the database itself: Windows has no signal
// that lets the VM do it on the way out.
func terminate(pid int, layout paths.Layout) {
	_ = exec.Command("taskkill", "/PID", strconv.Itoa(pid), "/T", "/F").Run()
	(&Local{Layout: layout}).stopDatabase()
}

func forceKill(pid int) {
	_ = exec.Command("taskkill", "/PID", strconv.Itoa(pid), "/T", "/F").Run()
}

func ownsProcess(pid int, _ string) bool {
	output, err := exec.Command("tasklist", "/FI", fmt.Sprintf("PID eq %d", pid), "/NH").Output()
	return err == nil && strings.Contains(string(output), strconv.Itoa(pid))
}

func findProcess(string) int { return 0 }
