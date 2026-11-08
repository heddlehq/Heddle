import { LitElement, html, css } from "lit";
import { repeat } from "lit/directives/repeat.js";
/**
 * Icon Safelist for Tailwind CSS
 * Since node icons are used dynamically via classes, we need to list them here
 * so Tailwind doesn't purge them during build.
 * 
 * hero-bolt-solid hero-play-solid hero-share-solid hero-flag-solid hero-variable-solid
 * hero-code-bracket-solid hero-globe-alt-solid hero-document-text-solid
 * hero-cube hero-circle-stack hero-arrows-pointing-out
 * hero-arrows-pointing-in hero-magnifying-glass hero-clock 
 * hero-adjustments-horizontal hero-tag hero-exclamation-triangle-solid
 * hero-check-micro hero-x-mark-micro hero-minus-micro hero-bookmark-solid
 */

const formatMs = (ms) => {
  if (ms == null) return '';
  if (ms < 1) return '<1 ms';
  if (ms < 1000) return `${Math.round(ms)} ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(ms < 10000 ? 2 : 1)} s`;
  return `${Math.floor(ms / 60000)} min`;
};

export class CustomNodeElement extends LitElement {
  createRenderRoot() {
    return this;
  }

  static get properties() {
    return {
      data: { type: Object },
      emit: { attribute: false },
      selected: { type: Boolean, reflect: true },
      onConfig: { attribute: false },
      onDelete: { attribute: false },
      onInspect: { attribute: false }
    };
  }

  static get styles() {
    return css`
      custom-node {
        display: block;
        width: 88px;
        height: 88px;
        position: relative;
      }
      .circular-node {
        display: flex;
        align-items: center;
        justify-content: center;
        background: var(--editor-surface);
        border: 3px solid var(--editor-border);
        border-radius: 50%;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
        cursor: pointer;
        width: 88px;
        height: 88px;
        box-sizing: border-box;
        position: relative;
        user-select: none;
        transition: transform 0.2s cubic-bezier(0.4, 0, 0.2, 1), box-shadow 0.2s;
        z-index: 10;
      }
      .circular-node:hover {
        transform: translateY(-2px) scale(1.05);
        box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
      }
      .selected .circular-node,
      .circular-node.is-selected {
        box-shadow: 0 0 0 4px color-mix(in oklab, var(--color-primary) 40%, transparent) !important;
        transform: scale(1.05);
        border-color: var(--color-primary) !important;
      }
      .selected .selection-indicator {
        opacity: 1;
      }
      .selection-indicator {
        position: absolute;
        top: -8px;
        right: -8px;
        width: 20px;
        height: 20px;
        background: var(--color-primary);
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        opacity: 0;
        transition: opacity 0.2s, transform 0.2s;
        transform: scale(0.5);
        z-index: 20;
      }
      .dark .circular-node {
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.3);
      }
      .icon-container {
        width: 48px;
        height: 48px;
        display: flex;
        align-items: center;
        justify-content: center;
        pointer-events: none;
      }
      .icon-container span {
        width: 35px;
        height: 35px;
      }
      .socket-container {
        position: absolute;
        top: 50%;
        margin-top: -12px; /* Half of 24px height for perfect centering */
        width: 24px;
        height: 24px;
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 100;
      }
      .socket-container.left {
        left: -12px;
      }
      .socket-container.right {
        right: -12px;
      }
      .circular-node.run-success {
        border-color: var(--run-success) !important;
        box-shadow: 0 0 0 4px color-mix(in oklab, var(--run-success) 16%, transparent);
      }
      .circular-node.run-error {
        border-color: var(--run-error) !important;
        box-shadow: 0 0 0 4px color-mix(in oklab, var(--run-error) 20%, transparent);
        animation: run-error-in 0.6s ease-out;
      }
      .circular-node.run-continued {
        border-color: var(--run-warning) !important;
        box-shadow: 0 0 0 4px color-mix(in oklab, var(--run-warning) 18%, transparent);
      }
      .circular-node.run-skipped {
        border-style: dashed !important;
        border-color: var(--run-skipped) !important;
        opacity: 0.75;
      }
      .circular-node.run-focused {
        box-shadow: 0 0 0 4px var(--editor-surface), 0 0 0 7px var(--color-primary) !important;
      }
      .circular-node.run-focused::after {
        content: "";
        position: absolute;
        inset: -3px;
        border-radius: 50%;
        border: 2px solid var(--color-primary);
        animation: run-ripple 1.2s ease-out 2;
        pointer-events: none;
      }
      @keyframes run-error-in {
        0% { transform: scale(1); }
        30% { transform: scale(1.08); }
        100% { transform: scale(1); }
      }
      @keyframes run-ripple {
        from { transform: scale(1); opacity: 0.8; }
        to { transform: scale(1.5); opacity: 0; }
      }
      .run-pill {
        position: absolute;
        top: calc(100% + 8px);
        left: 50%;
        transform: translateX(-50%);
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 2px 8px 2px 4px;
        border-radius: 999px;
        border: 1px solid var(--editor-border);
        background: var(--editor-surface);
        color: var(--editor-muted);
        font-size: 11px;
        font-weight: 600;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        cursor: pointer;
        z-index: 40;
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.06);
        transition: opacity 0.15s, transform 0.15s;
        animation: run-pill-in 0.25s cubic-bezier(0.16, 1, 0.3, 1);
      }
      .run-pill:hover { transform: translateX(-50%) translateY(-1px); }
      custom-node:hover .run-pill { opacity: 0; pointer-events: none; }
      .run-pill .run-icon {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 16px;
        height: 16px;
        border-radius: 50%;
        color: var(--editor-surface);
      }
      .run-pill.success .run-icon { background: var(--run-success); }
      .run-pill.error .run-icon { background: var(--run-error); }
      .run-pill.continued .run-icon { background: var(--run-warning); }
      .run-pill.skipped .run-icon { background: var(--run-skipped); }
      .run-pill.error { color: var(--run-error); border-color: color-mix(in oklab, var(--run-error) 45%, transparent); }
      .run-pill .run-count { color: var(--editor-text); }
      @keyframes run-pill-in {
        from { opacity: 0; transform: translateX(-50%) translateY(-4px); }
        to { opacity: 1; transform: translateX(-50%) translateY(0); }
      }
      .pin-badge {
        position: absolute;
        top: -6px;
        left: -6px;
        width: 22px;
        height: 22px;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        background: var(--color-primary);
        color: var(--color-primary-content);
        border: 2px solid var(--editor-surface);
        z-index: 30;
      }
      .node-actions-container {
        position: absolute;
        bottom: -40px;
        left: 50%;
        transform: translateX(-50%);
        display: flex;
        gap: 8px;
        padding: 4px 8px;
        background: var(--editor-surface);
        border: 1px solid var(--editor-border);
        border-radius: 20px;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
        opacity: 0;
        transition: opacity 0.2s, transform 0.2s;
        z-index: 50;
        pointer-events: auto;
      }
      custom-node:hover .node-actions-container,
      .node-actions-container:hover {
        opacity: 1;
        transform: translateX(-50%) translateY(2px);
      }
      .node-action-btn {
        width: 28px;
        height: 28px;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        cursor: pointer;
        transition: transform 0.1s, filter 0.2s;
        border: none;
      }
      .node-action-btn:hover {
        transform: scale(1.1);
        filter: brightness(1.1);
      }
      .node-action-btn.delete {
        background: var(--color-error);
        color: var(--color-error-content);
      }
      .node-action-btn.config {
        background: var(--color-primary);
        color: var(--color-primary-content);
      }
      .node-name {
        position: absolute;
        bottom: calc(100% + 8px);
        left: 50%;
        transform: translateX(-50%);
        width: 180px;
        color: var(--editor-text);
        font-size: 13px;
        font-weight: 500;
        line-height: 1.25;
        text-align: center;
        overflow-wrap: anywhere;
        user-select: none;
        -webkit-user-select: none;
        pointer-events: none;
        z-index: 60;
      }
      .language-badge {
        position: absolute;
        bottom: 4px;
        right: 4px;
        background: var(--color-primary);
        color: var(--color-primary-content);
        font-size: 9px;
        font-weight: 800;
        padding: 2px 4px;
        border-radius: 4px;
        text-transform: uppercase;
        border: 1px solid var(--editor-surface);
        line-height: 1;
        z-index: 20;
        pointer-events: none;
      }
    `;
  }

  connectedCallback() {
    super.connectedCallback();
    // Inject styles into the global scope for Light DOM support
    if (!document.getElementById('custom-node-styles')) {
      const style = document.createElement('style');
      style.id = 'custom-node-styles';
      style.textContent = CustomNodeElement.styles.cssText;
      document.head.appendChild(style);
    }
  }

  render() {
    const inputs = Object.entries(this.data.inputs || {});
    const outputs = Object.entries(this.data.outputs || {});

    const category = this.data.category || 'default';
    const colors = {
      'trigger': 'var(--node-trigger)',
      'flow_control': 'var(--node-flow-control)',
      'code': 'var(--node-code)',
      'data_manipulation': 'var(--node-data)',
      'http': 'var(--node-integration)',
      'database': 'var(--node-integration)',
      'email': 'var(--node-integration)',
      'ftp': 'var(--node-integration)',
      'google_sheets': 'var(--node-integration)',
      's3': 'var(--node-integration)',
      'slack': 'var(--node-integration)',
      'utility': 'var(--node-utility)',
      'default': 'var(--node-utility)'
    };
    const nodeColor = colors[category] || colors['default'];
    const language = this.data.controls?.language?.value;
    const langLabel = language === 'elixir' ? 'EX' : (language === 'python' ? 'PY' : null);

    return html`
      <div class="node-name">${this.data.label}</div>

      <div 
        class="circular-node ${this.selected ? 'is-selected' : ''} ${this._runClass()} ${this.data.runFocused ? 'run-focused' : ''}" 
        style="border-color: color-mix(in oklab, ${nodeColor} 67%, transparent)"
        @pointerdown=${(e) => {
          if (e.shiftKey) {
            e.preventDefault();
            e.stopPropagation();
            this.selected = !this.selected;
            // Also update the Rete node's selected property
            const nodeId = this.data.id;
            const reteNode = window.reteEditorInstance?.getNode(nodeId);
            if (reteNode) {
              reteNode.selected = this.selected;
            }
            this.requestUpdate();
            this.dispatchEvent(new CustomEvent('node-select', { 
              bubbles: true, 
              detail: { selected: this.selected, nodeId: this.data.id }
            }));
          } else if (this._onPointerDown) {
            this._onPointerDown(e);
          }
        }}
      >
        ${this.selected ? html`
          <div class="selection-indicator">
            <svg class="w-3 h-3 text-primary-content" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
            </svg>
          </div>
        ` : ''}
        ${this.data.settings?.pin ? html`
          <div class="pin-badge" title="${window.Translations?.["Pinned data"] || "Pinned data"}">
            <span class="hero-bookmark-solid w-3 h-3"></span>
          </div>
        ` : ''}

        <div class="icon-container" style="color: ${nodeColor}">
          <span class="${this.data.icon || 'hero-cube'}"></span>
        </div>

        ${langLabel ? html`
          <div class="language-badge">${langLabel}</div>
        ` : ''}
      </div>

      ${this.data.run ? this._runPill() : ''}

      <div class="node-actions-container">
        <div 
          class="node-action-btn config" 
          title="Configure Node"
          @pointerdown=${(e) => e.stopPropagation()}
          @mousedown=${(e) => e.stopPropagation()}
          @click=${(e) => {
            e.stopPropagation();
            if (this.onConfig) this.onConfig();
          }}
        >
          <span class="hero-cog-6-tooth w-4 h-4"></span>
        </div>

        <div 
          class="node-action-btn delete" 
          title="Delete Node"
          @pointerdown=${(e) => e.stopPropagation()}
          @mousedown=${(e) => e.stopPropagation()}
          @click=${(e) => {
            e.stopPropagation();
            if (this.onDelete) this.onDelete();
          }}
        >
          <span class="hero-x-mark w-4 h-4"></span>
        </div>
      </div>

      ${repeat(inputs, ([key]) => key, ([key, input]) => html`
        <div class="socket-container left" key="input-${key}" data-key="${key}" data-side="input"></div>
      `)}

      ${repeat(outputs, ([key]) => key, ([key, output]) => html`
        <div class="socket-container right" key="output-${key}" data-key="${key}" data-side="output"></div>
      `)}
    `;
  }

  // What the run being inspected did here, which the canvas keeps on the node as
  // `run`: { status, continued, count, duration_ms }. `runFocused` is set while the
  // inspector looks at one of its steps.
  _runState() {
    const run = this.data.run;
    if (!run) return null;
    return run.status === 'error' && run.continued ? 'continued' : run.status;
  }

  _runClass() {
    const state = this._runState();
    return state ? `run-${state}` : '';
  }

  _runPill() {
    const state = this._runState();
    const icon = { success: 'hero-check-micro', error: 'hero-x-mark-micro', continued: 'hero-x-mark-micro' }[state] || 'hero-minus-micro';
    return html`
      <div
        class="run-pill ${state}"
        title="${window.Translations?.["Inspect this step"] || "Inspect this step"}"
        @pointerdown=${(e) => e.stopPropagation()}
        @click=${(e) => {
          e.stopPropagation();
          if (this.onInspect) this.onInspect();
        }}
      >
        <span class="run-icon"><span class="${icon} w-3 h-3"></span></span>
        <span>${formatMs(this.data.run.duration_ms)}</span>
        ${this.data.run.count > 1 ? html`<span class="run-count">×${this.data.run.count}</span>` : ''}
      </div>
    `;
  }

  _onPointerDown(e) {
    this._clickHandled = false;
    this._downTime = Date.now();
  }

  _onClick(e) {
    const duration = Date.now() - this._downTime;
    // Only trigger config if it was a quick click (not a long press/drag)
    if (duration < 300) {
      if (this.onConfig) {
        this.onConfig();
        this._clickHandled = true;
      }
    }
  }

  bindSocket(el, type, key) {
    if (el && this.data && this.emit) {
      if (el._bound) return;
      el._bound = true;

      this.emit({
        type: 'render',
        data: {
          type: 'socket',
          element: el,
          payload: type === 'input' ? this.data.inputs[key] : this.data.outputs[key],
          side: type,
          key: key,
          nodeId: this.data.id
        }
      });
    }
  }

  updated() {
    this.querySelectorAll('.socket-container').forEach(el => {
      const type = el.dataset.side;
      const key = el.dataset.key;
      this.bindSocket(el, type, key);
    });
  }
}
