import { LitElement, html, css } from "lit";

export class CustomSocketElement extends LitElement {
  static get styles() {
    return css`
      :host {
        display: block;
        width: 24px;
        height: 24px;
        padding: 0;
        margin: 0;
      }
      .socket {
        width: 100% !important;
        height: 100% !important;
        background: var(--socket-color, var(--color-primary)) !important;
        border: 2px solid var(--editor-surface) !important;
        border-radius: 50%;
        cursor: pointer;
        z-index: 50;
        box-sizing: border-box;
        display: block !important;
      }
      .socket:hover {
        background: color-mix(in oklab, var(--socket-color, var(--color-primary)) 80%, black) !important;
        border-width: 3px !important;
        transform: scale(1.1);
      }
      
      :host(.multiple) {
        border-color: yellow;
      }
      :host(.multiple) {
        border-color: yellow;
      }
    `;
  }

  static get properties() {
    return {
      data: { type: Object }
    };
  }

  render() {
    return html`
        <div class="socket" title="${this.data?.payload?.label || ''}"></div>
        `;
  }
}
