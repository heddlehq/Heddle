// Package treadle installs the terminal editor and connects it to a Heddle.
package treadle

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/zalando/go-keyring"

	"github.com/heddlehq/heddle/cli/internal/paths"
	"github.com/heddlehq/heddle/cli/internal/release"
	"github.com/heddlehq/heddle/cli/internal/system"
	"github.com/heddlehq/heddle/cli/internal/text"
)

// Keep these in step with internal/tui/credentials.go in Treadle.
const (
	keyringService = "treadle"
	keyringSession = "session"
	loginAPIKey    = "api_key"
)

// Binary is where a Treadle in home keeps its command.
func Binary(home string) string {
	return filepath.Join(home, "bin", paths.Binary("treadle"))
}

// Version runs the command and returns its version, or "" when it doesn't run.
func Version(binary string) string {
	output, err := exec.Command(binary, "--version").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(string(output)), "treadle"))
}

// Install downloads Treadle into home and returns its version.
func Install(ctx context.Context, home, version string, progress release.Progress) (string, error) {
	target := system.Target(runtime.GOOS, runtime.GOARCH)
	if target == "" {
		return "", errors.New(text.T("There's no Treadle build for this system yet.", "Ainda não existe build do Treadle para este sistema."))
	}

	work, err := os.MkdirTemp("", "treadle-")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(work)

	archive := filepath.Join(work, "treadle.tar.gz")
	base := release.BaseURL(release.TreadleRepo, version, os.Getenv("TREADLE_DOWNLOAD_URL"))
	if err := release.Verified(ctx, base+"/treadle-"+target+".tar.gz", archive, progress); err != nil {
		return "", err
	}

	unpacked := filepath.Join(work, "app")
	if err := os.MkdirAll(unpacked, 0o755); err != nil {
		return "", err
	}
	if err := release.Extract(archive, unpacked); err != nil {
		return "", err
	}

	// Run it before replacing anything, so a bad build can't break a working install.
	incoming := filepath.Join(unpacked, paths.Binary("treadle"))
	installed := Version(incoming)
	if installed == "" {
		return "", errors.New(text.T("This Treadle build doesn't run on your system. Nothing was changed.", "Este build do Treadle não roda no seu sistema. Nada foi alterado."))
	}

	dest := Binary(home)
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return "", err
	}
	if err := replaceFile(incoming, dest); err != nil {
		return "", err
	}
	return installed, nil
}

// replaceFile copies through a temporary name, because the temp folder may be on
// another disk and a rename can't cross one.
func replaceFile(source, dest string) error {
	raw, err := os.ReadFile(source)
	if err != nil {
		return err
	}
	staged := dest + ".new"
	if err := os.WriteFile(staged, raw, 0o755); err != nil {
		return err
	}
	return os.Rename(staged, dest)
}

// NormalizeServer turns what a person types into an address, as Treadle does.
func NormalizeServer(server string) string {
	server = strings.TrimRight(strings.TrimSpace(server), "/")
	if server != "" && !strings.HasPrefix(server, "http://") && !strings.HasPrefix(server, "https://") {
		return "http://" + server
	}
	return server
}

// ErrUnauthorized means the server answered and refused the key.
var ErrUnauthorized = errors.New(text.T("The server refused this key.", "O servidor recusou esta chave."))

// Check tries a key against a server with the call Treadle makes first.
func Check(ctx context.Context, server, key string) error {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	target := NormalizeServer(server) + "/api/v1/workflows?page=1&per_page=1"
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", "Bearer "+key)

	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()

	switch {
	case response.StatusCode == http.StatusUnauthorized:
		return ErrUnauthorized
	case response.StatusCode < 200 || response.StatusCode >= 300:
		return fmt.Errorf("the server answered %s", response.Status)
	}
	return nil
}

type session struct {
	Host   string `json:"host"`
	Token  string `json:"token"`
	Method string `json:"method"`
}

// Connect saves a login where Treadle looks for it, so it opens already connected.
// Like Treadle, it prefers the keyring and needs none to work.
func Connect(server, key string) error {
	raw, err := json.Marshal(session{Host: NormalizeServer(server), Token: key, Method: loginAPIKey})
	if err != nil {
		return err
	}

	if keyring.Set(keyringService, keyringSession, string(raw)) == nil {
		return nil
	}

	dir, err := os.UserConfigDir()
	if err != nil {
		return err
	}
	dir = filepath.Join(dir, "treadle")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}

	file, err := os.CreateTemp(dir, "credentials-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	if _, err := file.Write(raw); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(file.Name(), filepath.Join(dir, "credentials.json"))
}
