// Package ui prints what the commands say in a normal terminal: unlike the wizard,
// this stays in the scrollback on whatever background the terminal has.
package ui

import (
	"fmt"
	"image/color"
	"os"
	"strings"
	"sync"
	"time"

	"charm.land/lipgloss/v2"
	"github.com/charmbracelet/x/ansi"
	"github.com/charmbracelet/x/term"

	"github.com/heddlehq/heddle/cli/internal/brand"
)

var (
	darkOnce sync.Once
	dark     = true
)

// Interactive says whether a person is on the other side of this terminal.
func Interactive() bool {
	return term.IsTerminal(os.Stdin.Fd()) && term.IsTerminal(os.Stdout.Fd())
}

func accent() color.Color {
	darkOnce.Do(func() {
		if Interactive() {
			dark = lipgloss.HasDarkBackground(os.Stdin, os.Stdout)
		}
	})
	if dark {
		return brand.Accent
	}
	return brand.Ribbon
}

func style() lipgloss.Style { return lipgloss.NewStyle() }

// Accent colors text with the brand.
func Accent(value string) string { return style().Foreground(accent()).Render(value) }

// Bold makes text stand out.
func Bold(value string) string { return style().Bold(true).Render(value) }

// Faint is for what's secondary.
func Faint(value string) string { return style().Faint(true).Render(value) }

// Command shows something to type.
func Command(value string) string { return style().Foreground(accent()).Bold(true).Render(value) }

func print(format string, args ...any) { lipgloss.Fprintf(os.Stdout, format, args...) }

// Title opens the output of a command with the mark of the brand.
func Title(name, detail string) {
	weft := Accent("▔▔")
	warp := "┃"
	print("\n  %s%s%s %s %s\n\n", weft, warp, weft, Bold(name), Faint(detail))
}

// Line prints an indented line.
func Line(value string) { print("  %s\n", value) }

// Blank prints an empty line.
func Blank() { print("\n") }

// Success says something worked.
func Success(value string) {
	print("  %s %s\n", style().Foreground(brand.Success).Render("✓"), value)
}

// Warning says something needs attention.
func Warning(value string) {
	print("  %s %s\n", style().Foreground(brand.Warm).Render("!"), value)
}

// Failure says something didn't work.
func Failure(value string) {
	lipgloss.Fprintf(os.Stderr, "\n  %s %s\n\n", style().Foreground(brand.Danger).Render("✕"), value)
}

// Rows prints a label and value per line, with the values aligned.
func Rows(rows [][2]string) {
	width := 0
	for _, row := range rows {
		width = max(width, lipgloss.Width(row[0]))
	}
	for _, row := range rows {
		padding := strings.Repeat(" ", width-lipgloss.Width(row[0]))
		print("  %s%s  %s\n", Faint(row[0]), padding, row[1])
	}
}

// Commands lists things to type and what they do, aligned.
func Commands(rows [][2]string) {
	width := 0
	for _, row := range rows {
		width = max(width, lipgloss.Width(row[0]))
	}
	for _, row := range rows {
		print("  %s%s  %s\n", Command(row[0]), strings.Repeat(" ", width-lipgloss.Width(row[0])), Faint(row[1]))
	}
}

// Spinner shows work going on, with the latest thing that happened next to it.
type Spinner struct {
	mutex  sync.Mutex
	title  string
	detail string
	done   chan struct{}
	wait   sync.WaitGroup
	live   bool
}

var frames = []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

// Spin starts a spinner. Away from a terminal it only prints the title.
func Spin(title string) *Spinner {
	spinner := &Spinner{title: title, done: make(chan struct{}), live: term.IsTerminal(os.Stdout.Fd())}
	if !spinner.live {
		print("  %s\n", title)
		return spinner
	}

	spinner.wait.Add(1)
	go spinner.run()
	return spinner
}

func (s *Spinner) run() {
	defer s.wait.Done()
	ticker := time.NewTicker(90 * time.Millisecond)
	defer ticker.Stop()

	for frame := 0; ; frame++ {
		select {
		case <-s.done:
			print("\r\033[K")
			return
		case <-ticker.C:
			s.mutex.Lock()
			line := Accent(frames[frame%len(frames)]) + " " + s.title
			if s.detail != "" {
				line += "  " + Faint(s.detail)
			}
			s.mutex.Unlock()
			print("\r\033[K  %s", ansi.Truncate(line, width()-4, "…"))
		}
	}
}

// Detail changes the note next to the title.
func (s *Spinner) Detail(detail string) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.detail = strings.TrimSpace(ansi.Strip(detail))
}

// Title changes what the spinner says it's doing.
func (s *Spinner) Title(title string) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.title = title
	s.detail = ""
}

// Stop clears the spinner, leaving the line free for the outcome.
func (s *Spinner) Stop() {
	if s.live {
		close(s.done)
		s.wait.Wait()
	}
}

func width() int {
	columns, _, err := term.GetSize(os.Stdout.Fd())
	if err != nil || columns <= 0 {
		return 80
	}
	return columns
}

// Confirm asks a yes or no question, and no is the answer to anything but yes.
func Confirm(question string, yes ...string) bool {
	print("  %s ", question)
	var answer string
	if _, err := fmt.Fscanln(os.Stdin, &answer); err != nil {
		return false
	}
	answer = strings.ToLower(strings.TrimSpace(answer))
	for _, accepted := range yes {
		if answer == accepted {
			return true
		}
	}
	return false
}
