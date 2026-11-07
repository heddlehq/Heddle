package install

import (
	"bufio"
	"io"
	"os/exec"
	"strings"
)

// streamCommand runs a command, passing its latest line to the reporter, and keeps
// the end of the output for when it fails.
func streamCommand(command *exec.Cmd, reporter Reporter) error {
	reader, writer := io.Pipe()
	command.Stdout = writer
	command.Stderr = writer

	var tail []string
	done := make(chan struct{})
	go func() {
		defer close(done)
		scanner := bufio.NewScanner(reader)
		scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if line == "" {
				continue
			}
			reporter.Progress(-1, line)
			tail = append(tail, line)
			if len(tail) > 15 {
				tail = tail[1:]
			}
		}
	}()

	err := command.Run()
	writer.Close()
	<-done
	if err != nil {
		return &commandError{err: err, output: strings.Join(tail, "\n")}
	}
	return nil
}

type commandError struct {
	err    error
	output string
}

func (e *commandError) Error() string { return e.err.Error() + "\n\n" + e.output }
func (e *commandError) Unwrap() error { return e.err }
