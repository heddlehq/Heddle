package commands

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/install"
	"github.com/heddlehq/heddle/cli/internal/paths"
	"github.com/heddlehq/heddle/cli/internal/runtime"
	"github.com/heddlehq/heddle/cli/internal/system"
	"github.com/heddlehq/heddle/cli/internal/text"
	"github.com/heddlehq/heddle/cli/internal/treadle"
	"github.com/heddlehq/heddle/cli/internal/ui"
)

type startFlags struct {
	detach    bool
	port      int
	noBrowser bool
	logs      bool
}

func startCommand() *cobra.Command {
	var flags startFlags
	command := &cobra.Command{
		Use:   "start",
		Short: text.T("Start Heddle", "Inicia o Heddle"),
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if flags.detach {
				return runDetached(cmd.Context(), flags)
			}
			return runForeground(cmd.Context(), flags)
		},
	}
	command.Flags().BoolVarP(&flags.detach, "detach", "d", false, text.T("keep running in the background", "continua rodando em segundo plano"))
	command.Flags().IntVarP(&flags.port, "port", "p", 0, text.T("port to try first, for this run", "porta a tentar primeiro, só nesta execução"))
	command.Flags().BoolVar(&flags.noBrowser, "no-browser", false, text.T("don't open the browser", "não abre o navegador"))
	command.Flags().BoolVar(&flags.logs, "logs", false, text.T("show the logs here", "mostra os logs aqui"))
	return command
}

func options(flags startFlags) runtime.StartOptions {
	return runtime.StartOptions{Port: flags.port, NoBrowser: flags.noBrowser, Output: os.Stdout}
}

func runDetached(ctx context.Context, flags startFlags) error {
	current, err := load()
	if err != nil {
		return err
	}

	ui.Title("Heddle", config.Version(current.layout))
	spinner := ui.Spin(text.T("Starting", "Iniciando"))
	settings := options(flags)
	settings.Progress = spinner.Detail
	url, err := current.runtime.Start(ctx, settings)
	spinner.Stop()
	if err != nil {
		return err
	}

	ui.Success(text.T("Running at ", "Rodando em ") + ui.Bold(url))
	ui.Line(ui.Faint(text.T("To stop it: ", "Para parar: ")) + ui.Command("heddle stop"))
	ui.Blank()
	return nil
}

// runForeground stays until Heddle stops. Away from a terminal, as under systemd, the
// logs are the output.
func runForeground(ctx context.Context, flags startFlags) error {
	current, err := load()
	if err != nil {
		return err
	}

	settings := options(flags)
	settings.Follow = flags.logs || !ui.Interactive()

	if settings.Follow {
		return current.runtime.Run(ctx, settings, nil)
	}

	ui.Title("Heddle", config.Version(current.layout))
	spinner := ui.Spin(text.T("Starting", "Iniciando"))
	settings.Progress = spinner.Detail

	stopped := false
	err = current.runtime.Run(ctx, settings, func(url string) {
		spinner.Stop()
		stopped = true
		ui.Success(text.T("Running at ", "Rodando em ") + ui.Bold(url))
		ui.Line(ui.Faint(text.T("Ctrl+C stops it. Logs: ", "Ctrl+C para. Logs: ")) + ui.Command("heddle logs -f"))
		ui.Blank()
	})
	if !stopped {
		spinner.Stop()
	}
	if err != nil {
		return err
	}
	ui.Success(text.T("Stopped", "Parado"))
	ui.Blank()
	return nil
}

func stopCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "stop",
		Short: text.T("Stop Heddle and its database", "Para o Heddle e o banco"),
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := load()
			if err != nil {
				return err
			}
			return stop(cmd.Context(), current)
		},
	}
}

func stop(ctx context.Context, current env) error {
	spinner := ui.Spin(text.T("Stopping", "Parando"))
	err := current.runtime.Stop(ctx)
	spinner.Stop()

	switch {
	case errors.Is(err, runtime.ErrNotRunning):
		ui.Line(ui.Faint(text.T("Heddle isn't running.", "O Heddle não está rodando.")))
		return nil
	case err != nil:
		return err
	}
	ui.Success(text.T("Stopped", "Parado"))
	return nil
}

func restartCommand() *cobra.Command {
	var flags startFlags
	command := &cobra.Command{
		Use:   "restart",
		Short: text.T("Stop and start again, in the background", "Para e inicia de novo, em segundo plano"),
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := load()
			if err != nil {
				return err
			}
			if err := stop(cmd.Context(), current); err != nil {
				return err
			}
			flags.noBrowser = true
			return runDetached(cmd.Context(), flags)
		},
	}
	command.Flags().IntVarP(&flags.port, "port", "p", 0, text.T("port to try first, for this run", "porta a tentar primeiro, só nesta execução"))
	return command
}

func statusCommand() *cobra.Command {
	var asJSON bool
	command := &cobra.Command{
		Use:   "status",
		Short: text.T("Show what's running and how it's set up", "Mostra o que está rodando e como está configurado"),
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := load()
			if err != nil {
				return err
			}
			status, err := current.runtime.Status(cmd.Context())
			if err != nil {
				return err
			}

			if asJSON {
				encoder := json.NewEncoder(os.Stdout)
				encoder.SetIndent("", "  ")
				return encoder.Encode(status)
			}
			return printStatus(current, status)
		},
	}
	command.Flags().BoolVar(&asJSON, "json", false, text.T("print as JSON", "imprime em JSON"))
	return command
}

func printStatus(current env, status runtime.Status) error {
	settings, err := current.settings()
	if err != nil {
		return err
	}

	ui.Title("Heddle", config.Version(current.layout))

	switch {
	case status.Running && status.Healthy:
		ui.Success(text.T("Running at ", "Rodando em ") + ui.Bold(status.URL))
	case status.Running:
		ui.Warning(text.T("Running, but not answering yet", "Rodando, mas ainda sem responder"))
	default:
		ui.Line(ui.Faint("○ " + text.T("Stopped", "Parado")))
	}
	ui.Blank()

	state := func(up bool) string {
		if up {
			return text.T("running", "rodando")
		}
		return text.T("stopped", "parado")
	}

	rows := [][2]string{}
	add := func(label, value string) { rows = append(rows, [2]string{label, value}) }

	if status.Running && status.PID != 0 {
		add("PID", strconv.Itoa(status.PID))
	}
	if status.Uptime > 0 {
		add(text.T("Uptime", "Tempo ativo"), status.Uptime.String())
	}
	add(text.T("Database", "Banco"), state(status.Database))
	for _, service := range status.Services {
		add(service.Name, service.State)
	}

	ai := text.T("not set", "não configurada")
	if provider := settings.Value("HEDDLE_LLM_PROVIDER"); provider != "" {
		ai = strings.TrimSpace(provider + " · " + settings.Value("HEDDLE_LLM_MODEL"))
	}
	add(text.T("AI", "IA"), ai)

	add(text.T("Folder", "Pasta"), current.layout.Home)
	if !current.docker() {
		add(text.T("Data", "Dados"), system.HumanSize(system.DirSize(current.layout.Data())))
		backups, err := install.Backups(current.layout)
		if err != nil {
			return err
		}
		add("Backups", strconv.Itoa(len(backups)))
		if install.AutostartSupported() {
			autostart := text.T("no", "não")
			if install.AutostartEnabled() {
				autostart = text.T("yes", "sim")
			}
			add(text.T("Starts with computer", "Inicia com o computador"), autostart)
		}
	}
	if version := treadleVersion(current); version != "" {
		add("Treadle", version)
	}

	ui.Rows(rows)
	ui.Blank()
	return nil
}

func treadleHome(current env) string {
	if current.manifest.Treadle != "" {
		return current.manifest.Treadle
	}
	return paths.DefaultTreadleHome()
}

func treadleVersion(current env) string {
	binary := treadle.Binary(treadleHome(current))
	if _, err := os.Stat(binary); err != nil {
		return ""
	}
	return treadle.Version(binary)
}

func logsCommand() *cobra.Command {
	var (
		follow   bool
		lines    int
		database bool
	)
	command := &cobra.Command{
		Use:   "logs",
		Short: text.T("Show the logs", "Mostra os logs"),
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := load()
			if err != nil {
				return err
			}
			return current.runtime.Logs(cmd.Context(), os.Stdout, lines, follow, database)
		},
	}
	command.Flags().BoolVarP(&follow, "follow", "f", false, text.T("keep showing new lines", "continua mostrando as novas linhas"))
	command.Flags().IntVarP(&lines, "lines", "n", 100, text.T("how many lines to show", "quantas linhas mostrar"))
	command.Flags().BoolVar(&database, "db", false, text.T("show the database log", "mostra o log do banco"))
	return command
}

func openCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "open",
		Short: text.T("Open Heddle in the browser", "Abre o Heddle no navegador"),
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := load()
			if err != nil {
				return err
			}
			status, err := current.runtime.Status(cmd.Context())
			if err != nil {
				return err
			}
			if !status.Running || status.URL == "" {
				return errors.New(text.T("Heddle isn't running. Start it with: heddle start -d", "O Heddle não está rodando. Inicie com: heddle start -d"))
			}
			if err := system.OpenBrowser(status.URL); err != nil {
				return fmt.Errorf("%s %s", text.T("Could not open a browser. The address is", "Não deu para abrir o navegador. O endereço é"), status.URL)
			}
			ui.Success(status.URL)
			return nil
		},
	}
}

func versionCommand() *cobra.Command {
	var asJSON bool
	command := &cobra.Command{
		Use:   "version",
		Short: text.T("Show the versions installed", "Mostra as versões instaladas"),
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			current, err := load()
			if err != nil {
				return err
			}

			versions := map[string]string{"cli": Version, "heddle": config.Version(current.layout), "treadle": treadleVersion(current)}
			if asJSON {
				return json.NewEncoder(os.Stdout).Encode(versions)
			}

			// The first line stays the bare version, which is what scripts read.
			heddle := versions["heddle"]
			if heddle == "" {
				heddle = Version
			}
			fmt.Println(heddle)
			if ui.Interactive() {
				ui.Rows([][2]string{{"CLI", Version}, {"Treadle", orDash(versions["treadle"])}})
			}
			return nil
		},
	}
	command.Flags().BoolVar(&asJSON, "json", false, text.T("print as JSON", "imprime em JSON"))
	return command
}

func orDash(value string) string {
	if value == "" {
		return "—"
	}
	return value
}

// clock keeps "how long ago" readable in lists.
func clock(moment time.Time) string { return moment.Format("2006-01-02 15:04") }
