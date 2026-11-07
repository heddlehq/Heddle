// Package runtime starts, stops and inspects a running Heddle, whichever way it was
// installed.
package runtime

import (
	"context"
	"errors"
	"io"
	"time"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/paths"
)

// ErrNotRunning is what stopping something already stopped answers.
var ErrNotRunning = errors.New("not running")

// Status is what `heddle status` shows.
type Status struct {
	Running  bool          `json:"running"`
	Healthy  bool          `json:"healthy"`
	URL      string        `json:"url,omitempty"`
	PID      int           `json:"pid,omitempty"`
	Uptime   time.Duration `json:"uptime_ns,omitempty"`
	Database bool          `json:"database"`
	Services []Service     `json:"services,omitempty"`
}

// Service is one container of a Docker install.
type Service struct {
	Name  string `json:"name"`
	State string `json:"state"`
}

// StartOptions changes one start, without touching the settings.
type StartOptions struct {
	Port      int
	NoBrowser bool
	// Follow streams the log to Output while Heddle runs in the foreground.
	Follow bool
	Output io.Writer
	// Progress hears the latest line while Heddle boots.
	Progress func(line string)
}

// Runtime is a way of running Heddle.
type Runtime interface {
	// Start returns once Heddle answers, with the address it answers on.
	Start(ctx context.Context, options StartOptions) (string, error)
	// Run starts Heddle and stays until it stops, or ctx is cancelled.
	Run(ctx context.Context, options StartOptions, ready func(url string)) error
	Stop(ctx context.Context) error
	Status(ctx context.Context) (Status, error)
	Logs(ctx context.Context, output io.Writer, lines int, follow, database bool) error
}

// For returns the runtime of an install.
func For(layout paths.Layout, manifest config.Manifest) Runtime {
	if manifest.Mode == config.ModeDocker {
		return &Docker{Layout: layout}
	}
	return &Local{Layout: layout}
}
