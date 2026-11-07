package commands

import (
	"errors"
	"fmt"
	"os"
	"slices"
	"strings"

	"github.com/spf13/cobra"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/install"
	"github.com/heddlehq/heddle/cli/internal/text"
	"github.com/heddlehq/heddle/cli/internal/ui"
)

// The bundled install works these out on every boot, so a value here would be
// silently replaced.
var managedKeys = []string{"DATABASE_URL", "SECRET_KEY_BASE", "PHX_SERVER"}

func configCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "config",
		Short: text.T("See and change the settings", "Vê e muda as configurações"),
		Args:  cobra.NoArgs,
		RunE:  func(*cobra.Command, []string) error { return listConfig(false) },
	}

	var reveal bool
	list := &cobra.Command{
		Use:   "list",
		Short: text.T("List the settings, with secrets hidden", "Lista as configurações, com segredos ocultos"),
		Args:  cobra.NoArgs,
		RunE:  func(*cobra.Command, []string) error { return listConfig(reveal) },
	}
	list.Flags().BoolVar(&reveal, "reveal", false, text.T("show the secrets too", "mostra os segredos também"))

	get := &cobra.Command{
		Use:   "get KEY",
		Short: text.T("Print one setting", "Imprime uma configuração"),
		Args:  cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			current, err := load()
			if err != nil {
				return err
			}
			settings, err := current.settings()
			if err != nil {
				return err
			}
			value, ok := settings.Get(args[0])
			if !ok {
				return fmt.Errorf("%s: %s", text.T("Not set", "Não configurado"), args[0])
			}
			fmt.Println(value)
			return nil
		},
	}

	set := &cobra.Command{
		Use:     "set KEY=VALUE...",
		Short:   text.T("Change settings", "Muda configurações"),
		Example: "heddle config set PORT=4100\nheddle config set HEDDLE_LLM_PROVIDER=anthropic HEDDLE_LLM_MODEL=claude-sonnet-5-5",
		Args:    cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			current, err := load()
			if err != nil {
				return err
			}
			settings, err := current.settings()
			if err != nil {
				return err
			}

			for _, pair := range args {
				key, value, found := strings.Cut(pair, "=")
				if !found {
					return fmt.Errorf("%s: %s", text.T("Expected KEY=VALUE", "Esperava KEY=VALOR"), pair)
				}
				if !current.docker() && slices.Contains(managedKeys, key) {
					return fmt.Errorf("%s: %s", text.T("Heddle manages this one by itself", "O Heddle cuida desta sozinho"), key)
				}
				if err := settings.Set(key, value); err != nil {
					return err
				}
			}
			if err := current.saveSettings(settings); err != nil {
				return err
			}
			ui.Success(text.T("Saved", "Salvo"))
			return restartHint(cmd, current)
		},
	}

	unset := &cobra.Command{
		Use:   "unset KEY...",
		Short: text.T("Remove settings", "Remove configurações"),
		Args:  cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			current, err := load()
			if err != nil {
				return err
			}
			settings, err := current.settings()
			if err != nil {
				return err
			}
			for _, key := range args {
				settings.Unset(key)
			}
			if err := current.saveSettings(settings); err != nil {
				return err
			}
			ui.Success(text.T("Removed", "Removido"))
			return restartHint(cmd, current)
		},
	}

	path := &cobra.Command{
		Use:   "path",
		Short: text.T("Print where the settings file is", "Imprime onde fica o arquivo de configurações"),
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			current, err := load()
			if err != nil {
				return err
			}
			fmt.Println(current.layout.EnvFile(current.docker()))
			return nil
		},
	}

	command.AddCommand(list, get, set, unset, path)
	return command
}

func listConfig(reveal bool) error {
	current, err := load()
	if err != nil {
		return err
	}
	settings, err := current.settings()
	if err != nil {
		return err
	}

	ui.Title(text.T("Settings", "Configurações"), current.layout.EnvFile(current.docker()))
	keys := settings.Keys()
	if len(keys) == 0 {
		ui.Line(ui.Faint(text.T("Nothing set. Heddle is using its defaults.", "Nada configurado. O Heddle está usando os padrões.")))
		ui.Blank()
		return nil
	}

	rows := make([][2]string, 0, len(keys))
	for _, key := range keys {
		value := settings.Value(key)
		if config.Secret(key) && !reveal {
			value = config.Mask(value)
		}
		rows = append(rows, [2]string{key, value})
	}
	ui.Rows(rows)
	ui.Blank()
	return nil
}

func restartHint(cmd *cobra.Command, current env) error {
	status, err := current.runtime.Status(cmd.Context())
	if err == nil && status.Running {
		ui.Line(ui.Faint(text.T("Restart to apply: ", "Reinicie para aplicar: ")) + ui.Command("heddle restart"))
	}
	return nil
}

func autostartCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "autostart",
		Short: text.T("Start Heddle with this computer", "Inicia o Heddle com o computador"),
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			if !install.AutostartSupported() {
				return errors.New(text.T("Starting with the computer needs systemd.", "Iniciar com o computador precisa do systemd."))
			}
			if install.AutostartEnabled() {
				ui.Success(text.T("Heddle starts with this computer.", "O Heddle inicia com o computador."))
			} else {
				ui.Line(ui.Faint(text.T("Heddle doesn't start with this computer.", "O Heddle não inicia com o computador.")))
			}
			return nil
		},
	}

	command.AddCommand(
		&cobra.Command{
			Use:   "on",
			Short: text.T("Turn it on", "Liga"),
			Args:  cobra.NoArgs,
			RunE: func(*cobra.Command, []string) error {
				current, err := load()
				if err != nil {
					return err
				}
				if current.docker() {
					return errors.New(text.T("Docker containers already come back on their own.", "Os containers do Docker já voltam sozinhos."))
				}
				if _, err := os.Stat(current.layout.Bin()); err != nil {
					return errors.New(text.T("Install Heddle first: heddle install", "Instale o Heddle primeiro: heddle install"))
				}
				if err := install.EnableAutostart(current.layout); err != nil {
					return err
				}
				ui.Success(text.T("Heddle now starts with this computer.", "O Heddle agora inicia com o computador."))
				return nil
			},
		},
		&cobra.Command{
			Use:   "off",
			Short: text.T("Turn it off", "Desliga"),
			Args:  cobra.NoArgs,
			RunE: func(*cobra.Command, []string) error {
				if err := install.DisableAutostart(); err != nil {
					return err
				}
				ui.Success(text.T("Heddle no longer starts with this computer.", "O Heddle não inicia mais com o computador."))
				return nil
			},
		},
	)
	return command
}
