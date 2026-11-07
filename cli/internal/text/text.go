// Package text picks the language of everything the CLI says. English and
// Brazilian Portuguese live side by side at the call site, so a message can't
// lose its translation by drifting away from a catalog.
package text

import (
	"os"
	"strings"
)

var portuguese = detect(os.Getenv)

func detect(env func(string) string) bool {
	for _, name := range []string{"HEDDLE_LANG", "LC_ALL", "LC_MESSAGES", "LANG"} {
		if value := env(name); value != "" {
			return strings.HasPrefix(strings.ToLower(value), "pt")
		}
	}
	return false
}

// SetLanguage overrides what the environment says. Anything starting with "pt" is
// Portuguese and the rest is English.
func SetLanguage(language string) {
	portuguese = strings.HasPrefix(strings.ToLower(language), "pt")
}

// T returns the message in the current language.
func T(en, pt string) string {
	if portuguese {
		return pt
	}
	return en
}
