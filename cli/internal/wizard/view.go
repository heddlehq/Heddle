package wizard

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"

	"charm.land/bubbles/v2/textinput"
	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	"github.com/charmbracelet/x/ansi"

	"github.com/heddlehq/heddle/cli/internal/brand"
	"github.com/heddlehq/heddle/cli/internal/text"
)

const (
	frameWidth  = 92
	frameHeight = 26
	sideWidth   = 26
	sideMinimum = 72 // Below this, the side column goes.
	logoMinimum = 22 // Below this, the logo goes.
	listRows    = 7  // A long list shows this many at a time.
	inputWidth  = 52
)

var spinnerFrames = []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

var (
	titleStyle   = lipgloss.NewStyle().Foreground(brand.Paper).Bold(true)
	textStyle    = lipgloss.NewStyle().Foreground(brand.Paper)
	mutedStyle   = lipgloss.NewStyle().Foreground(brand.Muted)
	dimStyle     = lipgloss.NewStyle().Foreground(brand.Dim)
	accentStyle  = lipgloss.NewStyle().Foreground(brand.Accent)
	successStyle = lipgloss.NewStyle().Foreground(brand.Success)
	dangerStyle  = lipgloss.NewStyle().Foreground(brand.Danger)
	warmStyle    = lipgloss.NewStyle().Foreground(brand.Warm)
	buttonStyle  = lipgloss.NewStyle().Foreground(brand.Deep).Background(brand.Accent).Bold(true).Padding(0, 3)
)

func newInput() textinput.Model {
	input := textinput.New()
	input.Prompt = ""
	input.EchoCharacter = '•'
	input.CharLimit = 512
	input.SetWidth(inputWidth)

	styles := textinput.DefaultDarkStyles()
	styles.Focused.Text = textStyle
	styles.Focused.Prompt = textStyle
	styles.Focused.Placeholder = dimStyle
	styles.Blurred.Text = textStyle
	styles.Blurred.Placeholder = dimStyle
	styles.Cursor.Color = brand.Accent
	styles.Cursor.Blink = true
	input.SetStyles(styles)
	return input
}

func (m *model) View() tea.View {
	view := tea.NewView(m.render())
	view.AltScreen = true
	view.BackgroundColor = brand.Ink
	view.ForegroundColor = brand.Paper
	view.WindowTitle = text.T("Heddle installer", "Instalador do Heddle")
	return view
}

func (m *model) render() string {
	width := min(frameWidth, m.width-4)
	height := min(frameHeight, m.height-2)

	side := m.width >= sideMinimum
	mainWidth := width
	if side {
		mainWidth = width - sideWidth - 4
	}

	var main string
	switch m.phase {
	case phaseAsking:
		main = m.renderQuestion(mainWidth)
	default:
		main = m.renderInstall(mainWidth)
	}

	body := main
	if side {
		divider := dimStyle.Render(strings.TrimRight(strings.Repeat("│\n", max(height-3, 1)), "\n"))
		left := lipgloss.NewStyle().Width(sideWidth).Render(m.renderSide(height))
		body = lipgloss.JoinHorizontal(lipgloss.Top, left, " ", divider, "  ", main)
	}

	footer := m.renderFooter(width)
	spacer := max(height-lipgloss.Height(body)-lipgloss.Height(footer), 1)
	frame := body + strings.Repeat("\n", spacer) + footer

	// A fixed width keeps every line aligned to the left of the frame: Place would
	// center each short line on its own.
	block := lipgloss.NewStyle().Width(width).Render(frame)
	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center, block)
}

func (m *model) renderSide(height int) string {
	var rows []string

	if height >= logoMinimum {
		fraction := 1.0
		if m.phase != phaseAsking {
			fraction = m.shown
		}
		if m.options.TreadleOnly {
			rows = append(rows, brand.WovenTreadle(fraction)...)
		} else {
			rows = append(rows, brand.Woven(fraction)...)
		}
		rows = append(rows, "")
	}

	name := "Heddle"
	if m.options.TreadleOnly {
		name = "Treadle"
	}
	rows = append(rows, titleStyle.Render(name)+" "+dimStyle.Render(m.options.CLIVersion), "")

	if m.phase == phaseAsking {
		rows = append(rows, m.renderRail()...)
	}
	return strings.Join(rows, "\n")
}

// renderRail shows the sections of this run, and how far it has come.
func (m *model) renderRail() []string {
	var sections []section
	for _, s := range m.visibleScreens() {
		if !slices.Contains(sections, s.section) {
			sections = append(sections, s.section)
		}
	}

	current := m.current().section
	rows := make([]string, 0, len(sections))
	for _, s := range sections {
		switch {
		case s == current:
			rows = append(rows, accentStyle.Render("●")+" "+titleStyle.Render(s.title()))
		case s < current:
			rows = append(rows, successStyle.Render("✓")+" "+mutedStyle.Render(s.title()))
		default:
			rows = append(rows, dimStyle.Render("○ "+s.title()))
		}
	}
	return rows
}

func (m *model) renderQuestion(width int) string {
	s := m.current()

	var b strings.Builder
	b.WriteString(titleStyle.Render(s.title(m)))
	b.WriteString("\n")
	if s.hint != nil {
		if hint := s.hint(m); hint != "" {
			b.WriteString(mutedStyle.Width(width).Render(hint))
			b.WriteString("\n")
		}
	}
	b.WriteString("\n")

	switch s.kind {
	case kindChoice:
		b.WriteString(m.renderChoice(s, width))
	case kindToggles:
		b.WriteString(m.renderToggles(s, width))
	case kindInput:
		b.WriteString(m.renderInput(width))
	case kindReview:
		b.WriteString(m.renderReview(width))
	}

	switch {
	case m.checking != "":
		b.WriteString("\n\n" + accentStyle.Render(m.spinner()) + " " + mutedStyle.Render(m.checking+"…"))
	case m.message != "":
		b.WriteString("\n\n" + dangerStyle.Width(width).Render("✕ "+m.message))
	case m.notice != "":
		b.WriteString("\n\n" + warmStyle.Width(width).Render("! "+m.notice))
	}
	return b.String()
}

func (m *model) spinner() string {
	return spinnerFrames[m.frame%len(spinnerFrames)]
}

func (m *model) renderChoice(s *screen, width int) string {
	options := s.options(m)
	compact := len(options) > 5

	start, end := 0, len(options)
	if compact && len(options) > listRows {
		start = min(max(m.cursor-listRows/2, 0), len(options)-listRows)
		end = start + listRows
	}

	label := 0
	for _, o := range options {
		label = max(label, lipgloss.Width(o.label))
	}

	rows := make([]string, 0, end-start+2)
	if start > 0 {
		rows = append(rows, dimStyle.Render("  ↑ "+fmt.Sprint(start)))
	}
	for index := start; index < end; index++ {
		rows = append(rows, renderOption(options[index], index == m.cursor, compact, label, width))
	}
	if end < len(options) {
		rows = append(rows, dimStyle.Render("  ↓ "+fmt.Sprint(len(options)-end)))
	}

	if compact {
		return strings.Join(rows, "\n")
	}
	return strings.Join(rows, "\n\n")
}

func renderOption(o option, selected, compact bool, labelWidth, width int) string {
	marker := "  "
	label := textStyle.Render(o.label)
	if selected {
		marker = accentStyle.Render("▌ ")
		label = titleStyle.Render(o.label)
	}

	note := o.note
	style := mutedStyle
	if o.disabled != "" {
		label = dimStyle.Render(o.label)
		note = o.disabled
		style = dimStyle
	}

	if note == "" {
		return marker + label
	}
	if compact {
		padding := strings.Repeat(" ", labelWidth-lipgloss.Width(o.label)+2)
		return ansi.Truncate(marker+label+padding+style.Render(note), width, "…")
	}
	return marker + label + "\n" + marker + style.Render(ansi.Truncate(note, width-2, "…"))
}

func (m *model) renderToggles(s *screen, width int) string {
	options := s.options(m)
	rows := make([]string, 0, len(options))
	for index, o := range options {
		box := dimStyle.Render("[ ]")
		if m.checked[o.value] {
			box = accentStyle.Render("[✓]")
		}
		marker := "  "
		label := textStyle.Render(o.label)
		if index == m.cursor {
			marker = accentStyle.Render("▌ ")
			label = titleStyle.Render(o.label)
		}
		rows = append(rows, ansi.Truncate(marker+box+" "+label, width, "…"))
	}
	return strings.Join(rows, "\n")
}

func (m *model) renderInput(width int) string {
	m.input.SetWidth(min(inputWidth, width-4))
	line := dimStyle.Render(strings.Repeat("─", min(inputWidth, width-2)))
	return accentStyle.Render("▌ ") + m.input.View() + "\n  " + line
}

func (m *model) renderReview(width int) string {
	rows := m.plan.Summary()
	if m.options.SettingsOnly {
		rows = m.plan.AISummary()
	}
	label := 0
	for _, row := range rows {
		label = max(label, lipgloss.Width(row[0]))
	}

	lines := make([]string, 0, len(rows))
	for _, row := range rows {
		padding := strings.Repeat(" ", label-lipgloss.Width(row[0])+2)
		lines = append(lines, ansi.Truncate(mutedStyle.Render(row[0])+padding+textStyle.Render(row[1]), width, "…"))
	}

	action := text.T("Install", "Instalar")
	if m.options.SettingsOnly {
		action = text.T("Save", "Salvar")
	} else if m.existing != "" {
		action = text.T("Update", "Atualizar")
	}
	return strings.Join(lines, "\n") + "\n\n" + buttonStyle.Render(action)
}

func (m *model) renderInstall(width int) string {
	var b strings.Builder

	switch {
	case m.failure != nil:
		b.WriteString(dangerStyle.Bold(true).Render(text.T("The install stopped", "A instalação parou")))
	case m.phase == phaseFinished:
		b.WriteString(titleStyle.Render(text.T("All woven", "Tudo tecido")))
	case m.cancelling:
		b.WriteString(titleStyle.Render(text.T("Cancelling", "Cancelando")))
	default:
		b.WriteString(titleStyle.Render(text.T("Installing", "Instalando")))
	}
	b.WriteString("\n\n")

	steps := m.steps
	if len(steps) > 9 {
		steps = steps[len(steps)-9:]
	}
	for _, step := range steps {
		b.WriteString(m.renderStep(step, width))
		b.WriteString("\n")
	}

	if m.failure == nil && m.phase == phaseInstalling {
		b.WriteString("\n")
		b.WriteString(renderThread(m.shown, min(width-8, 44)))
		b.WriteString(mutedStyle.Render(fmt.Sprintf("  %3.0f%%", m.shown*100)))
		if m.detail != "" {
			b.WriteString("\n" + dimStyle.Render(ansi.Truncate(ansi.Strip(m.detail), width, "…")))
		}
	}

	if errors.Is(m.failure, context.Canceled) {
		b.WriteString("\n" + mutedStyle.Render(text.T("Cancelled.", "Cancelado.")))
	} else if m.failure != nil {
		lines := strings.Split(strings.TrimSpace(m.failure.Error()), "\n")
		if len(lines) > 8 {
			lines = lines[len(lines)-8:]
		}
		b.WriteString("\n" + mutedStyle.Width(width).Render(strings.Join(lines, "\n")))
	}
	return b.String()
}

func (m *model) renderStep(step stepState, width int) string {
	var line string
	switch {
	case step.warn:
		line = warmStyle.Render("! ") + mutedStyle.Render(step.title)
	case step.done:
		line = successStyle.Render("✓ ") + textStyle.Render(step.title)
		if step.detail != "" {
			line += "  " + dimStyle.Render(step.detail)
		}
	case m.failure != nil:
		line = dangerStyle.Render("✕ ") + textStyle.Render(step.title)
	default:
		line = accentStyle.Render(m.spinner()+" ") + titleStyle.Render(step.title)
	}
	return ansi.Truncate(line, width, "…")
}

// renderThread is the progress bar: the weft being drawn, with the shuttle at its head.
func renderThread(fraction float64, width int) string {
	filled := int(fraction * float64(width))
	bar := accentStyle.Render(strings.Repeat("━", filled))
	if filled < width {
		bar += warmStyle.Render("╸") + dimStyle.Render(strings.Repeat("─", width-filled-1))
	}
	return bar
}

func (m *model) renderFooter(width int) string {
	hint := func(key, label string) string { return textStyle.Render(key) + " " + mutedStyle.Render(label) }

	var hints []string
	switch {
	case m.phase == phaseInstalling && m.cancelling:
		return ""
	case m.phase == phaseInstalling:
		hints = []string{hint("ctrl+c", text.T("cancel", "cancelar"))}
	case m.phase == phaseFinished && m.failure != nil:
		hints = []string{hint("enter", text.T("exit", "sair"))}
	case m.phase == phaseFinished:
		return ""
	default:
		switch m.current().kind {
		case kindChoice:
			hints = append(hints, hint("↑↓", text.T("choose", "escolher")), hint("enter", text.T("continue", "continuar")))
		case kindToggles:
			hints = append(hints, hint("↑↓", text.T("choose", "escolher")), hint("space", text.T("toggle", "alternar")), hint("enter", text.T("continue", "continuar")))
		case kindInput:
			hints = append(hints, hint("enter", text.T("continue", "continuar")))
		case kindReview:
			hints = append(hints, hint("enter", text.T("confirm", "confirmar")))
		}
		hints = append(hints, hint("esc", text.T("back", "voltar")), hint("ctrl+c", text.T("quit", "sair")))
	}
	return ansi.Truncate(strings.Join(hints, "   "), width, "…")
}
