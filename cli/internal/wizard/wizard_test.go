package wizard

import (
	"context"
	"errors"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/install"
	"github.com/heddlehq/heddle/cli/internal/providers"
	"github.com/heddlehq/heddle/cli/internal/system"
	"github.com/heddlehq/heddle/cli/internal/text"
)

var goodMachine = system.Facts{OS: "linux", Arch: "amd64", Target: "linux-x64", Docker: true}

func start(t *testing.T, options Options) *model {
	t.Helper()
	text.SetLanguage("en")
	for _, name := range []string{"ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY", "XAI_API_KEY"} {
		t.Setenv(name, "")
	}

	options.Plan = install.DefaultPlan()
	options.Plan.Home = t.TempDir()
	if options.Facts == (system.Facts{}) {
		options.Facts = goodMachine
	}
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	return newModel(ctx, cancel, options)
}

func (m *model) press(keys ...string) *model {
	for _, name := range keys {
		var msg tea.KeyPressMsg
		switch name {
		case "enter":
			msg = tea.KeyPressMsg{Code: tea.KeyEnter}
		case "esc":
			msg = tea.KeyPressMsg{Code: tea.KeyEscape}
		case "down":
			msg = tea.KeyPressMsg{Code: tea.KeyDown}
		case "up":
			msg = tea.KeyPressMsg{Code: tea.KeyUp}
		case "space":
			msg = tea.KeyPressMsg{Code: tea.KeySpace, Text: " "}
		default:
			msg = tea.KeyPressMsg{Code: []rune(name)[0], Text: name}
		}
		m.Update(msg)
	}
	return m
}

func (m *model) typed(value string) *model {
	m.input.SetValue(value)
	return m
}

func (m *model) at(t *testing.T, id string) {
	t.Helper()
	if got := m.current().id; got != id {
		t.Fatalf("on %q, expected %q", got, id)
	}
}

func TestQuickInstallAsksOnlyWhatMatters(t *testing.T) {
	m := start(t, Options{})
	m.at(t, "welcome")
	m.press("enter").at(t, "components")
	m.press("enter").at(t, "provider")

	// Not now is the last option, and going up from the first wraps to it.
	m.press("up", "enter").at(t, "review")

	if !m.plan.Heddle || !m.plan.Treadle {
		t.Fatalf("plan: %+v", m.plan)
	}
	if m.plan.LLMProvider != "" {
		t.Fatalf("provider %q", m.plan.LLMProvider)
	}
}

func TestProviderNeverDefaultsToSkipping(t *testing.T) {
	m := start(t, Options{}).press("enter", "enter")
	m.at(t, "provider")
	if got := m.current().options(m)[m.cursor].value; got == "" {
		t.Fatal("a distracted enter would skip the AI")
	}
}

func TestProviderFollowsAKeyInTheEnvironment(t *testing.T) {
	m := start(t, Options{})
	t.Setenv("OPENAI_API_KEY", "sk-from-env")
	m.press("enter", "enter").at(t, "provider")
	if got := m.current().options(m)[m.cursor].value; got != "openai" {
		t.Fatalf("got %q", got)
	}

	m.press("enter").at(t, "key")
	if got := m.input.Value(); got != "sk-from-env" {
		t.Fatalf("key %q", got)
	}
}

func TestAKeyMustNotBeEmpty(t *testing.T) {
	m := start(t, Options{}).press("enter", "enter", "enter")
	m.at(t, "key")
	m.press("enter").at(t, "key")
	if m.message == "" {
		t.Fatal("no explanation")
	}
}

func TestARefusedKeyStaysOnTheScreen(t *testing.T) {
	m := start(t, Options{}).press("enter", "enter", "enter").typed("bad")
	m.at(t, "key")

	m.Update(checkedMsg{value: "bad", err: fakeRejection{}})
	m.at(t, "key")
	if m.message == "" {
		t.Fatal("no explanation")
	}
	if m.plan.LLMKey != "" {
		t.Fatal("kept a refused key")
	}
}

type fakeRejection struct{}

func (fakeRejection) Error() string        { return "refused" }
func (fakeRejection) Is(target error) bool { return target == providers.ErrRejected }

func TestAnAcceptedKeyOffersItsModels(t *testing.T) {
	m := start(t, Options{}).press("enter", "enter", "enter").typed("good")
	m.Update(checkedMsg{value: "good", models: []string{"model-a", "model-b"}})
	m.at(t, "model")

	options := m.current().options(m)
	if options[0].value != "model-a" || options[len(options)-1].value != otherModel {
		t.Fatalf("got %+v", options)
	}

	m.press("down", "enter").at(t, "review")
	if m.plan.LLMKey != "good" || m.plan.LLMModel != "model-b" || m.plan.LLMProvider != "anthropic" {
		t.Fatalf("plan: %+v", m.plan)
	}
}

func TestBeingOfflineIsThePersonsCall(t *testing.T) {
	m := start(t, Options{}).press("enter", "enter", "enter").typed("maybe")
	m.Update(checkedMsg{value: "maybe", err: errors.New("no route to host")})
	m.at(t, "key")
	if m.notice == "" {
		t.Fatal("no notice")
	}

	m.press("enter").at(t, "model")
	if m.plan.LLMKey != "maybe" {
		t.Fatalf("key %q", m.plan.LLMKey)
	}
}

func TestChangingProviderForgetsTheKey(t *testing.T) {
	m := start(t, Options{}).press("enter", "enter", "enter").typed("anthropic-key")
	m.Update(checkedMsg{value: "anthropic-key"})
	m.at(t, "model")

	m.press("esc", "esc").at(t, "provider")
	m.press("down", "enter").at(t, "key")
	if got := m.input.Value(); got != "" {
		t.Fatalf("offered another provider's key: %q", got)
	}
}

func TestOtherProviderAsksNameKeyAndModel(t *testing.T) {
	m := start(t, Options{}).press("enter", "enter")
	m.press("up", "up", "enter").at(t, "provider-name")
	m.typed("OpenRouter").press("enter").at(t, "key")
	m.typed("key").press("enter")
	m.Update(checkedMsg{value: "key"})
	m.at(t, "model-name")
	m.typed("some/model").press("enter").at(t, "review")

	if m.plan.LLMProvider != "openrouter" || m.plan.LLMModel != "some/model" {
		t.Fatalf("plan: %+v", m.plan)
	}
}

func TestCustomInstallAsksEverything(t *testing.T) {
	m := start(t, Options{}).press("down", "enter")
	want := []string{"components", "mode", "home", "version", "port", "provider"}
	for _, id := range want {
		m.at(t, id)
		m.press("enter")
	}
}

func TestInvalidPortStays(t *testing.T) {
	m := start(t, Options{}).press("down", "enter", "enter", "enter", "enter", "enter")
	m.at(t, "port")
	m.typed("99999").press("enter").at(t, "port")
	if m.message == "" {
		t.Fatal("no explanation")
	}
	m.typed("4100").press("enter").at(t, "provider")
	if m.plan.Port != 4100 {
		t.Fatalf("port %d", m.plan.Port)
	}
}

func TestDockerAsksForTheDomainAndSkipsLocalQuestions(t *testing.T) {
	m := start(t, Options{}).press("down", "enter", "enter")
	m.at(t, "mode")
	m.press("down", "enter")
	if !m.plan.Docker() {
		t.Fatal("not Docker")
	}
	m.press("enter", "enter", "enter").at(t, "domain")
	m.typed("heddle.example.com").press("enter").at(t, "provider")

	for _, s := range m.visibleScreens() {
		if s.id == "concurrency" || s.id == "rescue" || s.id == "claude" {
			t.Errorf("%s has no effect in Docker", s.id)
		}
	}
}

func TestRootIsOfferedDockerInsteadOfAnError(t *testing.T) {
	m := start(t, Options{Facts: system.Facts{OS: "linux", Target: "linux-x64", Root: true, Docker: true}})
	if m.plan.Mode != config.ModeDocker {
		t.Fatalf("mode %q", m.plan.Mode)
	}

	m.press("enter", "enter").at(t, "mode")
	options := m.current().options(m)
	if options[0].disabled == "" {
		t.Fatal("offered what can't work")
	}
	if got := options[m.cursor].value; got != config.ModeDocker {
		t.Fatalf("cursor on %q", got)
	}
}

func TestNoWayToRunHeddleLeavesTreadle(t *testing.T) {
	m := start(t, Options{Facts: system.Facts{OS: "linux", Target: "linux-x64", Musl: true}})
	m.press("enter").at(t, "components")
	if got := m.current().options(m)[m.cursor].value; got != componentsTreadle {
		t.Fatalf("cursor on %q", got)
	}
}

func TestTreadleOnlySkipsEverythingAboutHeddle(t *testing.T) {
	m := start(t, Options{TreadleOnly: true})
	m.at(t, "treadle-home")
	m.press("enter").at(t, "treadle-server")
	m.typed("heddle.example.com").press("enter").at(t, "treadle-key")
	m.typed("").press("enter").at(t, "finish")

	if len(m.current().options(m)) != 1 {
		t.Fatal("only the PATH applies to Treadle")
	}
	m.press("enter").at(t, "review")

	if m.plan.Heddle || !m.plan.Treadle || m.plan.TreadleServer != "http://heddle.example.com" {
		t.Fatalf("plan: %+v", m.plan)
	}
}

func TestTreadleServerIsOptional(t *testing.T) {
	m := start(t, Options{TreadleOnly: true}).press("enter")
	m.at(t, "treadle-server")
	m.typed("").press("enter").at(t, "finish")
}

func TestSettingsOnlyAsksAboutTheAI(t *testing.T) {
	m := start(t, Options{SettingsOnly: true})
	m.at(t, "provider")
	for _, s := range m.visibleScreens() {
		if s.section != sectionAI && s.id != "review" {
			t.Errorf("%s isn't about the AI", s.id)
		}
	}
}

func TestSettingsOnlyFollowsTheAnswers(t *testing.T) {
	m := start(t, Options{SettingsOnly: true})
	m.press("up", "enter")
	if got := m.current().id; got == "provider-name" || got == "key" {
		t.Fatalf("Not now went on to %q", got)
	}
}

func TestClaudeAgentReusesTheAnthropicKey(t *testing.T) {
	m := start(t, Options{})
	m.custom = true
	m.plan.LLMProvider = "anthropic"
	m.plan.ClaudeAgent = true
	if m.visible(claudeKeyScreen()) {
		t.Fatal("asked for a key it already has")
	}

	m.plan.LLMProvider = "openai"
	if !m.visible(claudeKeyScreen()) {
		t.Fatal("the agent needs an Anthropic key")
	}
}

func TestBackNeverLeavesTheFirstScreen(t *testing.T) {
	m := start(t, Options{}).press("esc", "esc")
	m.at(t, "welcome")
}

func TestQuittingChangesNothing(t *testing.T) {
	m := start(t, Options{}).press("q")
	if !m.outcome.Cancelled {
		t.Fatal("didn't cancel")
	}
}

func TestRailNeverGoesBackwards(t *testing.T) {
	m := start(t, Options{})
	m.custom = true
	m.plan.Treadle = true

	last := sectionStart
	for _, s := range m.visibleScreens() {
		if s.section < last {
			t.Fatalf("%s goes back to an earlier section", s.id)
		}
		last = s.section
	}
}

func TestEveryScreenDraws(t *testing.T) {
	sizes := [][2]int{{120, 40}, {80, 24}, {60, 20}, {40, 12}}
	for _, size := range sizes {
		m := start(t, Options{})
		m.custom = true
		m.plan.LLMProvider = "anthropic"
		m.plan.ClaudeAgent = true
		m.Update(tea.WindowSizeMsg{Width: size[0], Height: size[1]})
		for index := range m.screens {
			m.index = index
			m.prepare()
			if strings.TrimSpace(m.render()) == "" {
				t.Errorf("%s drew nothing at %v", m.current().id, size)
			}
		}
	}
}

func TestInstallFailureIsShownAndKept(t *testing.T) {
	m := start(t, Options{})
	m.phase = phaseInstalling
	m.expected = 2
	m.Update(stepMsg{"Downloading"})
	m.Update(installedMsg{err: errors.New("the disk is full")})

	if !strings.Contains(m.render(), "the disk is full") {
		t.Fatal("hid the reason")
	}
	if m.outcome.Err == nil {
		t.Fatal("lost the error")
	}
}

func TestProgressNeverReachesTheEndBeforeItIsDone(t *testing.T) {
	m := start(t, Options{})
	m.phase = phaseInstalling
	m.expected = 1
	m.Update(stepMsg{"One"})
	m.Update(stepDoneMsg{""})
	m.Update(stepMsg{"An extra step"})
	if m.fraction >= 1 {
		t.Fatal("the weaving finished early")
	}
}
