// Package commands is the `heddle` command line.
package commands

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"strings"

	"charm.land/lipgloss/v2"
	"github.com/spf13/cobra"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/paths"
	"github.com/heddlehq/heddle/cli/internal/runtime"
	"github.com/heddlehq/heddle/cli/internal/text"
	"github.com/heddlehq/heddle/cli/internal/ui"
)

// Version is set when the binary is built.
var Version = "dev"

const (
	groupRun      = "run"
	groupSetup    = "setup"
	groupMaintain = "maintain"
)

// errQuiet ends a command that has already said what went wrong.
var errQuiet = errors.New("")

type env struct {
	layout   paths.Layout
	manifest config.Manifest
	runtime  runtime.Runtime
}

// load finds the install, for the commands that act on one.
func load() (env, error) {
	layout := paths.Resolve()
	manifest, err := config.LoadManifest(layout)
	if err != nil {
		return env{}, err
	}
	return env{layout: layout, manifest: manifest, runtime: runtime.For(layout, manifest)}, nil
}

func (e env) docker() bool { return e.manifest.Mode == config.ModeDocker }

func (e env) settings() (*config.Env, error) { return config.LoadEnv(e.layout.EnvFile(e.docker())) }

func (e env) saveSettings(settings *config.Env) error {
	return settings.Save(e.layout.EnvFile(e.docker()))
}

// Execute runs the command line and returns the exit code.
func Execute() int {
	// The help is written when the commands are built, before flags are parsed.
	applyLanguage(os.Args[1:])

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	root := newRoot()
	if err := root.ExecuteContext(ctx); err != nil {
		if !errors.Is(err, errQuiet) && !errors.Is(err, context.Canceled) {
			ui.Failure(err.Error())
		}
		return 1
	}
	return 0
}

func applyLanguage(args []string) {
	for index, arg := range args {
		if value, found := strings.CutPrefix(arg, "--lang="); found {
			text.SetLanguage(value)
		} else if arg == "--lang" && index+1 < len(args) {
			text.SetLanguage(args[index+1])
		}
	}
}

func newRoot() *cobra.Command {
	var language string

	// In the order a person reaches for them, not the alphabet's.
	cobra.EnableCommandSorting = false

	root := &cobra.Command{
		Use:           "heddle",
		Short:         text.T("The logic behind your business.", "A lógica por trás do seu negócio."),
		SilenceErrors: true,
		SilenceUsage:  true,
		Args:          cobra.NoArgs,
		// `heddle` alone has always started it.
		RunE: func(cmd *cobra.Command, _ []string) error { return runForeground(cmd.Context(), startFlags{}) },
	}
	root.PersistentFlags().StringVar(&language, "lang", "", text.T("language of the output: en or pt", "idioma da saída: en ou pt"))

	root.AddGroup(
		&cobra.Group{ID: groupRun, Title: text.T("Run", "Executar")},
		&cobra.Group{ID: groupSetup, Title: text.T("Set up", "Configurar")},
		&cobra.Group{ID: groupMaintain, Title: text.T("Maintain", "Manter")},
	)

	add := func(group string, commands ...*cobra.Command) {
		for _, command := range commands {
			command.GroupID = group
			root.AddCommand(command)
		}
	}
	add(groupRun, startCommand(), stopCommand(), restartCommand(), statusCommand(), logsCommand(), openCommand())
	add(groupSetup, installCommand(), setupCommand(), configCommand(), autostartCommand())
	add(groupMaintain, doctorCommand(), updateCommand(), backupCommand(), uninstallCommand(), versionCommand())

	root.SetHelpCommandGroupID(groupMaintain)
	root.SetCompletionCommandGroupID(groupMaintain)
	root.SetHelpFunc(help)

	root.InitDefaultCompletionCmd()
	for _, command := range root.Commands() {
		if command.Name() == "completion" {
			command.Short = text.T("Generate shell completions", "Gera o autocompletar do shell")
		}
	}
	translateHelpFlag(root)
	return root
}

func translateHelpFlag(command *cobra.Command) {
	command.InitDefaultHelpFlag()
	command.Flags().Lookup("help").Usage = text.T("show this help", "mostra esta ajuda")
	for _, child := range command.Commands() {
		translateHelpFlag(child)
	}
}

func help(cmd *cobra.Command, _ []string) {
	out := cmd.OutOrStdout()
	ui.Title(cmd.CommandPath(), Version)

	if cmd.Long != "" {
		ui.Line(strings.ReplaceAll(cmd.Long, "\n", "\n  "))
	} else if cmd.Short != "" {
		ui.Line(cmd.Short)
	}
	ui.Blank()

	if cmd.Runnable() && cmd.HasParent() {
		ui.Line(ui.Faint(text.T("Usage", "Uso")))
		ui.Line("  " + cmd.UseLine())
		ui.Blank()
	}

	if cmd.HasAvailableSubCommands() {
		printed := false
		for _, group := range cmd.Groups() {
			printed = true
			printCommands(cmd, group.ID, group.Title)
		}
		if !printed {
			printCommands(cmd, "", text.T("Commands", "Comandos"))
		}
	}

	if cmd.HasAvailableLocalFlags() {
		ui.Line(ui.Faint(text.T("Options", "Opções")))
		for line := range strings.SplitSeq(strings.TrimRight(cmd.LocalFlags().FlagUsages(), "\n"), "\n") {
			lipgloss.Fprintln(out, "  "+line)
		}
		ui.Blank()
	}
	if cmd.Example != "" {
		ui.Line(ui.Faint(text.T("Examples", "Exemplos")))
		for line := range strings.SplitSeq(cmd.Example, "\n") {
			ui.Line("  " + line)
		}
		ui.Blank()
	}
}

func printCommands(cmd *cobra.Command, group, title string) {
	ui.Line(ui.Faint(title))
	for _, child := range cmd.Commands() {
		if child.GroupID == group && child.IsAvailableCommand() {
			ui.Line(fmt.Sprintf("  %s %s", ui.Accent(fmt.Sprintf("%-11s", child.Name())), child.Short))
		}
	}
	ui.Blank()
}
