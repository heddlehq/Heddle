// Drags a flow of the flows page onto another group, see
// `HeddleUI.Components.Flow.FlowGroups`. The menu of each row does the same without a
// mouse, so this is only a shortcut.
const FLOW = "application/x-heddle-flow"

export const FlowDragHook = {
  mounted() {
    const over = (event) => event.target.closest("[data-group]")
    const clear = () =>
      this.el.querySelectorAll("[data-drop-target]").forEach((el) => el.removeAttribute("data-drop-target"))

    this.el.addEventListener("dragstart", (event) => {
      const row = event.target.closest("[data-flow-id]")
      if (!row) return
      event.dataTransfer.setData(FLOW, row.dataset.flowId)
      event.dataTransfer.effectAllowed = "move"
    })
    this.el.addEventListener("dragover", (event) => {
      const group = over(event)
      if (!group || !event.dataTransfer.types.includes(FLOW)) return
      event.preventDefault()
      clear()
      group.setAttribute("data-drop-target", "")
    })
    this.el.addEventListener("dragleave", (event) => {
      if (!this.el.contains(event.relatedTarget)) clear()
    })
    this.el.addEventListener("drop", (event) => {
      const group = over(event)
      const flow = event.dataTransfer.getData(FLOW)
      clear()
      if (!group || !flow) return
      event.preventDefault()
      this.pushEvent("move_flow", { flow, group: group.dataset.group })
    })
    this.el.addEventListener("dragend", clear)
  },
}
