// Package wizard is the interactive install. It only fills an install.Plan and draws
// install.Run: nothing here touches the machine.
package wizard

import (
	"context"
	"os"
	"slices"
	"time"

	"charm.land/bubbles/v2/textinput"
	tea "charm.land/bubbletea/v2"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/install"
	"github.com/heddlehq/heddle/cli/internal/providers"
	"github.com/heddlehq/heddle/cli/internal/release"
	"github.com/heddlehq/heddle/cli/internal/system"
	"github.com/heddlehq/heddle/cli/internal/text"
	"github.com/heddlehq/heddle/cli/internal/treadle"
)

// Options says what to ask.
type Options struct {
	Plan         install.Plan
	Facts        system.Facts
	TreadleOnly  bool // `heddle install --treadle`: only the questions about Treadle.
	SettingsOnly bool // `heddle setup`: only the AI, and nothing gets installed.
	CLIVersion   string
}

// Outcome is how the wizard ended.
type Outcome struct {
	Plan      install.Plan
	Result    install.Result
	Cancelled bool
	Err       error
}

// Run asks the questions and, unless told otherwise, runs the install.
func Run(ctx context.Context, options Options) (Outcome, error) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	state := newModel(ctx, cancel, options)
	program := tea.NewProgram(state)
	state.send = program.Send

	final, err := program.Run()
	if err != nil {
		return Outcome{}, err
	}
	return final.(*model).outcome, nil
}

type phase int

const (
	phaseAsking phase = iota
	phaseInstalling
	phaseFinished
)

type model struct {
	ctx     context.Context
	cancel  context.CancelFunc
	send    func(tea.Msg)
	options Options
	plan    install.Plan
	outcome Outcome

	screens []*screen
	index   int
	custom  bool // Asks everything, instead of only what can't have a default.

	cursor  int
	checked map[string]bool
	input   textinput.Model

	message  string // Why the answer on screen wasn't taken.
	notice   string // A note about the answer, that doesn't stop it.
	checking string // What's being checked in the background.
	accepted string // An answer that couldn't be checked, confirmed with a second enter.

	versions      []string
	models        []string
	customModel   bool
	existing      string // Version already installed in the chosen folder.
	otherProvider bool

	width  int
	height int
	frame  int

	phase      phase
	cancelling bool
	steps      []stepState
	fraction   float64 // Where the install is, from 0 to 1.
	shown      float64 // Where the weaving is: it eases towards fraction.
	detail     string
	expected   int
	failure    error
}

type stepState struct {
	title  string
	detail string
	done   bool
	warn   bool
}

type (
	tickMsg     struct{}
	versionsMsg []string
	checkedMsg  struct {
		value  string
		models []string
		err    error
	}
	stepMsg     struct{ title string }
	stepDoneMsg struct{ detail string }
	warnMsg     struct{ message string }
	progressMsg struct {
		fraction float64
		detail   string
	}
	installedMsg struct {
		result install.Result
		err    error
	}
	closeMsg struct{}
)

func newModel(ctx context.Context, cancel context.CancelFunc, options Options) *model {
	m := &model{
		ctx:     ctx,
		cancel:  cancel,
		options: options,
		plan:    options.Plan,
		checked: map[string]bool{},
		input:   newInput(),
		width:   80,
		height:  24,
	}

	if options.TreadleOnly {
		m.custom = true
		m.plan.Heddle = false
		m.plan.Treadle = true
	}
	if options.SettingsOnly {
		m.custom = true
	}

	// A machine that can't run the bundled install can still run Docker.
	if m.plan.Heddle && options.Facts.NativeProblem(text.T) != "" {
		m.plan.Mode = config.ModeDocker
		if !options.Facts.Docker {
			m.plan.Heddle = false
			m.plan.Treadle = true
		}
	}

	m.loadExisting()

	// Nothing to decide on an update, but a new install starts from the first option.
	if m.existing == "" && m.plan.Heddle && !options.SettingsOnly {
		m.plan.Treadle = true
	}

	m.screens = buildScreens()
	m.enter()
	return m
}

// loadExisting takes what an install in this folder already has, so running the
// installer again starts from its answers.
func (m *model) loadExisting() {
	layout := m.plan.Layout()
	m.existing = ""
	if !config.Installed(layout) {
		return
	}
	m.existing = config.Version(layout)

	if manifest, err := config.LoadManifest(layout); err == nil {
		m.plan.Mode = manifest.Mode
	}
	settings, err := config.LoadEnv(layout.EnvFile(m.plan.Docker()))
	if err != nil {
		return
	}
	if m.plan.LLMProvider == "" {
		m.plan.LLMProvider = settings.Value("HEDDLE_LLM_PROVIDER")
		m.plan.LLMModel = settings.Value("HEDDLE_LLM_MODEL")
		m.plan.LLMKey = settings.Value("HEDDLE_LLM_API_KEY")
	}
}

func (m *model) Init() tea.Cmd {
	return tea.Batch(tick(), m.loadVersions(), textinput.Blink)
}

func tick() tea.Cmd {
	return tea.Tick(80*time.Millisecond, func(time.Time) tea.Msg { return tickMsg{} })
}

func (m *model) loadVersions() tea.Cmd {
	return func() tea.Msg {
		versions, err := release.Versions(m.ctx, release.HeddleRepo, 6)
		if err != nil {
			return versionsMsg(nil)
		}
		return versionsMsg(versions)
	}
}

func (m *model) current() *screen { return m.screens[m.index] }

// visible says whether a screen belongs to this run.
func (m *model) visible(s *screen) bool {
	if m.options.SettingsOnly && s.section != sectionAI && s.id != "review" {
		return false
	}
	if s.advanced && !m.custom {
		return false
	}
	return s.when == nil || s.when(m)
}

func (m *model) visibleScreens() []*screen {
	return slices.DeleteFunc(slices.Clone(m.screens), func(s *screen) bool { return !m.visible(s) })
}

func (m *model) enter() {
	for !m.visible(m.current()) {
		m.index++
	}
	m.prepare()
}

// prepare sets the controls to what the plan says for this screen.
func (m *model) prepare() {
	s := m.current()
	m.message, m.notice, m.checking, m.accepted = "", "", "", ""

	switch s.kind {
	case kindInput:
		m.input.Reset()
		m.input.Placeholder = ""
		if s.placeholder != nil {
			m.input.Placeholder = s.placeholder(m)
		}
		m.input.EchoMode = textinput.EchoNormal
		if s.secret {
			m.input.EchoMode = textinput.EchoPassword
		}
		if s.value != nil {
			m.input.SetValue(s.value(m))
			m.input.CursorEnd()
		}
		m.input.Focus()
	case kindChoice:
		m.input.Blur()
		m.cursor = 0
		options := s.options(m)
		if s.value != nil {
			if index := slices.IndexFunc(options, func(o option) bool { return o.value == s.value(m) }); index >= 0 {
				m.cursor = index
			}
		}
		if options[m.cursor].disabled != "" {
			m.moveCursor(1, options)
		}
	case kindToggles:
		m.input.Blur()
		m.cursor = 0
		for _, o := range s.options(m) {
			m.checked[o.value] = s.toggled(m, o.value)
		}
	default:
		m.input.Blur()
	}
}

func (m *model) moveCursor(delta int, options []option) {
	for range options {
		m.cursor = (m.cursor + delta + len(options)) % len(options)
		if options[m.cursor].disabled == "" {
			return
		}
	}
}

func (m *model) next() tea.Cmd {
	for index := m.index + 1; index < len(m.screens); index++ {
		if m.visible(m.screens[index]) {
			m.index = index
			m.prepare()
			return nil
		}
	}
	return nil
}

func (m *model) back() {
	for index := m.index - 1; index >= 0; index-- {
		if m.visible(m.screens[index]) {
			m.index = index
			m.prepare()
			return
		}
	}
}

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, nil
	case tickMsg:
		m.frame++
		m.shown += (m.fraction - m.shown) * 0.15
		return m, tick()
	case versionsMsg:
		m.versions = msg
		return m, nil
	case checkedMsg:
		return m, m.finishCheck(msg)
	case stepMsg:
		m.closeStep("")
		m.steps = append(m.steps, stepState{title: msg.title})
		m.detail = ""
		m.advance(0)
		return m, nil
	case stepDoneMsg:
		m.closeStep(msg.detail)
		m.detail = ""
		m.advance(0)
		return m, nil
	case warnMsg:
		m.steps = append(m.steps, stepState{title: msg.message, done: true, warn: true})
		return m, nil
	case progressMsg:
		m.detail = msg.detail
		if msg.fraction >= 0 {
			m.advance(msg.fraction)
		}
		return m, nil
	case installedMsg:
		return m, m.finishInstall(msg)
	case closeMsg:
		return m, tea.Quit
	case tea.KeyPressMsg:
		return m, m.key(msg)
	}

	if m.current().kind == kindInput {
		var cmd tea.Cmd
		m.input, cmd = m.input.Update(msg)
		return m, cmd
	}
	return m, nil
}

func (m *model) closeStep(detail string) {
	if len(m.steps) == 0 {
		return
	}
	last := &m.steps[len(m.steps)-1]
	if !last.done {
		last.done = true
		last.detail = detail
	}
}

// advance moves the weaving by finished steps, plus how far into the current one.
func (m *model) advance(within float64) {
	finished := 0
	for _, step := range m.steps {
		if step.done && !step.warn {
			finished++
		}
	}
	m.fraction = min((float64(finished)+within)/float64(m.expected), 0.97)
}

func (m *model) finishInstall(msg installedMsg) tea.Cmd {
	m.outcome.Plan = m.plan
	m.outcome.Result = msg.result
	if msg.err != nil {
		m.failure = msg.err
		m.outcome.Err = msg.err
		m.phase = phaseFinished
		return nil
	}

	m.closeStep("")
	m.fraction = 1
	m.phase = phaseFinished
	return tea.Tick(1400*time.Millisecond, func(time.Time) tea.Msg { return closeMsg{} })
}

func (m *model) key(msg tea.KeyPressMsg) tea.Cmd {
	pressed := msg.String()

	switch m.phase {
	case phaseInstalling:
		if pressed == "ctrl+c" {
			m.cancelling = true
			m.cancel()
		}
		return nil
	case phaseFinished:
		if m.failure != nil || pressed == "enter" {
			return tea.Quit
		}
		return nil
	}

	if pressed == "ctrl+c" {
		m.outcome.Cancelled = true
		return tea.Quit
	}
	if m.checking != "" {
		return nil
	}
	if pressed == "esc" {
		m.back()
		return nil
	}

	s := m.current()
	switch s.kind {
	case kindInput:
		if pressed == "enter" {
			return m.submit(m.input.Value())
		}
		var cmd tea.Cmd
		m.input, cmd = m.input.Update(msg)
		m.message = ""
		return cmd
	case kindChoice:
		options := s.options(m)
		switch pressed {
		case "up", "k", "shift+tab":
			m.moveCursor(-1, options)
		case "down", "j", "tab":
			m.moveCursor(1, options)
		case "enter", "space":
			return m.submit(options[m.cursor].value)
		case "q":
			m.outcome.Cancelled = true
			return tea.Quit
		}
	case kindToggles:
		options := s.options(m)
		switch pressed {
		case "up", "k", "shift+tab":
			m.moveCursor(-1, options)
		case "down", "j", "tab":
			m.moveCursor(1, options)
		case "space":
			value := options[m.cursor].value
			m.checked[value] = !m.checked[value]
		case "enter":
			for _, o := range options {
				s.toggle(m, o.value, m.checked[o.value])
			}
			return m.next()
		}
	case kindReview:
		if pressed == "enter" {
			return m.confirm()
		}
		if pressed == "q" {
			m.outcome.Cancelled = true
			return tea.Quit
		}
	}
	return nil
}

// submit takes an answer through its checks and on to the next screen.
func (m *model) submit(value string) tea.Cmd {
	s := m.current()
	if s.validate != nil {
		if problem := s.validate(m, value); problem != "" {
			m.message = problem
			return nil
		}
	}

	if s.check != nil && value != "" && value != m.accepted {
		m.message = ""
		m.checking = s.checkLabel(m)
		return s.check(m, value)
	}
	return m.accept(value)
}

func (m *model) accept(value string) tea.Cmd {
	if s := m.current(); s.apply != nil {
		s.apply(m, value)
	}
	return m.next()
}

func (m *model) finishCheck(msg checkedMsg) tea.Cmd {
	m.checking = ""
	switch {
	case msg.err == nil:
		m.models = msg.models
		return m.accept(msg.value)
	case rejected(msg.err):
		m.message = msg.err.Error()
		return nil
	default:
		// Being offline says nothing about the answer, so it's still the person's call.
		m.accepted = msg.value
		m.notice = text.T("Could not check this. Press enter again to keep it anyway.", "Não deu para conferir. Tecle enter de novo para manter assim mesmo.")
		return nil
	}
}

func rejected(err error) bool {
	return isErr(err, providers.ErrRejected) || isErr(err, treadle.ErrUnauthorized)
}

// confirm ends the questions.
func (m *model) confirm() tea.Cmd {
	if err := m.plan.Validate(m.options.Facts); err != nil {
		m.message = err.Error()
		return nil
	}

	m.outcome.Plan = m.plan
	if m.options.SettingsOnly {
		return tea.Quit
	}

	m.phase = phaseInstalling
	m.expected = expectedSteps(m.plan, m.existing != "")
	plan := m.plan
	reporter := &reporter{send: m.send}
	return func() tea.Msg {
		result, err := install.Run(m.ctx, plan, reporter)
		return installedMsg{result: result, err: err}
	}
}

func expectedSteps(plan install.Plan, upgrade bool) int {
	count := 0
	if plan.Heddle {
		count += 3
		if plan.Docker() {
			count = 2
		} else if upgrade {
			count += 2
		}
		if plan.Autostart {
			count++
		}
		if plan.Start {
			count++
		}
	}
	if plan.Treadle {
		count++
	}
	return max(count, 1)
}

// reporter turns what the install says into messages for the screen.
type reporter struct {
	send func(tea.Msg)
}

func (r *reporter) Step(title string)  { r.send(stepMsg{title}) }
func (r *reporter) Done(detail string) { r.send(stepDoneMsg{detail}) }
func (r *reporter) Warn(message string) {
	r.send(warnMsg{message})
}
func (r *reporter) Progress(fraction float64, detail string) {
	r.send(progressMsg{fraction, detail})
}

// envKey finds a key for a provider already in this environment.
func envKey(provider providers.Provider) (string, string) {
	for _, name := range provider.EnvKeys {
		if value := os.Getenv(name); value != "" {
			return name, value
		}
	}
	return "", ""
}
