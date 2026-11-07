package runtime

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/heddlehq/heddle/cli/internal/paths"
)

func TestReadyLineFindsTheAddress(t *testing.T) {
	match := readyLine.FindStringSubmatch("Heddle is running at http://localhost:4001")
	if match == nil || match[1] != "http://localhost:4001" {
		t.Fatalf("got %v", match)
	}
}

func TestStopWithNothingRunning(t *testing.T) {
	local := &Local{Layout: paths.Layout{Home: t.TempDir()}}
	if err := local.Stop(context.Background()); !errors.Is(err, ErrNotRunning) {
		t.Fatalf("got %v", err)
	}
}

func TestStaleStateIsNotARunningHeddle(t *testing.T) {
	local := &Local{Layout: paths.Layout{Home: t.TempDir()}}
	// PID 1 exists, and is not a VM of this install.
	if err := local.writeState(state{PID: 1}); err != nil {
		t.Fatal(err)
	}
	status, err := local.Status(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if status.Running {
		t.Fatal("took another process for Heddle")
	}
}

func TestAStopIsToldApartFromACrash(t *testing.T) {
	local := &Local{Layout: paths.Layout{Home: t.TempDir()}}

	if err := local.writeState(state{PID: 1}); err != nil {
		t.Fatal(err)
	}
	if local.stopAsked() {
		t.Fatal("a VM that died by itself crashed")
	}

	if err := local.writeState(state{PID: 1, Stopping: true}); err != nil {
		t.Fatal(err)
	}
	if !local.stopAsked() {
		t.Fatal("heddle stop asked for this")
	}

	local.clearState()
	if !local.stopAsked() {
		t.Fatal("only Stop removes the state while the VM is up")
	}
}

func TestFollowerOnlyReturnsWholeLines(t *testing.T) {
	path := filepath.Join(t.TempDir(), "log")
	if err := os.WriteFile(path, []byte("one\ntw"), 0o644); err != nil {
		t.Fatal(err)
	}
	follower, err := newFollower(path, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer follower.close()

	if got := follower.lines(); !slices.Equal(got, []string{"one"}) {
		t.Fatalf("got %v", got)
	}

	file, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	if _, err := file.WriteString("o\n"); err != nil {
		t.Fatal(err)
	}
	if got := follower.lines(); !slices.Equal(got, []string{"two"}) {
		t.Fatalf("got %v", got)
	}
}

func TestParseServicesReadsBothFormats(t *testing.T) {
	lines := []byte(`{"Service":"ui","State":"running"}` + "\n" + `{"Service":"db","State":"exited"}`)
	array := []byte(`[{"Service":"ui","State":"running"},{"Service":"db","State":"exited"}]`)
	want := []Service{{"ui", "running"}, {"db", "exited"}}

	for _, output := range [][]byte{lines, array} {
		if got := parseServices(output); !slices.Equal(got, want) {
			t.Fatalf("got %v", got)
		}
	}
}
