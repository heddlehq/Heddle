import { LitElement, html, svg, css } from "lit";

export class CustomConnectionElement extends LitElement {
  static get styles() {
    return css`
      :host {
        cursor: pointer;
        display: block;
      }
      svg {
        overflow: visible !important;
        position: absolute;
        pointer-events: none;
        width: 9999px;
        height: 9999px;
      }
      path.hit-area {
        fill: none;
        stroke: transparent;
        stroke-width: 24px;
        pointer-events: auto;
        cursor: pointer;
      }
      path.visible {
        fill: none;
        stroke-width: 5px;
        stroke: var(--editor-wire);
        pointer-events: none;
        transition: stroke-width 0.15s ease, stroke 0.15s ease;
      }
      path.visible.selected {
        stroke: var(--color-primary);
        stroke-width: 7px;
      }
      path.visible:hover {
        stroke-width: 6px;
      }
      /* The wires the run being inspected went through. */
      path.visible.taken-success,
      path.visible.taken-error {
        stroke-dasharray: 12 6;
        animation: wire-flow 0.7s linear 4;
      }
      path.visible.taken-success {
        stroke: var(--run-success);
      }
      path.visible.taken-error {
        stroke: var(--run-error);
      }
      path.visible.taken-success.selected,
      path.visible.taken-error.selected {
        stroke: var(--color-primary);
      }
      @keyframes wire-flow {
        from { stroke-dashoffset: 18; }
        to { stroke-dashoffset: 0; }
      }
      @media (prefers-reduced-motion: reduce) {
        path.visible.taken-success,
        path.visible.taken-error {
          animation: none;
        }
      }
    `;
  }

  static get properties() {
    return {
      path: { type: String },
      connectionId: { type: String },
      selected: { type: Boolean },
      // "success" or "error" when the run being inspected went through this wire.
      taken: { type: String }
    };
  }

  render() {
    return html`
      <svg>
        <path class="hit-area" d="${this.path}" @click=${this._onClick} @contextmenu=${this._onContextMenu}></path>
        <path
          class="visible ${this.selected ? 'selected' : ''} ${this.taken ? `taken-${this.taken}` : ''}"
          d="${this.path}"
        ></path>
      </svg>
    `;
  }

  _onClick(e) {
    e.stopPropagation();
    this.dispatchEvent(new CustomEvent('connection-click', {
      detail: { connectionId: this.connectionId, shiftKey: e.shiftKey, ctrlKey: e.ctrlKey, metaKey: e.metaKey },
      bubbles: true,
      composed: true
    }));
  }

  _onContextMenu(e) {
    e.preventDefault();
    e.stopPropagation();
    this.dispatchEvent(new CustomEvent('connection-contextmenu', {
      detail: { connectionId: this.connectionId, clientX: e.clientX, clientY: e.clientY },
      bubbles: true,
      composed: true
    }));
  }
}
