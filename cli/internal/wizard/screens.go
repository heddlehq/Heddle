package wizard

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	tea "charm.land/bubbletea/v2"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/install"
	"github.com/heddlehq/heddle/cli/internal/paths"
	"github.com/heddlehq/heddle/cli/internal/providers"
	"github.com/heddlehq/heddle/cli/internal/system"
	"github.com/heddlehq/heddle/cli/internal/text"
	"github.com/heddlehq/heddle/cli/internal/treadle"
)

type kind int

const (
	kindChoice kind = iota
	kindToggles
	kindInput
	kindReview
)

type section int

const (
	sectionStart section = iota
	sectionPlace
	sectionAI
	sectionTreadle
	sectionFinish
)

func (s section) title() string {
	switch s {
	case sectionStart:
		return text.T("Welcome", "Boas-vindas")
	case sectionPlace:
		return text.T("Where it runs", "Onde roda")
	case sectionAI:
		return text.T("AI", "IA")
	case sectionTreadle:
		return "Treadle"
	}
	return text.T("Finish", "Concluir")
}

type option struct {
	value    string
	label    string
	note     string
	disabled string // Why it can't be picked, when it can't.
}

// screen is one question. Anything optional is nil on the screens that don't need it.
type screen struct {
	id       string
	section  section
	kind     kind
	advanced bool // Only asked in the custom install.
	secret   bool

	title func(*model) string
	hint  func(*model) string

	when        func(*model) bool
	options     func(*model) []option
	value       func(*model) string
	placeholder func(*model) string
	validate    func(*model, string) string
	apply       func(*model, string)

	// check goes to the network, on the way out of the screen.
	check      func(*model, string) tea.Cmd
	checkLabel func(*model) string

	toggled func(*model, string) bool
	toggle  func(*model, string, bool)
}

func static(value string) func(*model) string {
	return func(*model) string { return value }
}

const (
	componentsBoth    = "both"
	componentsHeddle  = "heddle"
	componentsTreadle = "treadle"

	otherProvider = "__other"
	otherModel    = "__other"

	toggleBrowser   = "browser"
	togglePath      = "path"
	toggleStart     = "start"
	toggleAutostart = "autostart"
)

func heddle(m *model) bool { return m.plan.Heddle }

func local(m *model) bool { return m.plan.Heddle && !m.plan.Docker() }

func hasAI(m *model) bool { return m.plan.Heddle && m.plan.LLMProvider != "" }

func buildScreens() []*screen {
	return []*screen{
		welcomeScreen(),
		componentsScreen(),
		modeScreen(),
		homeScreen(),
		versionScreen(),
		portScreen(),
		domainScreen(),
		providerScreen(),
		otherProviderScreen(),
		keyScreen(),
		modelScreen(),
		typedModelScreen(),
		claudeScreen(),
		claudeKeyScreen(),
		claudeBudgetScreen(),
		treadleHomeScreen(),
		treadleServerScreen(),
		treadleKeyScreen(),
		concurrencyScreen(),
		rescueScreen(),
		spoolTablesScreen(),
		spoolRowsScreen(),
		finishScreen(),
		reviewScreen(),
	}
}

func welcomeScreen() *screen {
	return &screen{
		id: "welcome", section: sectionStart, kind: kindChoice,
		when: func(m *model) bool { return !m.options.TreadleOnly },
		title: func(m *model) string {
			if m.existing != "" {
				return text.T("Heddle "+m.existing+" is already here", "O Heddle "+m.existing+" já está aqui")
			}
			return text.T("Welcome to Heddle", "Boas-vindas ao Heddle")
		},
		hint: func(m *model) string {
			if m.existing != "" {
				return text.T(
					"Updating keeps your data and settings, and saves a copy of the data first.",
					"Atualizar mantém seus dados e configurações, e salva uma cópia dos dados antes.",
				)
			}
			return text.T(
				"Everything Heddle needs comes in the download, the database included.",
				"Tudo que o Heddle precisa vem no download, inclusive o banco de dados.",
			)
		},
		options: func(*model) []option {
			return []option{
				{value: "quick", label: text.T("Quick install", "Instalação rápida"), note: text.T("Good defaults. Only asks what's yours to answer", "Bons padrões. Só pergunta o que depende de você")},
				{value: "custom", label: text.T("Customize everything", "Personalizar tudo"), note: text.T("Folder, version, port, performance and more", "Pasta, versão, porta, desempenho e mais")},
			}
		},
		value: func(m *model) string {
			if m.custom {
				return "custom"
			}
			return "quick"
		},
		apply: func(m *model, value string) { m.custom = value == "custom" },
	}
}

func componentsScreen() *screen {
	return &screen{
		id: "components", section: sectionStart, kind: kindChoice,
		when:  func(m *model) bool { return !m.options.TreadleOnly },
		title: static(text.T("What do you want to install?", "O que você quer instalar?")),
		hint:  static(text.T("Treadle edits your flows from the terminal, on this Heddle or on any other.", "O Treadle edita seus flows pelo terminal, neste Heddle ou em qualquer outro.")),
		options: func(m *model) []option {
			unavailable := ""
			if m.options.Facts.NativeProblem(text.T) != "" && !m.options.Facts.Docker {
				unavailable = m.options.Facts.NativeProblem(text.T) + " " + text.T("And Docker isn't running.", "E o Docker não está rodando.")
			}
			return []option{
				{value: componentsBoth, label: "Heddle + Treadle", note: text.T("The platform and the terminal editor", "A plataforma e o editor de terminal"), disabled: unavailable},
				{value: componentsHeddle, label: text.T("Only Heddle", "Só o Heddle"), note: text.T("The platform, with the editor in your browser", "A plataforma, com o editor no navegador"), disabled: unavailable},
				{value: componentsTreadle, label: text.T("Only Treadle", "Só o Treadle"), note: text.T("To connect to a Heddle running elsewhere", "Para conectar em um Heddle que roda em outro lugar")},
			}
		},
		value: func(m *model) string {
			switch {
			case m.plan.Heddle && m.plan.Treadle:
				return componentsBoth
			case m.plan.Treadle:
				return componentsTreadle
			}
			return componentsHeddle
		},
		apply: func(m *model, value string) {
			m.plan.Heddle = value != componentsTreadle
			m.plan.Treadle = value != componentsHeddle
		},
	}
}

func modeScreen() *screen {
	return &screen{
		id: "mode", section: sectionPlace, kind: kindChoice,
		// A quick install only has to ask when the usual answer isn't possible.
		when: func(m *model) bool {
			return heddle(m) && m.existing == "" && (m.custom || m.options.Facts.NativeProblem(text.T) != "")
		},
		title: static(text.T("Where will Heddle run?", "Onde o Heddle vai rodar?")),
		hint:  static(text.T("Flows run code, so this computer's install only answers on this computer.", "Flows rodam código, então a instalação neste computador só responde nele mesmo.")),
		options: func(m *model) []option {
			docker := ""
			if !m.options.Facts.Docker {
				docker = text.T("Docker isn't running on this machine", "O Docker não está rodando nesta máquina")
			}
			return []option{
				{value: config.ModeLocal, label: text.T("This computer", "Este computador"), note: text.T("For one person. Brings its own Postgres", "Para uma pessoa. Traz o próprio Postgres"), disabled: m.options.Facts.NativeProblem(text.T)},
				{value: config.ModeDocker, label: text.T("A server, with Docker", "Um servidor, com Docker"), note: text.T("For a team. UI, worker and Postgres in containers", "Para um time. UI, worker e Postgres em containers"), disabled: docker},
			}
		},
		value: func(m *model) string { return m.plan.Mode },
		apply: func(m *model, value string) { m.plan.Mode = value },
	}
}

func homeScreen() *screen {
	return &screen{
		id: "home", section: sectionPlace, kind: kindInput, advanced: true, when: heddle,
		title: static(text.T("Which folder?", "Em qual pasta?")),
		hint:  static(text.T("The program and your data live here. Removing it removes Heddle.", "O programa e seus dados ficam aqui. Remover a pasta remove o Heddle.")),
		value: func(m *model) string { return m.plan.Home },
		validate: func(m *model, value string) string {
			value = strings.TrimSpace(value)
			if value == "" || !filepath.IsAbs(expandHome(value)) {
				return text.T("Use a full path.", "Use um caminho completo.")
			}
			if !m.plan.Docker() && !paths.Supported(value) {
				return text.T("Postgres and Python don't load from a folder with accents.", "O Postgres e o Python não carregam de uma pasta com acentos.")
			}
			if info, err := os.Stat(expandHome(value)); err == nil && !info.IsDir() {
				return text.T("That's a file.", "Isso é um arquivo.")
			}
			return ""
		},
		apply: func(m *model, value string) {
			m.plan.Home = expandHome(strings.TrimSpace(value))
			m.loadExisting()
		},
	}
}

func expandHome(path string) string {
	if rest, found := strings.CutPrefix(path, "~/"); found {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, rest)
		}
	}
	return path
}

func versionScreen() *screen {
	return &screen{
		id: "version", section: sectionPlace, kind: kindChoice, advanced: true, when: heddle,
		title: static(text.T("Which version?", "Qual versão?")),
		hint:  static(text.T("The latest is the one that gets support.", "A mais recente é a que tem suporte.")),
		options: func(m *model) []option {
			options := []option{{value: "", label: text.T("Latest", "Mais recente")}}
			for _, version := range m.versions {
				options = append(options, option{value: version, label: version})
			}
			return options
		},
		value: func(m *model) string { return m.plan.Version },
		apply: func(m *model, value string) { m.plan.Version = value },
	}
}

func portScreen() *screen {
	return &screen{
		id: "port", section: sectionPlace, kind: kindInput, advanced: true, when: heddle,
		title: static(text.T("Which port?", "Qual porta?")),
		hint: func(m *model) string {
			if !m.plan.Docker() && !system.PortFree(m.plan.Port) {
				return text.T(
					fmt.Sprintf("Something is using %d now. Heddle takes the next free one, or pick another.", m.plan.Port),
					fmt.Sprintf("Algo está usando a %d agora. O Heddle pega a próxima livre, ou escolha outra.", m.plan.Port),
				)
			}
			return text.T("Where the editor and the API answer.", "Onde o editor e a API respondem.")
		},
		value: func(m *model) string { return strconv.Itoa(m.plan.Port) },
		validate: func(_ *model, value string) string {
			if port, err := strconv.Atoi(strings.TrimSpace(value)); err != nil || port < 1 || port > 65535 {
				return text.T("A port is a number from 1 to 65535.", "Uma porta é um número de 1 a 65535.")
			}
			return ""
		},
		apply: func(m *model, value string) { m.plan.Port, _ = strconv.Atoi(strings.TrimSpace(value)) },
	}
}

func domainScreen() *screen {
	return &screen{
		id: "domain", section: sectionPlace, kind: kindInput,
		when:        func(m *model) bool { return m.plan.Docker() },
		title:       static(text.T("Does it have a public domain?", "Tem um domínio público?")),
		hint:        static(text.T("Only behind HTTPS: this turns the HTTPS redirect on, so your proxy must send X-Forwarded-Proto. Leave it empty otherwise.", "Só atrás de HTTPS: isto liga o redirect para HTTPS, então seu proxy precisa mandar X-Forwarded-Proto. Se não, deixe vazio.")),
		placeholder: static("heddle.example.com"),
		value:       func(m *model) string { return m.plan.Domain },
		validate: func(_ *model, value string) string {
			if strings.ContainsAny(value, " /:") {
				return text.T("Only the name, like heddle.example.com.", "Só o nome, como heddle.example.com.")
			}
			return ""
		},
		apply: func(m *model, value string) { m.plan.Domain = strings.TrimSpace(value) },
	}
}

func providerScreen() *screen {
	return &screen{
		id: "provider", section: sectionAI, kind: kindChoice, when: heddle,
		title: static(text.T("Which AI should Heddle use?", "Qual IA o Heddle deve usar?")),
		hint:  static(text.T("For the flow chats and AI nodes. You can add more on the AI page later.", "Para os chats dos flows e os nós de IA. Dá para adicionar mais na página de IA depois.")),
		options: func(*model) []option {
			options := make([]option, 0, len(providers.All)+2)
			for _, provider := range providers.All {
				note := provider.Note
				if name, _ := envKey(provider); name != "" {
					note += text.T(" · key found in ", " · chave encontrada em ") + name
				}
				options = append(options, option{value: provider.ID, label: provider.Name, note: note})
			}
			return append(options,
				option{value: otherProvider, label: text.T("Another one", "Outro"), note: text.T("Any provider req_llm supports", "Qualquer provedor que o req_llm suporte")},
				option{value: "", label: text.T("Not now", "Agora não"), note: text.T("Set it up later, on the AI page", "Configure depois, na página de IA")},
			)
		},
		value: func(m *model) string {
			if m.otherProvider {
				return otherProvider
			}
			if m.plan.LLMProvider != "" {
				return m.plan.LLMProvider
			}
			// A key already in the environment is the best guess. "Not now" is never
			// the default: a distracted enter shouldn't skip the question.
			for _, provider := range providers.All {
				if name, _ := envKey(provider); name != "" {
					return provider.ID
				}
			}
			return providers.All[0].ID
		},
		apply: func(m *model, value string) {
			m.otherProvider = value == otherProvider
			if m.otherProvider {
				return
			}
			if value != m.plan.LLMProvider {
				m.plan.LLMKey, m.plan.LLMModel = "", ""
				m.models = nil
			}
			m.plan.LLMProvider = value
			if value == "" {
				m.plan.ClaudeAgent = false
			}
		},
	}
}

func otherProviderScreen() *screen {
	return &screen{
		id: "provider-name", section: sectionAI, kind: kindInput,
		when:        func(m *model) bool { return m.otherProvider },
		title:       static(text.T("Which provider?", "Qual provedor?")),
		hint:        static(text.T("The name req_llm knows it by.", "O nome pelo qual o req_llm o conhece.")),
		placeholder: static("openrouter"),
		value:       func(m *model) string { return m.plan.LLMProvider },
		validate: func(_ *model, value string) string {
			if strings.TrimSpace(value) == "" {
				return text.T("Type the name, or go back and pick one of the list.", "Digite o nome, ou volte e escolha um da lista.")
			}
			return ""
		},
		apply: func(m *model, value string) { m.plan.LLMProvider = strings.ToLower(strings.TrimSpace(value)) },
	}
}

func keyScreen() *screen {
	return &screen{
		id: "key", section: sectionAI, kind: kindInput, secret: true, when: hasAIOrOther,
		title: func(m *model) string {
			if provider, ok := providers.Find(m.plan.LLMProvider); ok {
				return text.T("Your "+provider.Name+" API key", "Sua chave de API da "+provider.Name)
			}
			return text.T("Your API key", "Sua chave de API")
		},
		hint: func(m *model) string {
			provider, ok := providers.Find(m.plan.LLMProvider)
			if !ok {
				return text.T("It stays in a file only you can read.", "Ela fica em um arquivo que só você pode ler.")
			}
			if name, _ := envKey(provider); name != "" {
				return text.T("Filled in from "+name+". It stays in a file only you can read.", "Preenchida a partir de "+name+". Ela fica em um arquivo que só você pode ler.")
			}
			return text.T("Create one at "+provider.KeyPage+". It stays in a file only you can read.", "Crie uma em "+provider.KeyPage+". Ela fica em um arquivo que só você pode ler.")
		},
		placeholder: func(m *model) string {
			provider, _ := providers.Find(m.plan.LLMProvider)
			return provider.KeyHint
		},
		value: func(m *model) string {
			if m.plan.LLMKey != "" {
				return m.plan.LLMKey
			}
			if provider, ok := providers.Find(m.plan.LLMProvider); ok {
				_, value := envKey(provider)
				return value
			}
			return ""
		},
		validate: func(_ *model, value string) string {
			if strings.TrimSpace(value) == "" {
				return text.T("Paste the key, or press esc and choose Not now.", "Cole a chave, ou tecle esc e escolha Agora não.")
			}
			return ""
		},
		check: func(m *model, value string) tea.Cmd {
			provider, known := providers.Find(m.plan.LLMProvider)
			if !known {
				return func() tea.Msg { return checkedMsg{value: value} }
			}
			return func() tea.Msg {
				models, err := provider.Check(m.ctx, strings.TrimSpace(value))
				return checkedMsg{value: value, models: models, err: err}
			}
		},
		checkLabel: func(m *model) string {
			provider, _ := providers.Find(m.plan.LLMProvider)
			return text.T("Checking the key with ", "Conferindo a chave com ") + provider.Name
		},
		apply: func(m *model, value string) { m.plan.LLMKey = strings.TrimSpace(value) },
	}
}

func hasAIOrOther(m *model) bool { return hasAI(m) || m.otherProvider }

func modelScreen() *screen {
	return &screen{
		id: "model", section: sectionAI, kind: kindChoice,
		when:  func(m *model) bool { return hasAI(m) && !m.otherProvider },
		title: static(text.T("Which model?", "Qual modelo?")),
		hint: func(m *model) string {
			if len(m.models) > 0 {
				return text.T("These are the ones your key has access to.", "Estes são os que sua chave acessa.")
			}
			return text.T("A node can always ask for another one.", "Um nó sempre pode pedir outro.")
		},
		options: func(m *model) []option {
			provider, _ := providers.Find(m.plan.LLMProvider)
			names := m.models
			if len(names) == 0 && provider.DefaultModel != "" {
				names = []string{provider.DefaultModel}
			}

			options := make([]option, 0, len(names)+1)
			for _, name := range names {
				note := ""
				if name == provider.DefaultModel {
					note = text.T("recommended", "recomendado")
				}
				options = append(options, option{value: name, label: name, note: note})
			}
			return append(options, option{value: otherModel, label: text.T("Type another…", "Digitar outro…")})
		},
		value: func(m *model) string {
			if m.plan.LLMModel != "" {
				return m.plan.LLMModel
			}
			provider, _ := providers.Find(m.plan.LLMProvider)
			return provider.DefaultModel
		},
		apply: func(m *model, value string) {
			m.customModel = value == otherModel
			if !m.customModel {
				m.plan.LLMModel = value
			}
		},
	}
}

func typedModelScreen() *screen {
	return &screen{
		id: "model-name", section: sectionAI, kind: kindInput,
		when:  func(m *model) bool { return hasAI(m) && (m.customModel || m.otherProvider) },
		title: static(text.T("Which model?", "Qual modelo?")),
		hint:  static(text.T("Its exact name at the provider.", "O nome exato no provedor.")),
		value: func(m *model) string { return m.plan.LLMModel },
		validate: func(_ *model, value string) string {
			if strings.TrimSpace(value) == "" {
				return text.T("Heddle needs a model to go with the key.", "O Heddle precisa de um modelo para usar com a chave.")
			}
			return ""
		},
		apply: func(m *model, value string) { m.plan.LLMModel = strings.TrimSpace(value) },
	}
}

func claudeScreen() *screen {
	return &screen{
		id: "claude", section: sectionAI, kind: kindChoice, advanced: true,
		// The image of a Docker install leaves the claude binary out.
		when:  local,
		title: static(text.T("Set up the Claude Agent?", "Configurar o Claude Agent?")),
		hint: func(m *model) string {
			if m.options.Facts.Claude != "" {
				return text.T("The copilot of the editor chat, which you then turn on in LLM & Agents. Found claude at ", "O copiloto do chat do editor, que você depois liga em LLM & Agents. Encontrei o claude em ") + m.options.Facts.Claude + "."
			}
			return text.T("The copilot of the editor chat, which you then turn on in LLM & Agents. It needs the claude command, which isn't on this machine yet.", "O copiloto do chat do editor, que você depois liga em LLM & Agents. Ele precisa do comando claude, que ainda não está nesta máquina.")
		},
		options: func(*model) []option {
			return []option{
				{value: "no", label: text.T("Not now", "Agora não")},
				{value: "yes", label: text.T("Set it up", "Configurar"), note: text.T("Uses an Anthropic API key", "Usa uma chave de API da Anthropic")},
			}
		},
		value: func(m *model) string {
			if m.plan.ClaudeAgent {
				return "yes"
			}
			return "no"
		},
		apply: func(m *model, value string) {
			m.plan.ClaudeAgent = value == "yes"
			m.plan.ClaudeBin = ""
			if m.plan.ClaudeAgent {
				m.plan.ClaudeBin = m.options.Facts.Claude
			}
		},
	}
}

func claudeKeyScreen() *screen {
	return &screen{
		id: "claude-key", section: sectionAI, kind: kindInput, secret: true, advanced: true,
		// With Anthropic as the provider, Heddle reuses that key.
		when:  func(m *model) bool { return m.plan.ClaudeAgent && m.plan.LLMProvider != "anthropic" },
		title: static(text.T("Anthropic API key for the agent", "Chave de API da Anthropic para o agente")),
		hint:  static(text.T("Anthropic doesn't allow claude.ai logins in other products, so this takes an API key.", "A Anthropic não permite login do claude.ai em outros produtos, então precisa de uma chave de API.")),
		value: func(m *model) string { return m.plan.ClaudeKey },
		validate: func(_ *model, value string) string {
			if strings.TrimSpace(value) == "" {
				return text.T("The agent can't work without one. Press esc to leave it for later.", "O agente não funciona sem ela. Tecle esc para deixar para depois.")
			}
			return ""
		},
		apply: func(m *model, value string) { m.plan.ClaudeKey = strings.TrimSpace(value) },
	}
}

func claudeBudgetScreen() *screen {
	return &screen{
		id: "claude-budget", section: sectionAI, kind: kindInput, advanced: true,
		when:  func(m *model) bool { return m.plan.ClaudeAgent },
		title: static(text.T("Spending limit per chat", "Limite de gasto por chat")),
		hint:  static(text.T("In US dollars.", "Em dólares.")),
		value: func(m *model) string {
			if m.plan.ClaudeBudget != "" {
				return m.plan.ClaudeBudget
			}
			return "1"
		},
		validate: func(_ *model, value string) string {
			if amount, err := strconv.ParseFloat(strings.TrimSpace(value), 64); err != nil || amount <= 0 {
				return text.T("Use a number above zero, like 1 or 2.5.", "Use um número acima de zero, como 1 ou 2.5.")
			}
			return ""
		},
		apply: func(m *model, value string) { m.plan.ClaudeBudget = strings.TrimSpace(value) },
	}
}

// Docker Compose sets these two in its own file, so they only reach a local install.
func concurrencyScreen() *screen {
	return &screen{
		id: "concurrency", section: sectionFinish, kind: kindInput, advanced: true, when: local,
		title: static(text.T("How many flows at the same time?", "Quantos flows ao mesmo tempo?")),
		hint:  static(text.T("Runs beyond this wait in line. The default suits most computers.", "Execuções além disso esperam na fila. O padrão serve para a maioria dos computadores.")),
		value: func(m *model) string {
			if m.plan.ExecutionConcurrency > 0 {
				return strconv.Itoa(m.plan.ExecutionConcurrency)
			}
			return "50"
		},
		validate: positive,
		apply: func(m *model, value string) {
			if amount, _ := strconv.Atoi(strings.TrimSpace(value)); amount != 50 {
				m.plan.ExecutionConcurrency = amount
			}
		},
	}
}

func rescueScreen() *screen {
	return &screen{
		id: "rescue", section: sectionFinish, kind: kindInput, advanced: true, when: local,
		title: static(text.T("How long can a flow run?", "Quanto tempo um flow pode rodar?")),
		hint:  static(text.T("In minutes. After this, Heddle assumes its worker died and starts it again from the beginning, so keep it longer than your longest flow.", "Em minutos. Depois disso, o Heddle assume que o worker morreu e recomeça do início, então mantenha acima do seu flow mais longo.")),
		value: func(m *model) string {
			if m.plan.RescueMinutes > 0 {
				return strconv.Itoa(m.plan.RescueMinutes)
			}
			return "60"
		},
		validate: positive,
		apply: func(m *model, value string) {
			if amount, _ := strconv.Atoi(strings.TrimSpace(value)); amount != 60 {
				m.plan.RescueMinutes = amount
			}
		},
	}
}

// Spool is the database Heddle keeps for each workspace. Docker reads these from
// .env too, so they reach either install.
func spoolTablesScreen() *screen {
	return &screen{
		id: "spool-tables", section: sectionFinish, kind: kindInput, advanced: true, when: heddle,
		title: static(text.T("How many Spool tables can a workspace keep?", "Quantas tabelas do Spool um workspace pode ter?")),
		hint:  static(text.T("Spool keeps tables inside Heddle's own database, for forms and flows.", "O Spool guarda tabelas no próprio banco do Heddle, para formulários e flows.")),
		value: func(m *model) string {
			if m.plan.SpoolMaxTables > 0 {
				return strconv.Itoa(m.plan.SpoolMaxTables)
			}
			return "50"
		},
		validate: positive,
		apply: func(m *model, value string) {
			if amount, _ := strconv.Atoi(strings.TrimSpace(value)); amount != 50 {
				m.plan.SpoolMaxTables = amount
			}
		},
	}
}

func spoolRowsScreen() *screen {
	return &screen{
		id: "spool-rows", section: sectionFinish, kind: kindInput, advanced: true, when: heddle,
		title: static(text.T("How many rows can a Spool table keep?", "Quantas linhas uma tabela do Spool pode ter?")),
		hint:  static(text.T("A public form can fill a table quickly, so this keeps one from filling the database.", "Um formulário público pode encher uma tabela depressa, então isso impede que uma tabela lote o banco.")),
		value: func(m *model) string {
			if m.plan.SpoolMaxRows > 0 {
				return strconv.Itoa(m.plan.SpoolMaxRows)
			}
			return "100000"
		},
		validate: positive,
		apply: func(m *model, value string) {
			if amount, _ := strconv.Atoi(strings.TrimSpace(value)); amount != 100000 {
				m.plan.SpoolMaxRows = amount
			}
		},
	}
}

func positive(_ *model, value string) string {
	if amount, err := strconv.Atoi(strings.TrimSpace(value)); err != nil || amount < 1 {
		return text.T("Use a whole number above zero.", "Use um número inteiro acima de zero.")
	}
	return ""
}

func treadleHomeScreen() *screen {
	return &screen{
		id: "treadle-home", section: sectionTreadle, kind: kindInput, advanced: true,
		when:  func(m *model) bool { return m.plan.Treadle },
		title: static(text.T("Where should Treadle go?", "Onde o Treadle deve ficar?")),
		hint:  static(text.T("Your login is kept elsewhere, so updating won't sign you out.", "Seu login fica em outro lugar, então atualizar não desconecta você.")),
		value: func(m *model) string { return m.plan.TreadleHome },
		validate: func(_ *model, value string) string {
			if !filepath.IsAbs(expandHome(strings.TrimSpace(value))) {
				return text.T("Use a full path.", "Use um caminho completo.")
			}
			return ""
		},
		apply: func(m *model, value string) { m.plan.TreadleHome = expandHome(strings.TrimSpace(value)) },
	}
}

func treadleServerScreen() *screen {
	return &screen{
		id: "treadle-server", section: sectionTreadle, kind: kindInput,
		// A Heddle installed now has no account yet, so there's no key to give it.
		when:        func(m *model) bool { return m.plan.Treadle && !m.plan.Heddle },
		title:       static(text.T("Which Heddle will Treadle connect to?", "Em qual Heddle o Treadle vai conectar?")),
		hint:        static(text.T("Leave it empty to answer when you open Treadle.", "Deixe vazio para responder quando abrir o Treadle.")),
		placeholder: static("https://heddle.example.com"),
		value:       func(m *model) string { return m.plan.TreadleServer },
		apply: func(m *model, value string) {
			m.plan.TreadleServer = treadle.NormalizeServer(value)
			if m.plan.TreadleServer == "" {
				m.plan.TreadleKey = ""
			}
		},
	}
}

func treadleKeyScreen() *screen {
	return &screen{
		id: "treadle-key", section: sectionTreadle, kind: kindInput, secret: true,
		when:  func(m *model) bool { return m.plan.Treadle && !m.plan.Heddle && m.plan.TreadleServer != "" },
		title: static(text.T("API key of that server", "Chave de API desse servidor")),
		hint:  static(text.T("Leave it empty to sign in with your browser when you open Treadle.", "Deixe vazio para entrar pelo navegador quando abrir o Treadle.")),
		value: func(m *model) string { return m.plan.TreadleKey },
		check: func(m *model, value string) tea.Cmd {
			server := m.plan.TreadleServer
			return func() tea.Msg {
				return checkedMsg{value: value, err: treadle.Check(m.ctx, server, strings.TrimSpace(value))}
			}
		},
		checkLabel: func(m *model) string {
			return text.T("Checking with ", "Conferindo com ") + m.plan.TreadleServer
		},
		apply: func(m *model, value string) { m.plan.TreadleKey = strings.TrimSpace(value) },
	}
}

func finishScreen() *screen {
	return &screen{
		id: "finish", section: sectionFinish, kind: kindToggles, advanced: true,
		title: static(text.T("Last touches", "Últimos detalhes")),
		hint:  static(text.T("Space turns an option on or off.", "Espaço liga ou desliga uma opção.")),
		options: func(m *model) []option {
			options := []option{{value: togglePath, label: text.T("Add the commands to my PATH", "Adicionar os comandos ao meu PATH")}}
			if !m.plan.Heddle {
				return options
			}
			options = append(options, option{value: toggleStart, label: text.T("Start Heddle when it's done", "Iniciar o Heddle ao terminar")})
			if !m.plan.Docker() {
				options = append(options, option{value: toggleBrowser, label: text.T("Open the browser", "Abrir o navegador")})
				if install.AutostartSupported() {
					options = append(options, option{value: toggleAutostart, label: text.T("Start Heddle with this computer", "Iniciar o Heddle com o computador")})
				}
			}
			return options
		},
		toggled: func(m *model, value string) bool {
			switch value {
			case togglePath:
				return m.plan.AddToPath
			case toggleStart:
				return m.plan.Start
			case toggleBrowser:
				return m.plan.Browser
			}
			return m.plan.Autostart
		},
		toggle: func(m *model, value string, on bool) {
			switch value {
			case togglePath:
				m.plan.AddToPath = on
			case toggleStart:
				m.plan.Start = on
			case toggleBrowser:
				m.plan.Browser = on
			case toggleAutostart:
				m.plan.Autostart = on
			}
		},
	}
}

func reviewScreen() *screen {
	return &screen{
		id: "review", section: sectionFinish, kind: kindReview,
		title: func(m *model) string {
			if m.options.SettingsOnly {
				return text.T("Save these settings?", "Salvar estas configurações?")
			}
			return text.T("Ready to install", "Pronto para instalar")
		},
		hint: func(m *model) string {
			if m.options.SettingsOnly {
				return ""
			}
			return text.T("Nothing has changed on your computer so far.", "Nada mudou no seu computador até aqui.")
		},
	}
}

func isErr(err, target error) bool { return errors.Is(err, target) }
