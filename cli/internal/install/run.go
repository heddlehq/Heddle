package install

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	goruntime "runtime"
	"strings"
	"time"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/paths"
	"github.com/heddlehq/heddle/cli/internal/release"
	"github.com/heddlehq/heddle/cli/internal/runtime"
	"github.com/heddlehq/heddle/cli/internal/system"
	"github.com/heddlehq/heddle/cli/internal/text"
	"github.com/heddlehq/heddle/cli/internal/treadle"
)

// Reporter hears how an install is going. The wizard draws it and the plain output
// prints it.
type Reporter interface {
	// Step announces the step that begins now.
	Step(title string)
	// Done closes the current step, with what it did.
	Done(detail string)
	// Warn says something didn't work and the install is going on anyway.
	Warn(message string)
	// Progress is how far the current step is, from 0 to 1, or negative when unknown.
	Progress(fraction float64, detail string)
}

// Result is what the end of an install has to show.
type Result struct {
	Version        string
	TreadleVersion string
	URL            string
	Profile        string // The shell file that got the PATH line.
	BackupName     string
	Upgraded       bool
}

// Run carries out a plan.
func Run(ctx context.Context, plan Plan, reporter Reporter) (Result, error) {
	var result Result

	if plan.Heddle {
		var err error
		if plan.Docker() {
			err = installDocker(ctx, plan, reporter, &result)
		} else {
			err = installLocal(ctx, plan, reporter, &result)
		}
		if err != nil {
			return result, err
		}
	}

	if plan.Treadle {
		if err := installTreadle(ctx, plan, reporter, &result); err != nil {
			return result, err
		}
	}

	if plan.Heddle && plan.Start {
		reporter.Step(text.T("Starting Heddle", "Iniciando o Heddle"))
		manifest, err := config.LoadManifest(plan.Layout())
		if err != nil {
			return result, err
		}
		url, err := runtime.For(plan.Layout(), manifest).Start(ctx, runtime.StartOptions{
			NoBrowser: !plan.Browser,
			Progress:  func(line string) { reporter.Progress(-1, line) },
		})
		if err != nil {
			return result, err
		}
		result.URL = url
		reporter.Done(url)
	}
	return result, nil
}

func installLocal(ctx context.Context, plan Plan, reporter Reporter, result *Result) error {
	layout := plan.Layout()
	target := system.Target(goruntime.GOOS, goruntime.GOARCH)
	archive := "heddle-" + target + ".tar.gz"
	base := release.BaseURL(release.HeddleRepo, plan.Version, os.Getenv("HEDDLE_DOWNLOAD_URL"))

	if err := os.MkdirAll(layout.Home, 0o755); err != nil {
		return err
	}
	if err := system.Protect(layout.Home); err != nil {
		return err
	}

	// Staged next to the install, so the final move is a rename on the same disk.
	staging, err := os.MkdirTemp(layout.Home, ".install-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(staging)

	reporter.Step(text.T("Downloading Heddle", "Baixando o Heddle"))
	file := filepath.Join(staging, archive)
	if err := release.Verified(ctx, base+"/"+archive, file, progressOf(reporter)); err != nil {
		return err
	}
	reporter.Done(target)

	reporter.Step(text.T("Unpacking", "Descompactando"))
	incoming := filepath.Join(staging, "app")
	if err := os.MkdirAll(incoming, 0o755); err != nil {
		return err
	}
	if err := release.Extract(file, incoming); err != nil {
		return err
	}
	_ = os.Remove(file)
	if err := checkPostgres(layout, incoming); err != nil {
		return err
	}
	reporter.Done("")

	// An update replaces the program and leaves the data alone. The database has to
	// be stopped for the copy of it to be consistent.
	result.Upgraded = config.Installed(layout)
	if result.Upgraded {
		reporter.Step(text.T("Stopping the running Heddle", "Parando o Heddle em execução"))
		local := &runtime.Local{Layout: layout}
		if err := local.Stop(ctx); err != nil && !errors.Is(err, runtime.ErrNotRunning) {
			return err
		}
		reporter.Done("")

		reporter.Step(text.T("Backing up your data", "Fazendo backup dos dados"))
		name, err := CreateBackup(layout, plan.BackupKeep)
		if err != nil {
			return err
		}
		result.BackupName = name
		reporter.Done(name)
	}

	reporter.Step(text.T("Installing", "Instalando"))
	if err := swapApp(layout, incoming); err != nil {
		return err
	}
	result.Version = config.Version(layout)

	if err := writeSettings(plan); err != nil {
		return err
	}
	if err := installSelf(layout); err != nil {
		return err
	}
	reporter.Done(result.Version)

	if err := finishShell(plan, reporter, result); err != nil {
		return err
	}
	return nil
}

// checkPostgres stops here, before anything changed: a major Postgres version can't
// open the data of another one.
func checkPostgres(layout paths.Layout, incoming string) error {
	raw, err := os.ReadFile(filepath.Join(layout.Cluster(), "PG_VERSION"))
	if err != nil {
		return nil
	}
	current := strings.TrimSpace(string(raw))

	output, err := exec.Command(filepath.Join(incoming, "pgsql", "bin", paths.Binary("postgres")), "--version").Output()
	if err != nil {
		return err
	}
	fields := strings.Fields(string(output))
	if len(fields) == 0 {
		return errors.New("postgres --version printed nothing")
	}
	major, _, _ := strings.Cut(fields[len(fields)-1], ".")
	if major != current {
		return errors.New(text.T(
			"This version of Heddle needs Postgres "+major+", and your data is on Postgres "+current+". Nothing was changed.",
			"Esta versão do Heddle precisa do Postgres "+major+", e seus dados estão no Postgres "+current+". Nada foi alterado.",
		))
	}
	return nil
}

// swapApp moves the old program aside first, so a failed move can put it back.
func swapApp(layout paths.Layout, incoming string) error {
	app := layout.App()
	aside := app + ".old"
	_ = os.RemoveAll(aside)

	hadApp := true
	if err := os.Rename(app, aside); err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return err
		}
		hadApp = false
	}
	if err := os.Rename(incoming, app); err != nil {
		if hadApp {
			_ = os.Rename(aside, app)
		}
		return err
	}

	// The command now lives in bin, and survives this folder being replaced.
	_ = os.Remove(filepath.Join(app, "heddle"))
	_ = os.Remove(filepath.Join(app, "heddle.cmd"))
	return os.RemoveAll(aside)
}

func writeSettings(plan Plan) error {
	layout := plan.Layout()
	path := layout.EnvFile(plan.Docker())

	settings, err := config.LoadEnv(path)
	if err != nil {
		return err
	}
	if err := plan.Settings(settings); err != nil {
		return err
	}
	if err := settings.Save(path); err != nil {
		return err
	}

	manifest, err := config.LoadManifest(layout)
	if err != nil {
		return err
	}
	manifest.Mode = plan.Mode
	if manifest.InstalledAt.IsZero() {
		manifest.InstalledAt = time.Now()
	}
	if plan.Treadle {
		manifest.Treadle = plan.TreadleHome
	}
	return config.SaveManifest(layout, manifest)
}

// installSelf leaves this binary in the install, where it becomes the `heddle` command.
func installSelf(layout paths.Layout) error {
	source, err := os.Executable()
	if err != nil {
		return err
	}
	dest := filepath.Join(layout.Bin(), paths.Binary("heddle"))
	if resolved, err := filepath.EvalSymlinks(source); err == nil {
		source = resolved
	}
	if source == dest {
		return nil
	}

	if err := os.MkdirAll(layout.Bin(), 0o755); err != nil {
		return err
	}
	return ReplaceBinary(source, dest)
}

// ReplaceBinary puts a command in place, even the one running: Windows won't
// overwrite a running file, but lets it be renamed out of the way.
func ReplaceBinary(source, dest string) error {
	raw, err := os.ReadFile(source)
	if err != nil {
		return err
	}
	staged := dest + ".new"
	if err := os.WriteFile(staged, raw, 0o755); err != nil {
		return err
	}
	if goruntime.GOOS == "windows" {
		_ = os.Remove(dest + ".old")
		_ = os.Rename(dest, dest+".old")
	}
	return os.Rename(staged, dest)
}

func finishShell(plan Plan, reporter Reporter, result *Result) error {
	layout := plan.Layout()
	if plan.AddToPath {
		profile, err := system.AddToPath(layout.Bin(), "Heddle")
		if err != nil {
			reporter.Warn(err.Error())
		}
		result.Profile = profile
	}
	if plan.Autostart {
		reporter.Step(text.T("Setting up the start with this computer", "Configurando o início com o computador"))
		if err := EnableAutostart(layout); err != nil {
			reporter.Warn(err.Error())
		}
		reporter.Done("")
	}
	return nil
}

func installDocker(ctx context.Context, plan Plan, reporter Reporter, result *Result) error {
	layout := plan.Layout()
	docker := &runtime.Docker{Layout: layout}

	version := plan.Version
	if version == "" {
		latest, err := release.Latest(ctx, release.HeddleRepo)
		if err != nil {
			return err
		}
		version = latest
	}

	if err := os.MkdirAll(layout.Docker(), 0o755); err != nil {
		return err
	}
	staging, err := os.MkdirTemp(layout.Docker(), ".install-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(staging)

	reporter.Step(text.T("Downloading the source", "Baixando o código"))
	url := "https://github.com/" + release.HeddleRepo + "/archive/refs/tags/v" + strings.TrimPrefix(version, "v") + ".tar.gz"
	file := filepath.Join(staging, "source.tar.gz")
	if err := release.Download(ctx, url, file, progressOf(reporter)); err != nil {
		return err
	}
	unpacked := filepath.Join(staging, "unpacked")
	if err := os.MkdirAll(unpacked, 0o755); err != nil {
		return err
	}
	if err := release.Extract(file, unpacked); err != nil {
		return err
	}
	entries, err := os.ReadDir(unpacked)
	if err != nil || len(entries) != 1 {
		return errors.New(text.T("The source archive isn't what was expected.", "O arquivo do código não veio como esperado."))
	}

	source := filepath.Join(layout.Docker(), "src")
	if err := os.RemoveAll(source); err != nil {
		return err
	}
	if err := os.Rename(filepath.Join(unpacked, entries[0].Name()), source); err != nil {
		return err
	}
	reporter.Done(version)
	result.Version = version

	if err := writeSettings(plan); err != nil {
		return err
	}
	if err := installSelf(layout); err != nil {
		return err
	}

	reporter.Step(text.T("Building the image. This takes a few minutes", "Construindo a imagem. Leva alguns minutos"))
	build := docker.Compose(ctx, "build")
	if err := streamCommand(build, reporter); err != nil {
		return fmt.Errorf("docker compose build: %w", err)
	}
	reporter.Done("")

	return finishShell(plan, reporter, result)
}

func installTreadle(ctx context.Context, plan Plan, reporter Reporter, result *Result) error {
	reporter.Step(text.T("Installing Treadle", "Instalando o Treadle"))
	version, err := treadle.Install(ctx, plan.TreadleHome, plan.TreadleVersion, progressOf(reporter))
	if err != nil {
		return err
	}
	result.TreadleVersion = version
	reporter.Done(version)

	if plan.AddToPath {
		if profile, err := system.AddToPath(filepath.Join(plan.TreadleHome, "bin"), "Treadle"); err != nil {
			reporter.Warn(err.Error())
		} else if profile != "" {
			result.Profile = profile
		}
	}

	if plan.TreadleServer != "" && plan.TreadleKey != "" {
		if err := treadle.Connect(plan.TreadleServer, plan.TreadleKey); err != nil {
			reporter.Warn(err.Error())
		}
	}
	return nil
}

func progressOf(reporter Reporter) release.Progress {
	return func(done, total int64) {
		detail := system.HumanSize(done)
		if total <= 0 {
			reporter.Progress(-1, detail)
			return
		}
		reporter.Progress(float64(done)/float64(total), detail+" / "+system.HumanSize(total))
	}
}
