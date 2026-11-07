package commands

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	goruntime "runtime"
	"strings"

	"github.com/spf13/cobra"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/install"
	"github.com/heddlehq/heddle/cli/internal/paths"
	"github.com/heddlehq/heddle/cli/internal/providers"
	"github.com/heddlehq/heddle/cli/internal/release"
	"github.com/heddlehq/heddle/cli/internal/runtime"
	"github.com/heddlehq/heddle/cli/internal/system"
	"github.com/heddlehq/heddle/cli/internal/text"
	"github.com/heddlehq/heddle/cli/internal/treadle"
	"github.com/heddlehq/heddle/cli/internal/ui"
)

func backupCommand() *cobra.Command {
	var keep int
	command := &cobra.Command{
		Use:   "backup",
		Short: text.T("Copy your data, list copies, restore one", "Copia seus dados, lista cópias, restaura uma"),
		Long: text.T(
			"Copies your data folder. Heddle stops for the copy and starts again after it.",
			"Copia a pasta de dados. O Heddle para durante a cópia e volta depois.",
		),
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := localOnly()
			if err != nil {
				return err
			}
			return whileStopped(cmd.Context(), current, func() error {
				spinner := ui.Spin(text.T("Copying your data", "Copiando seus dados"))
				name, err := install.CreateBackup(current.layout, keep)
				spinner.Stop()
				if err != nil {
					return err
				}
				if name == "" {
					ui.Line(ui.Faint(text.T("There's no data to copy yet.", "Ainda não há dados para copiar.")))
					return nil
				}
				ui.Success(text.T("Saved in ", "Salvo em ") + filepath.Join(current.layout.Backups(), name))
				return nil
			})
		},
	}
	command.Flags().IntVar(&keep, "keep", 0, text.T("how many copies to keep (0 keeps them all)", "quantas cópias manter (0 mantém todas)"))

	var yes bool
	restore := &cobra.Command{
		Use:   "restore NAME",
		Short: text.T("Put a copy back", "Restaura uma cópia"),
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			current, err := localOnly()
			if err != nil {
				return err
			}
			if !yes && !confirm(text.T("Replace your current data with this copy? [y/N]", "Trocar seus dados atuais por esta cópia? [s/N]")) {
				return errQuiet
			}
			return whileStopped(cmd.Context(), current, func() error {
				spinner := ui.Spin(text.T("Restoring", "Restaurando"))
				aside, err := install.RestoreBackup(current.layout, args[0])
				spinner.Stop()
				if err != nil {
					return err
				}
				ui.Success(text.T("Restored ", "Restaurado ") + args[0])
				ui.Line(ui.Faint(text.T("The data you had is in ", "Os dados que você tinha estão em ") + aside))
				return nil
			})
		},
	}
	restore.Flags().BoolVarP(&yes, "yes", "y", false, text.T("don't ask", "não pergunta"))

	list := &cobra.Command{
		Use:   "list",
		Short: text.T("List the copies", "Lista as cópias"),
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			current, err := localOnly()
			if err != nil {
				return err
			}
			backups, err := install.Backups(current.layout)
			if err != nil {
				return err
			}

			ui.Title("Backups", current.layout.Backups())
			if len(backups) == 0 {
				ui.Line(ui.Faint(text.T("No copies yet. Make one with: heddle backup", "Nenhuma cópia ainda. Faça uma com: heddle backup")))
			}
			rows := make([][2]string, 0, len(backups))
			for _, backup := range backups {
				rows = append(rows, [2]string{clock(backup.Created), backup.Name + "  " + ui.Faint(system.HumanSize(system.DirSize(backup.Path)))})
			}
			ui.Rows(rows)
			ui.Blank()
			return nil
		},
	}

	command.AddCommand(list, restore)
	return command
}

func localOnly() (env, error) {
	current, err := load()
	if err != nil {
		return env{}, err
	}
	if current.docker() {
		return env{}, errors.New(text.T(
			"Your data is in Docker volumes. Back them up with pg_dump or your own volume backups.",
			"Seus dados estão em volumes do Docker. Faça backup com pg_dump ou com seus backups de volume.",
		))
	}
	return current, nil
}

// whileStopped runs work with the database down, since a copy of a running one isn't
// consistent, and leaves Heddle as it found it.
func whileStopped(ctx context.Context, current env, work func() error) error {
	status, err := current.runtime.Status(ctx)
	if err != nil {
		return err
	}

	if status.Running || status.Database {
		if err := current.runtime.Stop(ctx); err != nil && !errors.Is(err, runtime.ErrNotRunning) {
			return err
		}
	}

	failure := work()

	if status.Running {
		spinner := ui.Spin(text.T("Starting Heddle again", "Iniciando o Heddle de novo"))
		_, err := current.runtime.Start(ctx, runtime.StartOptions{NoBrowser: true, Progress: spinner.Detail})
		spinner.Stop()
		if err != nil {
			return errors.Join(failure, err)
		}
		ui.Success(text.T("Heddle is running again", "O Heddle voltou a rodar"))
	}
	return failure
}

func confirm(question string) bool {
	if !ui.Interactive() {
		ui.Failure(text.T("Nobody to ask here. Pass --yes.", "Não há ninguém para responder aqui. Passe --yes."))
		return false
	}
	return ui.Confirm(question, "y", "yes", "s", "sim")
}

func updateCommand() *cobra.Command {
	var (
		version string
		check   bool
		force   bool
	)
	command := &cobra.Command{
		Use:   "update",
		Short: text.T("Update Heddle, Treadle and this command", "Atualiza o Heddle, o Treadle e este comando"),
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := load()
			if err != nil {
				return err
			}
			if !config.Installed(current.layout) {
				return errors.New(text.T("Heddle isn't installed here. Run: heddle install", "O Heddle não está instalado aqui. Rode: heddle install"))
			}

			ctx := cmd.Context()
			installed := config.Version(current.layout)
			target := version
			if target == "" {
				target, err = release.Latest(ctx, release.HeddleRepo)
				if err != nil {
					return err
				}
			}
			target = strings.TrimPrefix(target, "v")

			ui.Title("Heddle", installed)
			if target == installed && !force {
				ui.Success(text.T("You're on the latest version.", "Você está na versão mais recente."))
				ui.Blank()
				return updateTreadle(ctx, current, check)
			}
			ui.Line(fmt.Sprintf("%s → %s", installed, ui.Bold(target)))
			ui.Blank()
			if check {
				ui.Line(ui.Faint(text.T("To update: ", "Para atualizar: ")) + ui.Command("heddle update"))
				ui.Blank()
				return nil
			}

			status, err := current.runtime.Status(ctx)
			if err != nil {
				return err
			}

			plan := install.DefaultPlan()
			plan.Home = current.layout.Home
			plan.Mode = current.manifest.Mode
			plan.Version = target
			plan.Port = 4000
			if port, err := portOf(current); err == nil {
				plan.Port = port
			}
			plan.AddToPath = true
			plan.Browser = false
			plan.Start = status.Running

			reporter := newPlainReporter()
			result, err := install.Run(ctx, plan, reporter)
			reporter.finish()
			if err != nil {
				return err
			}

			if err := updateSelf(ctx, current, target); err != nil {
				ui.Warning(err.Error())
			}
			ui.Success(text.T("Heddle ", "Heddle ") + result.Version)
			ui.Blank()
			return updateTreadle(ctx, current, false)
		},
	}
	command.Flags().StringVar(&version, "version", "", text.T("install this version instead of the latest", "instala esta versão em vez da mais recente"))
	command.Flags().BoolVar(&check, "check", false, text.T("only say whether there's a new version", "só diz se há versão nova"))
	command.Flags().BoolVar(&force, "force", false, text.T("install even if it's the same version", "instala mesmo sendo a mesma versão"))
	return command
}

// updateSelf replaces this binary with the one published for a version. Releases from
// before this command existed don't have it, and that's not an error.
func updateSelf(ctx context.Context, current env, version string) error {
	target := system.Target(goruntime.GOOS, goruntime.GOARCH)
	base := release.BaseURL(release.HeddleRepo, version, os.Getenv("HEDDLE_DOWNLOAD_URL"))
	url := base + "/heddle-cli-" + target
	if goruntime.GOOS == "windows" {
		url += ".exe"
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodHead, url, nil)
	if err != nil {
		return err
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return err
	}
	response.Body.Close()
	if response.StatusCode == http.StatusNotFound {
		return nil
	}

	work, err := os.MkdirTemp("", "heddle-cli-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(work)

	file := filepath.Join(work, "heddle")
	if err := release.Verified(ctx, url, file, nil); err != nil {
		return err
	}
	return install.ReplaceBinary(file, filepath.Join(current.layout.Bin(), paths.Binary("heddle")))
}

func updateTreadle(ctx context.Context, current env, check bool) error {
	home := treadleHome(current)
	installed := treadleVersion(current)
	if installed == "" {
		return nil
	}

	latest, err := release.Latest(ctx, release.TreadleRepo)
	if err != nil {
		return err
	}
	if latest == installed {
		ui.Success("Treadle " + installed)
		ui.Blank()
		return nil
	}
	if check {
		ui.Line(fmt.Sprintf("Treadle %s → %s", installed, ui.Bold(latest)))
		ui.Blank()
		return nil
	}

	spinner := ui.Spin(text.T("Updating Treadle", "Atualizando o Treadle"))
	version, err := treadle.Install(ctx, home, latest, nil)
	spinner.Stop()
	if err != nil {
		return err
	}
	ui.Success("Treadle " + version)
	ui.Blank()
	return nil
}

func uninstallCommand() *cobra.Command {
	var (
		keepData bool
		yes      bool
		removeTr bool
	)
	command := &cobra.Command{
		Use:   "uninstall",
		Short: text.T("Remove Heddle from this computer", "Remove o Heddle deste computador"),
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := load()
			if err != nil {
				return err
			}
			if !config.Installed(current.layout) {
				return errors.New(text.T("Heddle isn't installed in ", "O Heddle não está instalado em ") + current.layout.Home)
			}

			ui.Title(text.T("Uninstall", "Desinstalar"), current.layout.Home)
			if keepData {
				ui.Line(text.T("Removes the program. Your data and settings stay.", "Remove o programa. Seus dados e configurações ficam."))
			} else {
				ui.Warning(text.T("Removes the program and ", "Remove o programa e ") + ui.Bold(text.T("all your data", "todos os seus dados")) +
					" (" + system.HumanSize(system.DirSize(current.layout.Home)) + "), " + text.T("backups included.", "backups inclusive."))
			}
			ui.Blank()

			if !yes && !confirm(text.T("Go ahead? [y/N]", "Continuar? [s/N]")) {
				return errQuiet
			}
			return uninstall(cmd.Context(), current, keepData, removeTr)
		},
	}
	command.Flags().BoolVar(&keepData, "keep-data", false, text.T("keep your data, backups and settings", "mantém seus dados, backups e configurações"))
	command.Flags().BoolVar(&removeTr, "treadle", false, text.T("remove Treadle too", "remove o Treadle também"))
	command.Flags().BoolVarP(&yes, "yes", "y", false, text.T("don't ask", "não pergunta"))
	return command
}

func uninstall(ctx context.Context, current env, keepData, removeTreadle bool) error {
	if err := current.runtime.Stop(ctx); err != nil && !errors.Is(err, runtime.ErrNotRunning) {
		return err
	}
	if err := install.DisableAutostart(); err != nil {
		ui.Warning(err.Error())
	}
	if err := system.RemoveFromPath(current.layout.Bin(), current.layout.App()); err != nil {
		ui.Warning(err.Error())
	}

	if current.docker() {
		args := []string{"down"}
		if !keepData {
			args = append(args, "--volumes", "--rmi", "local")
		}
		docker := &runtime.Docker{Layout: current.layout}
		if output, err := docker.Compose(ctx, args...).CombinedOutput(); err != nil {
			return fmt.Errorf("%w\n\n%s", err, output)
		}
	}

	if keepData {
		for _, path := range []string{current.layout.App(), current.layout.Bin(), filepath.Join(current.layout.Docker(), "src")} {
			if err := os.RemoveAll(path); err != nil {
				return err
			}
		}
	} else if err := os.RemoveAll(current.layout.Home); err != nil {
		return err
	}

	if removeTreadle {
		home := treadleHome(current)
		if err := system.RemoveFromPath(filepath.Join(home, "bin")); err != nil {
			ui.Warning(err.Error())
		}
		if err := os.RemoveAll(home); err != nil {
			return err
		}
	}

	ui.Success(text.T("Removed", "Removido"))
	ui.Blank()
	return nil
}

func portOf(current env) (int, error) {
	settings, err := current.settings()
	if err != nil {
		return 0, err
	}
	key := "PORT"
	if current.docker() {
		key = "HEDDLE_PORT"
	}
	value := settings.Value(key)
	if value == "" {
		return 4000, nil
	}
	var port int
	_, err = fmt.Sscanf(value, "%d", &port)
	return port, err
}

func doctorCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "doctor",
		Short: text.T("Check that everything is in order", "Confere se está tudo em ordem"),
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			current, err := load()
			if err != nil {
				return err
			}
			ui.Title(text.T("Doctor", "Diagnóstico"), current.layout.Home)
			failures := diagnose(cmd.Context(), current)
			ui.Blank()
			if failures > 0 {
				return errQuiet
			}
			ui.Success(text.T("All good.", "Tudo certo."))
			ui.Blank()
			return nil
		},
	}
}

const minFreeDisk = 2 * 1024 * 1024 * 1024

func diagnose(ctx context.Context, current env) int {
	failures := 0
	ok := ui.Success
	warn := ui.Warning
	bad := func(message, fix string) {
		failures++
		ui.Line(ui.Accent("✕") + " " + message)
		if fix != "" {
			ui.Line("  " + ui.Faint(fix))
		}
	}

	facts := system.Detect()

	if !config.Installed(current.layout) {
		bad(text.T("Heddle isn't installed here", "O Heddle não está instalado aqui"), "heddle install")
		return failures
	}
	ok(fmt.Sprintf("Heddle %s (%s)", config.Version(current.layout), current.manifest.Mode))

	if current.docker() {
		if facts.Docker {
			ok(text.T("Docker is running", "O Docker está rodando"))
		} else {
			bad(text.T("Docker isn't running", "O Docker não está rodando"), "")
		}
	} else {
		if problem := facts.NativeProblem(text.T); problem != "" {
			bad(problem, "")
		}
		if !paths.Supported(current.layout.Home) {
			bad(text.T("The install folder has accents in its name", "A pasta da instalação tem acentos no nome"), "HEDDLE_HOME")
		}
		diagnoseDatabase(current, bad, ok)
	}

	if free, err := system.FreeDisk(current.layout.Home); err == nil {
		if free < minFreeDisk {
			warn(text.T("Little disk space left: ", "Pouco espaço em disco: ") + system.HumanSize(int64(free)))
		} else {
			ok(system.HumanSize(int64(free)) + text.T(" free on disk", " livres em disco"))
		}
	}

	status, err := current.runtime.Status(ctx)
	switch {
	case err != nil:
		bad(err.Error(), "")
	case status.Running && status.Healthy:
		ok(text.T("Answering at ", "Respondendo em ") + status.URL)
	case status.Running:
		bad(text.T("Running, but not answering", "Rodando, mas sem responder"), "heddle logs -n 50")
	default:
		warn(text.T("Not running", "Não está rodando"))
	}

	if !current.docker() {
		if info, err := os.Stat(current.layout.EnvFile(false)); err == nil && goruntime.GOOS != "windows" && info.Mode().Perm()&0o077 != 0 {
			bad(text.T("Other users can read your settings, which hold API keys", "Outros usuários podem ler suas configurações, que têm chaves de API"),
				"chmod 600 "+current.layout.EnvFile(false))
		}
	}

	diagnoseAI(ctx, current, bad, ok, warn)

	if version := treadleVersion(current); version != "" {
		ok("Treadle " + version)
	}
	if latest, err := release.Latest(ctx, release.HeddleRepo); err == nil {
		if latest != config.Version(current.layout) {
			warn(text.T("Heddle ", "Heddle ") + latest + text.T(" is out: ", " saiu: ") + ui.Command("heddle update"))
		}
	} else {
		warn(text.T("Could not check for updates", "Não deu para procurar atualizações"))
	}
	return failures
}

func diagnoseDatabase(current env, bad func(string, string), ok func(string)) {
	raw, err := os.ReadFile(filepath.Join(current.layout.Cluster(), "PG_VERSION"))
	if err != nil {
		ok(text.T("The database gets created on the first start", "O banco é criado na primeira inicialização"))
		return
	}
	ok("Postgres " + strings.TrimSpace(string(raw)))

	info, err := os.Stat(current.layout.Cluster())
	if err == nil && goruntime.GOOS != "windows" && info.Mode().Perm()&0o077 != 0 {
		bad(text.T("Postgres refuses a data folder others can read", "O Postgres recusa uma pasta de dados que outros podem ler"), "chmod 700 "+current.layout.Cluster())
	}
}

func diagnoseAI(ctx context.Context, current env, bad func(string, string), ok, warn func(string)) {
	settings, err := current.settings()
	if err != nil {
		bad(err.Error(), "")
		return
	}

	id := settings.Value("HEDDLE_LLM_PROVIDER")
	if id == "" {
		warn(text.T("No AI set in the settings. The AI page can have one: ", "Nenhuma IA nas configurações. A página de IA pode ter uma: ") + ui.Command("heddle setup"))
		return
	}

	provider, known := providers.Find(id)
	if !known {
		ok(text.T("AI: ", "IA: ") + id)
		return
	}

	_, err = provider.Check(ctx, settings.Value("HEDDLE_LLM_API_KEY"))
	switch {
	case err == nil:
		ok(text.T("AI: ", "IA: ") + provider.Name + text.T(" accepts your key", " aceita sua chave"))
	case errors.Is(err, providers.ErrRejected):
		bad(text.T("AI: ", "IA: ")+provider.Name+text.T(" refused your key", " recusou sua chave"), "heddle setup")
	default:
		warn(text.T("AI: could not reach ", "IA: não deu para falar com a ") + provider.Name)
	}
}
