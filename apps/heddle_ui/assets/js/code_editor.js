// Monaco is served by the app itself, so the editor works without internet access.
// It only runs on the flow editor page, which starts loading it ahead of time.
const MONACO_PATH = "/assets/vendor/monaco/vs";

let monacoLoading = null;

const registerCompletions = (monaco) => {
    try {
        monaco.languages.registerCompletionItemProvider('elixir', {
            provideCompletionItems: (model, position) => {
                const suggestions = [
                    {
                        label: 'variable',
                        kind: monaco.languages.CompletionItemKind.Function,
                        insertText: 'variable',
                        documentation: 'Get a variable from context (returns nil if missing)',
                        detail: 'HeddleRuntime.Runtime.Elixir.variable/1'
                    },
                    {
                        label: 'variable!',
                        kind: monaco.languages.CompletionItemKind.Function,
                        insertText: 'variable!',
                        documentation: 'Get a variable from context (raises if missing)',
                        detail: 'HeddleRuntime.Runtime.Elixir.variable!/1'
                    },
                    {
                        label: 'set_result',
                        kind: monaco.languages.CompletionItemKind.Function,
                        insertText: 'set_result',
                        documentation: 'Set the value passed to the next node (overrides last expression)',
                        detail: 'HeddleRuntime.Runtime.Elixir.set_result/1'
                    }
                ];

                const availableVars = window.__heddleCurrentVariables || [];
                availableVars.forEach(varName => {
                    suggestions.push({
                        label: `:${varName}`,
                        kind: monaco.languages.CompletionItemKind.Constant,
                        insertText: `:${varName}`,
                        documentation: `Variable from flow: ${varName}`,
                        detail: 'Atom'
                    });
                });

                return { suggestions: suggestions };
            }
        });
    } catch (e) {
        console.error("Failed to register Elixir completion provider:", e);
    }

    try {
        monaco.languages.registerCompletionItemProvider('python', {
            provideCompletionItems: (model, position) => {
                const suggestions = [
                    {
                        label: 'variable',
                        kind: monaco.languages.CompletionItemKind.Function,
                        insertText: 'variable',
                        documentation: 'Get a variable from context (returns None if missing)',
                        detail: 'HeddleRuntime.Runtime.Python.variable(name, default=None)'
                    },
                    {
                        label: 'variable_required',
                        kind: monaco.languages.CompletionItemKind.Function,
                        insertText: 'variable_required',
                        documentation: 'Get a variable from context (raises KeyError if missing)',
                        detail: 'HeddleRuntime.Runtime.Python.variable_required(name)'
                    },
                    {
                        label: 'set_result',
                        kind: monaco.languages.CompletionItemKind.Function,
                        insertText: 'set_result',
                        documentation: 'Set the value passed to the next node (overrides last expression)',
                        detail: 'HeddleRuntime.Runtime.Python.set_result(value)'
                    }
                ];

                const availableVars = window.__heddleCurrentVariables || [];
                availableVars.forEach(varName => {
                    suggestions.push({
                        label: varName,
                        kind: monaco.languages.CompletionItemKind.Variable,
                        insertText: varName,
                        documentation: `Variable from flow: ${varName}`,
                        detail: 'Flow variable'
                    });
                });

                return { suggestions: suggestions };
            }
        });
    } catch (e) {
        console.error("Failed to register Python completion provider:", e);
    }
};

export const loadMonaco = () => {
    if (monacoLoading) return monacoLoading;

    monacoLoading = new Promise((resolve, reject) => {
        const start = () => {
            window.require.config({ paths: { vs: MONACO_PATH } });
            window.require(["vs/editor/editor.main"], () => {
                registerCompletions(window.monaco);
                resolve(window.monaco);
            }, reject);
        };

        if (window.require) return start();

        const script = document.createElement("script");
        script.src = `${MONACO_PATH}/loader.js`;
        script.async = true;
        script.onload = start;
        script.onerror = reject;
        document.body.appendChild(script);
    }).catch((error) => {
        monacoLoading = null;
        throw error;
    });

    return monacoLoading;
};

export const CodeEditorHook = {
    mounted() {
        this.language = this.el.dataset.language || "elixir";
        this.showField();

        window.__heddleCurrentVariables = JSON.parse(this.el.dataset.variables || "[]");

        // The field already shows the code, so a slow or failed load never leaves
        // the modal empty. Monaco takes over when it is ready.
        loadMonaco()
            .then((monaco) => {
                if (!this.gone) this.createEditor(monaco);
            })
            .catch((error) => console.error("Could not load the code editor:", error));
    },

    updated() {
        const language = this.el.dataset.language;
        if (!language || language === this.language) return;

        // The language changes first: setValue fires the change listener, which
        // would otherwise write the new text over the code of the old language.
        this.language = language;
        this.showField();

        if (this.editor) {
            this.editor.setValue(this.field().value);
            window.monaco.editor.setModelLanguage(this.editor.getModel(), language);
        }
    },

    destroyed() {
        this.gone = true;
        if (this.editor) this.editor.dispose();
    },

    field(language = this.language) {
        return this.el.querySelector(`#code_${language}_textarea`);
    },

    showField() {
        for (const language of ["elixir", "python"]) {
            this.field(language).classList.toggle("hidden", !!this.editor || language !== this.language);
        }
    },

    createEditor(monaco) {
        const container = document.createElement("div");
        container.className = "absolute inset-0";
        this.el.appendChild(container);

        this.editor = monaco.editor.create(container, {
            value: this.field().value,
            language: this.language,
            theme: "vs-dark",
            automaticLayout: true,
            minimap: { enabled: false },
            scrollBeyondLastLine: false,
            fontSize: 14,
            fontFamily: "'Fira Code', Consolas, 'Courier New', monospace",
        });

        this.editor.onDidChangeModelContent(() => {
            this.field().value = this.editor.getValue();
        });

        this.showField();
        this.editor.focus();
    },
};
