import { LitElement, html, nothing } from "lit";

/**
 * A value of a run, as a tree that opens and closes, with a filter. Clicking a key
 * copies it as the placeholder that reads it in a node, like {{result.items.0.name}}.
 *
 * It takes the value as JSON in `data-value`, and its words in `data-labels`, so the
 * page translates them. It draws in the light DOM, for the icons of the page, so the
 * LiveView that renders it must mark it `phx-update="ignore"` and give it a new id
 * for a new value.
 *
 * Colors come from the `--json-*` tokens in rete_custom.css.
 */

const OPEN_DEPTH = 2;

const STYLES = `
json-tree { color: var(--editor-text); font-size: 12px; }
json-tree .jt-toolbar { position: sticky; top: 0; z-index: 1; display: flex; align-items: center; gap: 4px; padding: 6px 12px; background: var(--editor-surface); border-bottom: 1px solid var(--editor-border); }
json-tree .jt-search { flex: 1; min-width: 0; display: flex; align-items: center; gap: 6px; padding: 4px 8px; border-radius: 6px; border: 1px solid var(--editor-input-border); background: var(--editor-input-bg); color: var(--editor-muted); transition: border-color .15s, box-shadow .15s; }
json-tree .jt-search:focus-within { border-color: var(--color-primary); box-shadow: 0 0 0 3px color-mix(in oklab, var(--color-primary) 18%, transparent); }
json-tree .jt-search input { flex: 1; min-width: 0; border: 0; outline: 0; padding: 0; background: transparent; color: var(--editor-text); font-size: 12px; }
json-tree .jt-tool { display: inline-flex; align-items: center; gap: 4px; height: 26px; padding: 0 7px; border-radius: 6px; color: var(--editor-muted); font-size: 11px; font-weight: 600; transition: background .15s, color .15s; }
json-tree .jt-tool:hover { background: var(--json-hover); color: var(--editor-text); }
json-tree .jt-tool.done { color: var(--json-string); }
json-tree .jt-body { padding: 6px 0 12px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; line-height: 20px; }
json-tree .jt-row { display: flex; align-items: flex-start; gap: 4px; padding-right: 12px; border-radius: 4px; }
json-tree .jt-row:hover { background: var(--json-hover); }
json-tree .jt-toggle { flex-shrink: 0; width: 16px; height: 20px; display: inline-flex; align-items: center; justify-content: center; color: var(--editor-muted); transition: transform .15s; }
json-tree .jt-toggle.open { transform: rotate(90deg); }
json-tree .jt-spacer { flex-shrink: 0; width: 16px; }
json-tree .jt-key { flex-shrink: 0; color: var(--json-key); cursor: copy; border-radius: 3px; padding: 0 2px; margin: 0 -2px; }
json-tree .jt-key:hover { background: color-mix(in oklab, var(--json-key) 14%, transparent); }
json-tree .jt-index { color: var(--editor-muted); }
json-tree .jt-colon { color: var(--editor-muted); margin-right: 4px; }
json-tree .jt-string { color: var(--json-string); white-space: pre-wrap; word-break: break-word; }
json-tree .jt-number { color: var(--json-number); }
json-tree .jt-boolean { color: var(--json-boolean); }
json-tree .jt-null { color: var(--editor-muted); font-style: italic; }
json-tree .jt-summary { color: var(--editor-muted); cursor: pointer; }
json-tree .jt-copied { margin-left: 8px; color: var(--json-string); font-family: ui-sans-serif, system-ui, sans-serif; font-size: 11px; }
json-tree mark { background: var(--json-match); color: inherit; border-radius: 2px; }
json-tree .jt-empty { padding: 16px 12px; color: var(--editor-muted); font-family: ui-sans-serif, system-ui, sans-serif; }
`;

const isContainer = (value) => value !== null && typeof value === "object";

const pathOf = (parent, key) => (parent === "" ? String(key) : `${parent}.${key}`);

export class JsonTreeElement extends LitElement {
  static properties = {
    _open: { state: true },
    _query: { state: true },
    _copied: { state: true },
  };

  createRenderRoot() {
    return this;
  }

  constructor() {
    super();
    this._open = new Set();
    this._query = "";
    this._copied = null;
  }

  connectedCallback() {
    super.connectedCallback();
    if (!document.getElementById("json-tree-styles")) {
      const style = document.createElement("style");
      style.id = "json-tree-styles";
      style.textContent = STYLES;
      document.head.appendChild(style);
    }
    this._labels = this._parse(this.dataset.labels, {});
    this._value = this._parse(this.dataset.value, null);
    this._open = new Set(this._containers(this._value).filter(({ depth }) => depth < OPEN_DEPTH).map(({ path }) => path));
  }

  _parse(text, fallback) {
    try {
      return text ? JSON.parse(text) : fallback;
    } catch (_error) {
      return fallback;
    }
  }

  // Every object and list in `value`, with how deep it is. The value itself is at 0.
  _containers(value, path = "", depth = 0, found = []) {
    if (!isContainer(value)) return found;
    found.push({ path, depth });
    for (const [key, child] of Object.entries(value)) this._containers(child, pathOf(path, key), depth + 1, found);
    return found;
  }

  _matches(key, value, query) {
    if (String(key).toLowerCase().includes(query)) return true;
    if (isContainer(value)) return Object.entries(value).some(([k, v]) => this._matches(k, v, query));
    return String(value).toLowerCase().includes(query);
  }

  _toggle(path) {
    const open = new Set(this._open);
    open.has(path) ? open.delete(path) : open.add(path);
    this._open = open;
  }

  _setAll(open) {
    this._open = new Set(open ? this._containers(this._value).map(({ path }) => path) : []);
  }

  async _copy(text, what) {
    try {
      await navigator.clipboard.writeText(text);
    } catch (_error) {
      return;
    }
    this._copied = what;
    clearTimeout(this._copiedTimer);
    this._copiedTimer = setTimeout(() => (this._copied = null), 1400);
  }

  _highlight(text) {
    const query = this._query;
    const value = String(text);
    if (!query) return value;
    const at = value.toLowerCase().indexOf(query);
    if (at < 0) return value;
    return html`${value.slice(0, at)}<mark>${value.slice(at, at + query.length)}</mark>${value.slice(at + query.length)}`;
  }

  _primitive(value) {
    if (value === null) return html`<span class="jt-null">null</span>`;
    switch (typeof value) {
      case "string":
        return html`<span class="jt-string">"${this._highlight(value)}"</span>`;
      case "number":
        return html`<span class="jt-number">${this._highlight(value)}</span>`;
      case "boolean":
        return html`<span class="jt-boolean">${this._highlight(value)}</span>`;
      default:
        return html`<span>${this._highlight(value)}</span>`;
    }
  }

  _summary(value) {
    const size = Object.keys(value).length;
    return Array.isArray(value)
      ? `[ ${size} ${this._labels.items || "items"} ]`
      : `{ ${size} ${this._labels.keys || "keys"} }`;
  }

  _rows(value, path, depth, query) {
    return Object.entries(value).map(([key, child]) => {
      if (query && !this._matches(key, child, query)) return nothing;

      const childPath = pathOf(path, key);
      const container = isContainer(child);
      const open = container && (query ? true : this._open.has(childPath));
      const indent = `padding-left: ${12 + depth * 16}px`;
      const keyClass = Array.isArray(value) ? "jt-key jt-index" : "jt-key";

      return html`
        <div class="jt-row" style=${indent}>
          ${container
            ? html`<button type="button" class="jt-toggle ${open ? "open" : ""}" @click=${() => this._toggle(childPath)} aria-label=${childPath}>
                <span class="hero-chevron-right-micro size-3.5"></span>
              </button>`
            : html`<span class="jt-spacer"></span>`}
          <span
            class=${keyClass}
            title=${`${this._labels.copy_path || "Copy"}: {{${childPath}}}`}
            @click=${() => this._copy(`{{${childPath}}}`, childPath)}
          >${this._highlight(key)}</span><span class="jt-colon">:</span>
          ${container
            ? html`<span class="jt-summary" @click=${() => this._toggle(childPath)}>${open ? (Array.isArray(child) ? "[" : "{") : this._summary(child)}</span>`
            : this._primitive(child)}
          ${this._copied === childPath ? html`<span class="jt-copied">${this._labels.copied || "Copied"}</span>` : nothing}
        </div>
        ${open ? this._rows(child, childPath, depth + 1, query) : nothing}
        ${open
          ? html`<div class="jt-row" style=${`padding-left: ${28 + depth * 16}px`}><span class="jt-summary">${Array.isArray(child) ? "]" : "}"}</span></div>`
          : nothing}
      `;
    });
  }

  render() {
    const value = this._value;
    const query = this._query.trim().toLowerCase();
    const labels = this._labels;

    if (!isContainer(value)) {
      return html`<div class="jt-body" style="padding-left: 12px">${this._primitive(value)}</div>`;
    }

    const rows = this._rows(value, "", 0, query);
    const empty = query && rows.every((row) => row === nothing);

    return html`
      <div class="jt-toolbar">
        <label class="jt-search">
          <span class="hero-magnifying-glass-micro size-3.5"></span>
          <input
            type="search"
            .value=${this._query}
            placeholder=${labels.search || "Filter"}
            @input=${(e) => (this._query = e.target.value)}
          />
        </label>
        <button type="button" class="jt-tool" title=${labels.expand || "Expand all"} @click=${() => this._setAll(true)}>
          <span class="hero-arrows-pointing-out-micro size-3.5"></span>
        </button>
        <button type="button" class="jt-tool" title=${labels.collapse || "Collapse all"} @click=${() => this._setAll(false)}>
          <span class="hero-arrows-pointing-in-micro size-3.5"></span>
        </button>
        <button
          type="button"
          class="jt-tool ${this._copied === "" ? "done" : ""}"
          @click=${() => this._copy(JSON.stringify(value, null, 2), "")}
        >
          <span class="${this._copied === "" ? "hero-check-micro" : "hero-clipboard-document-micro"} size-3.5"></span>
          ${this._copied === "" ? labels.copied || "Copied" : labels.copy || "Copy"}
        </button>
      </div>
      <div class="jt-body">
        ${empty ? html`<p class="jt-empty">${labels.no_match || "Nothing matches."}</p>` : rows}
      </div>
    `;
  }
}

if (!customElements.get("json-tree")) {
  customElements.define("json-tree", JsonTreeElement);
}
