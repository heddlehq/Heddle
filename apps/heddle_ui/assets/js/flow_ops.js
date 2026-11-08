// The operations of `Heddle.Graph.Ops`, for the canvas: what changed between two
// graphs, and applying what others changed. A graph is { nodes, connections, comments }
// as the canvas snapshots it. Keep this in step with the Elixir module.

const CONNECTION_KEYS = ["source", "sourceOutput", "target", "targetInput"];
const NODE_FIELDS = ["label", "type", "settings"];

const clone = (value) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)));
const same = (a, b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
const connectionKey = (c) => CONNECTION_KEYS.map((k) => c[k]).join("|");
const pickConnection = (c) => Object.fromEntries(CONNECTION_KEYS.map((k) => [k, c[k]]));
const byId = (items) => new Map(items.map((item) => [item.id, item]));
const withoutPosition = ({ position, ...rest }) => rest;

export const emptyGraph = () => ({ nodes: [], connections: [], comments: [] });

export function normalize(graph) {
  return {
    nodes: clone(graph?.nodes || []),
    connections: (graph?.connections || []).map(pickConnection),
    comments: clone(graph?.comments || []),
  };
}

// The operations that turn `before` into `after`.
export function diffOps(before, after) {
  before = normalize(before);
  after = normalize(after);
  const ops = [];
  const oldNodes = byId(before.nodes);
  const newNodes = byId(after.nodes);
  const positions = {};

  for (const node of before.nodes) {
    if (!newNodes.has(node.id)) ops.push({ op: "remove_node", id: node.id });
  }

  for (const node of after.nodes) {
    const old = oldNodes.get(node.id);
    if (!old) {
      ops.push({ op: "add_node", node });
      continue;
    }
    const set = {};
    for (const field of NODE_FIELDS) {
      if (!same(old[field], node[field])) set[field] = node[field] ?? null;
    }
    const controls = {};
    const oldControls = old.controls || {};
    const newControls = node.controls || {};
    for (const [key, value] of Object.entries(newControls)) {
      if (!same(oldControls[key], value)) controls[key] = value;
    }
    for (const key of Object.keys(oldControls)) {
      if (!(key in newControls)) controls[key] = null;
    }
    if (Object.keys(controls).length > 0) set.controls = controls;
    if (Object.keys(set).length > 0) ops.push({ op: "update_node", id: node.id, set });
    if (node.position && !same(old.position, node.position)) positions[node.id] = node.position;
  }

  const oldComments = byId(before.comments);
  const newComments = byId(after.comments);
  for (const comment of before.comments) {
    if (!newComments.has(comment.id)) ops.push({ op: "remove_comment", id: comment.id });
  }
  for (const comment of after.comments) {
    const old = oldComments.get(comment.id);
    if (!old) {
      ops.push({ op: "add_comment", comment });
      continue;
    }
    if (!same(withoutPosition(old), withoutPosition(comment))) {
      const set = {};
      const { id, position, ...fields } = comment;
      for (const [key, value] of Object.entries(fields)) {
        if (!same(old[key], value)) set[key] = value;
      }
      for (const key of Object.keys(withoutPosition(old))) {
        if (key !== "id" && !(key in comment)) set[key] = null;
      }
      ops.push({ op: "update_comment", id: comment.id, set });
    }
    if (comment.position && !same(old.position, comment.position)) positions[comment.id] = comment.position;
  }

  ops.push(...connectionOps(before, after, newNodes));

  if (Object.keys(positions).length > 0) ops.push({ op: "move_nodes", positions });
  return ops;
}

// Removing a node takes its connections. Added connections go after the others of their
// output, so when that isn't the order wanted, all of them go in that order instead.
function connectionOps(before, after, newNodes) {
  const kept = before.connections.filter((c) => newNodes.has(c.source) && newNodes.has(c.target));
  const afterKeys = new Set(after.connections.map(connectionKey));
  const keptKeys = new Set(kept.map(connectionKey));
  const removed = kept.filter((c) => !afterKeys.has(connectionKey(c)));
  const added = after.connections.filter((c) => !keptKeys.has(connectionKey(c)));

  const result = kept.filter((c) => afterKeys.has(connectionKey(c))).concat(added);
  if (result.map(connectionKey).join() === after.connections.map(connectionKey).join()) {
    return [
      ...removed.map((connection) => ({ op: "remove_connection", connection })),
      ...added.map((connection) => ({ op: "add_connection", connection })),
    ];
  }
  return [{ op: "set_connections", connections: after.connections }];
}

// Applies `ops` to a copy of `graph`. What doesn't apply is left out, and `skip`
// lists the fields ("node:ID:FIELD"...) to leave as they are.
export function applyOps(graph, ops, { skip = new Set() } = {}) {
  let g = normalize(graph);
  for (const op of ops) {
    const next = applyOne(g, filterOp(op, skip));
    if (next) g = next;
  }
  return g;
}

function filterOp(op, skip) {
  if (skip.size === 0) return op;
  if (op.op === "update_node") {
    const set = {};
    for (const [key, value] of Object.entries(op.set || {})) {
      if (key === "controls") {
        const controls = Object.fromEntries(
          Object.entries(value || {}).filter(([k]) => !skip.has(`node:${op.id}:controls.${k}`))
        );
        if (Object.keys(controls).length > 0) set.controls = controls;
      } else if (!skip.has(`node:${op.id}:${key}`)) {
        set[key] = value;
      }
    }
    return { ...op, set };
  }
  if (op.op === "move_nodes") {
    return {
      ...op,
      positions: Object.fromEntries(Object.entries(op.positions || {}).filter(([id]) => !skip.has(`position:${id}`))),
    };
  }
  if (op.op === "update_comment") {
    return {
      ...op,
      set: Object.fromEntries(Object.entries(op.set || {}).filter(([k]) => !skip.has(`comment:${op.id}:${k}`))),
    };
  }
  return op;
}

function applyOne(g, op) {
  const nodes = byId(g.nodes);
  switch (op.op) {
    case "add_node":
      if (nodes.has(op.node.id)) return null;
      return { ...g, nodes: [...g.nodes, clone(op.node)] };
    case "remove_node":
      if (!nodes.has(op.id)) return null;
      return {
        nodes: g.nodes.filter((n) => n.id !== op.id),
        connections: g.connections.filter((c) => c.source !== op.id && c.target !== op.id),
        comments: g.comments.map((c) => (Array.isArray(c.nodes) ? { ...c, nodes: c.nodes.filter((id) => id !== op.id) } : c)),
      };
    case "update_node": {
      if (!nodes.has(op.id)) return null;
      return {
        ...g,
        nodes: g.nodes.map((n) => {
          if (n.id !== op.id) return n;
          const node = { ...n };
          for (const [key, value] of Object.entries(op.set || {})) {
            if (key === "controls") {
              const controls = { ...(node.controls || {}) };
              for (const [k, v] of Object.entries(value || {})) {
                if (v === null) delete controls[k];
                else controls[k] = clone(v);
              }
              node.controls = controls;
            } else if (key === "settings" && value === null) {
              delete node.settings;
            } else {
              node[key] = clone(value);
            }
          }
          return node;
        }),
      };
    }
    case "move_nodes": {
      const move = (item) => (op.positions?.[item.id] ? { ...item, position: { ...op.positions[item.id] } } : item);
      return { ...g, nodes: g.nodes.map(move), comments: g.comments.map(move) };
    }
    case "add_connection": {
      const c = pickConnection(op.connection);
      if (!nodes.has(c.source) || !nodes.has(c.target)) return null;
      if (g.connections.some((x) => connectionKey(x) === connectionKey(c))) return null;
      return { ...g, connections: [...g.connections, c] };
    }
    case "remove_connection": {
      const key = connectionKey(op.connection);
      if (!g.connections.some((x) => connectionKey(x) === key)) return null;
      return { ...g, connections: g.connections.filter((x) => connectionKey(x) !== key) };
    }
    case "set_connections":
      return {
        ...g,
        connections: (op.connections || []).map(pickConnection).filter((c) => nodes.has(c.source) && nodes.has(c.target)),
      };
    case "add_comment":
      if (g.comments.some((c) => c.id === op.comment.id)) return null;
      return { ...g, comments: [...g.comments, clone(op.comment)] };
    case "remove_comment":
      if (!g.comments.some((c) => c.id === op.id)) return null;
      return { ...g, comments: g.comments.filter((c) => c.id !== op.id) };
    case "update_comment":
      if (!g.comments.some((c) => c.id === op.id)) return null;
      return {
        ...g,
        comments: g.comments.map((c) => {
          if (c.id !== op.id) return c;
          const comment = { ...c };
          for (const [key, value] of Object.entries(op.set || {})) {
            if (value === null) delete comment[key];
            else comment[key] = clone(value);
          }
          return comment;
        }),
      };
    default:
      return null;
  }
}

// The fields an operation changes, as `Heddle.Graph.Ops.fields/1` says them.
export function fieldsOf(op) {
  switch (op.op) {
    case "update_node":
      return Object.entries(op.set || {}).flatMap(([key, value]) =>
        key === "controls" ? Object.keys(value || {}).map((k) => `node:${op.id}:controls.${k}`) : [`node:${op.id}:${key}`]
      );
    case "move_nodes":
      return Object.keys(op.positions || {}).map((id) => `position:${id}`);
    case "update_comment":
      return Object.keys(op.set || {}).map((k) => `comment:${op.id}:${k}`);
    default:
      return [];
  }
}
