package runtime

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/paths"
	"github.com/heddlehq/heddle/cli/internal/text"
)

// ProjectName keeps these containers apart from a `docker compose up` in a checkout,
// which would otherwise share volumes with this install.
const ProjectName = "heddle-server"

// Docker runs Heddle with Docker Compose.
type Docker struct {
	Layout paths.Layout
}

func (d *Docker) source() string { return d.Layout.Docker() + string(os.PathSeparator) + "src" }

// Compose builds a `docker compose` command for this install.
func (d *Docker) Compose(ctx context.Context, args ...string) *exec.Cmd {
	full := append([]string{
		"compose", "-p", ProjectName,
		"--project-directory", d.source(),
		"--env-file", d.Layout.EnvFile(true),
	}, args...)
	return exec.CommandContext(ctx, "docker", full...)
}

func (d *Docker) url() string {
	settings, err := config.LoadEnv(d.Layout.EnvFile(true))
	if err == nil {
		if domain := settings.Value("PHX_HOST"); domain != "" {
			return "https://" + domain
		}
		if port := settings.Value("HEDDLE_PORT"); port != "" {
			return "http://localhost:" + port
		}
	}
	return "http://localhost:4000"
}

// Start brings the containers up.
func (d *Docker) Start(ctx context.Context, options StartOptions) (string, error) {
	command := d.Compose(ctx, "up", "-d", "--wait", "ui", "worker", "db")
	if output, err := command.CombinedOutput(); err != nil {
		return "", fmt.Errorf("%w\n\n%s", err, output)
	}
	return d.url(), nil
}

// Run brings the containers up and follows them. They keep running afterwards,
// as they're meant to on a server.
func (d *Docker) Run(ctx context.Context, options StartOptions, ready func(string)) error {
	url, err := d.Start(ctx, options)
	if err != nil {
		return err
	}
	if ready != nil {
		ready(url)
	}
	if options.Follow {
		return d.Logs(ctx, options.Output, 50, true, false)
	}
	return nil
}

// Stop stops the containers and keeps them and their data.
func (d *Docker) Stop(ctx context.Context) error {
	status, err := d.Status(ctx)
	if err != nil {
		return err
	}
	if !status.Running {
		return ErrNotRunning
	}
	if output, err := d.Compose(ctx, "stop").CombinedOutput(); err != nil {
		return fmt.Errorf("%w\n\n%s", err, output)
	}
	return nil
}

// Status reads the state of each container.
func (d *Docker) Status(ctx context.Context) (Status, error) {
	output, err := d.Compose(ctx, "ps", "-a", "--format", "json").Output()
	if err != nil {
		return Status{}, errors.New(text.T("Docker isn't answering. Is it running?", "O Docker não responde. Ele está rodando?"))
	}

	status := Status{URL: d.url()}
	for _, service := range parseServices(output) {
		status.Services = append(status.Services, service)
		if service.State != "running" {
			continue
		}
		switch service.Name {
		case "db":
			status.Database = true
		case "ui", "all":
			status.Running = true
		}
	}
	if status.Running {
		status.Healthy = answers(ctx, "http://localhost:"+strconv.Itoa(d.port()))
	}
	return status, nil
}

func (d *Docker) port() int {
	settings, err := config.LoadEnv(d.Layout.EnvFile(true))
	if err == nil {
		if port, err := strconv.Atoi(settings.Value("HEDDLE_PORT")); err == nil {
			return port
		}
	}
	return 4000
}

// parseServices reads `compose ps`, which prints one JSON object per line in recent
// versions and an array in older ones.
func parseServices(output []byte) []Service {
	type row struct {
		Service string `json:"Service"`
		State   string `json:"State"`
	}

	var rows []row
	trimmed := bytes.TrimSpace(output)
	if len(trimmed) > 0 && trimmed[0] == '[' {
		_ = json.Unmarshal(trimmed, &rows)
	} else {
		for line := range strings.SplitSeq(string(trimmed), "\n") {
			var one row
			if json.Unmarshal([]byte(line), &one) == nil && one.Service != "" {
				rows = append(rows, one)
			}
		}
	}

	services := make([]Service, 0, len(rows))
	for _, one := range rows {
		services = append(services, Service{Name: one.Service, State: one.State})
	}
	return services
}

// Logs prints the logs of the containers.
func (d *Docker) Logs(ctx context.Context, output io.Writer, lines int, follow, database bool) error {
	args := []string{"logs", "--tail", strconv.Itoa(lines)}
	if follow {
		args = append(args, "--follow")
	}
	if database {
		args = append(args, "db")
	}
	command := d.Compose(ctx, args...)
	command.Stdout = output
	command.Stderr = output
	return command.Run()
}
