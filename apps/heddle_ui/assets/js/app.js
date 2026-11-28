import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { CodeEditorHook, loadMonaco } from "./code_editor"
import { CodeFieldHook } from "./code_field"
import { WebhookBodyHook } from "./webhook_body"
import { TerminalHook } from "./terminal"
import { FlowDragHook } from "./flow_drag"
import { setupNodeDrag } from "./node_drag"
import "./json-tree"

// A flow is a few hundred kilobytes at most. A bigger file is something else.
const MAX_IMPORT_BYTES = 2 * 1024 * 1024

const hooks = {
  CodeField: CodeFieldHook,
  // Reads a flow from a JSON file and hands it to the server, which checks it.
  ImportFlow: {
    mounted() {
      this.el.addEventListener("click", () => {
        const input = document.createElement("input")
        input.type = "file"
        input.accept = ".json,application/json"
        input.addEventListener("change", async () => {
          const file = input.files?.[0]
          if (!file) return
          if (file.size > MAX_IMPORT_BYTES) {
            this.pushEvent("import_flow_too_big", {})
            return
          }
          if (this.el.dataset.replace === "true" && !window.confirm(this.el.dataset.confirmReplace)) return
          this.pushEvent("import_flow", { json: await file.text() })
        })
        input.click()
      })
    },
  },
  CodeEditor: CodeEditorHook,
  WebhookBody: WebhookBodyHook,
  Terminal: TerminalHook,
  FlowDrag: FlowDragHook,
  NodeSearch: {
    mounted() {
      this.el.focus();
      this.el.addEventListener("input", (e) => {
        this.pushEvent("filter_nodes", { value: e.target.value });
      });
      this.el.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          document.querySelector('[phx-click="create_node_from_modal"]')?.click();
        }
        if (e.key === "Escape") this.pushEvent("close_create_node_modal", {});
      });
    }
  },
  FlowCanvas: {
    async mounted() {
      const { createEditor } = await import("./rete_editor.js");
      const container = this.el;
      const editor = await createEditor(container, {
        readOnly: container.dataset.readOnly === "true",
      });

      // Loads ahead of time, so the code modal doesn't wait for it.
      const whenIdle = window.requestIdleCallback || setTimeout;
      whenIdle(() => loadMonaco().catch(() => {}));

      this.handleEvent("add_node", async ({ name, definition, data }) => {
        if (editor.addNode) {
          await editor.addNode(name, definition, data);
        }
      });

      // The canvas edits the flow with whoever else has it open, and the server saves
      // what changes. See collab.js.
      const { startCollab } = await import("./collab.js");
      const saveState = document.getElementById("save-state");
      const collab = startCollab(editor, {
        flowId: container.dataset.flowId,
        token: container.dataset.socketToken,
        container,
        avatars: document.getElementById("presence-avatars"),
        onSaveState: (state) => {
          if (!saveState) return;
          saveState.dataset.state = state;
          const text = { saved: "Saved", saving: "Saving...", offline: "Reconnecting..." }[state];
          saveState.textContent = (window.Translations && window.Translations[text]) || text;
          saveState.title = saveState.textContent;
        },
        onJoinError: () => this.pushEvent("canvas_join_failed", {}),
      });
      this.collab = collab;

      // Resolves once the node is on the canvas, so what was dragged fades into it.
      editor.onDrop((name, position) => new Promise((resolve) => {
        this.pushEvent("get_node_definition", { name }, async ({ definition }) => {
          const node_data = {
            id: `node_${Date.now()}_${Math.floor(Math.random() * 1000)}`,
            label: name,
            position: position
          };

          try {
            await editor.addNode(name, definition, node_data);
            this.pushEvent("node_added_internally", { name, data: node_data });
          } finally {
            resolve();
          }
        });
      }));

      const stopNodeDrag = setupNodeDrag({ root: document.body, container, editor });

      if (editor.onRunSection) {
        editor.onRunSection(async (sectionId) => {
          await collab.flush();
          const data = editor.snapshot();
          this.pushEvent("run_section", { section_id: sectionId, data });
        });
      }

      // Publishing and running take what the canvas has, once the server has it too.
      this.handleEvent("request_publish_data", async () => {
        await collab.flush();
        this.pushEvent("publish_graph_data", {});
      });

      this.handleEvent("request_save_and_run", async () => {
        await collab.flush();
        this.pushEvent("save_and_run", { data: editor.snapshot() });
      });

      // What changes the whole canvas runs one after the other: a run's state that
      // arrives while the flow is still loading must wait for its nodes.
      let queue = Promise.resolve();
      const inOrder = (fn) => (payload) => {
        queue = queue.then(() => fn(payload)).catch((error) => console.error(error));
      };

      this.handleEvent("load_graph_data", inOrder(async ({ nodes, connections, comments, definitions }) => {
        await editor.importData({ nodes, connections, comments, definitions });
      }));

      this.handleEvent("run_state", inOrder((state) => editor.setRunState(state)));
      this.handleEvent("run_steps", inOrder(({ steps }) => editor.addRunSteps(steps)));
      this.handleEvent("run_focus", inOrder(({ nodeId }) => editor.focusRunNode(nodeId)));
      this.handleEvent("update_node_settings", inOrder(({ nodeId, settings }) => editor.updateNodeSettings(nodeId, settings)));
      this.handleEvent("pin_node", inOrder(({ nodeId, pin }) => editor.pinNode(nodeId, pin)));

      editor.onInspect((nodeId) => this.pushEvent("inspector_select_node", { node_id: nodeId }));

      this.handleEvent("update_node_code", inOrder(({ nodeId, code_elixir, code_python, fieldName }) =>
        editor.updateNodeCode?.(nodeId, code_elixir, code_python, fieldName)));

      this.handleEvent("update_node_data", ({ nodeId, data }) => {
        if (editor.updateNodeData) {
          editor.updateNodeData(nodeId, data);
        }
      });

      this.handleEvent("update_node_label", ({ nodeId, label }) => {
        if (editor.updateNodeLabel) {
          editor.updateNodeLabel(nodeId, label);
        }
      });

      this.handleEvent("update_node_sockets", ({ nodeId, inputs, outputs }) => {
        if (editor.updateNodeSockets) {
          editor.updateNodeSockets(nodeId, { inputs, outputs });
        }
      });

      document.querySelectorAll("[data-comment-kind]").forEach((button) => {
        button.addEventListener("click", () => editor.addComment(button.dataset.commentKind));
      });

      if (editor.onChange) {
        editor.onChange(() => collab.changed());
      }

      if (editor.onCodeEdit) {
        editor.onCodeEdit((nodeId, code_elixir, code_python, fieldName, language, variables, code) => {
          this.pushEvent("open_code_editor", { nodeId, code_elixir, code_python, fieldName, language, variables, code });
        });
      }


      if (editor.onNodeConfig) {
        editor.onNodeConfig((nodeId, nodeData) => {
          collab.setEditing(nodeId);
          this.pushEvent("open_node_config", { nodeId, nodeData });
        });
      }

      if (editor.onCanvasClick) {
        editor.onCanvasClick(() => {
          collab.setEditing(null);
          this.pushEvent("close_config_modal", {});
        });
      }

      if (editor.onCreateNode) {
        editor.onCreateNode((x, y) => {
          this.pushEvent("open_create_node_modal", { x, y });
        });
      }


      this.destroyed = () => {
        stopNodeDrag();
        collab.destroy();
        if (editor.destroy) editor.destroy();
      };

      this.pushEvent("client_ready", {});
    },
  },
  // A version of the flow, on a canvas of its own that nothing can change, with what
  // it changed marked on its nodes. The draft stays under it as it was.
  VersionPreview: {
    async mounted() {
      const { createEditor } = await import("./rete_editor.js");
      this.editor = await createEditor(this.el, { readOnly: true });
      if (this.gone) return this.editor.destroy();

      this.pushEvent("version_preview_ready", {}, async (graph) => {
        if (this.gone || !graph.nodes) return;
        await this.editor.importData(graph);
        await this.editor.setDiff(graph.diff || {});
      });
    },
    destroyed() {
      this.gone = true;
      if (this.editor) this.editor.destroy();
    },
  },
  ScrollToBottom: {
    mounted() {
      this.el.scrollTop = this.el.scrollHeight;
    },
    updated() {
      this.el.scrollTop = this.el.scrollHeight;
    },
  },
  // A chat's box: Enter sends and Shift+Enter breaks the line. It empties once the
  // message is sent, and keeps what was written when it couldn't be.
  SubmitOnEnter: {
    mounted() {
      this.el.addEventListener("keydown", (event) => {
        if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
          event.preventDefault();
          this.el.form.requestSubmit();
        }
      });
      this.handleEvent("chat:sent", () => {
        this.el.value = "";
        this.el.focus();
      });
      this.el.focus();
    },
  },
  FocusInput: {
    mounted() {
      this.el.focus();
    },
    updated() {
      this.el.focus();
    }
  },
  ApiKeyScopeToggle: {
    mounted() {
      this.el.addEventListener("click", () => {
        const form = this.el.closest("form");
        const selector = this.el.dataset.scopeSelector;
        if (!form || !selector) return;

        const scopes = Array.from(form.querySelectorAll(selector));
        const shouldCheck = scopes.some((scope) => !scope.checked);

        scopes.forEach((scope) => {
          scope.checked = shouldCheck;
          scope.dispatchEvent(new Event("change", { bubbles: true }));
        });
      });
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  // The theme this browser shows, which the preferences page marks until the person
  // saves one of their own.
  params: () => ({ _csrf_token: csrfToken, theme: document.documentElement.dataset.themeChoice }),
  hooks: hooks,
})

const primaryColor = getComputedStyle(document.documentElement).getPropertyValue("--color-primary").trim()
topbar.config({ barColors: { 0: primaryColor }, shadowColor: "rgba(0, 0, 0, .3)" })
// Copies the value of the element `detail.to` names, and marks the button that asked
// with data-copied for a moment, which its classes can show.
window.addEventListener("phx:copy", (e) => {
  const source = e.detail?.to && document.querySelector(e.detail.to)
  if (!source || !navigator.clipboard) return
  navigator.clipboard.writeText(source.value ?? source.textContent).then(() => {
    e.target.dataset.copied = "true"
    setTimeout(() => delete e.target.dataset.copied, 1500)
  })
})

window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()

// The theme is the root layout's: what the person chose, or this browser, or the
// device. See root.html.heex.

window.liveSocket = liveSocket

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    reloader.enableServerLogs()

    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if (keyDown === "c") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if (keyDown === "d") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

document.addEventListener('DOMContentLoaded', () => {
  const node1 = document.getElementById('node-1');
  const node2 = document.getElementById('node-2');
  const path = document.getElementById('connection-path');

  if (node1 && node2 && path) {
    const container = path.closest('svg');
    let animationFrameId;

    function updatePath() {
      const containerRect = container.getBoundingClientRect();
      const r1 = node1.getBoundingClientRect();
      const r2 = node2.getBoundingClientRect();

      const x1 = r1.x + r1.width - containerRect.x;
      const y1 = r1.y + r1.height / 2 - containerRect.y;

      const x2 = r2.x - containerRect.x;
      const y2 = r2.y + r2.height / 2 - containerRect.y;

      const controlPointX1 = x1 + (x2 - x1) / 2;
      const controlPointX2 = x1 + (x2 - x1) / 2;

      path.setAttribute('d', `M ${x1} ${y1} C ${controlPointX1} ${y1} ${controlPointX2} ${y2} ${x2} ${y2}`);

      animationFrameId = requestAnimationFrame(updatePath);
    }

    animationFrameId = requestAnimationFrame(updatePath);
  }
});
