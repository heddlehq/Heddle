// The `heddle` command: installs Heddle, and then runs and maintains it.
package main

import (
	"os"

	"github.com/heddlehq/heddle/cli/internal/commands"
)

func main() {
	os.Exit(commands.Execute())
}
