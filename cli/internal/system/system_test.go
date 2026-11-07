//go:build !windows

package system

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func profile(t *testing.T, content string) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("SHELL", "/bin/zsh")
	t.Setenv("PATH", "/usr/bin")
	path := filepath.Join(home, ".zshrc")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestAddToPathOnlyOnce(t *testing.T) {
	path := profile(t, "alias ll='ls -l'\n")

	for range 2 {
		if _, err := AddToPath("/opt/heddle/bin", "Heddle"); err != nil {
			t.Fatal(err)
		}
	}

	raw, _ := os.ReadFile(path)
	if got := strings.Count(string(raw), "/opt/heddle/bin"); got != 1 {
		t.Fatalf("written %d times:\n%s", got, raw)
	}
}

func TestRemoveFromPathLeavesTheRest(t *testing.T) {
	path := profile(t, "alias ll='ls -l'\n# A note of mine\nexport EDITOR=vim\n\n# Heddle\nexport PATH=\"/opt/heddle/app:$PATH\"\n\n# Heddle\nexport PATH=\"/opt/heddle/bin:$PATH\"\n")

	if err := RemoveFromPath("/opt/heddle/bin", "/opt/heddle/app"); err != nil {
		t.Fatal(err)
	}

	raw, _ := os.ReadFile(path)
	for _, gone := range []string{"/opt/heddle", "# Heddle"} {
		if strings.Contains(string(raw), gone) {
			t.Errorf("left %q:\n%s", gone, raw)
		}
	}
	for _, kept := range []string{"alias ll='ls -l'", "# A note of mine", "export EDITOR=vim"} {
		if !strings.Contains(string(raw), kept) {
			t.Errorf("removed %q:\n%s", kept, raw)
		}
	}
}

func TestTarget(t *testing.T) {
	if got := Target("linux", "amd64"); got != "linux-x64" {
		t.Fatalf("got %q", got)
	}
	if got := Target("darwin", "amd64"); got != "" {
		t.Fatalf("Intel Macs have no build: %q", got)
	}
}

func TestNativeProblem(t *testing.T) {
	tr := func(en, _ string) string { return en }
	if got := (Facts{Target: "linux-x64"}).NativeProblem(tr); got != "" {
		t.Fatalf("got %q", got)
	}
	if got := (Facts{Target: "linux-x64", Root: true}).NativeProblem(tr); got == "" {
		t.Fatal("root can't run the bundled Postgres")
	}
}
