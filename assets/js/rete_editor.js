import { NodeEditor, ClassicPreset } from "rete";
import { AreaPlugin, AreaExtensions } from "rete-area-plugin";
import { ConnectionPlugin, Presets as ConnectionPresets } from "rete-connection-plugin";
import { LitPlugin, Presets } from "@retejs/lit-plugin";
import { html } from "lit";

import { CustomNodeElement } from "./custom-node.js";
import { CustomConnectionElement } from "./custom-connection.js";
import { CustomSocketElement } from "./custom-socket.js";
import { addCustomBackground } from "./custom-background.js";

import { CustomControlElement } from "./custom-control.js";

if (!customElements.get("custom-node")) {
    customElements.define("custom-node", CustomNodeElement);
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

export async function createEditor(container) {
    const socket = new ClassicPreset.Socket("socket");

    const editor = new NodeEditor();
    const area = new AreaPlugin(container);
    const connection = new ConnectionPlugin();
    const render = new LitPlugin();

    AreaExtensions.selectableNodes(area, AreaExtensions.selector(), {
        accumulating: AreaExtensions.accumulateOnCtrl(),
    });

    render.addPreset(
        Presets.classic.setup({
            customize: {
                node(data) {
                    return ({ emit }) =>
                        html`<custom-node 
                .data=${data.payload} 
                .emit=${emit} 
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
                                        controls: {},
                                        variables: variables
                                    };

                                    if (node.controls) {
                                        Object.entries(node.controls).forEach(([key, control]) => {
                                            cleanData.controls[key] = {
                                                value: control.value,
                                                label: control.label || key,
                                                type: control.type || 'text',
                                                options: control.options || []
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
                connection() {
                    return (props) =>
                        html`<custom-connection .path=${props.path}></custom-connection>`;
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
    area.use(connection);
    area.use(render);

    AreaExtensions.simpleNodesOrder(area);

    const processChange = () => {
        if (editor.triggerChange) editor.triggerChange();
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

            if ((currentNode.type === 'Variable' || currentNode.label === 'Variable') && currentNode.id !== startNodeId) {
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
            context.type === 'connectionremoved' ||
            context.type === 'translated'
        ) {
            processChange();
        }
        return context;
    });

    container.addEventListener("dragover", (e) => {
        e.preventDefault();
        e.dataTransfer.dropEffect = "copy";
    });

    container.addEventListener("drop", async (e) => {
        e.preventDefault();
        const nodeName = e.dataTransfer.getData("application/vnd.fusionflow.node");
        
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
            border: 2px solid oklch(58% 0.233 277.117);
            background: oklch(58% 0.233 277.117 / 0.1);
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
                
                if (overlaps) {
                    node.selected = true;
                    const customNode = nodeEl.querySelector('custom-node');
                    if (customNode) {
                        customNode.selected = true;
                        customNode.requestUpdate();
                    }
                }
            }
        });
        
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
        
        if (clickedNodeId && e.shiftKey && e.button === 0) {
            e.preventDefault();
            e.stopPropagation();
            const node = editor.getNode(clickedNodeId);
            if (node) {
                node.selected = true;
                const view = area.nodeViews.get(clickedNodeId);
                if (view && view.element) {
                    const customNode = view.element.querySelector('custom-node');
                    if (customNode) {
                        customNode.selected = true;
                        customNode.requestUpdate();
                    }
                }
                return;
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
            editor.getNodes().forEach(node => {
                node.selected = false;
                const view = area.nodeViews.get(node.id);
                if (view && view.element) {
                    const customNode = view.element.querySelector('custom-node');
                    if (customNode) {
                        customNode.selected = false;
                        customNode.requestUpdate();
                    }
                }
            });
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

    const createContextMenu = (x, y) => {
        removeContextMenu();
        
        contextMenuX = x;
        contextMenuY = y;
        
        const menu = document.createElement('div');
        menu.className = 'fixed z-[200] bg-white dark:bg-slate-800 rounded-xl shadow-2xl border border-gray-100 dark:border-slate-700 py-1.5 min-w-[200px]';
        
        const allNodes = editor.getNodes();
        
        const selectedNodes = allNodes.filter(n => {
            if (n.selected) return true;
            const view = area.nodeViews.get(n.id);
            if (view && view.element) {
                const customNode = view.element.querySelector('custom-node');
                if (customNode && customNode.selected) return true;
            }
            return false;
        });
        
        const hasSelection = selectedNodes.length > 0;
        const hasCopiedData = window.copiedNodesData && window.copiedNodesData.length > 0;
        
        if (hasSelection) {
            const copyItem = document.createElement('button');
            copyItem.className = 'w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700 flex items-center gap-3';
            copyItem.innerHTML = `<span>Copy <span class="text-gray-400 text-xs">Ctrl+C</span></span>`;
            copyItem.addEventListener('click', (e) => {
                e.stopPropagation();
                window.copiedNodesData = selectedNodes.map(node => {
                    let position = { x: 0, y: 0 };
                    const view = area.nodeViews.get(node.id);
                    if (view && view.position) position = { x: view.position.x, y: view.position.y };
                    return { type: node.type, label: node.label, data: { ...node.data }, position };
                });
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
                const pasteX = (contextMenuX - tx) / k;
                const pasteY = (contextMenuY - ty) / k;
                const positions = window.copiedNodesData.map(n => n.position || { x: 0, y: 0 });
                const minX = Math.min(...positions.map(p => p.x));
                const minY = Math.min(...positions.map(p => p.y));
                
                for (const nodeData of window.copiedNodesData) {
                    const pos = nodeData.position || { x: 0, y: 0 };
                    const newId = 'node_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
                    const newData = { ...nodeData.data, id: newId, label: nodeData.label, position: { x: pasteX + (pos.x - minX) + 20, y: pasteY + (pos.y - minY) + 20 }};
                    const definition = editor.nodeDefinitions && editor.nodeDefinitions[nodeData.type];
                    if (definition) {
                        await processAddNode(nodeData.type, definition, newData);
                    }
                }
                removeContextMenu();
            });
            menu.appendChild(pasteItem);
        }
        
        if (hasSelection) {
            const deleteItem = document.createElement('button');
            deleteItem.className = 'w-full px-4 py-2 text-left text-sm text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 flex items-center gap-3';
            deleteItem.innerHTML = `<span>Delete <span class="text-gray-400 text-xs">Del</span></span>`;
            deleteItem.addEventListener('click', (e) => {
                e.stopPropagation();
                
                const currentNodes = editor.getNodes();
                const selectedIds = new Set(selectedNodes.map(n => n.id));
                
                const allConnections = [...editor.getConnections()];
                allConnections.forEach(conn => {
                    if (selectedIds.has(conn.source) || selectedIds.has(conn.target)) {
                        try { editor.removeConnection(conn.id); } catch(e) { 
                        }
                    }
                });
                
                currentNodes.forEach(node => {
                    if (selectedIds.has(node.id)) {
                        try { editor.removeNode(node.id); } catch(e) { 
                        }
                    }
                });
                
                removeContextMenu();
            });
            menu.appendChild(deleteItem);
            
            const sep = document.createElement('div');
            sep.className = 'my-1 border-t border-gray-100 dark:border-slate-700';
            menu.appendChild(sep);
        }
        
        const createItem = document.createElement('button');
        createItem.className = 'w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700 flex items-center gap-3';
        createItem.innerHTML = `<span>Create Node</span>`;
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
        
        let posX = x;
        let posY = y;
        if (x + 200 > window.innerWidth) posX = window.innerWidth - 210;
        if (y + 200 > window.innerHeight) posY = window.innerHeight - 210;
        
        menu.style.left = posX + 'px';
        menu.style.top = posY + 'px';
        document.body.appendChild(menu);
        contextMenu = menu;
    };

    container.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        createContextMenu(e.clientX, e.clientY);
    });

    document.addEventListener('click', (e) => {
        if (e.button === 0 && contextMenu && !contextMenu.contains(e.target)) {
            removeContextMenu();
        }
    });

    document.addEventListener('keydown', (e) => {
        
        if (e.key === 'Escape') {
            removeContextMenu();
            editor.getNodes().forEach(node => {
                node.selected = false;
                const view = area.nodeViews.get(node.id);
                if (view && view.element) {
                    const customNode = view.element.querySelector('custom-node');
                    if (customNode) { customNode.selected = false; customNode.requestUpdate(); }
                }
            });
        }
        
        if (e.key === 'c' && (e.ctrlKey || e.metaKey)) {
            const nodes = editor.getNodes().filter(n => n.selected);
            if (nodes.length > 0) {
                e.preventDefault();
                window.copiedNodesData = nodes.map(node => {
                    let position = { x: 0, y: 0 };
                    const view = area.nodeViews.get(node.id);
                    if (view && view.position) position = { x: view.position.x, y: view.position.y };
                    return { type: node.type, label: node.label, data: { ...node.data }, position };
                });
            }
        }
        
        if (e.key === 'v' && (e.ctrlKey || e.metaKey)) {
            if (window.copiedNodesData && window.copiedNodesData.length > 0) {
                e.preventDefault();
                const { k, x: tx, y: ty } = area.area.transform;
                const centerX = window.innerWidth / 2;
                const centerY = window.innerHeight / 2;
                const pasteX = (centerX - tx) / k;
                const pasteY = (centerY - ty) / k;
                const positions = window.copiedNodesData.map(n => n.position || { x: 0, y: 0 });
                const minX = Math.min(...positions.map(p => p.x));
                const minY = Math.min(...positions.map(p => p.y));
                
                window.copiedNodesData.forEach(async (nodeData) => {
                    const pos = nodeData.position || { x: 0, y: 0 };
                    const newId = 'node_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
                    const newData = { ...nodeData.data, id: newId, label: nodeData.label, position: { x: pasteX + (pos.x - minX) + 20, y: pasteY + (pos.y - minY) + 20 }};
                    const definition = editor.nodeDefinitions && editor.nodeDefinitions[nodeData.type];
                    if (definition) await processAddNode(nodeData.type, definition, newData);
                });
            }
        }
        
        if (e.key === 'Delete' || e.key === 'Backspace') {
            const allNodes = editor.getNodes();
            const nodes = allNodes.filter(n => {
                if (n.selected) return true;
                const view = area.nodeViews.get(n.id);
                if (view && view.element) {
                    const customNode = view.element.querySelector('custom-node');
                    if (customNode && customNode.selected) return true;
                }
                return false;
            });
            
            if (nodes.length > 0) {
                e.preventDefault();
                
                const selectedIds = new Set(nodes.map(n => n.id));
                
                const allConnections = [...editor.getConnections()];
                allConnections.forEach(conn => {
                    if (selectedIds.has(conn.source) || selectedIds.has(conn.target)) {
                        try { editor.removeConnection(conn.id); } catch(e) {}
                    }
                });
                
                const currentNodes = editor.getNodes();
                currentNodes.forEach(node => {
                    if (selectedIds.has(node.id)) {
                        try { editor.removeNode(node.id); } catch(e) {}
                    }
                });
            }
        }
    });

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
            const initialValue = (data && data.controls && data.controls[field.name]) || field.default || "";
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
                        const variables = getUpstreamVariables(node.id);
                        editor.triggerCodeEdit(node.id, code_elixir, code_python, field.name, language, variables);
                    }
                };
            } else {
                control.type = field.type === 'select' ? 'select' : 'text';
                control.label = field.label;
                if (field.options) control.options = field.options;
            }

            node.addControl(field.name, control);
        });

        const elixirField = uiFields.find(f => f.name === 'code_elixir');
        const pythonField = uiFields.find(f => f.name === 'code_python');
        
        const initialElixir = (data && data.controls && data.controls.code_elixir !== undefined) 
            ? data.controls.code_elixir 
            : (elixirField ? elixirField.default : "");
            
        const initialPython = (data && data.controls && data.controls.code_python !== undefined) 
            ? data.controls.code_python 
            : (pythonField ? pythonField.default : "");

        if (!node.controls.code_elixir) {
            const ctrl = new ClassicPreset.InputControl("text", { initial: initialElixir });
            ctrl.value = initialElixir;
            ctrl.type = 'hidden';
            node.addControl('code_elixir', ctrl);
        } else if (data && data.controls && data.controls.code_elixir !== undefined) {
             node.controls.code_elixir.value = data.controls.code_elixir;
        }

        if (!node.controls.code_python) {
            const ctrl = new ClassicPreset.InputControl("text", { initial: initialPython });
            ctrl.value = initialPython;
            ctrl.type = 'hidden';
            node.addControl('code_python', ctrl);
        } else if (data && data.controls && data.controls.code_python !== undefined) {
             node.controls.code_python.value = data.controls.code_python;
        }

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
        importData: async ({ nodes, connections, definitions }) => {
            await editor.clear();

            editor.nodeDefinitions = definitions || {};

            for (const nodeData of nodes) {
                const nodeType = nodeData.type || nodeData.label;
                const definition = definitions[nodeType];

                if (!definition) {
                    console.warn(`Definition not found for node type: ${nodeType}`);
                    continue;
                }
                await processAddNode(nodeType, definition, nodeData);
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

            if (nodes.length > 0) {
                AreaExtensions.zoomAt(area, editor.getNodes());
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
            const nodes = [];
            const connections = [];

            for (const node of editor.getNodes()) {
                const controls = {};

                Object.keys(node.controls).forEach(key => {
                    controls[key] = node.controls[key].value;
                });

                nodes.push({
                    id: node.id,
                    type: node.type || node.label,
                    label: node.label,
                    controls,
                    position: area.nodeViews.get(node.id)?.position || { x: 0, y: 0 }
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

            return { nodes, connections };
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
