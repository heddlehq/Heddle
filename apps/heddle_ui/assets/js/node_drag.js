// Drags a node of the sidebar onto the canvas, see `HeddleUI.Components.Flow.NodeSidebar`.
//
// It is the pointer, not the browser's drag and drop, so what is dragged can move: it
// lifts off its row, follows the pointer with a little lag and tilt, turns into the node
// it will be once it is over the canvas, at the canvas's zoom, and lands where it is let
// go. Let go anywhere else, or with Escape, it goes back to its row.
import { categoryColor } from "./node_colors.js";

// How far the pointer moves before a press is a drag and not a click.
const THRESHOLD = 4;
// The node's size and where it is held when it lands, in the canvas's units. The drop
// puts the node's corner 40 units up and left of the pointer.
const NODE_SIZE = 88;
const NODE_GRAB = 40;
const PILL_HEIGHT = 40;

const reducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

export function setupNodeDrag({ root, container, editor }) {
  let drag = null;

  const onPointerDown = (event) => {
    const button = event.target.closest("[data-node-name]");
    if (!button || !root.contains(button) || event.button !== 0 || drag) return;
    event.preventDefault();
    drag = {
      button,
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      x: event.clientX,
      y: event.clientY,
      started: false,
    };
    window.addEventListener("pointermove", onPointerMove);
    window.addEventListener("pointerup", onPointerUp);
    window.addEventListener("pointercancel", onPointerCancel);
  };

  const onPointerMove = (event) => {
    if (!drag || event.pointerId !== drag.pointerId) return;
    drag.x = event.clientX;
    drag.y = event.clientY;
    if (!drag.started) {
      if (Math.hypot(drag.x - drag.startX, drag.y - drag.startY) < THRESHOLD) return;
      start();
    }
    updateTarget();
  };

  const onPointerUp = (event) => {
    if (!drag || event.pointerId !== drag.pointerId) return;
    if (!drag.started) return stopListening();
    swallowClick();
    if (overCanvas(event.clientX, event.clientY)) land(event.clientX, event.clientY);
    else goBack();
  };

  const onPointerCancel = (event) => {
    if (!drag || event.pointerId !== drag.pointerId) return;
    if (drag.started) goBack();
    else stopListening();
  };

  const onKeyDown = (event) => {
    if (event.key !== "Escape" || !drag?.started || drag.ending) return;
    event.preventDefault();
    event.stopPropagation();
    goBack();
  };

  const stopListening = () => {
    window.removeEventListener("pointermove", onPointerMove);
    window.removeEventListener("pointerup", onPointerUp);
    window.removeEventListener("pointercancel", onPointerCancel);
    window.removeEventListener("keydown", onKeyDown, true);
    if (!drag?.started) drag = null;
  };

  // A drag that ends over its own row would also click it, which tells to drag it.
  const swallowClick = () => {
    const swallow = (event) => {
      event.preventDefault();
      event.stopPropagation();
    };
    window.addEventListener("click", swallow, { capture: true, once: true });
    setTimeout(() => window.removeEventListener("click", swallow, true), 0);
  };

  const overCanvas = (x, y) => {
    const el = document.elementFromPoint(x, y);
    return !!el && container.contains(el);
  };

  const start = () => {
    const { button } = drag;
    const chip = button.querySelector("[data-node-chip]") || button;
    const chipRect = chip.getBoundingClientRect();
    const name = button.dataset.nodeName;
    const color = categoryColor(button.dataset.nodeCategory);
    const icon = button.dataset.nodeIcon || "hero-cube";

    const ghost = document.createElement("div");
    ghost.className = "node-ghost";
    ghost.setAttribute("aria-hidden", "true");
    ghost.style.setProperty("--ghost-color", color);
    ghost.innerHTML = `
      <div class="node-ghost-body">
        <span class="node-ghost-title"></span>
        <span class="node-ghost-chip"><span class="node-ghost-icon ${icon}"></span></span>
        <span class="node-ghost-label"></span>
      </div>`;
    ghost.querySelector(".node-ghost-title").textContent = name;
    ghost.querySelector(".node-ghost-label").textContent = name;
    document.body.appendChild(ghost);

    const body = ghost.querySelector(".node-ghost-body");
    // A pill keeps its width while it turns into a node, so the change can be animated.
    const pillWidth = Math.min(240, body.scrollWidth + 2);

    // It starts where its row's icon is, so it is the row that lifts off.
    const pillX = chipRect.left - 6;
    const pillY = chipRect.top + chipRect.height / 2 - PILL_HEIGHT / 2;
    Object.assign(drag, {
      started: true,
      name,
      chip,
      ghost,
      body,
      pillWidth,
      grabX: Math.max(10, Math.min(drag.startX - pillX, pillWidth - 10)),
      grabY: Math.max(8, Math.min(drag.startY - pillY, PILL_HEIGHT - 8)),
      posX: pillX,
      posY: pillY,
      tilt: 0,
      lift: 1,
      liftTarget: 1.04,
      onCanvas: null,
      last: performance.now(),
    });

    setMode(false);
    render();
    // The next frame, so it is first drawn as the row and then grows from it.
    requestAnimationFrame(() => ghost.classList.add("is-lifted"));

    button.setAttribute("data-dragging", "");
    document.documentElement.classList.add("node-dragging");
    window.addEventListener("keydown", onKeyDown, true);
    drag.frame = requestAnimationFrame(tick);
  };

  // A pill with the node's name off the canvas, the node itself on it.
  const setMode = (onCanvas) => {
    if (drag.onCanvas === onCanvas) return;
    drag.onCanvas = onCanvas;
    drag.ghost.classList.toggle("is-node", onCanvas);
    container.toggleAttribute("data-node-over", onCanvas);
    sizeBody();
  };

  const sizeBody = () => {
    const { body } = drag;
    if (drag.onCanvas) {
      const size = NODE_SIZE * editor.zoom();
      drag.ghost.style.setProperty("--ghost-zoom", editor.zoom());
      body.style.width = `${size}px`;
      body.style.height = `${size}px`;
    } else {
      body.style.width = `${drag.pillWidth}px`;
      body.style.height = `${PILL_HEIGHT}px`;
    }
  };

  const updateTarget = () => {
    if (drag.ending) return;
    setMode(overCanvas(drag.x, drag.y));
    if (drag.onCanvas) {
      // The canvas may have been zoomed while it was dragged.
      sizeBody();
      const grab = NODE_GRAB * editor.zoom();
      drag.targetX = drag.x - grab;
      drag.targetY = drag.y - grab;
    } else {
      drag.targetX = drag.x - drag.grabX;
      drag.targetY = drag.y - drag.grabY;
    }
  };

  const tick = (now) => {
    if (!drag?.ghost) return;
    const dt = Math.min(0.05, (now - drag.last) / 1000);
    drag.last = now;

    // Follows the pointer with a little lag, and leans the way it is going.
    const follow = reducedMotion() ? 1 : 1 - Math.exp(-dt * (drag.ending ? 18 : 28));
    const dx = (drag.targetX - drag.posX) * follow;
    const dy = (drag.targetY - drag.posY) * follow;
    drag.posX += dx;
    drag.posY += dy;

    const speed = dt > 0 ? dx / dt : 0;
    const lean = drag.ending || reducedMotion() ? 0 : Math.max(-10, Math.min(10, speed * 0.012));
    drag.tilt += (lean - drag.tilt) * (1 - Math.exp(-dt * 14));
    drag.lift += (drag.liftTarget - drag.lift) * (1 - Math.exp(-dt * 16));

    render();

    const settled =
      Math.abs(drag.targetX - drag.posX) < 0.5 &&
      Math.abs(drag.targetY - drag.posY) < 0.5 &&
      Math.abs(drag.tilt) < 0.2;
    if (drag.ending && settled && drag.onSettled) {
      const done = drag.onSettled;
      drag.onSettled = null;
      done();
    }
    if (drag?.ghost) drag.frame = requestAnimationFrame(tick);
  };

  const render = () => {
    const { ghost, posX, posY, tilt, lift } = drag;
    ghost.style.transform =
      `translate3d(${posX}px, ${posY}px, 0) rotate(${tilt.toFixed(2)}deg) scale(${lift.toFixed(3)})`;
  };

  // Lands on the canvas: it settles where the node goes, the node is added under it, and
  // then it fades into it.
  const land = (x, y) => {
    stopListening();
    drag.ending = true;
    drag.x = x;
    drag.y = y;
    setMode(true);
    const grab = NODE_GRAB * editor.zoom();
    drag.targetX = x - grab;
    drag.targetY = y - grab;
    drag.liftTarget = 1;
    drag.ghost.classList.add("is-landing");

    const current = drag;
    const added = Promise.resolve(editor.dropNode(current.name, x, y)).catch(() => {});
    const timeout = new Promise((resolve) => setTimeout(resolve, 1500));
    let landed = false;
    current.onSettled = () => {
      landed = true;
    };
    Promise.race([added, timeout]).then(() => {
      const fade = () => finish(current, "is-placed", 160);
      if (landed || reducedMotion()) fade();
      else current.onSettled = fade;
    });
  };

  // Goes back to its row, smaller, and fades as it gets there.
  const goBack = () => {
    stopListening();
    drag.ending = true;
    setMode(false);
    drag.liftTarget = 0.92;
    const current = drag;
    if (current.chip.isConnected) {
      const rect = current.chip.getBoundingClientRect();
      current.targetX = rect.left - 6;
      current.targetY = rect.top + rect.height / 2 - PILL_HEIGHT / 2;
      current.ghost.classList.add("is-returning");
      current.onSettled = () => finish(current, "is-gone", 120);
      // Should it never quite get there, it doesn't stay.
      setTimeout(() => finish(current, "is-gone", 120), 700);
    } else {
      finish(current, "is-gone", 160);
    }
  };

  const finish = (current, className, duration) => {
    if (current.finished) return;
    current.finished = true;
    current.ghost.classList.add(className);
    current.button.removeAttribute("data-dragging");
    container.removeAttribute("data-node-over");
    document.documentElement.classList.remove("node-dragging");
    setTimeout(() => {
      cancelAnimationFrame(current.frame);
      current.ghost.remove();
      if (drag === current) drag = null;
    }, reducedMotion() ? 0 : duration);
  };

  root.addEventListener("pointerdown", onPointerDown);

  return () => {
    root.removeEventListener("pointerdown", onPointerDown);
    stopListening();
    if (drag?.ghost) {
      cancelAnimationFrame(drag.frame);
      drag.ghost.remove();
      drag.button.removeAttribute("data-dragging");
      document.documentElement.classList.remove("node-dragging");
    }
    container.removeAttribute("data-node-over");
    drag = null;
  };
}
