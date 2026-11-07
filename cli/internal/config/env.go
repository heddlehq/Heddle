// Package config reads and writes what an install remembers: its settings, in a
// file of KEY=value lines, and the manifest describing how it was installed.
package config

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
)

var keyPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

// Env is a settings file. It keeps comments and order, so a file someone edited by
// hand survives the CLI changing one value in it.
type Env struct {
	lines []line
}

type line struct {
	raw   string
	key   string
	value string
}

// LoadEnv reads a settings file. A file that isn't there is an empty one.
func LoadEnv(path string) (*Env, error) {
	file, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return &Env{}, nil
	}
	if err != nil {
		return nil, err
	}
	defer file.Close()

	env := &Env{}
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		env.lines = append(env.lines, parseLine(scanner.Text()))
	}
	return env, scanner.Err()
}

func parseLine(raw string) line {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" || strings.HasPrefix(trimmed, "#") {
		return line{raw: raw}
	}

	key, value, found := strings.Cut(strings.TrimPrefix(trimmed, "export "), "=")
	key = strings.TrimSpace(key)
	if !found || !keyPattern.MatchString(key) {
		return line{raw: raw}
	}
	return line{raw: raw, key: key, value: unquote(strings.TrimSpace(value))}
}

func unquote(value string) string {
	if len(value) >= 2 {
		first, last := value[0], value[len(value)-1]
		if first == '\'' && last == '\'' {
			return value[1 : len(value)-1]
		}
		if first == '"' && last == '"' {
			inner := value[1 : len(value)-1]
			return strings.NewReplacer(`\\`, `\`, `\"`, `"`, `\$`, `$`).Replace(inner)
		}
	}
	return value
}

// quote wraps a value in single quotes when it needs them. Compose would read a
// `$` inside double quotes as a variable, and a key can have one.
func quote(value string) (string, error) {
	if strings.ContainsAny(value, "\n\r") {
		return "", errors.New("a value can't have line breaks")
	}
	if value == "" || !strings.ContainsAny(value, " \t#'\"$`\\") {
		return value, nil
	}
	if strings.Contains(value, "'") {
		return `"` + strings.NewReplacer(`\`, `\\`, `"`, `\"`, `$`, `\$`).Replace(value) + `"`, nil
	}
	return "'" + value + "'", nil
}

// Get returns a value, and whether it's set.
func (e *Env) Get(key string) (string, bool) {
	for _, l := range e.lines {
		if l.key == key {
			return l.value, true
		}
	}
	return "", false
}

// Value returns a value, or an empty string when it isn't set.
func (e *Env) Value(key string) string {
	value, _ := e.Get(key)
	return value
}

// Set changes a value in place, or adds it at the end.
func (e *Env) Set(key, value string) error {
	if !keyPattern.MatchString(key) {
		return fmt.Errorf("%q isn't a valid name", key)
	}
	quoted, err := quote(value)
	if err != nil {
		return err
	}

	updated := line{raw: key + "=" + quoted, key: key, value: value}
	for i, l := range e.lines {
		if l.key == key {
			e.lines[i] = updated
			return nil
		}
	}
	e.lines = append(e.lines, updated)
	return nil
}

// Unset removes a value.
func (e *Env) Unset(key string) {
	e.lines = slices.DeleteFunc(e.lines, func(l line) bool { return l.key == key })
}

// Keys lists what's set, in file order.
func (e *Env) Keys() []string {
	keys := make([]string, 0, len(e.lines))
	for _, l := range e.lines {
		if l.key != "" {
			keys = append(keys, l.key)
		}
	}
	return keys
}

// Environ returns the values as KEY=value, the way a process takes them. An empty
// value is left out: it would mask the default, like a blank line in .env.example.
func (e *Env) Environ() []string {
	var environ []string
	for _, l := range e.lines {
		if l.key != "" && l.value != "" {
			environ = append(environ, l.key+"="+l.value)
		}
	}
	return environ
}

// Save writes the file through a temporary one, so a crash can't leave half of it,
// and only this user can read it: it holds API keys.
func (e *Env) Save(path string) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}

	file, err := os.CreateTemp(dir, ".env-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())

	writer := bufio.NewWriter(file)
	for _, l := range e.lines {
		fmt.Fprintln(writer, l.raw)
	}
	if err := writer.Flush(); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(file.Name(), path)
}

// Secret says whether a setting shouldn't be printed.
func Secret(key string) bool {
	upper := strings.ToUpper(key)
	for _, word := range []string{"KEY", "TOKEN", "SECRET", "PASSWORD"} {
		if strings.Contains(upper, word) {
			return true
		}
	}
	return false
}

// Mask hides most of a secret and keeps enough to tell two keys apart.
func Mask(value string) string {
	if len(value) <= 8 {
		return strings.Repeat("•", len(value))
	}
	return value[:4] + "••••" + value[len(value)-4:]
}
