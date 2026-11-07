package config

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestEnvKeepsCommentsAndOrder(t *testing.T) {
	path := filepath.Join(t.TempDir(), "heddle.env")
	original := "# A comment\nPORT=4000\n\nOTHER=\"a b\"\n"
	if err := os.WriteFile(path, []byte(original), 0o600); err != nil {
		t.Fatal(err)
	}

	env, err := LoadEnv(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := env.Set("PORT", "4100"); err != nil {
		t.Fatal(err)
	}
	if err := env.Save(path); err != nil {
		t.Fatal(err)
	}

	got, _ := os.ReadFile(path)
	want := "# A comment\nPORT=4100\n\nOTHER=\"a b\"\n"
	if string(got) != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestEnvRoundTripsHardValues(t *testing.T) {
	values := []string{"plain", "with space", "it's", `say "hi"`, "$HOME", `back\slash`, "#hash", "it's $5"}

	for _, value := range values {
		path := filepath.Join(t.TempDir(), "heddle.env")
		env := &Env{}
		if err := env.Set("KEY", value); err != nil {
			t.Fatal(err)
		}
		if err := env.Save(path); err != nil {
			t.Fatal(err)
		}

		reloaded, err := LoadEnv(path)
		if err != nil {
			t.Fatal(err)
		}
		if got := reloaded.Value("KEY"); got != value {
			t.Errorf("got %q, want %q", got, value)
		}
	}
}

func TestSaveKeepsSecretsPrivate(t *testing.T) {
	path := filepath.Join(t.TempDir(), "heddle.env")
	env := &Env{}
	_ = env.Set("HEDDLE_LLM_API_KEY", "secret")
	if err := env.Save(path); err != nil {
		t.Fatal(err)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode %o", info.Mode().Perm())
	}
}

func TestSetRefusesLineBreaks(t *testing.T) {
	env := &Env{}
	if err := env.Set("KEY", "one\nINJECTED=1"); err == nil {
		t.Fatal("a line break would add a setting")
	}
}

func TestEnvironSkipsEmptyValues(t *testing.T) {
	env := &Env{}
	_ = env.Set("EMPTY", "")
	_ = env.Set("FULL", "1")
	if got := env.Environ(); !slices.Equal(got, []string{"FULL=1"}) {
		t.Fatalf("got %v", got)
	}
}

func TestMaskNeverShowsAShortSecret(t *testing.T) {
	if got := Mask("short"); got != "•••••" {
		t.Fatalf("got %q", got)
	}
	if got := Mask("sk-ant-abcdefgh1234"); got != "sk-a••••1234" {
		t.Fatalf("got %q", got)
	}
}
