// Package install turns a Plan into an install. The wizard and the flags of
// `heddle install` only differ in how they fill the Plan: everything that touches
// the machine happens in Run.
package install

import (
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/paths"
	"github.com/heddlehq/heddle/cli/internal/system"
	"github.com/heddlehq/heddle/cli/internal/text"
)

// Plan is every decision of an install.
type Plan struct {
	Heddle  bool
	Treadle bool

	Mode    string
	Home    string
	Version string // Empty means the latest.
	Port    int
	Domain  string // Docker only: the public domain, behind HTTPS.

	LLMProvider string
	LLMModel    string
	LLMKey      string

	ClaudeAgent  bool
	ClaudeKey    string // Empty reuses the LLM key when the provider is Anthropic.
	ClaudeBin    string
	ClaudeBudget string

	ExecutionConcurrency int // 0 keeps the default.
	RescueMinutes        int // 0 keeps the default.

	SpoolMaxTables int // 0 keeps the default.
	SpoolMaxRows   int // 0 keeps the default.

	TreadleHome    string
	TreadleVersion string
	TreadleServer  string
	TreadleKey     string

	AddToPath bool
	Autostart bool
	Start     bool
	Browser   bool

	BackupKeep int
}

// DefaultPlan is the install that needs no answers: what the one-liner has always
// done, plus Treadle left out.
func DefaultPlan() Plan {
	home := paths.Resolve().Home
	return Plan{
		Heddle:      true,
		Mode:        config.ModeLocal,
		Home:        home,
		Port:        4000,
		TreadleHome: paths.DefaultTreadleHome(),
		AddToPath:   true,
		Start:       true,
		Browser:     true,
		BackupKeep:  DefaultKeep,
	}
}

// Layout is the install this plan makes.
func (p Plan) Layout() paths.Layout { return paths.Layout{Home: p.Home} }

// Docker says whether this plan runs Heddle in containers.
func (p Plan) Docker() bool { return p.Heddle && p.Mode == config.ModeDocker }

// Validate catches what can't work, before anything changes.
func (p Plan) Validate(facts system.Facts) error {
	if !p.Heddle && !p.Treadle {
		return errors.New(text.T("There's nothing to install.", "Não há nada para instalar."))
	}
	if !p.Heddle {
		return nil
	}

	switch p.Mode {
	case config.ModeLocal:
		if problem := facts.NativeProblem(text.T); problem != "" {
			return fmt.Errorf("%s %s", problem, text.T("Use --docker, or --treadle for only the editor.", "Use --docker, ou --treadle para ter só o editor."))
		}
		if !paths.Supported(p.Home) {
			return errors.New(text.T(
				"Heddle can't run from "+p.Home+", because the name has accents. Pick another folder.",
				"O Heddle não roda em "+p.Home+", porque o nome tem acentos. Escolha outra pasta.",
			))
		}
		if p.Domain != "" {
			return errors.New(text.T("A domain needs a server install: use --docker.", "Um domínio precisa da instalação em servidor: use --docker."))
		}
	case config.ModeDocker:
		if !facts.Docker {
			return errors.New(text.T("Docker isn't running on this machine.", "O Docker não está rodando nesta máquina."))
		}
	default:
		return fmt.Errorf("%s: %s", text.T("Unknown install type", "Tipo de instalação desconhecido"), p.Mode)
	}

	if p.Port < 1 || p.Port > 65535 {
		return fmt.Errorf("%s: %d", text.T("Invalid port", "Porta inválida"), p.Port)
	}
	if (p.LLMProvider == "") != (p.LLMKey == "") {
		return errors.New(text.T("The AI provider and its key go together.", "O provedor de IA e a chave vão juntos."))
	}
	return nil
}

// Settings writes this plan's answers over what an install already had, so running
// the installer again never loses what it didn't ask about.
func (p Plan) Settings(env *config.Env) error {
	set := func(key, value string) error {
		if value == "" {
			return nil
		}
		return env.Set(key, value)
	}

	port := "PORT"
	if p.Docker() {
		port = "HEDDLE_PORT"
	}

	values := [][2]string{
		{"HEDDLE_LLM_PROVIDER", p.LLMProvider},
		{"HEDDLE_LLM_MODEL", p.LLMModel},
		{"HEDDLE_LLM_API_KEY", p.LLMKey},
		{"PHX_HOST", p.Domain},
	}
	if p.Port != 4000 || hasKey(env, port) {
		values = append(values, [2]string{port, strconv.Itoa(p.Port)})
	}
	if p.ClaudeAgent {
		values = append(values,
			[2]string{"HEDDLE_CLAUDE_API_KEY", p.ClaudeKey},
			[2]string{"HEDDLE_CLAUDE_BIN", p.ClaudeBin},
			[2]string{"HEDDLE_CLAUDE_MAX_BUDGET_USD", p.ClaudeBudget},
		)
	}
	if p.ExecutionConcurrency > 0 {
		values = append(values, [2]string{"OBAN_EXECUTIONS_CONCURRENCY", strconv.Itoa(p.ExecutionConcurrency)})
	}
	if p.RescueMinutes > 0 {
		values = append(values, [2]string{"OBAN_RESCUE_AFTER_MINUTES", strconv.Itoa(p.RescueMinutes)})
	}
	if p.SpoolMaxTables > 0 {
		values = append(values, [2]string{"SPOOL_MAX_TABLES", strconv.Itoa(p.SpoolMaxTables)})
	}
	if p.SpoolMaxRows > 0 {
		values = append(values, [2]string{"SPOOL_MAX_ROWS", strconv.Itoa(p.SpoolMaxRows)})
	}

	for _, pair := range values {
		if err := set(pair[0], pair[1]); err != nil {
			return err
		}
	}
	return nil
}

func hasKey(env *config.Env, key string) bool {
	_, ok := env.Get(key)
	return ok
}

// AISummary is the part of Summary about the AI.
func (p Plan) AISummary() [][2]string {
	ai := text.T("set it up later, on the AI page", "configurar depois, na página de IA")
	if p.LLMProvider != "" {
		ai = strings.TrimSpace(p.LLMProvider + " · " + p.LLMModel)
	}

	rows := [][2]string{{text.T("AI", "IA"), ai}}
	if p.ClaudeAgent {
		rows = append(rows, [2]string{"Claude Agent", text.T("yes", "sim")})
	}
	return rows
}

// Summary is what the review screen and the plain output list.
func (p Plan) Summary() [][2]string {
	yes, no := text.T("yes", "sim"), text.T("no", "não")
	flag := func(value bool) string {
		if value {
			return yes
		}
		return no
	}
	version := p.Version
	if version == "" {
		version = text.T("latest", "mais recente")
	}

	var rows [][2]string
	add := func(label, value string) { rows = append(rows, [2]string{label, value}) }

	if p.Heddle {
		kind := text.T("This computer, with its own database", "Este computador, com banco próprio")
		if p.Docker() {
			kind = text.T("Server, with Docker", "Servidor, com Docker")
		}
		add("Heddle", version)
		add(text.T("Runs on", "Roda em"), kind)
		add(text.T("Folder", "Pasta"), p.Home)
		add(text.T("Port", "Porta"), strconv.Itoa(p.Port))
		if p.Domain != "" {
			add(text.T("Domain", "Domínio"), p.Domain)
		}
		rows = append(rows, p.AISummary()...)
	}
	if p.Treadle {
		add("Treadle", p.TreadleHome)
		if p.TreadleServer != "" {
			add(text.T("Connects to", "Conecta em"), p.TreadleServer)
		}
	}
	if p.Heddle {
		if !p.Docker() {
			add(text.T("Start with this computer", "Iniciar com o computador"), flag(p.Autostart))
		}
		add(text.T("Start now", "Iniciar agora"), flag(p.Start))
	}
	return rows
}
