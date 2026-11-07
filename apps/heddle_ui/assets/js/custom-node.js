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
 * hero-adjustments-horizontal hero-tag
 */

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
      error: { type: String, reflect: true },
      onErrorDetails: { attribute: false }
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
      .error-node-btn {
        position: absolute;
        top: -4px;
        left: -4px;
        background: var(--color-error);
        color: var(--color-error-content);
        border: 2px solid var(--editor-surface);
        border-radius: 50%;
        width: 24px;
        height: 24px;
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 50;
        animation: node-pulse 2s infinite;
      }
      @keyframes node-pulse {
        0% { box-shadow: 0 0 0 0 color-mix(in oklab, var(--color-error) 70%, transparent); }
        70% { box-shadow: 0 0 0 8px transparent; }
        100% { box-shadow: 0 0 0 0 transparent; }
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
        class="circular-node ${this.selected ? 'is-selected' : ''}" 
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
        ${this.error ? html`
          <div 
            class="error-node-btn"
            style="position: absolute; top: -4px; left: -4px; background: var(--color-error); color: var(--color-error-content); border: 2px solid var(--editor-surface); border-radius: 50%; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; z-index: 50; animation: node-pulse 2s infinite;"
            @click=${(e) => {
              e.stopPropagation();
              if (this.onErrorDetails) this.onErrorDetails();
            }}
          >!</div>
        ` : ''}

        <div class="icon-container" style="color: ${nodeColor}">
          <span class="${this.data.icon || 'hero-cube'}"></span>
        </div>

        ${langLabel ? html`
          <div class="language-badge">${langLabel}</div>
        ` : ''}
      </div>

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
