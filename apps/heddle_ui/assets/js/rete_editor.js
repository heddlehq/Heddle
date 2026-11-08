import { NodeEditor, ClassicPreset } from "rete";
import { AreaPlugin, AreaExtensions } from "rete-area-plugin";
import { ConnectionPlugin, Presets as ConnectionPresets } from "rete-connection-plugin";
import { LitPlugin, Presets } from "@retejs/lit-plugin";
import { html } from "lit";

import { CustomNodeElement } from "./custom-node.js";
import { CustomCommentElement, COMMENT_TYPE, COMMENT_KINDS, defaultCommentColor } from "./custom-comment.js";
import { CustomConnectionElement } from "./custom-connection.js";
import { CustomSocketElement } from "./custom-socket.js";
import { addCustomBackground } from "./custom-background.js";

import { CustomControlElement } from "./custom-control.js";

if (!customElements.get("custom-node")) {
    customElements.define("custom-node", CustomNodeElement);
}
if (!customElements.get("custom-comment")) {
    customElements.define("custom-comment", CustomCommentElement);
}
if (!customElements.get("custom-connection")) {
    customElements.define("custom-connection", CustomConnectionElement);
}
if (!customElements.get("custom-socket")) {
    customElements.define("custom-socket", CustomSocketElement);
}
if (!customElements.get("custom-control")) {
    customElements.define("custom-control", CustomControlElement);
}

const CODE_CONTROLS = ['code_elixir', 'code_python'];

/**
 * The canvas, built on Rete. This file and the custom-*.js elements it renders are the
 * only ones that know about it.
 *
 * To draw flows with something else, return an object with the same methods from
 * `createEditor`: the FlowCanvas hook in app.js only talks to them. `importData` and
 * `exportData` take the flow as it is stored ({ nodes, connections, comments }), and
 * `connections` must come back in the order they went in: that order is what runs
 * first, see `Heddle.Graph`.
 */
// `readOnly` is for a person who can see a flow but not change it: they can still pan,
// zoom, select and open a node to read it. The server refuses their changes anyway.
export async function createEditor(container, { readOnly = false } = {}) {
    const socket = new ClassicPreset.Socket("socket");

    const editor = new NodeEditor();
    const area = new AreaPlugin(container);
    const connection = new ConnectionPlugin();
    const render = new LitPlugin();

    const selectedNodeIds = new Set();
    const selectNode = (nodeId, add = false) => {
        if (!add) selectedNodeIds.clear();
        selectedNodeIds.add(nodeId);
        updateNodeSelectionVisuals();
    };
    const deselectNode = (nodeId) => {
        selectedNodeIds.delete(nodeId);
        updateNodeSelectionVisuals();
    };
    const clearNodeSelection = () => {
        selectedNodeIds.clear();
        updateNodeSelectionVisuals();
    };
    const updateNodeSelectionVisuals = () => {
        for (const node of editor.getNodes()) {
            const sel = selectedNodeIds.has(node.id);
            node.selected = sel;
            const view = area.nodeViews.get(node.id);
            if (view && view.element) {
                const customNode = view.element.querySelector('custom-node, custom-comment');
                if (customNode) {
                    customNode.selected = sel;
                    customNode.requestUpdate();
                }
            }
        }
    };

    AreaExtensions.selectableNodes(area, AreaExtensions.selector(), {
        accumulating: AreaExtensions.accumulateOnCtrl(),
    });

    const selectedConnectionIds = new Set();
    const selectConnection = (connId, addToSelection = false) => {
        if (!addToSelection) selectedConnectionIds.clear();
        selectedConnectionIds.add(connId);
        area.update('connection', connId);
    };
    const clearConnectionSelection = () => {
        if (selectedConnectionIds.size === 0) return;
        selectedConnectionIds.clear();
        editor.getConnections().forEach(c => area.update('connection', c.id));
    };

    render.addPreset(
        Presets.classic.setup({
            customize: {
                node(data) {
                    if (data.payload.type === COMMENT_TYPE) {
                        return () =>
                            html`<custom-comment
                                .data=${data.payload}
                                .selected=${data.payload.selected}
                                .getZoom=${() => area.area.transform.k}
                                .readOnly=${readOnly}
                                .onChange=${() => {
                                    processChange();
                                    pushUndo();
                                }}
                                .onDelete=${() => editor.removeNode(data.payload.id)}
                            ></custom-comment>`;
                    }

                    return ({ emit }) =>
                        html`<custom-node 
                .data=${data.payload} 
                .emit=${emit} 
                .readOnly=${readOnly}
                class="${data.payload.selected ? 'selected' : ''}"
                .onDelete=${async () => {
                                const nodeId = data.payload.id;
                                const connections = editor.getConnections();
                                for (const conn of connections) {
                                    if (conn.source === nodeId || conn.target === nodeId) {
                                        await editor.removeConnection(conn.id);
                                    }
                                }
                                await editor.removeNode(nodeId);
                            }}
                .onConfig=${() => {
                                if (editor.triggerNodeConfig) {
                                    const node = data.payload;
                                    const variables = getUpstreamVariables(node.id);
                                    const cleanData = {
                                        id: node.id,
                                        label: node.label,
                                        type: node.type,
                                        icon: node.icon,
                                        controls: {},
                                        variables: variables
                                    };

                                    if (node.controls) {
                                        Object.entries(node.controls).forEach(([key, control]) => {
                                            cleanData.controls[key] = {
                                                value: control.value,
                                                label: control.label || key,
                                                type: control.type || 'text',
                                                options: control.options || [],
                                                credential_kind: control.credentialKind
                                            };
                                        });
                                    }

                                    editor.triggerNodeConfig(node.id, cleanData);
                                }
                            }}
                .onErrorDetails=${() => {
                                if (editor.triggerErrorDetails) {
                                    const node = data.payload;
                                    const view = area.nodeViews.get(node.id);
                                    let message = "Error details not available";
                                    if (view && view.element) {
                                        const customNode = view.element.querySelector('custom-node');
                                        if (customNode && customNode.error) {
                                            message = customNode.error;
                                        }
                                    }
                                    editor.triggerErrorDetails(node.id, message);
                                }
                            }}
                .onControlChange=${(key, value) => {
                                if (editor.triggerChange) {
                                    const node = data.payload;
                                    if (node.controls[key]) {
                                        node.controls[key].value = value;
                                        editor.triggerChange();
                                    }
                                }
                            }}
            ></custom-node>`;
                },
                connection(data) {
                    const connId = data.payload?.id;
                    const selected = connId ? selectedConnectionIds.has(connId) : false;
                    return (props) =>
                        html`<custom-connection
                            .path=${props.path}
                            .connectionId=${connId}
                            .selected=${selected}
                            data-connection-id=${connId || ''}
                            @connection-click=${(e) => {
                                if (e.detail && e.detail.connectionId) {
                                    selectConnection(e.detail.connectionId, e.detail.shiftKey || e.detail.ctrlKey || e.detail.metaKey);
                                }
                            }}
                        ></custom-connection>`;
                },
                socket(data) {
                    return () => html`<custom-socket .data=${data}></custom-socket>`;
                },
            },
        })
    );

    connection.addPreset(ConnectionPresets.classic.setup());

    addCustomBackground(area);

    editor.use(area);
    if (!readOnly) area.use(connection);
    area.use(render);

    if (readOnly) {
        // Dragging a node translates it while the pointer is down. Loading and
        // laying out the flow translate nodes too, with no pointer.
        let pointerDown = false;
        container.addEventListener('pointerdown', () => { pointerDown = true; }, true);
        window.addEventListener('pointerup', () => { pointerDown = false; }, true);
        area.addPipe((context) => {
            if (context && context.type === 'nodetranslate' && pointerDown) return;
            return context;
        });
    }

    AreaExtensions.simpleNodesOrder(area);

    let isMultiNodeDragging = false;
    let isTranslatingSelection = false;
    const clearMultiDragCursor = () => {
        if (isMultiNodeDragging) {
            isMultiNodeDragging = false;
            container.style.cursor = '';
        }
        window.removeEventListener('pointerup', clearMultiDragCursor);
    };
    area.addPipe(async (context) => {
        if (!context || context.type !== 'nodetranslated') return context;
        if (isTranslatingSelection) return context;
        if (!isRestoring && !isImportingData) trackMove();
        const { id: draggedId, position, previous } = context.data;
        const delta = { x: position.x - previous.x, y: position.y - previous.y };
        if (selectedNodeIds.size <= 1) return context;
        if (!selectedNodeIds.has(draggedId)) return context;
        const selected = editor.getNodes().filter(n => selectedNodeIds.has(n.id));
        if (!isMultiNodeDragging) {
            isMultiNodeDragging = true;
            container.style.cursor = 'grabbing';
            window.addEventListener('pointerup', clearMultiDragCursor, { once: true });
        }
        isTranslatingSelection = true;
        try {
            for (const node of selected) {
                if (node.id === draggedId) continue;
                const view = area.nodeViews.get(node.id);
                if (view) {
                    const p = view.position;
                    await area.translate(node.id, { x: p.x + delta.x, y: p.y + delta.y });
                }
            }
        } finally {
            isTranslatingSelection = false;
        }
        return context;
    });

    const UNDO_MAX = 50;
    const undoStack = [];
    const redoStack = [];
    let isRestoring = false;
    let isImportingData = false;
    let isDeletingSelection = false;
    let translateDebounce = null;

    const processChange = () => {
        if (editor.triggerChange) editor.triggerChange();
    };

    const commentFields = ({ kind, color, text, width, height }) => ({ kind, color, text, width, height });

    const trackMove = () => {
        if (translateDebounce) clearTimeout(translateDebounce);
        translateDebounce = setTimeout(() => {
            translateDebounce = null;
            processChange();
            pushUndo();
        }, 400);
    };

    // A node whose definition is gone stays on the canvas, or saving would erase it.
    const definitionFor = (nodeData, connections, definitions) => {
        const ports = (matches, key) => [...new Set(connections.filter(matches).map(c => c[key]))];

        return definitions[nodeData.type] ?? {
            name: nodeData.type,
            inputs: ports(c => c.target === nodeData.id, 'targetInput'),
            outputs: ports(c => c.source === nodeData.id, 'sourceOutput'),
            ui_fields: []
        };
    };

    const addHiddenControl = (node, key, value) => {
        const control = new ClassicPreset.InputControl("text", { initial: value });
        control.value = value;
        control.type = 'hidden';
        node.addControl(key, control);
    };

    const getSnapshot = () => {
        const nodes = [];
        const connections = [];
        const comments = [];
        for (const node of editor.getNodes()) {
            const position = area.nodeViews.get(node.id)?.position || { x: 0, y: 0 };
            if (node.type === COMMENT_TYPE) {
                comments.push({ ...commentFields(node), id: node.id, position });
                continue;
            }
            const controls = {};
            Object.keys(node.controls).forEach(key => {
                controls[key] = node.controls[key].value;
            });
            nodes.push({
                id: node.id,
                type: node.type,
                label: node.label,
                controls,
                position
            });
        }
        for (const conn of editor.getConnections()) {
            connections.push({
                source: conn.source,
                sourceOutput: conn.sourceOutput,
                target: conn.target,
                targetInput: conn.targetInput
            });
        }
        return { nodes, connections, comments };
    };

    const clearSelection = () => {
        clearNodeSelection();
    };

    const pushUndo = () => {
        if (isRestoring || isTranslatingSelection) return;
        const snapshot = getSnapshot();
        const top = undoStack[undoStack.length - 1];
        if (top && isSameSnapshot(top, snapshot)) {
            // Keeps where things moved to, so that undoing a later change puts them back there.
            undoStack[undoStack.length - 1] = snapshot;
            return;
        }
        undoStack.push(snapshot);
        if (undoStack.length > UNDO_MAX) undoStack.shift();
        redoStack.length = 0;
    };

    const commentKey = ({ id, kind, color, text, width, height }) => JSON.stringify([id, kind, color, text, width, height]);

    const isSameSnapshot = (a, b) => {
        if (a.nodes.length !== b.nodes.length || a.connections.length !== b.connections.length) return false;
        if (a.comments.map(commentKey).join() !== b.comments.map(commentKey).join()) return false;
        const aIds = new Set(a.nodes.map(n => n.id));
        const bIds = new Set(b.nodes.map(n => n.id));
        if (aIds.size !== bIds.size) return false;
        for (const id of aIds) { if (!bIds.has(id)) return false; }
        const aConnKeys = new Set(a.connections.map(c => `${c.source}:${c.sourceOutput}-${c.target}:${c.targetInput}`));
        const bConnKeys = new Set(b.connections.map(c => `${c.source}:${c.sourceOutput}-${c.target}:${c.targetInput}`));
        if (aConnKeys.size !== bConnKeys.size) return false;
        for (const k of aConnKeys) { if (!bConnKeys.has(k)) return false; }
        return true;
    };

    const restoreState = async (snapshot) => {
        const { nodes, connections, comments } = snapshot;
        const definitions = editor.nodeDefinitions || {};
        if (translateDebounce) {
            clearTimeout(translateDebounce);
            translateDebounce = null;
        }
        isRestoring = true;
        try {
            await editor.clear();
            editor.nodeDefinitions = definitions;
            for (const nodeData of nodes) {
                await processAddNode(nodeData.type, definitionFor(nodeData, connections, definitions), nodeData);
            }
            for (const comment of comments) {
                await processAddComment(comment);
            }
            for (const connData of connections) {
                const sourceNode = editor.getNode(connData.source);
                const targetNode = editor.getNode(connData.target);
                if (sourceNode && targetNode) {
                    try {
                        await editor.addConnection(
                            new ClassicPreset.Connection(
                                sourceNode,
                                connData.sourceOutput,
                                targetNode,
                                connData.targetInput
                            )
                        );
                    } catch (e) {}
                }
            }
            clearSelection();
            if (editor.getNodes().length > 0) {
                AreaExtensions.zoomAt(area, editor.getNodes());
            }
        } finally {
            isRestoring = false;
        }
    };

    const getUpstreamVariables = (startNodeId) => {
        const variables = new Set();
        const visited = new Set();
        const queue = [startNodeId];

        while (queue.length > 0) {
            const currentId = queue.shift();
            if (visited.has(currentId)) continue;
            visited.add(currentId);

            const currentNode = editor.getNode(currentId);
            if (!currentNode) continue;

            if (currentNode.type === 'Variable' && currentNode.id !== startNodeId) {
                const varName = currentNode.controls.var_name?.value;
                if (varName) variables.add(varName);
            }

            const connections = editor.getConnections().filter(c => c.target === currentId);
            for (const conn of connections) {
                queue.push(conn.source);
            }
        }
        return Array.from(variables);
    };

    editor.addPipe(context => {
        if (
            context.type === 'nodecreated' ||
            context.type === 'noderemoved' ||
            context.type === 'connectioncreated' ||
            context.type === 'connectionremoved'
        ) {
            // Drawing a flow that was loaded isn't a change. Undo reports its own.
            if (!isRestoring && !isImportingData) processChange();
            if (!isRestoring && !isImportingData && !isTranslatingSelection && !isDeletingSelection) {
                if (translateDebounce) {
                    clearTimeout(translateDebounce);
                    translateDebounce = null;
                }
                pushUndo();
            }
        }
        return context;
    });

    pushUndo();

    container.addEventListener("dragover", (e) => {
        e.preventDefault();
        e.dataTransfer.dropEffect = "copy";
    });

    container.addEventListener("drop", async (e) => {
        e.preventDefault();
        if (readOnly) return;
        const nodeName = e.dataTransfer.getData("application/vnd.heddle.node");
        
        if (!nodeName) return;

        if (editor.handleDrop) {
            const rect = container.getBoundingClientRect();
            
            const { k, x: tx, y: ty } = area.area.transform;
            const x = (e.clientX - rect.left - tx - 40 * k) / k;
            const y = (e.clientY - rect.top - ty - 40 * k) / k;
            
            editor.handleDrop(nodeName, { x, y });
        }
    });

    let isSelecting = false;
    let selectionStartX = 0;
    let selectionStartY = 0;

    const createSelectionBox = () => {
        const box = document.createElement('div');
        box.id = 'rete-selection-box';
        document.body.appendChild(box);
        return box;
    };
    const selectionBox = createSelectionBox();

    const updateSelectionBox = (startX, startY, endX, endY) => {
        const left = Math.min(startX, endX);
        const top = Math.min(startY, endY);
        const width = Math.abs(endX - startX);
        const height = Math.abs(endY - startY);
        
        selectionBox.style.cssText = `
            position: fixed;
            left: ${left}px;
            top: ${top}px;
            width: ${width}px;
            height: ${height}px;
            border: 2px solid var(--color-primary);
            background: color-mix(in oklab, var(--color-primary) 10%, transparent);
            border-radius: 0.5rem;
            z-index: 9999;
            pointer-events: none;
            display: ${width > 5 && height > 5 ? 'block' : 'none'};
        `;
    };

    const selectNodesInBox = () => {
        const boxRect = selectionBox.getBoundingClientRect();
        const { k, x: tx, y: ty } = area.area.transform;
        
        const boxLeft = (boxRect.left - tx) / k;
        const boxRight = (boxRect.right - tx) / k;
        const boxTop = (boxRect.top - ty) / k;
        const boxBottom = (boxRect.bottom - ty) / k;
        
        const nodesInBox = [];
        editor.getNodes().forEach(node => {
            const view = area.nodeViews.get(node.id);
            if (view && view.element) {
                const nodeEl = view.element;
                const nodeRect = nodeEl.getBoundingClientRect();
                
                const nodeLeft = (nodeRect.left - tx) / k;
                const nodeRight = (nodeRect.right - tx) / k;
                const nodeTop = (nodeRect.top - ty) / k;
                const nodeBottom = (nodeRect.bottom - ty) / k;
                
                const overlaps = !(nodeRight < boxLeft || nodeLeft > boxRight || nodeBottom < boxTop || nodeTop > boxBottom);
                
                if (overlaps) nodesInBox.push(node);
            }
        });
        
        selectedNodeIds.clear();
        nodesInBox.forEach(node => selectedNodeIds.add(node.id));
        updateNodeSelectionVisuals();
        const nodeIdsInBox = new Set(nodesInBox.map(n => n.id));
        selectedConnectionIds.clear();
        editor.getConnections().forEach(conn => {
            if (nodeIdsInBox.has(conn.source) && nodeIdsInBox.has(conn.target)) {
                selectedConnectionIds.add(conn.id);
            }
        });
        editor.getConnections().forEach(c => area.update('connection', c.id));
        
        selectionBox.style.display = 'none';
        
        if (area.area.privateDragInit) {
            area.area.setDragHandler(area.area.privateDragInit);
        }
        
        isSelecting = false;
    };

    const handleSelectionMove = (e) => {
        if (isSelecting) {
            e.preventDefault();
            updateSelectionBox(selectionStartX, selectionStartY, e.clientX, e.clientY);
        }
    };

    const handleSelectionUp = (e) => {
        if (isSelecting) {
            e.preventDefault();
            document.removeEventListener('mousemove', handleSelectionMove);
            document.removeEventListener('mouseup', handleSelectionUp);
            selectNodesInBox();
        }
    };

    document.addEventListener('pointerdown', (e) => {
        if (e.button !== 0 || !container.contains(e.target)) return;
        let clickedNodeId = null;
        for (const [nodeId, view] of area.nodeViews) {
            if (view.element && (view.element.contains(e.target) || view.element === e.target)) {
                clickedNodeId = nodeId;
                break;
            }
        }
        if (!clickedNodeId) {
            const el = document.elementFromPoint(e.clientX, e.clientY);
            for (const [nodeId, view] of area.nodeViews) {
                if (view.element && view.element.contains(el)) {
                    clickedNodeId = nodeId;
                    break;
                }
            }
        }
        if ((e.shiftKey || e.ctrlKey || e.metaKey) && clickedNodeId) {
            if (selectedNodeIds.has(clickedNodeId)) {
                deselectNode(clickedNodeId);
            } else {
                selectNode(clickedNodeId, true);
            }
            e.stopPropagation();
            e.preventDefault();
            return;
        }
        if (clickedNodeId) {
            if (!selectedNodeIds.has(clickedNodeId)) {
                selectNode(clickedNodeId, false);
            }
        }
    }, true);
    container.addEventListener('mousedown', (e) => {
        if (!container.contains(e.target)) return;
        
        const containerRect = container.getBoundingClientRect();
        const isInsideContainer = e.clientX >= containerRect.left && 
                                  e.clientX <= containerRect.right && 
                                  e.clientY >= containerRect.top && 
                                  e.clientY <= containerRect.bottom;
        
        if (!isInsideContainer) return;
        
        const isBackground = e.target === container || 
            e.target.classList.contains('rete-area') || 
            e.target.classList.contains('scene-layer') ||
            e.target.classList.contains('layer');
        
        const clickedElement = document.elementFromPoint(e.clientX, e.clientY);
        let clickedNodeId = null;
        
        const nodeViews = area.nodeViews;
        for (const [nodeId, view] of nodeViews) {
            if (view.element && view.element.contains(clickedElement)) {
                clickedNodeId = nodeId;
                break;
            }
        }
        
        if (e.shiftKey && isBackground) {
            e.preventDefault();
            e.stopPropagation();
            isSelecting = true;
            
            area.area.privateDragInit = area.area.dragHandler;
            area.area.setDragHandler(null);
            
            selectionStartX = e.clientX;
            selectionStartY = e.clientY;
            updateSelectionBox(selectionStartX, selectionStartY, selectionStartX, selectionStartY);
            
            document.addEventListener('mousemove', handleSelectionMove);
            document.addEventListener('mouseup', handleSelectionUp);
        }
        else if (isBackground && e.button === 0) {
            clearNodeSelection();
            clearConnectionSelection();
            if (editor.triggerCanvasClick) editor.triggerCanvasClick();
        } else if (clickedNodeId && e.button === 0) {
            clearConnectionSelection();
        }
    });

    let contextMenu = null;
    let contextMenuX = 0;
    let contextMenuY = 0;

    window.copiedNodesData = [];

    const removeContextMenu = () => {
        if (contextMenu) {
            contextMenu.remove();
            contextMenu = null;
        }
    };

    const createContextMenu = (x, y, contextMenuConnectionId = null) => {
        removeContextMenu();
        
        contextMenuX = x;
        contextMenuY = y;
        
        const menu = document.createElement('div');
        menu.className = 'fixed z-[200] bg-white dark:bg-slate-800 rounded-xl shadow-2xl border border-gray-100 dark:border-slate-700 py-1.5 min-w-[200px]';
        
        const allNodes = editor.getNodes();
        
        const selectedNodes = allNodes.filter(n => selectedNodeIds.has(n.id));
        
        const hasSelection = selectedNodes.length > 0;
        const hasConnectionSelection = selectedConnectionIds.size > 0;
        const hasDeleteTarget = hasSelection || hasConnectionSelection;
        const hasCopiedData = window.copiedNodesData && window.copiedNodesData.length > 0;
        
        const undoItem = document.createElement('button');
        undoItem.className = 'w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700 flex items-center gap-3';
        undoItem.innerHTML = `<span>${(window.Translations && window.Translations["Undo"]) || "Undo"} <span class="text-gray-400 text-xs">Ctrl+Z</span></span>`;
        undoItem.addEventListener('click', async (e) => {
            e.stopPropagation();
            await doUndo();
            removeContextMenu();
        });
        menu.appendChild(undoItem);
        
        const redoItem = document.createElement('button');
        redoItem.className = 'w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700 flex items-center gap-3';
        redoItem.innerHTML = `<span>${(window.Translations && window.Translations["Redo"]) || "Redo"} <span class="text-gray-400 text-xs">Ctrl+Y</span></span>`;
        redoItem.addEventListener('click', async (e) => {
            e.stopPropagation();
            await doRedo();
            removeContextMenu();
        });
        menu.appendChild(redoItem);
        
        const sepHistory = document.createElement('div');
        sepHistory.className = 'my-1 border-t border-gray-100 dark:border-slate-700';
        menu.appendChild(sepHistory);
        
        if (hasSelection) {
            const copyItem = document.createElement('button');
            copyItem.className = 'w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700 flex items-center gap-3';
            copyItem.innerHTML = `<span>Copy <span class="text-gray-400 text-xs">Ctrl+C</span></span>`;
            copyItem.addEventListener('click', (e) => {
                e.stopPropagation();
                copyNodes(selectedNodes);
                removeContextMenu();
            });
            menu.appendChild(copyItem);
        }
        
        if (hasCopiedData) {
            const pasteItem = document.createElement('button');
            pasteItem.className = 'w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700 flex items-center gap-3';
            pasteItem.innerHTML = `<span>Paste <span class="text-gray-400 text-xs">Ctrl+V</span></span>`;
            pasteItem.addEventListener('click', async (e) => {
                e.stopPropagation();
                const { k, x: tx, y: ty } = area.area.transform;
                await pasteNodes((contextMenuX - tx) / k, (contextMenuY - ty) / k);
                removeContextMenu();
            });
            menu.appendChild(pasteItem);
        }
        
        if (hasDeleteTarget) {
            const deleteItem = document.createElement('button');
            deleteItem.className = 'w-full px-4 py-2 text-left text-sm text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 flex items-center gap-3';
            deleteItem.innerHTML = `<span>Delete <span class="text-gray-400 text-xs">Del</span></span>`;
            deleteItem.addEventListener('click', async (e) => {
                e.stopPropagation();
                isDeletingSelection = true;
                try {
                    const selectedIds = new Set(selectedNodes.map(n => n.id));
                    for (const connId of [...selectedConnectionIds]) {
                        try { await editor.removeConnection(connId); } catch (err) {}
                    }
                    selectedConnectionIds.clear();
                    const allConnections = [...editor.getConnections()];
                    for (const conn of allConnections) {
                        if (selectedIds.has(conn.source) || selectedIds.has(conn.target)) {
                            try { await editor.removeConnection(conn.id); } catch (err) {}
                        }
                    }
                    for (const node of editor.getNodes()) {
                        if (selectedIds.has(node.id)) {
                            try { await editor.removeNode(node.id); } catch (err) {}
                        }
                    }
                    editor.getConnections().forEach(c => area.update('connection', c.id));
                    processChange();
                } finally {
                    isDeletingSelection = false;
                    pushUndo();
                }
                removeContextMenu();
            });
            menu.appendChild(deleteItem);
            
            const sep = document.createElement('div');
            sep.className = 'my-1 border-t border-gray-100 dark:border-slate-700';
            menu.appendChild(sep);
        }
        
        const createItem = document.createElement('button');
        createItem.className = 'w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700 flex items-center gap-3';
        createItem.innerHTML = `<span>${(window.Translations && window.Translations["Create Node"]) || "Create Node"} <span class="text-gray-400 text-xs">A</span></span>`;
        createItem.addEventListener('click', (e) => {
            e.stopPropagation();
            const { k, x: tx, y: ty } = area.area.transform;
            const nodeX = (contextMenuX - tx) / k;
            const nodeY = (contextMenuY - ty) / k;
            if (editor.triggerCreateNode) {
                editor.triggerCreateNode(nodeX, nodeY);
            }
            removeContextMenu();
        });
        menu.appendChild(createItem);

        Object.entries(COMMENT_KINDS).forEach(([kind, { label }]) => {
            const item = document.createElement('button');
            const text = `Add ${label}`;
            item.className = createItem.className;
            item.innerHTML = `<span>${(window.Translations && window.Translations[text]) || text}</span>`;
            item.addEventListener('click', async (e) => {
                e.stopPropagation();
                removeContextMenu();
                const rect = container.getBoundingClientRect();
                const { k, x: tx, y: ty } = area.area.transform;
                await processAddComment({
                    kind,
                    position: { x: (contextMenuX - rect.left - tx) / k, y: (contextMenuY - rect.top - ty) / k },
                    startEditing: true
                });
            });
            menu.appendChild(item);
        });

        let posX = x;
        let posY = y;
        if (x + 200 > window.innerWidth) posX = window.innerWidth - 210;
        if (y + 360 > window.innerHeight) posY = window.innerHeight - 370;
        
        menu.style.left = posX + 'px';
        menu.style.top = posY + 'px';
        document.body.appendChild(menu);
        contextMenu = menu;
    };

    container.addEventListener('connection-contextmenu', (e) => {
        e.preventDefault();
        e.stopPropagation();
        if (e.detail && e.detail.connectionId != null) {
            selectConnection(e.detail.connectionId, true);
            createContextMenu(e.detail.clientX, e.detail.clientY, e.detail.connectionId);
        }
    });
    container.addEventListener('contextmenu', (e) => {
        if (e.target.closest?.('textarea')) return;
        e.preventDefault();
        if (readOnly) return;
        const path = e.composedPath && e.composedPath();
        const connectionEl = path && Array.isArray(path) && path.find(el => {
            if (el.nodeType !== 1) return false;
            if (el.hasAttribute && el.hasAttribute('data-connection-id')) return true;
            return el.tagName && el.tagName.toLowerCase() === 'custom-connection' && el.connectionId;
        });
        const contextMenuConnectionId = connectionEl
            ? (connectionEl.getAttribute && connectionEl.getAttribute('data-connection-id')) || connectionEl.connectionId || null
            : null;
        if (contextMenuConnectionId) selectConnection(contextMenuConnectionId, true);
        createContextMenu(e.clientX, e.clientY, contextMenuConnectionId);
    }, true);

    document.addEventListener('click', (e) => {
        if (e.button === 0 && contextMenu && !contextMenu.contains(e.target)) {
            removeContextMenu();
        }
    });

    const copyNodes = (nodes) => {
        const selectedIds = new Set(nodes.map(n => n.id));
        window.copiedNodesData = nodes.map(node => {
            let position = { x: 0, y: 0 };
            const view = area.nodeViews.get(node.id);
            if (view && view.position) position = { x: view.position.x, y: view.position.y };
            const copied = { type: node.type, label: node.label, data: { ...node.data }, position, originalId: node.id };
            if (node.type === COMMENT_TYPE) {
                copied.comment = commentFields(node);
            }
            return copied;
        });
        window.copiedConnections = editor.getConnections()
            .filter(c => selectedIds.has(c.source) && selectedIds.has(c.target))
            .map(c => ({ source: c.source, target: c.target, sourceOutput: c.sourceOutput, targetInput: c.targetInput }));
    };

    const pasteNodes = async (pasteX, pasteY) => {
        const positions = window.copiedNodesData.map(n => n.position || { x: 0, y: 0 });
        const minX = Math.min(...positions.map(p => p.x));
        const minY = Math.min(...positions.map(p => p.y));
        const oldIdToNewId = {};
        for (const nodeData of window.copiedNodesData) {
            const pos = nodeData.position || { x: 0, y: 0 };
            const newId = 'node_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
            const position = { x: pasteX + (pos.x - minX) + 20, y: pasteY + (pos.y - minY) + 20 };
            oldIdToNewId[nodeData.originalId || nodeData.data?.id] = newId;
            if (nodeData.type === COMMENT_TYPE) {
                await processAddComment({ ...nodeData.comment, id: newId, position });
                continue;
            }
            const newData = { ...nodeData.data, id: newId, label: nodeData.label, position };
            const definition = editor.nodeDefinitions && editor.nodeDefinitions[nodeData.type];
            if (definition) await processAddNode(nodeData.type, definition, newData);
        }
        const conns = window.copiedConnections || [];
        for (const conn of conns) {
            const sourceNew = oldIdToNewId[conn.source];
            const targetNew = oldIdToNewId[conn.target];
            if (!sourceNew || !targetNew) continue;
            const sourceNode = editor.getNode(sourceNew);
            const targetNode = editor.getNode(targetNew);
            if (sourceNode && targetNode) {
                try {
                    await editor.addConnection(new ClassicPreset.Connection(sourceNode, conn.sourceOutput, targetNode, conn.targetInput));
                } catch (err) {}
            }
        }
    };

    const doUndo = async () => {
        if (undoStack.length < 2) return;
        redoStack.push(getSnapshot());
        undoStack.pop();
        const toRestore = undoStack[undoStack.length - 1];
        await restoreState(toRestore);
        processChange();
    };
    const doRedo = async () => {
        if (redoStack.length === 0) return;
        undoStack.push(getSnapshot());
        const toRestore = redoStack.pop();
        await restoreState(toRestore);
        processChange();
    };

    document.addEventListener('keydown', (e) => {
        if (readOnly) return;
        const isInput = e.target && (e.target.closest('input') || e.target.closest('textarea') || e.target.closest('[contenteditable="true"]'));
        if (!isInput && e.key === 'z' && (e.ctrlKey || e.metaKey) && !e.shiftKey) {
            e.preventDefault();
            doUndo();
            return;
        }
        if (!isInput && (e.key === 'y' && (e.ctrlKey || e.metaKey) || e.key === 'z' && (e.ctrlKey || e.metaKey) && e.shiftKey)) {
            e.preventDefault();
            doRedo();
            return;
        }
        
        if (!isInput && e.key === 'a' && !e.ctrlKey && !e.metaKey && !e.altKey && editor.triggerCreateNode) {
            e.preventDefault();
            removeContextMenu();
            const rect = container.getBoundingClientRect();
            const { k, x: tx, y: ty } = area.area.transform;
            editor.triggerCreateNode((rect.width / 2 - tx) / k, (rect.height / 2 - ty) / k);
            return;
        }

        if (e.key === 'Escape') {
            removeContextMenu();
            clearNodeSelection();
            clearConnectionSelection();
        }
        
        if (!isInput && e.key === 'c' && (e.ctrlKey || e.metaKey)) {
            const nodes = editor.getNodes().filter(n => selectedNodeIds.has(n.id));
            if (nodes.length > 0) {
                e.preventDefault();
                copyNodes(nodes);
            }
        }
        
        if (!isInput && e.key === 'v' && (e.ctrlKey || e.metaKey)) {
            if (window.copiedNodesData && window.copiedNodesData.length > 0) {
                e.preventDefault();
                const { k, x: tx, y: ty } = area.area.transform;
                pasteNodes((window.innerWidth / 2 - tx) / k, (window.innerHeight / 2 - ty) / k);
            }
        }
        
        if (e.key === 'Delete' || e.key === 'Backspace') {
            if (isInput) return;
            const allNodes = editor.getNodes();
            const selectedNodes = allNodes.filter(n => selectedNodeIds.has(n.id));
            const hasConnectionSelection = selectedConnectionIds.size > 0;
            const hasNodeSelection = selectedNodes.length > 0;
            if (!hasConnectionSelection && !hasNodeSelection) return;
            e.preventDefault();
            isDeletingSelection = true;
            (async () => {
                try {
                    const selectedIds = new Set(selectedNodes.map(n => n.id));
                    for (const connId of [...selectedConnectionIds]) {
                        try { await editor.removeConnection(connId); } catch (err) {}
                    }
                    selectedConnectionIds.clear();
                    const allConnections = [...editor.getConnections()];
                    for (const conn of allConnections) {
                        if (selectedIds.has(conn.source) || selectedIds.has(conn.target)) {
                            try { await editor.removeConnection(conn.id); } catch (err) {}
                        }
                    }
                    for (const node of editor.getNodes()) {
                        if (selectedIds.has(node.id)) {
                            try { await editor.removeNode(node.id); } catch (err) {}
                        }
                    }
                    editor.getConnections().forEach(c => area.update('connection', c.id));
                    processChange();
                } finally {
                    isDeletingSelection = false;
                    pushUndo();
                }
            })();
        }
    });

    const processAddComment = async ({ id, kind = 'note', color, text = "", width, height, position, startEditing = false }) => {
        const node = new ClassicPreset.Node(COMMENT_TYPE);
        node.type = COMMENT_TYPE;
        node.kind = kind;
        node.color = color || defaultCommentColor(kind);
        node.text = text;
        node.width = width || COMMENT_KINDS[kind].width;
        node.height = height || COMMENT_KINDS[kind].height;
        node.startEditing = startEditing;
        if (id) node.id = id;

        await editor.addNode(node);
        // Below the wires and nodes, and a section below the other comments.
        area.nodeViews.get(node.id).element.style.zIndex = kind === 'section' ? '-2' : '-1';
        await area.translate(node.id, position);

        return node;
    };

    const processAddNode = async (name, definition, data = null) => {
        if (!definition) {
            console.error("Node definition not provided for", name);
            return;
        }

        const node = new ClassicPreset.Node(definition.name);
        node.type = definition.name;
        node.icon = definition.icon;
        node.category = definition.category;

        if (data && data.id) {
            node.id = data.id;
        }
        if (data && data.label) {
            node.label = data.label;
        }


        if (definition.inputs) {
            definition.inputs.forEach(inputName => {
                node.addInput(inputName, new ClassicPreset.Input(socket));
            });
        }

        if (definition.outputs) {
            definition.outputs.forEach(outputName => {
                node.addOutput(outputName, new ClassicPreset.Output(socket));
            });
        }

        const uiFields = definition.ui_fields || [];

        uiFields.forEach(field => {
            const initialValue = data?.controls?.[field.name] ?? field.default ?? "";
            const control = new ClassicPreset.InputControl("text", { initial: initialValue });
            control.value = initialValue;

            if (field.type === 'code') {
                const renderMode = field.render || 'icon';

                if (renderMode === 'button') {
                    control.type = 'code-button';
                } else {
                    control.type = 'code-icon';
                }
                control.label = field.label || 'Edit Code';

                control.language = field.language || 'elixir';

                control.onClick = () => {
                    if (editor.triggerCodeEdit) {

                        const language = node.controls.language?.value || control.language;
                        const code_elixir = node.controls.code_elixir?.value || '';
                        const code_python = node.controls.code_python?.value || '';
                        const code = node.controls.code?.value || '';
                        const variables = getUpstreamVariables(node.id);
                        editor.triggerCodeEdit(node.id, code_elixir, code_python, field.name, language, variables, code);
                    }
                };
            } else {
                control.type = ['select', 'credential', 'model', 'textarea'].includes(field.type) ? field.type : 'text';
                control.label = field.label;
                control.credentialKind = field.kind;
                if (field.options) control.options = field.options;
            }

            node.addControl(field.name, control);
        });

        if (uiFields.some(field => field.type === 'code')) {
            CODE_CONTROLS.forEach(key => {
                if (!node.controls[key]) addHiddenControl(node, key, "");
            });
        }

        // What this version of the node doesn't show still belongs to the flow.
        Object.entries(data?.controls ?? {}).forEach(([key, value]) => {
            if (node.controls[key]) {
                node.controls[key].value = value;
            } else if (!(CODE_CONTROLS.includes(key) && value === "")) {
                addHiddenControl(node, key, value);
            }
        });

        await editor.addNode(node);

        if (data && data.position) {
            await area.translate(node.id, data.position);
        }

        return node;
    };

    return {
        destroy: () => area.destroy(),
        addNode: async (name, definition, data = null) => {
            return await processAddNode(name, definition, data);
        },
        addComment: async (kind) => {
            if (readOnly) return;
            const rect = container.getBoundingClientRect();
            const { k, x: tx, y: ty } = area.area.transform;
            await processAddComment({
                kind,
                position: {
                    x: (rect.width / 2 - tx) / k - COMMENT_KINDS[kind].width / 2,
                    // Above the middle, where the nodes of a flow that was just opened are.
                    y: (rect.height / 4 - ty) / k - COMMENT_KINDS[kind].height / 2
                },
                startEditing: true
            });
        },
        importData: async ({ nodes, connections, comments, definitions }) => {
            if (translateDebounce) {
                clearTimeout(translateDebounce);
                translateDebounce = null;
            }
            isImportingData = true;
            try {
                // A flow from the AI comes without comments, and must not wipe the ones here.
                const keptComments = comments ?? getSnapshot().comments;
                await editor.clear();
                editor.nodeDefinitions = definitions || {};

                for (const nodeData of nodes) {
                    await processAddNode(nodeData.type, definitionFor(nodeData, connections, definitions), nodeData);
                }

                for (const comment of keptComments) {
                    await processAddComment(comment);
                }

                for (const connData of connections) {
                    const sourceNode = editor.getNode(connData.source);
                    const targetNode = editor.getNode(connData.target);

                    if (sourceNode && targetNode) {
                        try {
                            await editor.addConnection(
                                new ClassicPreset.Connection(
                                    sourceNode,
                                    connData.sourceOutput,
                                    targetNode,
                                    connData.targetInput
                                )
                            );
                        } catch (e) {
                            console.error("Failed to restore connection:", connData, e);
                        }
                    } else {
                        console.warn("Source or Target node not found for connection:", connData);
                    }
                }

                if (editor.getNodes().length > 0) {
                    AreaExtensions.zoomAt(area, editor.getNodes());
                }
                clearSelection();
                pushUndo();
            } finally {
                setTimeout(() => { isImportingData = false; }, 0);
            }
        },

        onChange: (cb) => {
            editor.triggerChange = cb;
        },
        onCodeEdit: (cb) => {
            editor.triggerCodeEdit = cb;
        },
        onNodeConfig: (cb) => {
            editor.triggerNodeConfig = cb;
        },
        onCanvasClick: (cb) => {
            editor.triggerCanvasClick = cb;
        },
        onErrorDetails: (cb) => {
            editor.triggerErrorDetails = cb;
        },
        onCreateNode: (cb) => {
            editor.triggerCreateNode = cb;
        },
        onDrop: (cb) => {
            editor.handleDrop = cb;
        },
        updateNodeCode: async (nodeId, code_elixir, code_python, fieldName) => {
            const node = editor.getNode(nodeId);
            if (!node) return;

            if (!node.controls.code_elixir) {
                node.controls.code_elixir = { value: '' };
            }
            if (!node.controls.code_python) {
                node.controls.code_python = { value: '' };
            }

            node.controls.code_elixir.value = code_elixir;
            node.controls.code_python.value = code_python;
            // The code now lives in the fields above. Left here, the older field
            // would come back at run time if the code were cleared.
            if (node.controls.code) node.controls.code.value = '';

            await area.update('node', nodeId);
            processChange();
        },
        updateNodeData: async (nodeId, data) => {
            const node = editor.getNode(nodeId);
            if (!node) return;

            Object.entries(data).forEach(([key, value]) => {
                if (node.controls[key]) {
                    node.controls[key].value = value;
                }
            });

            await area.update('node', nodeId);
            processChange();
        },
        updateNodeLabel: async (nodeId, label) => {
            const node = editor.getNode(nodeId);
            if (!node) return;

            node.label = label;
            await area.update('node', nodeId);
            processChange();
        },
        updateNodeSockets: async (nodeId, { inputs, outputs }) => {
            const node = editor.getNode(nodeId);
            if (!node) return;

            const currentInputs = Object.keys(node.inputs);

            for (const inputKey of currentInputs) {
                if (!inputs.includes(inputKey)) {
                    const connections = editor.getConnections().filter(c => c.target === nodeId && c.targetInput === inputKey);
                    for (const conn of connections) {
                        await editor.removeConnection(conn.id);
                    }
                    node.removeInput(inputKey);
                }
            }

            for (const inputKey of inputs) {
                if (!node.inputs[inputKey]) {
                    node.addInput(inputKey, new ClassicPreset.Input(socket));
                }
            }

            const currentOutputs = Object.keys(node.outputs);

            for (const outputKey of currentOutputs) {
                if (!outputs.includes(outputKey)) {
                    const connections = editor.getConnections().filter(c => c.source === nodeId && c.sourceOutput === outputKey);
                    for (const conn of connections) {
                        await editor.removeConnection(conn.id);
                    }
                    node.removeOutput(outputKey);
                }
            }

            for (const outputKey of outputs) {
                if (!node.outputs[outputKey]) {
                    node.addOutput(outputKey, new ClassicPreset.Output(socket));
                }
            }

            await area.update('node', nodeId);
            processChange();
        },
        exportData: async () => {
            // What this would report is in the snapshot, and reporting it after the save
            // would bring back a warning about changes that were just saved.
            if (translateDebounce) {
                clearTimeout(translateDebounce);
                translateDebounce = null;
                pushUndo();
            }
            return getSnapshot();
        },
        addNodeError: (nodeId, message) => {
            const view = area.nodeViews.get(nodeId);
            if (view && view.element) {
                const customNode = view.element.querySelector('custom-node');
                if (customNode) {
                    customNode.classList.add('error');
                    customNode.error = message;
                } else {
                    view.element.classList.add('error');
                }
            } else {
                console.warn("ReteEditor: View or element not found for nodeId", nodeId);
            }
        },
        clearNodeErrors: () => {
            area.nodeViews.forEach(view => {
                if (view.element) {
                    view.element.classList.remove('error');
                    const customNode = view.element.querySelector('custom-node');
                    if (customNode) {
                        customNode.classList.remove('error');
                        customNode.error = null;
                    }
                }
            });
        },
    };
}
