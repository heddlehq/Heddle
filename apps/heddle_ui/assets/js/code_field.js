import { loadMonaco } from "./code_editor"
import { registerJson, themeName } from "./webhook_body"

// A field of a node that holds code, like a JSON body or a SQL query, in the node's
// drawer: Monaco with its colors, over the textarea the form sends. The textarea shows
// the text until Monaco loads, and stays the field: each change is written to it, and
// it tells the form, so the canvas gets it as with any other field.

const MIN_HEIGHT = 96;
const MAX_HEIGHT = 360;
const LINE_HEIGHT = 19;

// The placeholders of a flow, like {{body.email}}, in every language.
const PLACEHOLDER = [/\{\{[^}]*\}\}/, "placeholder"];

const SQL_KEYWORDS = [
    "select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set",
    "delete", "join", "left", "right", "inner", "outer", "on", "group", "by", "order", "having",
    "limit", "offset", "as", "in", "is", "null", "like", "between", "distinct", "returning",
    "create", "table", "drop", "alter", "with", "case", "when", "then", "else", "end", "asc", "desc",
    "union", "all", "exists", "true", "false",
];

const registerLanguages = (monaco) => {
    registerJson(monaco);
    const known = (id) => monaco.languages.getLanguages().some((language) => language.id === id);

    if (!known("heddle-json-template")) {
        monaco.languages.register({ id: "heddle-json-template" });
        monaco.languages.setLanguageConfiguration("heddle-json-template", {
            brackets: [["{", "}"], ["[", "]"]],
            autoClosingPairs: [
                { open: "[", close: "]" },
                { open: '"', close: '"' },
            ],
        });
        monaco.languages.setMonarchTokensProvider("heddle-json-template", {
            tokenizer: {
                root: [
                    PLACEHOLDER,
                    [/"(?:[^"\\]|\\.)*"(?=\s*:)/, "key"],
                    [/"/, { token: "string", next: "@string" }],
                    [/-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/, "number"],
                    [/\b(?:true|false|null)\b/, "keyword"],
                    [/[{}[\],:]/, "delimiter"],
                ],
                string: [
                    PLACEHOLDER,
                    [/[^"\\{]+/, "string"],
                    [/\\./, "string"],
                    [/\{/, "string"],
                    [/"/, { token: "string", next: "@pop" }],
                ],
            },
        });
    }

    if (!known("heddle-sql")) {
        monaco.languages.register({ id: "heddle-sql" });
        monaco.languages.setMonarchTokensProvider("heddle-sql", {
            ignoreCase: true,
            keywords: SQL_KEYWORDS,
            tokenizer: {
                root: [
                    PLACEHOLDER,
                    [/--.*$/, "comment"],
                    [/'(?:[^']|'')*'/, "string"],
                    [/-?\d+(?:\.\d+)?/, "number"],
                    [/[a-zA-Z_][\w$]*/, { cases: { "@keywords": "keyword", "@default": "identifier" } }],
                    [/[(),;.*=<>!+\-/]/, "delimiter"],
                ],
            },
        });
    }

    if (!known("heddle-html")) {
        monaco.languages.register({ id: "heddle-html" });
        monaco.languages.setMonarchTokensProvider("heddle-html", {
            tokenizer: {
                root: [
                    PLACEHOLDER,
                    [/<!--[\s\S]*?-->/, "comment"],
                    [/<\/?[\w-]+/, "key"],
                    [/\/?>/, "key"],
                    [/"[^"]*"/, "string"],
                    [/[\w-]+(?==)/, "number"],
                ],
            },
        });
    }

    if (!known("heddle-text")) {
        monaco.languages.register({ id: "heddle-text" });
        monaco.languages.setMonarchTokensProvider("heddle-text", { tokenizer: { root: [PLACEHOLDER] } });
    }

    for (const [name, placeholder, comment] of [
        ["heddle-code-dark", "e0b561", "8d8a82"],
        ["heddle-code-light", "9a6a13", "8a8578"],
    ]) {
        const dark = name.endsWith("dark");
        monaco.editor.defineTheme(name, {
            base: dark ? "vs-dark" : "vs",
            inherit: true,
            rules: [
                { token: "placeholder", foreground: placeholder, fontStyle: "bold" },
                { token: "comment", foreground: comment, fontStyle: "italic" },
                { token: "key", foreground: dark ? "e8907d" : "a63a2b", fontStyle: "bold" },
                { token: "string", foreground: dark ? "7fc4a0" : "3f7d5e" },
                { token: "number", foreground: dark ? "7cc0d0" : "2f6f7e" },
                { token: "keyword", foreground: dark ? "e0b561" : "9a6a13" },
                { token: "identifier", foreground: dark ? "f3ebdc" : "23262b" },
                { token: "delimiter", foreground: comment },
            ],
            colors: {
                "editor.background": dark ? "#181a1e" : "#fbf6ec",
                "editor.foreground": dark ? "#f3ebdc" : "#23262b",
                "editor.lineHighlightBackground": "#00000000",
                "editor.lineHighlightBorder": "#00000000",
            },
        });
    }
};

const LANGUAGES = {
    json: "heddle-json-template",
    sql: "heddle-sql",
    html: "heddle-html",
    elixir: "elixir",
    python: "python",
    text: "heddle-text",
};

const codeTheme = () => (themeName().endsWith("dark") ? "heddle-code-dark" : "heddle-code-light");

export const CodeFieldHook = {
    mounted() {
        this.field = this.el.querySelector("textarea");
        this.host = this.el.querySelector("[data-monaco]");

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
        registerLanguages(monaco);

        this.editor = monaco.editor.create(this.host, {
            value: this.field.value,
            language: LANGUAGES[this.el.dataset.language] || "heddle-text",
            theme: codeTheme(),
            readOnly: this.field.disabled || this.el.dataset.readOnly === "true",
            automaticLayout: true,
            wordWrap: "on",
            renderLineHighlight: "none",
            overviewRulerLanes: 0,
            hideCursorInOverviewRuler: true,
            padding: { top: 10, bottom: 10 },
            scrollbar: { verticalScrollbarSize: 8, horizontalScrollbarSize: 8, alwaysConsumeMouseWheel: false },
            minimap: { enabled: false },
            scrollBeyondLastLine: false,
            lineNumbers: "off",
            folding: false,
            glyphMargin: false,
            lineDecorationsWidth: 10,
            tabSize: 2,
            fontSize: 13,
            lineHeight: LINE_HEIGHT,
            fontFamily: "'Fira Code', Consolas, 'Courier New', monospace",
        });

        this.editor.onDidChangeModelContent(() => {
            this.field.value = this.editor.getValue();
            this.field.dispatchEvent(new Event("input", { bubbles: true }));
            this.fit();
        });

        this.field.classList.add("hidden");
        this.host.classList.remove("hidden");
        this.fit();

        // Monaco has one theme for the page, so this also covers a change of theme.
        this.themeObserver = new MutationObserver(() => monaco.editor.setTheme(codeTheme()));
        this.themeObserver.observe(document.documentElement, {
            attributes: true,
            attributeFilter: ["data-theme"],
        });
    },

    // As tall as the code, between a few lines and a screenful.
    fit() {
        const height = Math.min(MAX_HEIGHT, Math.max(MIN_HEIGHT, this.editor.getContentHeight()));
        this.host.style.height = `${height}px`;
        this.editor.layout();
    },
};
