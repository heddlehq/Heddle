package commands

import (
	"fmt"
	"strings"

	"github.com/heddlehq/heddle/cli/internal/ui"
)

// plainReporter shows an install away from the wizard: on a server, in a script, or
// in `heddle update`.
type plainReporter struct {
	spinner *ui.Spinner
	title   string
}

func newPlainReporter() *plainReporter { return &plainReporter{} }

func (r *plainReporter) finish() {
	if r.spinner != nil {
		r.spinner.Stop()
		r.spinner = nil
	}
}

func (r *plainReporter) Step(title string) {
	r.finish()
	r.title = title
	r.spinner = ui.Spin(title)
}

func (r *plainReporter) Done(detail string) {
	r.finish()
	line := r.title
	if detail = strings.TrimSpace(detail); detail != "" {
		line += "  " + ui.Faint(detail)
	}
	ui.Success(line)
}

func (r *plainReporter) Warn(message string) {
	r.finish()
	ui.Warning(message)
	if r.title != "" {
		r.spinner = ui.Spin(r.title)
	}
}

func (r *plainReporter) Progress(fraction float64, detail string) {
	if r.spinner == nil {
		return
	}
	if fraction >= 0 {
		detail = fmt.Sprintf("%3.0f%%  %s", fraction*100, detail)
	}
	r.spinner.Detail(detail)
}
