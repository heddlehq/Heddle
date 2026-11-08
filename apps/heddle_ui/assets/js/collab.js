// Editing a flow with others: the canvas talks to the session of the flow on the server
// (HeddleCore.Flows.Session) through the channel "flow:<id>" (HeddleUI.FlowChannel).
//
// What this person changes goes out as operations (flow_ops.js) a moment after they
// change it, and is saved by the server: there is no save button. What others change
// comes in, numbered in the order the server applied it. Until the server confirms a
// change of this person, nothing someone else sent overrides the same field here: the
// server applies this person's change after theirs, so it wins there too. A change the
// server refuses, or a gap in the numbers, reloads the flow from the server.
//
// Undo takes back only what this person did, applied to the flow as it is now: a step
// on something that isn't there anymore is skipped.

import { Socket } from "phoenix";
import { applyOps, diffOps, fieldsOf, normalize } from "./flow_ops.js";

const SEND_AFTER = 120;
const UNDO_MAX = 50;

export function startCollab(editor, { flowId, token, onSaveState, onRemote, onReady, onJoinError }) {
  const socket = new Socket("/flow", { params: { token } });
  socket.connect();
  const channel = socket.channel(`flow:${flowId}`, {});

  let shadow = normalize({});
  let epoch = null;
  let lastSeq = 0;
  let client = null;
  let canEdit = false;
  let ready = false;
  let refCounter = 0;
  let timer = null;
  let syncing = Promise.resolve();
  const pending = new Map(); // ref -> fields
  const undoStack = [];
  const redoStack = [];
  const waiters = [];

  const setState = (state) => onSaveState && onSaveState(state);

  const pendingFields = () => new Set([...pending.values()].flat());

  const settle = () => {
    if (timer || pending.size > 0) return;
    setState("saved");
    while (waiters.length) waiters.shift()();
  };

  const load = async ({ graph, seq, epoch: e, definitions }) => {
    epoch = e;
    lastSeq = seq;
    pending.clear();
    undoStack.length = 0;
    redoStack.length = 0;
    await editor.importData({ ...graph, definitions });
    shadow = normalize(editor.snapshot());
    ready = true;
    settle();
  };

  const resync = () => {
    ready = false;
    channel
      .push("snapshot", {})
      .receive("ok", (reply) => load(reply))
      .receive("error", () => setTimeout(resync, 1000));
  };

  // Sends what changed here since the last time. `record` says what undo keeps of it.
  const send = async ({ record = "undo" } = {}) => {
    if (!ready || !canEdit) return;
    const current = normalize(editor.snapshot());
    const ops = diffOps(shadow, current);
    if (ops.length === 0) return settle();

    const inverse = diffOps(current, shadow);
    const ref = ++refCounter;
    pending.set(ref, ops.flatMap(fieldsOf));
    shadow = current;
    setState("saving");

    if (record === "undo") {
      undoStack.push({ inverse });
      if (undoStack.length > UNDO_MAX) undoStack.shift();
      redoStack.length = 0;
    } else if (record) {
      record.push({ inverse });
    }

    channel
      .push("ops", { ops, ref, client })
      .receive("ok", () => {
        pending.delete(ref);
        settle();
      })
      .receive("error", () => {
        pending.delete(ref);
        resync();
      })
      .receive("timeout", () => {
        pending.delete(ref);
        resync();
      });
  };

  const queue = (fn) => (syncing = syncing.then(fn).catch((error) => console.error(error)));

  const changed = () => {
    if (!ready || !canEdit) return;
    setState("saving");
    clearTimeout(timer);
    timer = setTimeout(() => {
      timer = null;
      queue(() => send());
    }, SEND_AFTER);
  };

  const sendNow = () => {
    clearTimeout(timer);
    timer = null;
    return queue(() => send());
  };

  channel.on("ops", (change) => {
    queue(async () => {
      if (!ready) return;
      if (change.epoch !== epoch || change.seq !== lastSeq + 1) return resync();
      lastSeq = change.seq;
      if (change.client === client) return;

      // What is still here only goes first, so the canvas and the shadow agree.
      clearTimeout(timer);
      timer = null;
      await send();

      shadow = applyOps(shadow, change.ops, { skip: pendingFields() });
      await editor.reconcile(shadow);
      shadow = normalize(editor.snapshot());
      onRemote && onRemote(change);
      settle();
    });
  });

  // Each entry is what one change did, so undoing it, or redoing what an undo took
  // back, applies its inverse. What that sends goes on the other stack.
  const step = (from, to) =>
    queue(async () => {
      if (!ready || !canEdit) return;
      await send();
      const entry = from.pop();
      if (!entry) return;
      const target = applyOps(shadow, entry.inverse);
      await editor.reconcile(target);
      await send({ record: to });
    });

  editor.setHistory({
    undo: () => step(undoStack, redoStack),
    redo: () => step(redoStack, undoStack),
  });

  channel
    .join()
    .receive("ok", async (reply) => {
      client = reply.client;
      canEdit = reply.can_edit;
      await load(reply);
      onReady && onReady(reply);
    })
    .receive("error", (reply) => onJoinError && onJoinError(reply));

  // A lost connection joins again by itself, and joining loads the flow anew.
  channel.onError(() => {
    ready = false;
    setState("offline");
  });

  return {
    changed,
    channel,
    // Resolves once everything changed here is on the server: before a run or a publish.
    flush: async () => {
      await sendNow();
      if (pending.size === 0 && !timer) return;
      await new Promise((resolve) => waiters.push(resolve));
    },
    destroy: () => {
      clearTimeout(timer);
      channel.leave();
      socket.disconnect();
    },
  };
}
