import { LitElement, html } from "lit";

export const COMMENT_TYPE = "__comment";

export const COMMENT_KINDS = {
  title: { label: "Title", placeholder: "Add a title", icon: "hero-h1", width: 520, height: 64 },
  text: { label: "Text", placeholder: "Write something", icon: "hero-bars-3-bottom-left", width: 280, height: 96 },
  note: { label: "Note", placeholder: "Write something", icon: "hero-document-text", width: 240, height: 140 },
  section: { label: "Section", placeholder: "Name this section", icon: "hero-rectangle-group", width: 520, height: 320 },
};

export const defaultCommentColor = (kind) => (kind === "note" ? "yellow" : "default");

const COLORS = ["default", "yellow", "green", "blue", "red"];
const MIN_SIZE = { width: 120, height: 40 };

const translate = (key) => (window.Translations && window.Translations[key]) || key;
const stop = (e) => e.stopPropagation();

// Keeps the focus in the text, and the press from reaching the canvas.
const hold = (e) => {
  e.stopPropagation();
  e.preventDefault();
};

export class CustomCommentElement extends LitElement {
  createRenderRoot() {
    return this;
  }

  static get properties() {
    return {
      data: { attribute: false },
      selected: { type: Boolean },
      editing: { state: true },
      getZoom: { attribute: false },
      onChange: { attribute: false },
      onDelete: { attribute: false },
      // A section only: what keeps it from running, or null, and how to run it.
      getRunBlocker: { attribute: false },
      onRun: { attribute: false },
      settingsOpen: { state: true },
    };
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._closeSettings();
  }

  firstUpdated() {
    if (this.data.startEditing) {
      this.data.startEditing = false;
      this.editing = true;
    }
  }

  updated(changed) {
    if (changed.has("editing") && this.editing) {
      this.querySelector("textarea")?.focus();
    }
  }

  render() {
    const { kind, color, text, width, height } = this.data;

    return html`
      <div
        class="comment-note ${this.selected || this.editing ? "is-selected" : ""}"
        data-kind=${kind}
        data-color=${color}
        data-manual=${kind === "section" && this.data.manual ? "true" : "false"}
        style="width: ${width}px; height: ${height}px"
        @mouseup=${this._editOnDoubleClick}
      >
        ${this.selected || this.editing ? this._renderToolbar() : ""}
        ${this.editing ? this._renderInput(text) : this._renderText(text)}
        ${kind === "section" ? this._renderSectionActions() : ""}
        <div class="comment-resize" @pointerdown=${this._startResize}></div>
      </div>
    `;
  }

  // Always there, so a section shows whether it runs with the flow without a click.
  _renderSectionActions() {
    const manual = this.data.manual === true;
    const blocker = this.getRunBlocker?.();
    const runLabel = blocker ? translate(blocker) : translate("Run section");

    return html`
      <div
        class="section-actions"
        @pointerdown=${stop}
        @mousedown=${hold}
        @mouseup=${stop}
        @pointerenter=${() => this.requestUpdate()}
      >
        ${manual ? html`<span class="section-badge">${translate("Manual")}</span>` : ""}
        <button
          type="button"
          class="section-action ${this.settingsOpen ? "is-active" : ""}"
          title=${translate("Section settings")}
          aria-label=${translate("Section settings")}
          aria-expanded=${this.settingsOpen ? "true" : "false"}
          @click=${this._toggleSettings}
        >
          <span class="hero-cog-6-tooth w-4 h-4"></span>
        </button>
        <button
          type="button"
          class="section-action section-run"
          title=${runLabel}
          aria-label=${runLabel}
          ?disabled=${!!blocker}
          @click=${() => this.onRun?.()}
        >
          <span class="hero-play w-4 h-4"></span>
        </button>
        ${this.settingsOpen ? this._renderSettings(manual) : ""}
      </div>
    `;
  }

  _renderSettings(manual) {
    return html`
      <div class="section-settings" role="dialog" aria-label=${translate("Section settings")}>
        <label class="section-setting">
          <span class="section-setting-text">
            <span class="section-setting-title">${translate("Run with the flow")}</span>
            <span class="section-setting-hint">
              ${translate("When off, it runs only from the play button.")}
            </span>
          </span>
          <input
            type="checkbox"
            role="switch"
            class="section-switch"
            .checked=${!manual}
            @change=${(e) => this._set({ manual: !e.target.checked })}
          />
        </label>
      </div>
    `;
  }

  _toggleSettings = () => {
    if (this.settingsOpen) {
      this._closeSettings();
      return;
    }

    this.settingsOpen = true;
    // The press that opened it is already over, so it doesn't close it again.
    setTimeout(() => document.addEventListener("pointerdown", this._closeOnOutside, true));
  };

  _closeOnOutside = (e) => {
    if (!this.querySelector(".section-actions")?.contains(e.target)) this._closeSettings();
  };

  _closeSettings() {
    this.settingsOpen = false;
    document.removeEventListener("pointerdown", this._closeOnOutside, true);
  }

  _renderToolbar() {
    return html`
      <div
        class="comment-toolbar"
        style="transform: scale(${1 / this.getZoom()})"
        @pointerdown=${stop}
        @mousedown=${hold}
        @mouseup=${stop}
      >
        ${Object.entries(COMMENT_KINDS).map(([kind, { label, icon }]) => html`
          <button
            type="button"
            class="comment-tool ${kind === this.data.kind ? "is-active" : ""}"
            title=${translate(label)}
            aria-label=${translate(label)}
            @click=${() => this._set({ kind })}
          >
            <span class="${icon} w-4 h-4"></span>
          </button>
        `)}

        <span class="comment-toolbar-divider"></span>

        ${COLORS.map((color) => html`
          <button
            type="button"
            class="comment-swatch ${color === this.data.color ? "is-active" : ""}"
            data-color=${color}
            title=${translate("Color")}
            aria-label=${`${translate("Color")} ${color}`}
            @click=${() => this._set({ color })}
          ></button>
        `)}

        <span class="comment-toolbar-divider"></span>

        <button
          type="button"
          class="comment-tool comment-delete"
          title=${translate("Delete")}
          aria-label=${translate("Delete")}
          @click=${() => this.onDelete()}
        >
          <span class="hero-trash w-4 h-4"></span>
        </button>
      </div>
    `;
  }

  _renderText(text) {
    const placeholder = translate(COMMENT_KINDS[this.data.kind].placeholder);

    return html`<div class="comment-text ${text ? "" : "is-empty"}">${text || placeholder}</div>`;
  }

  _renderInput(text) {
    return html`
      <textarea
        class="comment-text"
        .value=${text}
        placeholder=${translate(COMMENT_KINDS[this.data.kind].placeholder)}
        @pointerdown=${stop}
        @mousedown=${stop}
        @wheel=${stop}
        @input=${this._growToFit}
        @keydown=${(e) => {
          if (e.key === "Escape") e.target.blur();
        }}
        @blur=${(e) => {
          this.editing = false;
          this.data.text = e.target.value;
          this.onChange();
        }}
      ></textarea>
    `;
  }

  _growToFit = ({ target }) => {
    const hidden = target.scrollHeight - target.clientHeight;

    if (hidden > 0) {
      this.data.height += hidden;
      this.requestUpdate();
    }
  };

  _set(changes) {
    Object.assign(this.data, changes);
    this.requestUpdate();
    this.onChange();
  }

  // Picking a node moves it in the DOM, so the browser never fires dblclick on it.
  _editOnDoubleClick = (e) => {
    if (e.detail === 2) this.editing = true;
  };

  _startResize = (e) => {
    e.stopPropagation();
    e.preventDefault();

    const { clientX, clientY } = e;
    const { width, height } = this.data;
    const zoom = this.getZoom();

    const resize = (move) => {
      this.data.width = Math.max(MIN_SIZE.width, Math.round(width + (move.clientX - clientX) / zoom));
      this.data.height = Math.max(MIN_SIZE.height, Math.round(height + (move.clientY - clientY) / zoom));
      this.requestUpdate();
    };

    const finish = () => {
      window.removeEventListener("pointermove", resize);
      this.onChange();
    };

    window.addEventListener("pointermove", resize);
    window.addEventListener("pointerup", finish, { once: true });
  };
}
