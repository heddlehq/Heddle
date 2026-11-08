// Who else is on the canvas, and where: their avatars in the header, their cursors,
// the nodes they have selected or open, what they drag as it moves, and following one
// of them. See HeddleUI.FlowPresence and HeddleUI.FlowChannel.
//
// Presence keeps who is there and what they point at. Cursors and drags go from canvas
// to canvas without it, as they change too often.

import { Presence } from "phoenix";

const CURSOR_EVERY = 40;
const DRAG_EVERY = 50;
const CURSOR_IDLE = 30000;
const DRAGGED_FOR = 1500;

const t = (text) => (window.Translations && window.Translations[text]) || text;

const initials = (name) =>
  (name || "?")
    .split(/[\s._-]+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0].toUpperCase())
    .join("") || "?";

const throttle = (fn, every) => {
  let last = 0;
  let timer = null;
  let args = null;
  return (...next) => {
    args = next;
    const wait = every - (Date.now() - last);
    if (wait <= 0) {
      last = Date.now();
      fn(...args);
    } else if (!timer) {
      timer = setTimeout(() => {
        timer = null;
        last = Date.now();
        fn(...args);
      }, wait);
    }
  };
};

// Which nodes an operation touches, to light them up.
const touched = (ops) =>
  ops.flatMap((op) => {
    if (op.op === "add_node") return [op.node.id];
    if (op.op === "update_node") return [op.id];
    if (op.op === "move_nodes") return Object.keys(op.positions || {});
    if (op.op === "add_comment") return [op.comment.id];
    if (op.op === "update_comment") return [op.id];
    return [];
  });

export function startPresence(editor, channel, { client, userId, container, avatars }) {
  let me = client;
  let people = [];
  let selected = [];
  let editing = null;
  let following = null;
  const cursors = new Map(); // client -> { x, y, at, el }
  const drags = new Map(); // node id -> until
  const presence = new Presence(channel);
  const layer = document.createElement("div");
  layer.className = "remote-cursors";
  (container.parentElement || container).appendChild(layer);

  const others = () => people.filter((p) => p.client !== me);
  const byClient = (id) => people.find((p) => p.client === id);

  // The nodes others point at, in their colors.
  const mark = () => {
    const marks = {};
    for (const person of others()) {
      for (const id of person.selected || []) marks[id] = marks[id] || person.color;
      if (person.editing) marks[person.editing] = person.color;
    }
    editor.setRemoteMarks(marks);
  };

  // One avatar per person, however many tabs they have, and the agent while it works.
  const renderAvatars = () => {
    if (!avatars) return;
    const seen = new Map();
    for (const person of others()) {
      // This person's other tabs show their cursor, not another avatar.
      if (person.kind === "person" && person.user_id === userId) continue;
      const key = person.kind === "agent" ? `agent:${person.user_id}` : `person:${person.user_id}`;
      if (!seen.has(key)) seen.set(key, person);
    }
    avatars.replaceChildren();
    for (const person of seen.values()) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "presence-avatar";
      button.dataset.kind = person.kind;
      button.dataset.client = person.client;
      button.style.setProperty("--presence-color", person.color);
      const name = person.kind === "agent" ? `${t("Agent")} · ${person.name}` : person.name;
      button.title = person.kind === "agent" ? name : `${name} · ${t("Click to follow")}`;
      button.setAttribute("aria-label", button.title);
      if (person.kind === "agent") {
        const icon = document.createElement("span");
        icon.className = "hero-sparkles-micro size-3.5";
        button.appendChild(icon);
      } else {
        button.textContent = initials(person.name);
        button.addEventListener("click", () => follow(following === person.client ? null : person.client));
      }
      if (following === person.client) button.classList.add("is-following");
      avatars.appendChild(button);
    }
    avatars.dataset.count = String(seen.size);
  };

  const place = (cursor) => {
    const { x, y } = editor.toScreen(cursor);
    cursor.el.style.transform = `translate(${x}px, ${y}px)`;
  };

  const placeAll = () => cursors.forEach(place);

  const cursorFor = (id) => {
    let cursor = cursors.get(id);
    if (!cursor) {
      const person = byClient(id);
      if (!person) return null;
      const el = document.createElement("div");
      el.className = "remote-cursor";
      el.dataset.client = id;
      el.style.setProperty("--presence-color", person.color);
      const arrow = document.createElement("span");
      arrow.className = "remote-cursor-arrow";
      const label = document.createElement("span");
      label.className = "remote-cursor-name";
      label.textContent = person.name;
      el.append(arrow, label);
      layer.appendChild(el);
      cursor = { el, x: 0, y: 0, at: 0 };
      cursors.set(id, cursor);
    }
    return cursor;
  };

  const dropCursor = (id) => {
    const cursor = cursors.get(id);
    if (cursor) cursor.el.remove();
    cursors.delete(id);
  };

  const follow = (id) => {
    following = id;
    renderAvatars();
    const cursor = id && cursors.get(id);
    if (cursor) editor.centerOn(cursor);
  };

  presence.onSync(() => {
    people = presence.list((id, { metas }) => ({ client: id, ...metas[0] }));
    for (const id of [...cursors.keys()]) if (!byClient(id)) dropCursor(id);
    if (following && !byClient(following)) following = null;
    renderAvatars();
    mark();
  });

  channel.on("cursor", ({ client: id, x, y }) => {
    if (id === me) return;
    if (x === null || x === undefined) return dropCursor(id);
    const cursor = cursorFor(id);
    if (!cursor) return;
    Object.assign(cursor, { x, y, at: Date.now() });
    cursor.el.classList.remove("is-idle");
    place(cursor);
    if (following === id) editor.centerOn(cursor);
  });

  channel.on("drag", ({ client: id, positions }) => {
    if (id === me) return;
    const until = Date.now() + DRAGGED_FOR;
    Object.keys(positions || {}).forEach((nodeId) => drags.set(nodeId, until));
    editor.previewMove(positions || {});
  });

  // This person's cursor and drags, for the others.
  const sendCursor = throttle((point) => channel.push("cursor", point), CURSOR_EVERY);
  const onMove = (e) => sendCursor(editor.toCanvas(e.clientX, e.clientY));
  const onLeave = () => channel.push("cursor", {});
  const stopFollowing = () => following && follow(null);
  container.addEventListener("pointermove", onMove);
  container.addEventListener("pointerleave", onLeave);
  container.addEventListener("pointerdown", stopFollowing);
  container.addEventListener("wheel", stopFollowing, { passive: true });

  let dragging = {};
  const sendDrag = throttle(() => {
    channel.push("drag", { positions: dragging });
    dragging = {};
  }, DRAG_EVERY);
  editor.onDrag((id, position) => {
    dragging[id] = position;
    sendDrag();
  });

  const sendFocus = throttle(() => channel.push("focus", { selected, editing }), 100);
  editor.onSelection((ids) => {
    selected = ids;
    if (ids.length === 0) editing = null;
    sendFocus();
  });

  editor.onView(placeAll);

  const idle = setInterval(() => {
    const now = Date.now();
    cursors.forEach((cursor) => cursor.el.classList.toggle("is-idle", now - cursor.at > CURSOR_IDLE));
  }, 5000);

  return {
    rejoined: (client) => {
      me = client;
      sendFocus();
    },
    setEditing: (id) => {
      editing = id;
      sendFocus();
    },
    // What someone else is dragging right now.
    dragged: () => {
      const now = Date.now();
      for (const [id, until] of drags) if (until < now) drags.delete(id);
      return new Set(drags.keys());
    },
    // A change someone made: the agent's light up in its color.
    changed: (change) => {
      if (change.client !== "agent") return;
      const agent = people.find((p) => p.kind === "agent" && p.user_id === change.user_id);
      editor.flash(touched(change.ops), agent ? agent.color : "var(--color-primary)");
    },
    destroy: () => {
      clearInterval(idle);
      container.removeEventListener("pointermove", onMove);
      container.removeEventListener("pointerleave", onLeave);
      container.removeEventListener("pointerdown", stopFollowing);
      container.removeEventListener("wheel", stopFollowing);
      layer.remove();
    },
  };
}
