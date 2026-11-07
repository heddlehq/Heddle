import { loadMonaco } from "./code_editor"

// The body of a test request, as JSON or as a list of parameters. Both edit the same
// value, which the form sends through the hidden input.

const TAB_ACTIVE = "border-primary text-primary";
const TAB_IDLE = "border-transparent text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200";
const VALUE_FIELD = "w-full rounded-md border border-gray-200 bg-white py-2 pl-3 pr-16 text-sm text-gray-900 outline-none transition placeholder:text-gray-400 focus:border-primary dark:border-slate-700 dark:bg-slate-900 dark:text-white";
const NAME_FIELD = "w-full min-w-0 truncate rounded-md border border-transparent bg-transparent px-1 py-2 font-mono text-sm text-gray-900 outline-none transition placeholder:text-gray-400 focus:border-primary dark:text-white";

// What is typed becomes the value it looks like: 10 is a number, and "10" a string.
export const parseValue = (text) => {
    const trimmed = text.trim();

    if (trimmed === "true") return true;
    if (trimmed === "false") return false;
    if (trimmed === "null") return null;
    if (/^-?\d+(\.\d+)?$/.test(trimmed)) return Number(trimmed);

    if (/^[[{"]/.test(trimmed)) {
        try {
            return JSON.parse(trimmed);
        } catch (_error) {
            return text;
        }
    }
    return text;
};

const typeOf = (value) => {
    if (value === null) return "null";
    if (Array.isArray(value)) return "list";
    return typeof value;
};

const toText = (value) => (typeof value === "string" ? value : JSON.stringify(value));

const isDark = () => document.documentElement.dataset.theme === "dark";

const themeName = () => (isDark() ? "heddle-json-dark" : "heddle-json-light");

// Only the part of Monaco the code modal uses is served, which leaves JSON out.
const registerJson = (monaco) => {
    if (monaco.languages.getLanguages().some(({ id }) => id === "heddle-json")) return;

    monaco.languages.register({ id: "heddle-json" });
    monaco.languages.setLanguageConfiguration("heddle-json", {
        brackets: [["{", "}"], ["[", "]"]],
        autoClosingPairs: [
            { open: "{", close: "}" },
            { open: "[", close: "]" },
            { open: '"', close: '"' },
        ],
    });
    monaco.languages.setMonarchTokensProvider("heddle-json", {
        tokenizer: {
            root: [
                [/"(?:[^"\\]|\\.)*"(?=\s*:)/, "key"],
                [/"(?:[^"\\]|\\.)*"/, "string"],
                [/-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/, "number"],
                [/\b(?:true|false|null)\b/, "keyword"],
                [/[{}[\],:]/, "delimiter"],
            ],
        },
    });

    // The colors of the brand: ribbon for keys, and the node colors for values.
    const theme = (base, background, foreground, muted, key, text, number, keyword) => ({
        base,
        inherit: true,
        rules: [
            { token: "key", foreground: key, fontStyle: "bold" },
            { token: "string", foreground: text },
            { token: "number", foreground: number },
            { token: "keyword", foreground: keyword },
            { token: "delimiter", foreground: muted },
        ],
        colors: {
            "editor.background": background,
            "editor.foreground": foreground,
            "editor.lineHighlightBackground": "#00000000",
            "editor.lineHighlightBorder": "#00000000",
            "editorCursor.foreground": `#${key}`,
        },
    });

    monaco.editor.defineTheme(
        "heddle-json-dark",
        theme("vs-dark", "#181a1e", "#f3ebdc", "8d8a82", "e8907d", "7fc4a0", "7cc0d0", "e0b561"),
    );
    monaco.editor.defineTheme(
        "heddle-json-light",
        theme("vs", "#fbf6ec", "#23262b", "8a8578", "a63a2b", "3f7d5e", "2f6f7e", "9a6a13"),
    );
};

export const WebhookBodyHook = {
    mounted() {
        this.input = this.el.querySelector("input[type=hidden]");
        this.jsonPane = this.el.querySelector("[data-pane=json]");
        this.paramsPane = this.el.querySelector("[data-pane=params]");
        this.rowsEl = this.el.querySelector("[data-rows]");
        this.errorEl = this.el.querySelector("[data-error]");
        this.tabs = this.el.querySelectorAll("[data-tab]");
        this.labels = this.el.dataset;
        this.suggested = JSON.parse(this.labels.fields || "[]");
        this.tab = this.suggested.length > 0 ? "params" : "json";
        this.rows = [];

        this.tabs.forEach((tab) => {
            tab.addEventListener("click", () => this.switchTo(tab.dataset.tab));
        });
        this.el.querySelector("[data-add]").addEventListener("click", () => this.addRow());
        this.el.querySelector("[data-format]").addEventListener("click", () => this.format());

        this.loadRows(this.parsed() ?? {});
        this.show();

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

    parsed() {
        try {
            return JSON.parse(this.input.value || "{}");
        } catch (_error) {
            return null;
        }
    },

    createEditor(monaco) {
        registerJson(monaco);

        this.editor = monaco.editor.create(this.el.querySelector("[data-monaco]"), {
            value: this.input.value,
            language: "heddle-json",
            theme: themeName(),
            automaticLayout: true,
            renderLineHighlight: "none",
            overviewRulerLanes: 0,
            hideCursorInOverviewRuler: true,
            padding: { top: 12, bottom: 12 },
            scrollbar: { verticalScrollbarSize: 8, horizontalScrollbarSize: 8 },
            minimap: { enabled: false },
            scrollBeyondLastLine: false,
            lineNumbers: "off",
            folding: false,
            glyphMargin: false,
            lineDecorationsWidth: 12,
            tabSize: 2,
            fontSize: 13,
            fontFamily: "'Fira Code', Consolas, 'Courier New', monospace",
        });

        this.editor.onDidChangeModelContent(() => {
            this.input.value = this.editor.getValue();
            this.setError(null);
        });
        this.el.querySelector("[data-fallback]").classList.add("hidden");

        // Monaco has one theme for the page, so this also covers a change of theme.
        this.themeObserver = new MutationObserver(() => monaco.editor.setTheme(themeName()));
        this.themeObserver.observe(document.documentElement, {
            attributes: true,
            attributeFilter: ["data-theme"],
        });
    },

    format() {
        const value = this.parsed();
        if (value === null) return this.setError(this.labels.invalid);

        this.writeJson(value);
    },

    writeJson(value) {
        const text = JSON.stringify(value, null, 2);

        this.input.value = text;
        if (this.editor && this.editor.getValue() !== text) this.editor.setValue(text);
    },

    switchTo(tab) {
        if (tab === this.tab) return;

        if (tab === "params") {
            const value = this.parsed();
            if (value === null || typeOf(value) !== "object") {
                return this.setError(this.labels.invalid);
            }
            this.loadRows(value);
        } else {
            this.writeJson(this.fromRows());
        }

        this.tab = tab;
        this.setError(null);
        this.show();
    },

    show() {
        this.jsonPane.classList.toggle("hidden", this.tab !== "json");
        this.paramsPane.classList.toggle("hidden", this.tab !== "params");
        this.el.querySelector("[data-format]").classList.toggle("hidden", this.tab !== "json");

        this.tabs.forEach((tab) => {
            const active = tab.dataset.tab === this.tab;
            tab.className = `-mb-px border-b-2 px-3 py-2 text-sm font-medium transition ${active ? TAB_ACTIVE : TAB_IDLE}`;
        });
    },

    setError(message) {
        this.errorEl.textContent = message || "";
        this.errorEl.classList.toggle("hidden", !message);
    },

    // What the flow reads comes first, so filling it in is all it takes.
    loadRows(value) {
        const names = [...new Set([...this.suggested, ...Object.keys(value)])];

        this.rows = names.map((name) => ({
            name,
            text: name in value ? toText(value[name]) : "",
            suggested: this.suggested.includes(name),
        }));
        this.renderRows();
    },

    fromRows() {
        const value = {};

        this.rows
            .filter((row) => row.name.trim() !== "")
            .filter((row) => !row.suggested || row.text !== "")
            .forEach((row) => {
                value[row.name.trim()] = parseValue(row.text);
            });
        return value;
    },

    addRow() {
        this.rows.push({ name: "", text: "", suggested: false });
        this.renderRows();
        this.rowsEl.querySelector("[data-row]:last-child input").focus();
    },

    renderRows() {
        this.rowsEl.replaceChildren(...this.rows.map((row, index) => this.rowElement(row, index)));
    },

    rowElement(row, index) {
        const element = document.createElement("div");
        element.dataset.row = "";
        element.className = "group grid grid-cols-[minmax(0,2fr)_minmax(0,3fr)_1.25rem] items-center gap-2";

        // A field the flow reads has its name settled, so only its value is left to fill.
        const name = document.createElement("input");
        name.value = row.name;
        name.readOnly = row.suggested;
        name.placeholder = this.labels.nameLabel;
        name.setAttribute("aria-label", this.labels.nameLabel);
        name.className = NAME_FIELD;

        const box = document.createElement("div");
        box.className = "relative min-w-0";

        const value = document.createElement("input");
        value.value = row.text;
        value.placeholder = this.labels.valueLabel;
        value.setAttribute("aria-label", row.name || this.labels.valueLabel);
        value.className = VALUE_FIELD;

        const type = document.createElement("span");
        type.dataset.type = "";
        type.className = "pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 rounded bg-primary/10 px-1.5 py-0.5 font-mono text-[10px] text-primary empty:hidden";

        const remove = document.createElement("button");
        remove.type = "button";
        remove.textContent = "×";
        remove.setAttribute("aria-label", this.labels.removeLabel);
        remove.className = "text-lg leading-none text-gray-400 opacity-0 transition hover:text-error focus:opacity-100 group-hover:opacity-100";

        const showType = () => {
            type.textContent = row.text === "" ? "" : typeOf(parseValue(row.text));
        };
        const refresh = () => {
            showType();
            this.writeJson(this.fromRows());
        };

        name.addEventListener("input", () => {
            row.name = name.value;
            refresh();
        });
        value.addEventListener("input", () => {
            row.text = value.value;
            refresh();
        });
        remove.addEventListener("click", () => {
            this.rows.splice(index, 1);
            this.renderRows();
            this.writeJson(this.fromRows());
        });

        showType();
        box.append(value, type);
        element.append(name, box, remove);
        return element;
    },
};
