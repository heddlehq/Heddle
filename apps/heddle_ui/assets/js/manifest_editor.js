import { loadMonaco } from "./code_editor"

// The manifest of a new integration, in YAML. Monaco edits it, and the hidden textarea
// carries it to the form, so the page checks it as it changes.

const isDark = () => document.documentElement.dataset.theme === "dark";
const themeName = () => (isDark() ? "heddle-yaml-dark" : "heddle-yaml-light");

// The keys a manifest takes, by where they go, for the suggestions.
const KEYS = {
  top: ["id", "name", "version", "description", "icon", "base_url", "credential", "errors", "actions", "triggers"],
  credential: ["label", "fields", "auth"],
  auth: ["type", "token", "name", "value", "username", "password", "authorize_url", "token_url", "scopes"],
  action: ["name", "description", "fields", "request", "output", "pagination", "poll"],
  field: ["name", "label", "type", "default", "options", "secret", "required"],
  request: ["method", "path", "query", "headers", "body", "body_type"],
  output: ["path", "pick", "value"],
  pagination: ["type", "items_path", "page_size", "limit_param", "cursor_param", "next_path", "offset_param"],
};

const VALUES = {
  type: ["bearer", "header", "query", "basic", "oauth2", "none", "text", "textarea", "number", "select", "cursor", "offset", "link"],
  method: ["GET", "POST", "PUT", "PATCH", "DELETE"],
  body_type: ["json", "form"],
};

const registerManifest = (monaco) => {
  if (window.__heddleManifestReady) return;
  window.__heddleManifestReady = true;

  const theme = (base, background, foreground, muted, key, text, number, keyword) => ({
    base,
    inherit: true,
    rules: [
      { token: "type", foreground: key, fontStyle: "bold" },
      { token: "string", foreground: text },
      { token: "number", foreground: number },
      { token: "keyword", foreground: keyword },
      { token: "comment", foreground: muted, fontStyle: "italic" },
      { token: "operators", foreground: muted },
      { token: "delimiter", foreground: muted },
    ],
    colors: {
      "editor.background": background,
      "editor.foreground": foreground,
      "editor.lineHighlightBackground": "#00000000",
      "editor.lineHighlightBorder": "#00000000",
      "editorLineNumber.foreground": `#${muted}`,
      "editorCursor.foreground": `#${key}`,
      "editorIndentGuide.background1": `#${muted}33`,
    },
  });

  monaco.editor.defineTheme(
    "heddle-yaml-dark",
    theme("vs-dark", "#181a1e", "#f3ebdc", "8d8a82", "e8907d", "7fc4a0", "7cc0d0", "e0b561"),
  );
  monaco.editor.defineTheme(
    "heddle-yaml-light",
    theme("vs", "#fbf6ec", "#23262b", "8a8578", "a63a2b", "3f7d5e", "2f6f7e", "9a6a13"),
  );

  monaco.languages.registerCompletionItemProvider("yaml", {
    triggerCharacters: ["{", " "],
    provideCompletionItems: (model, position) => {
      const line = model.getLineContent(position.lineNumber).slice(0, position.column - 1);
      const word = model.getWordUntilPosition(position);
      const range = {
        startLineNumber: position.lineNumber,
        endLineNumber: position.lineNumber,
        startColumn: word.startColumn,
        endColumn: word.endColumn,
      };
      const { CompletionItemKind: Kind, CompletionItemInsertTextRule: Rule } = monaco.languages;

      // Inside {{ }}: what a template reads.
      if (/\{\{[\w.]*$/.test(line)) {
        return {
          suggestions: ["fields.", "credential."].map((label) => ({
            label,
            kind: Kind.Variable,
            insertText: label,
            range,
            command: { id: "editor.action.triggerSuggest" },
          })),
        };
      }

      // After `key: `, the values that key takes.
      const valueOf = line.match(/^\s*-?\s*(\w+):\s+\w*$/);
      if (valueOf && VALUES[valueOf[1]]) {
        return {
          suggestions: VALUES[valueOf[1]].map((label) => ({
            label,
            kind: Kind.EnumMember,
            insertText: label,
            range,
          })),
        };
      }

      // At the start of a line, the keys.
      if (/^\s*-?\s*\w*$/.test(line)) {
        const keys = [...new Set(Object.values(KEYS).flat())];
        return {
          suggestions: keys.map((key) => ({
            label: key,
            kind: Kind.Property,
            insertText: `${key}: $0`,
            insertTextRules: Rule.InsertAsSnippet,
            range,
          })),
        };
      }

      return { suggestions: [] };
    },
  });
};

export const ManifestEditorHook = {
  mounted() {
    this.input = this.el.querySelector("textarea");

    loadMonaco()
      .then((monaco) => {
        if (!this.gone) this.createEditor(monaco);
      })
      .catch((error) => console.error("Could not load the code editor:", error));
  },

  destroyed() {
    this.gone = true;
    if (this.themeObserver) this.themeObserver.disconnect();
    if (this.editor) this.editor.dispose();
  },

  createEditor(monaco) {
    registerManifest(monaco);
    this.monaco = monaco;

    const holder = this.el.querySelector("[data-monaco]");
    this.editor = monaco.editor.create(holder, {
      value: this.input.value,
      language: "yaml",
      theme: themeName(),
      automaticLayout: true,
      renderLineHighlight: "none",
      overviewRulerLanes: 0,
      hideCursorInOverviewRuler: true,
      padding: { top: 14, bottom: 14 },
      scrollbar: { verticalScrollbarSize: 8, horizontalScrollbarSize: 8 },
      minimap: { enabled: false },
      scrollBeyondLastLine: false,
      lineNumbersMinChars: 3,
      folding: true,
      showFoldingControls: "mouseover",
      glyphMargin: false,
      tabSize: 2,
      insertSpaces: true,
      detectIndentation: false,
      guides: { indentation: true },
      fontSize: 13,
      lineHeight: 21,
      fontFamily: "'Fira Code', Consolas, 'Courier New', monospace",
      quickSuggestions: { other: true, strings: true, comments: false },
    });

    this.input.classList.add("hidden");
    holder.classList.remove("hidden");

    this.editor.onDidChangeModelContent(() => {
      this.input.value = this.editor.getValue();
      this.input.dispatchEvent(new Event("input", { bubbles: true }));
    });

    this.themeObserver = new MutationObserver(() => monaco.editor.setTheme(themeName()));
    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    });

    this.editor.focus();
  },
};
