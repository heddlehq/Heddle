import { Socket } from "phoenix"

// The screen of the terminal. It talks to the server on a socket of its own, because a
// terminal sends a message for every key and repaint, and LiveView is for something else.

const palette = () => {
    const style = getComputedStyle(document.documentElement);
    const color = (name) => style.getPropertyValue(name).trim();

    return {
        background: color("--editor-surface"),
        foreground: color("--editor-text"),
        cursor: color("--color-primary"),
        selectionBackground: color("--editor-border"),
    };
};

// WebGL draws much faster on a graphics card, and much slower without one: in software,
// 400 repaints took three times as long and froze the page. So it has to be a real card.
const hasGpu = () => {
    const gl = document.createElement("canvas").getContext("webgl2");
    if (!gl) return false;

    const info = gl.getExtension("WEBGL_debug_renderer_info");
    const renderer = info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : "";

    return renderer !== "" && !/swiftshader|llvmpipe|softpipe|software/i.test(renderer);
};

export const TerminalHook = {
    mounted() {
        this.observer = new ResizeObserver(() => this.fit());
        this.observer.observe(this.el);

        this.handleEvent("terminal_restart", () => this.connect());

        this.themeObserver = new MutationObserver(() => {
            if (this.term) this.term.options.theme = palette();
        });
        this.themeObserver.observe(document.documentElement, {
            attributes: true,
            attributeFilter: ["data-theme"],
        });
    },

    destroyed() {
        this.observer?.disconnect();
        this.themeObserver?.disconnect();
        this.channel?.leave();
        this.socket?.disconnect();
        this.term?.dispose();
    },

    async open() {
        const [{ Terminal }, { FitAddon }, { WebglAddon }] = await Promise.all([
            import("@xterm/xterm"),
            import("@xterm/addon-fit"),
            import("@xterm/addon-webgl"),
        ]);

        this.term = new Terminal({
            cursorBlink: true,
            fontSize: 13,
            fontFamily: "'Fira Code', Consolas, 'Courier New', monospace",
            scrollback: 2000,
            theme: palette(),
        });
        this.fitAddon = new FitAddon();
        this.term.loadAddon(this.fitAddon);
        this.term.open(this.el);
        this.el.xterm = this.term;
        this.useGpu(WebglAddon);
        this.fitAddon.fit();

        this.term.onData((data) => this.channel?.push("input", { data }));
        this.term.onResize(({ cols, rows }) => this.channel?.push("resize", { cols, rows }));

        this.socket = new Socket("/terminal", { params: { token: this.el.dataset.token } });
        this.socket.connect();
        this.connect();
        this.term.focus();
    },

    useGpu(WebglAddon) {
        if (!hasGpu()) return;

        try {
            const addon = new WebglAddon();
            addon.onContextLoss(() => addon.dispose());
            this.term.loadAddon(addon);
        } catch (error) {
            console.warn("The terminal runs without WebGL:", error);
        }
    },

    connect() {
        this.channel?.leave();
        this.term.reset();

        this.channel = this.socket.channel(`terminal:${this.el.dataset.flowId}`, {
            cols: this.term.cols,
            rows: this.term.rows,
        });
        this.channel.on("output", (data) => this.term.write(new Uint8Array(data)));
        this.channel.on("exited", () => this.pushEvent("terminal_exited", {}));
        this.channel.join();
    },

    // Hidden, the panel measures zero, and that is no size for a terminal.
    fit() {
        if (this.el.clientHeight === 0) return;

        if (this.term) {
            this.fitAddon.fit();
            this.term.focus();
        } else if (!this.opening) {
            this.opening = true;
            this.open();
        }
    },
};
