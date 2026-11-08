package commands

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/install"
	"github.com/heddlehq/heddle/cli/internal/system"
	"github.com/heddlehq/heddle/cli/internal/text"
	"github.com/heddlehq/heddle/cli/internal/ui"
	"github.com/heddlehq/heddle/cli/internal/wizard"
)

type installFlags struct {
	yes         bool
	treadleOnly bool
	withTreadle bool
	docker      bool
	noPath      bool
	noStart     bool
	noBrowser   bool
}

func installCommand() *cobra.Command {
	var flags installFlags
	plan := install.DefaultPlan()

	// The old install script read these, and the one-liner still takes them.
	_, noStart := os.LookupEnv("HEDDLE_NO_START")
	_, noBrowser := os.LookupEnv("HEDDLE_NO_BROWSER")

	command := &cobra.Command{
		Use:   "install",
		Short: text.T("Install Heddle and Treadle, your way", "Instala o Heddle e o Treadle do seu jeito"),
		Long: text.T(
			"Asks what you want and installs it. Every question has a flag, and with --yes\nnothing is asked: what wasn't passed takes its default.",
			"Pergunta o que você quer e instala. Toda pergunta tem uma opção, e com --yes\nnada é perguntado: o que não foi passado usa o padrão.",
		),
		Example: "heddle install\n" +
			"heddle install --treadle\n" +
			"heddle install --yes --port 4100 --llm-provider anthropic --llm-model claude-sonnet-5-5\n" +
			"heddle install --yes --docker --domain heddle.example.com",
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			applyFlags(&plan, flags, noStart || flags.noStart, noBrowser || flags.noBrowser)
			if plan.LLMKey == "" {
				plan.LLMKey = os.Getenv("HEDDLE_LLM_API_KEY")
			}

			facts := system.Detect()
			if !flags.yes && ui.Interactive() {
				return runWizard(cmd, plan, facts, flags)
			}
			return runPlain(cmd, plan, facts)
		},
	}

	options := command.Flags()
	options.BoolVarP(&flags.yes, "yes", "y", false, text.T("ask nothing", "não pergunta nada"))
	options.BoolVar(&flags.treadleOnly, "treadle", false, text.T("install only Treadle, the terminal editor", "instala só o Treadle, o editor de terminal"))
	options.BoolVar(&flags.withTreadle, "with-treadle", false, text.T("install Treadle along with Heddle", "instala o Treadle junto com o Heddle"))
	options.BoolVar(&flags.docker, "docker", false, text.T("run with Docker, for a server", "roda com Docker, para um servidor"))
	options.StringVar(&plan.Home, "home", plan.Home, text.T("where to install Heddle", "onde instalar o Heddle"))
	options.StringVar(&plan.Version, "version", "", text.T("version of Heddle (default: the latest)", "versão do Heddle (padrão: a mais recente)"))
	options.IntVar(&plan.Port, "port", plan.Port, text.T("port for Heddle", "porta do Heddle"))
	options.StringVar(&plan.Domain, "domain", "", text.T("public domain, behind HTTPS (needs --docker)", "domínio público, atrás de HTTPS (precisa de --docker)"))
	options.StringVar(&plan.LLMProvider, "llm-provider", "", "anthropic, openai, google, xai")
	options.StringVar(&plan.LLMModel, "llm-model", "", text.T("model for chat and text", "modelo para chat e texto"))
	options.StringVar(&plan.LLMKey, "llm-key", "", text.T("API key (better: the HEDDLE_LLM_API_KEY variable)", "chave de API (melhor: a variável HEDDLE_LLM_API_KEY)"))
	options.BoolVar(&plan.ClaudeAgent, "claude-agent", false, text.T("set up the Claude Agent of the editor chat", "configura o Claude Agent do chat do editor"))
	options.StringVar(&plan.ClaudeKey, "claude-key", "", text.T("API key for the Claude Agent", "chave de API do Claude Agent"))
	options.StringVar(&plan.ClaudeBudget, "claude-budget", "", text.T("spending limit per chat, in USD", "limite de gasto por chat, em USD"))
	options.IntVar(&plan.ExecutionConcurrency, "concurrency", 0, text.T("flows running at the same time", "flows rodando ao mesmo tempo"))
	options.IntVar(&plan.SpoolMaxTables, "spool-max-tables", 0, text.T("Spool tables per workspace (default: 50)", "tabelas do Spool por workspace (padrão: 50)"))
	options.IntVar(&plan.SpoolMaxRows, "spool-max-rows", 0, text.T("rows per Spool table (default: 100000)", "linhas por tabela do Spool (padrão: 100000)"))
	options.StringVar(&plan.TreadleHome, "treadle-home", plan.TreadleHome, text.T("where to install Treadle", "onde instalar o Treadle"))
	options.StringVar(&plan.TreadleVersion, "treadle-version", "", text.T("version of Treadle", "versão do Treadle"))
	options.StringVar(&plan.TreadleServer, "server", "", text.T("Heddle server for Treadle", "servidor Heddle do Treadle"))
	options.StringVar(&plan.TreadleKey, "api-key", "", text.T("API key of that server", "chave de API desse servidor"))
	options.BoolVar(&plan.Autostart, "autostart", false, text.T("start with this computer", "inicia com o computador"))
	options.IntVar(&plan.BackupKeep, "keep-backups", plan.BackupKeep, text.T("backups to keep when updating", "backups a manter nas atualizações"))
	options.BoolVar(&flags.noPath, "no-path", false, text.T("don't change your PATH", "não muda seu PATH"))
	options.BoolVar(&flags.noStart, "no-start", false, text.T("don't start after installing", "não inicia depois de instalar"))
	options.BoolVar(&flags.noBrowser, "no-browser", false, text.T("don't open the browser", "não abre o navegador"))
	return command
}

func applyFlags(plan *install.Plan, flags installFlags, noStart, noBrowser bool) {
	if flags.treadleOnly {
		plan.Heddle = false
		plan.Treadle = true
	}
	if flags.withTreadle {
		plan.Treadle = true
	}
	if flags.docker {
		plan.Mode = config.ModeDocker
	}
	if flags.noPath {
		plan.AddToPath = false
	}
	if noStart {
		plan.Start = false
	}
	if noBrowser {
		plan.Browser = false
	}
}

func runWizard(cmd *cobra.Command, plan install.Plan, facts system.Facts, flags installFlags) error {
	outcome, err := wizard.Run(cmd.Context(), wizard.Options{
		Plan:        plan,
		Facts:       facts,
		TreadleOnly: flags.treadleOnly,
		CLIVersion:  Version,
	})
	if err != nil {
		return err
	}
	if outcome.Cancelled {
		ui.Blank()
		ui.Line(ui.Faint(text.T("Nothing was changed.", "Nada foi alterado.")))
		ui.Blank()
		return nil
	}
	if outcome.Err != nil {
		return outcome.Err
	}
	printResult(outcome.Plan, outcome.Result)
	return nil
}

func runPlain(cmd *cobra.Command, plan install.Plan, facts system.Facts) error {
	if err := plan.Validate(facts); err != nil {
		return err
	}

	ui.Title(text.T("Heddle installer", "Instalador do Heddle"), Version)
	reporter := newPlainReporter()
	result, err := install.Run(cmd.Context(), plan, reporter)
	reporter.finish()
	if err != nil {
		return err
	}
	printResult(plan, result)
	return nil
}

func printResult(plan install.Plan, result install.Result) {
	ui.Blank()
	if plan.Heddle {
		ui.Success(fmt.Sprintf("Heddle %s %s %s", result.Version, text.T("is installed in", "instalado em"), plan.Home))
	}
	if plan.Treadle {
		ui.Success(fmt.Sprintf("Treadle %s %s %s", result.TreadleVersion, text.T("is installed in", "instalado em"), plan.TreadleHome))
	}
	if result.BackupName != "" {
		ui.Line(ui.Faint(text.T("Your data was copied to ", "Seus dados foram copiados para ") + filepath.Join("backups", result.BackupName)))
	}
	ui.Blank()

	if result.URL != "" {
		ui.Line(text.T("Heddle is running at ", "O Heddle está rodando em ") + ui.Bold(result.URL))
		ui.Line(ui.Faint(text.T("The first visit asks you to create the admin account.", "A primeira visita pede para criar a conta de admin.")))
		ui.Blank()
	}

	if result.Profile != "" {
		ui.Line(ui.Faint(text.T("Open a new terminal to use the commands below.", "Abra um novo terminal para usar os comandos abaixo.")))
	}

	var rows [][2]string
	if plan.Heddle {
		rows = append(rows,
			[2]string{"heddle status", text.T("what's running", "o que está rodando")},
			[2]string{"heddle stop", text.T("stop it", "para")},
			[2]string{"heddle start -d", text.T("start in the background", "inicia em segundo plano")},
			[2]string{"heddle --help", text.T("everything else", "todo o resto")},
		)
	}
	if plan.Treadle {
		rows = append(rows, [2]string{"treadle", text.T("open the terminal editor", "abre o editor de terminal")})
	}
	ui.Commands(rows)
	ui.Blank()
}

func setupCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "setup",
		Short: text.T("Change the AI of an install, step by step", "Muda a IA de uma instalação, passo a passo"),
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := load()
			if err != nil {
				return err
			}
			if !config.Installed(current.layout) {
				return errors.New(text.T("Heddle isn't installed here. Run: heddle install", "O Heddle não está instalado aqui. Rode: heddle install"))
			}
			if !ui.Interactive() {
				return errors.New(text.T("This one needs a terminal. Use: heddle config set", "Este precisa de um terminal. Use: heddle config set"))
			}

			settings, err := current.settings()
			if err != nil {
				return err
			}
			plan := install.DefaultPlan()
			plan.Home = current.layout.Home
			plan.Mode = current.manifest.Mode
			plan.LLMProvider = settings.Value("HEDDLE_LLM_PROVIDER")
			plan.LLMModel = settings.Value("HEDDLE_LLM_MODEL")
			plan.LLMKey = settings.Value("HEDDLE_LLM_API_KEY")

			outcome, err := wizard.Run(cmd.Context(), wizard.Options{Plan: plan, Facts: system.Detect(), SettingsOnly: true, CLIVersion: Version})
			if err != nil {
				return err
			}
			if outcome.Cancelled {
				return nil
			}
			if err := outcome.Plan.Settings(settings); err != nil {
				return err
			}
			// Here "Not now" is an answer about what's already set, not a question left
			// for later, and Settings keeps whatever an answer leaves empty.
			if outcome.Plan.LLMProvider == "" {
				for _, key := range []string{"HEDDLE_LLM_PROVIDER", "HEDDLE_LLM_MODEL", "HEDDLE_LLM_API_KEY"} {
					settings.Unset(key)
				}
			}
			if err := current.saveSettings(settings); err != nil {
				return err
			}
			ui.Success(text.T("Saved", "Salvo"))
			return restartHint(cmd, current)
		},
	}
}
