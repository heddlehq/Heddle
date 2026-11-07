package runtime

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	goruntime "runtime"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/paths"
	"github.com/heddlehq/heddle/cli/internal/text"
)

const (
	bootTimeout    = 10 * time.Minute // The first boot downloads Python.
	stopTimeout    = 30 * time.Second
	signalInterval = 2 * time.Second
	logRotateAt    = 10 * 1024 * 1024
	pollInterval   = 150 * time.Millisecond
)

// HeddleLocal prints this once the editor answers.
var readyLine = regexp.MustCompile(`Heddle is running at (http://\S+)`)

// Local runs the release with its own Postgres.
type Local struct {
	Layout paths.Layout
}

type state struct {
	PID       int       `json:"pid"`
	URL       string    `json:"url,omitempty"`
	StartedAt time.Time `json:"started_at"`
	// Stopping marks a stop someone asked for. The way the VM exits can't say: Windows
	// kills it with status 1, the same as a crash.
	Stopping bool `json:"stopping,omitempty"`
}

func (l *Local) readState() (state, bool) {
	raw, err := os.ReadFile(l.Layout.State())
	if err != nil {
		return state{}, false
	}
	var current state
	if json.Unmarshal(raw, &current) != nil || current.PID == 0 {
		return state{}, false
	}
	return current, true
}

func (l *Local) writeState(current state) error {
	if err := os.MkdirAll(filepath.Dir(l.Layout.State()), 0o755); err != nil {
		return err
	}
	raw, err := json.Marshal(current)
	if err != nil {
		return err
	}
	return os.WriteFile(l.Layout.State(), raw, 0o644)
}

// running finds the VM of this install, even one started by the old launcher, which
// left no state behind.
func (l *Local) running() (state, bool) {
	if current, ok := l.readState(); ok && ownsProcess(current.PID, l.Layout.App()) {
		return current, true
	}
	if pid := findProcess(l.Layout.App()); pid != 0 {
		return state{PID: pid}, true
	}
	return state{}, false
}

func (l *Local) command(options StartOptions) (*exec.Cmd, error) {
	script := filepath.Join(l.Layout.App(), "bin", "heddle")
	if goruntime.GOOS == "windows" {
		script += ".bat"
	}
	if _, err := os.Stat(script); err != nil {
		return nil, errors.New(text.T(
			"Heddle isn't installed in "+l.Layout.Home+". Run: heddle install",
			"O Heddle não está instalado em "+l.Layout.Home+". Rode: heddle install",
		))
	}

	settings, err := config.LoadEnv(l.Layout.EnvFile(false))
	if err != nil {
		return nil, err
	}

	command := exec.Command(script, "start")
	command.Dir = l.Layout.Home
	command.Env = append(os.Environ(), settings.Environ()...)
	command.Env = append(command.Env,
		"HEDDLE_HOME="+l.Layout.Home,
		// The release cookie is the same in every download, so no distribution at all.
		"RELEASE_DISTRIBUTION=none",
	)
	if os.Getenv("ELIXIR_ERL_OPTIONS") == "" {
		// +fnu: paths may hold accents even when the terminal has no UTF-8 locale.
		// +Bi: the VM would die on Ctrl+C and leave the database running.
		command.Env = append(command.Env, "ELIXIR_ERL_OPTIONS=+fnu +Bi")
	}
	if options.Port != 0 {
		command.Env = append(command.Env, "PORT="+strconv.Itoa(options.Port))
	}
	if options.NoBrowser {
		command.Env = append(command.Env, "HEDDLE_NO_BROWSER=1")
	}
	detach(command)
	return command, nil
}

// launch starts the VM with its output going to the log, so nothing depends on this
// process staying around. It returns where in the log this run begins.
func (l *Local) launch(options StartOptions) (*exec.Cmd, int64, error) {
	if current, ok := l.running(); ok {
		return nil, 0, fmt.Errorf("%s (PID %d)", text.T("Heddle is already running", "O Heddle já está rodando"), current.PID)
	}

	command, err := l.command(options)
	if err != nil {
		return nil, 0, err
	}

	log, offset, err := l.openLog()
	if err != nil {
		return nil, 0, err
	}
	defer log.Close()

	command.Stdout = log
	command.Stderr = log
	if err := command.Start(); err != nil {
		return nil, 0, err
	}
	if err := l.writeState(state{PID: command.Process.Pid, StartedAt: time.Now()}); err != nil {
		_ = command.Process.Kill()
		return nil, 0, err
	}
	return command, offset, nil
}

func (l *Local) openLog() (*os.File, int64, error) {
	if err := os.MkdirAll(l.Layout.Logs(), 0o755); err != nil {
		return nil, 0, err
	}
	path := l.Layout.Log()
	if info, err := os.Stat(path); err == nil && info.Size() > logRotateAt {
		_ = os.Rename(path, path+".1")
	}

	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return nil, 0, err
	}
	info, err := file.Stat()
	if err != nil {
		file.Close()
		return nil, 0, err
	}
	return file, info.Size(), nil
}

// Start boots Heddle in the background and returns once it answers.
func (l *Local) Start(ctx context.Context, options StartOptions) (string, error) {
	command, offset, err := l.launch(options)
	if err != nil {
		return "", err
	}

	exited := make(chan error, 1)
	go func() { exited <- command.Wait() }()

	url, err := l.awaitReady(ctx, offset, exited, options)
	if err != nil {
		// Given up on, like with Ctrl+C: it must not stay behind on its own. The context
		// is already over, so stopping can't use it.
		if ctx.Err() != nil {
			_ = l.Stop(context.Background())
		}
		return "", err
	}
	_ = command.Process.Release()
	return url, nil
}

// Run keeps Heddle in the foreground. Ctrl+C reaches the VM as the signal that makes
// it shut down in order and stop the database on its way out.
func (l *Local) Run(ctx context.Context, options StartOptions, ready func(string)) error {
	command, offset, err := l.launch(options)
	if err != nil {
		return err
	}

	exited := make(chan error, 1)
	go func() { exited <- command.Wait() }()

	interrupts := make(chan os.Signal, 1)
	signal.Notify(interrupts, os.Interrupt, syscall.SIGTERM, syscall.SIGHUP)
	defer signal.Stop(interrupts)

	if options.Follow && options.Output != nil {
		streamCtx, stopStream := context.WithCancel(ctx)
		defer stopStream()
		if logs, err := newFollower(l.Layout.Log(), offset); err == nil {
			defer logs.close()
			go logs.stream(streamCtx, options.Output)
		}
	}

	booting := make(chan error, 1)
	bootCtx, cancelBoot := context.WithCancel(ctx)
	defer cancelBoot()
	watch := make(chan error, 1)
	go func() {
		url, err := l.awaitReady(bootCtx, offset, watch, options)
		if err == nil && ready != nil {
			ready(url)
		}
		booting <- err
	}()

	stopping := false
	for {
		select {
		case <-interrupts:
			if !stopping {
				stopping = true
				cancelBoot()
				terminate(command.Process.Pid, l.Layout)
			}
		case <-ctx.Done():
			if !stopping {
				stopping = true
				terminate(command.Process.Pid, l.Layout)
			}
		case err := <-booting:
			if err != nil && !stopping && !errors.Is(err, context.Canceled) {
				terminate(command.Process.Pid, l.Layout)
				<-exited
				l.clearState()
				return err
			}
		case err := <-exited:
			cancelBoot()
			watch <- err
			asked := l.stopAsked()
			l.clearState()
			// A VM stopped by a signal, here or by `heddle stop`, stopped on purpose.
			var exit *exec.ExitError
			if err == nil || stopping || asked || (errors.As(err, &exit) && !exit.Exited()) {
				return nil
			}
			return fmt.Errorf("%s: %w\n\n%s", text.T("Heddle stopped", "O Heddle parou"), err, l.tail(offset, 15))
		}
	}
}

// awaitReady follows the log from offset until Heddle says it's up.
func (l *Local) awaitReady(ctx context.Context, offset int64, exited <-chan error, options StartOptions) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, bootTimeout)
	defer cancel()

	follower, err := newFollower(l.Layout.Log(), offset)
	if err != nil {
		return "", err
	}
	defer follower.close()

	ticker := time.NewTicker(pollInterval)
	defer ticker.Stop()

	for {
		for _, line := range follower.lines() {
			if match := readyLine.FindStringSubmatch(line); match != nil {
				current, _ := l.readState()
				current.URL = match[1]
				if err := l.writeState(current); err != nil {
					return "", err
				}
				return match[1], nil
			}
			if options.Progress != nil && strings.TrimSpace(line) != "" {
				options.Progress(line)
			}
		}

		select {
		case <-ctx.Done():
			return "", ctx.Err()
		case err := <-exited:
			l.clearState()
			return "", fmt.Errorf("%s (%v)\n\n%s", text.T("Heddle could not start", "O Heddle não conseguiu iniciar"), err, l.tail(offset, 15))
		case <-ticker.C:
		}
	}
}

func (l *Local) clearState() { _ = os.Remove(l.Layout.State()) }

// stopAsked says whether `heddle stop` is behind the end of a run. A state already
// gone counts: only Stop removes it while the VM is up.
func (l *Local) stopAsked() bool {
	current, ok := l.readState()
	return !ok || current.Stopping
}

func (l *Local) tail(offset int64, count int) string {
	follower, err := newFollower(l.Layout.Log(), offset)
	if err != nil {
		return ""
	}
	defer follower.close()

	lines := follower.lines()
	if len(lines) > count {
		lines = lines[len(lines)-count:]
	}
	return strings.Join(lines, "\n")
}

// Stop shuts the VM down, which stops the database with it, and only then checks
// nothing was left behind. Stopping only the database leaves a VM with nothing to
// talk to, still answering on its port.
func (l *Local) Stop(ctx context.Context) error {
	current, vm := l.running()
	database := l.databaseUp()
	if !vm && !database {
		l.clearState()
		return ErrNotRunning
	}

	if vm {
		// Before the signal, so a foreground `heddle` sees it when the VM goes.
		current.Stopping = true
		if err := l.writeState(current); err != nil {
			return err
		}
		terminate(current.PID, l.Layout)

		deadline := time.After(stopTimeout)
		// A VM still booting has no signal handler yet and loses the signal, so it
		// goes again until one lands.
		again := time.NewTicker(signalInterval)
		defer again.Stop()
		ticker := time.NewTicker(pollInterval)
		defer ticker.Stop()
	waiting:
		for ownsProcess(current.PID, l.Layout.App()) {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-deadline:
				forceKill(current.PID)
				break waiting
			case <-again.C:
				terminate(current.PID, l.Layout)
			case <-ticker.C:
			}
		}
	}

	l.clearState()
	if l.databaseUp() {
		return l.stopDatabase()
	}
	return nil
}

func (l *Local) pgCtl(args ...string) *exec.Cmd {
	binary := filepath.Join(l.Layout.App(), "pgsql", "bin", paths.Binary("pg_ctl"))
	return exec.Command(binary, append([]string{"-D", l.Layout.Cluster()}, args...)...)
}

func (l *Local) databaseUp() bool {
	if _, err := os.Stat(filepath.Join(l.Layout.Cluster(), "postmaster.pid")); err != nil {
		return false
	}
	return l.pgCtl("status").Run() == nil
}

func (l *Local) stopDatabase() error {
	if output, err := l.pgCtl("-m", "fast", "-w", "stop").CombinedOutput(); err != nil {
		return fmt.Errorf("%w: %s", err, output)
	}
	return nil
}

// Status reports on the VM, the database and whether the editor answers.
func (l *Local) Status(ctx context.Context) (Status, error) {
	current, vm := l.running()
	status := Status{Running: vm, PID: current.PID, Database: l.databaseUp(), URL: current.URL}
	if !current.StartedAt.IsZero() {
		status.Uptime = time.Since(current.StartedAt).Round(time.Second)
	}
	if vm && status.URL != "" {
		status.Healthy = answers(ctx, status.URL)
	}
	return status, nil
}

func answers(ctx context.Context, url string) bool {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return false
	}
	client := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	response, err := client.Do(request)
	if err != nil {
		return false
	}
	response.Body.Close()
	return response.StatusCode < 500
}

// Logs prints the end of a log, and keeps following it when asked.
func (l *Local) Logs(ctx context.Context, output io.Writer, lines int, follow, database bool) error {
	path := l.Layout.Log()
	if database {
		path = l.Layout.DBLog()
	}

	file, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return errors.New(text.T("There's no log yet. Start Heddle first.", "Ainda não há log. Inicie o Heddle primeiro."))
	}
	if err != nil {
		return err
	}
	defer file.Close()

	var ring []string
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for scanner.Scan() {
		ring = append(ring, scanner.Text())
		if len(ring) > lines {
			ring = ring[1:]
		}
	}
	for _, line := range ring {
		fmt.Fprintln(output, line)
	}
	if !follow {
		return scanner.Err()
	}

	info, err := file.Stat()
	if err != nil {
		return err
	}
	follower, err := newFollower(path, info.Size())
	if err != nil {
		return err
	}
	defer follower.close()
	follower.stream(ctx, output)
	return nil
}

// follower reads what's appended to a file.
type follower struct {
	file    *os.File
	partial string
}

func newFollower(path string, offset int64) (*follower, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	if _, err := file.Seek(offset, io.SeekStart); err != nil {
		file.Close()
		return nil, err
	}
	return &follower{file: file}, nil
}

func (f *follower) close() { f.file.Close() }

// lines returns the whole lines that arrived since the last call.
func (f *follower) lines() []string {
	raw, err := io.ReadAll(f.file)
	if err != nil || len(raw) == 0 {
		return nil
	}

	parts := strings.Split(f.partial+string(raw), "\n")
	f.partial = parts[len(parts)-1]
	return parts[:len(parts)-1]
}

func (f *follower) stream(ctx context.Context, output io.Writer) {
	ticker := time.NewTicker(pollInterval)
	defer ticker.Stop()
	for {
		for _, line := range f.lines() {
			fmt.Fprintln(output, line)
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
