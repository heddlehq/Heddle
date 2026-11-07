package paths

import (
	"path/filepath"
	"testing"
)

func TestSupportedRefusesAccents(t *testing.T) {
	if Supported("/home/joão/.heddle") {
		t.Fatal("Postgres doesn't load from a folder with accents")
	}
	if !Supported("/home/joao/.heddle") {
		t.Fatal("this one is fine")
	}
}

func TestWindowsAvoidsAUserFolderWithAccents(t *testing.T) {
	got := defaultHome("windows", `C:\Users\João\AppData\Local`, `C:\ProgramData`, "")
	if got != filepath.Join(`C:\ProgramData`, "Heddle") {
		t.Fatalf("got %q", got)
	}
}

func TestResolvePrefersTheEnvironment(t *testing.T) {
	t.Setenv("HEDDLE_HOME", "/somewhere")
	if got := Resolve().Home; got != "/somewhere" {
		t.Fatalf("got %q", got)
	}
}
