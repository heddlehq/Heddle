package install

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/paths"
	"github.com/heddlehq/heddle/cli/internal/system"
)

var goodMachine = system.Facts{OS: "linux", Arch: "amd64", Target: "linux-x64", Docker: true}

func plan(t *testing.T) Plan {
	t.Helper()
	p := DefaultPlan()
	p.Home = t.TempDir()
	return p
}

func TestValidate(t *testing.T) {
	cases := []struct {
		name   string
		change func(*Plan)
		facts  system.Facts
		wrong  bool
	}{
		{name: "the default works", change: func(*Plan) {}, facts: goodMachine},
		{name: "nothing to install", change: func(p *Plan) { p.Heddle = false }, facts: goodMachine, wrong: true},
		{name: "root can't run the bundled Postgres", change: func(*Plan) {}, facts: system.Facts{Target: "linux-x64", Root: true}, wrong: true},
		{name: "root can run Docker", change: func(p *Plan) { p.Mode = config.ModeDocker }, facts: system.Facts{Target: "linux-x64", Root: true, Docker: true}},
		{name: "musl can't run the build", change: func(*Plan) {}, facts: system.Facts{Target: "linux-x64", Musl: true}, wrong: true},
		{name: "any machine can have Treadle", change: func(p *Plan) { p.Heddle, p.Treadle = false, true }, facts: system.Facts{Root: true, Musl: true}},
		{name: "accents", change: func(p *Plan) { p.Home = "/home/joão/.heddle" }, facts: goodMachine, wrong: true},
		{name: "Docker that's off", change: func(p *Plan) { p.Mode = config.ModeDocker }, facts: system.Facts{Target: "linux-x64"}, wrong: true},
		{name: "a domain needs a server", change: func(p *Plan) { p.Domain = "a.io" }, facts: goodMachine, wrong: true},
		{name: "bad port", change: func(p *Plan) { p.Port = 70000 }, facts: goodMachine, wrong: true},
		{name: "a provider with no key", change: func(p *Plan) { p.LLMProvider = "openai" }, facts: goodMachine, wrong: true},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			p := plan(t)
			c.change(&p)
			if err := p.Validate(c.facts); (err != nil) != c.wrong {
				t.Fatalf("got %v", err)
			}
		})
	}
}

func TestSettingsKeepWhatWasNotAsked(t *testing.T) {
	env := &config.Env{}
	_ = env.Set("HEDDLE_LLM_MODEL", "old-model")
	_ = env.Set("CUSTOM", "mine")

	p := plan(t)
	p.Port = 4100
	if err := p.Settings(env); err != nil {
		t.Fatal(err)
	}

	if got := env.Value("HEDDLE_LLM_MODEL"); got != "old-model" {
		t.Fatalf("an empty answer erased the setting: %q", got)
	}
	if got := env.Value("CUSTOM"); got != "mine" {
		t.Fatalf("lost a setting: %q", got)
	}
	if got := env.Value("PORT"); got != "4100" {
		t.Fatalf("port: %q", got)
	}
}

func TestSettingsUseThePortNameOfDocker(t *testing.T) {
	env := &config.Env{}
	p := plan(t)
	p.Mode = config.ModeDocker
	p.Port = 8080
	if err := p.Settings(env); err != nil {
		t.Fatal(err)
	}
	if got := env.Value("HEDDLE_PORT"); got != "8080" {
		t.Fatalf("got %q", got)
	}
	if _, ok := env.Get("PORT"); ok {
		t.Fatal("PORT is the port inside the container")
	}
}

func TestSettingsWriteOnlyTheSpoolLimitsThatChange(t *testing.T) {
	env := &config.Env{}
	p := plan(t)
	p.SpoolMaxRows = 5000
	if err := p.Settings(env); err != nil {
		t.Fatal(err)
	}
	if got := env.Value("SPOOL_MAX_ROWS"); got != "5000" {
		t.Fatalf("rows: %q", got)
	}
	if _, ok := env.Get("SPOOL_MAX_TABLES"); ok {
		t.Fatal("wrote a limit that keeps its default")
	}
}

func cluster(t *testing.T, layout paths.Layout, marker string) {
	t.Helper()
	if err := os.MkdirAll(layout.Cluster(), 0o700); err != nil {
		t.Fatal(err)
	}
	for name, body := range map[string]string{"PG_VERSION": "17\n", "marker": marker} {
		if err := os.WriteFile(filepath.Join(layout.Cluster(), name), []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}
}

func TestBackupKeepsTheModePostgresRequires(t *testing.T) {
	layout := paths.Layout{Home: t.TempDir()}
	cluster(t, layout, "one")

	name, err := CreateBackup(layout, 0)
	if err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(filepath.Join(layout.Backups(), name, "postgres"))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o700 {
		t.Fatalf("mode %o: Postgres would refuse to start", info.Mode().Perm())
	}
}

func TestBackupKeepsOnlyTheLatest(t *testing.T) {
	layout := paths.Layout{Home: t.TempDir()}
	cluster(t, layout, "one")

	for _, name := range []string{"a", "b", "c", "d"} {
		if err := os.MkdirAll(filepath.Join(layout.Backups(), name), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := CreateBackup(layout, 3); err != nil {
		t.Fatal(err)
	}

	backups, err := Backups(layout)
	if err != nil {
		t.Fatal(err)
	}
	if len(backups) != 3 {
		t.Fatalf("%d left", len(backups))
	}
}

func TestBackupOfNothingIsFine(t *testing.T) {
	name, err := CreateBackup(paths.Layout{Home: t.TempDir()}, 3)
	if err != nil || name != "" {
		t.Fatalf("got %q, %v", name, err)
	}
}

func TestRestoreKeepsTheDataItReplaces(t *testing.T) {
	layout := paths.Layout{Home: t.TempDir()}
	cluster(t, layout, "old")
	name, err := CreateBackup(layout, 0)
	if err != nil {
		t.Fatal(err)
	}
	cluster(t, layout, "new")

	aside, err := RestoreBackup(layout, name)
	if err != nil {
		t.Fatal(err)
	}

	if got, _ := os.ReadFile(filepath.Join(layout.Cluster(), "marker")); string(got) != "old" {
		t.Fatalf("restored %q", got)
	}
	if got, _ := os.ReadFile(filepath.Join(aside, "postgres", "marker")); string(got) != "new" {
		t.Fatalf("set aside %q", got)
	}
}

func TestRestoreRefusesWhatIsNotABackup(t *testing.T) {
	layout := paths.Layout{Home: t.TempDir()}
	cluster(t, layout, "mine")

	if _, err := RestoreBackup(layout, "../data/postgres"); err == nil {
		t.Fatal("restored something that isn't a backup")
	}
	if got, _ := os.ReadFile(filepath.Join(layout.Cluster(), "marker")); string(got) != "mine" {
		t.Fatal("touched the data")
	}
}

func TestSwapAppReplacesTheProgramAndDropsTheOldLauncher(t *testing.T) {
	layout := paths.Layout{Home: t.TempDir()}
	incoming := filepath.Join(layout.Home, "incoming")
	for _, path := range []string{filepath.Join(layout.App(), "old"), filepath.Join(incoming, "new"), filepath.Join(incoming, "heddle")} {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}

	if err := swapApp(layout, incoming); err != nil {
		t.Fatal(err)
	}

	entries, err := os.ReadDir(layout.App())
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Name() != "new" {
		t.Fatalf("left %v", entries)
	}
	if _, err := os.Stat(layout.App() + ".old"); err == nil {
		t.Fatal("left the old program behind")
	}
}

func TestUnitFileUsesTheInstall(t *testing.T) {
	unit := unitFile(paths.Layout{Home: "/opt/heddle"})
	for _, want := range []string{"Environment=HEDDLE_HOME=/opt/heddle", "ExecStart=/opt/heddle/bin/heddle start --no-browser", "ExecStop=/opt/heddle/bin/heddle stop"} {
		if !strings.Contains(unit, want) {
			t.Errorf("missing %q in:\n%s", want, unit)
		}
	}
}
