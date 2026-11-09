defmodule HeddleUI.Components.Flow.FlowGroups do
  @moduledoc """
  The flows page with its groups, see `HeddleCore.Flows.Groups`: each group with its
  flows, then the flows without one. A group folds away, and an editor moves a flow
  from the menu of its row, or by dragging it onto another group, see `flow_drag.js`.
  """

  use HeddleUI, :html

  attr :groups, :list, required: true
  attr :flows, :list, required: true
  attr :can_edit, :boolean, default: false
  attr :renaming_group_id, :any, default: nil
  attr :rename_form, :any, default: nil

  def flow_groups(assigns) do
    assigns =
      assign(assigns,
        by_group: Enum.group_by(assigns.flows, & &1.group_id),
        menu_groups: Enum.map(assigns.groups, &{&1.id, &1.name})
      )

    ~H"""
    <div
      id="flow-groups"
      phx-hook={@can_edit && "FlowDrag"}
      class="space-y-4"
    >
      <%= if @groups == [] do %>
        <div id="flow-group-none" class={[section_class(), "overflow-hidden"]} data-group="">
          <.flow_list flows={@flows} can_edit={@can_edit} groups={@menu_groups} />
        </div>
      <% else %>
        <.group_section
          :for={group <- @groups}
          id={"flow-group-#{group.id}"}
          group={group}
          flows={Map.get(@by_group, group.id, [])}
          groups={@menu_groups}
          can_edit={@can_edit}
          renaming={@renaming_group_id == group.id}
          rename_form={@rename_form}
        />
        <.group_section
          id="flow-group-none"
          group={nil}
          flows={Map.get(@by_group, nil, [])}
          groups={@menu_groups}
          can_edit={@can_edit}
          renaming={false}
          rename_form={nil}
        />
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :group, :any, required: true
  attr :flows, :list, required: true
  attr :groups, :list, required: true
  attr :can_edit, :boolean, required: true
  attr :renaming, :boolean, required: true
  attr :rename_form, :any, required: true

  defp group_section(assigns) do
    assigns = assign(assigns, :list_id, "#{assigns.id}-flows")

    ~H"""
    <section
      id={@id}
      data-group={@group && @group.id}
      class={[
        section_class(),
        "transition-shadow data-[drop-target]:ring-2 data-[drop-target]:ring-primary/50"
      ]}
    >
      <header class="group/header flex items-center gap-2 px-4 py-3">
        <button
          id={"#{@id}-toggle"}
          type="button"
          phx-click={
            JS.toggle_class("hidden", to: "##{@list_id}")
            |> JS.toggle_class("-rotate-90", to: "##{@id}-chevron")
          }
          class={[
            "flex min-w-0 items-center gap-2 rounded-md text-left focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40",
            not @renaming && "flex-1"
          ]}
          aria-controls={@list_id}
        >
          <span id={"#{@id}-chevron"} class="flex shrink-0 transition-transform duration-150">
            <.icon name="hero-chevron-down-mini" class="size-4 text-gray-400" />
          </span>
          <.icon
            name={if(@group, do: "hero-folder", else: "hero-inbox")}
            class="size-4 shrink-0 text-gray-500 dark:text-gray-400"
          />
          <span
            :if={not @renaming}
            class="truncate text-sm font-semibold text-gray-900 dark:text-white"
          >
            {if(@group, do: @group.name, else: gettext("No group"))}
          </span>
          <span class="shrink-0 rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600 dark:bg-slate-700 dark:text-gray-300">
            {length(@flows)}
          </span>
        </button>

        <%!-- The input's fieldset keeps 8px below it: mt-2 puts as much above, so the
             header centers the input with the icons. --%>
        <.form
          :if={@renaming}
          for={@rename_form}
          id={"#{@id}-rename"}
          phx-submit="rename_group"
          phx-click-away="cancel_rename_group"
          class="mt-2 flex flex-1 items-start gap-2"
        >
          <input type="hidden" name="group_id" value={@group.id} />
          <div class="min-w-0 flex-1">
            <.input
              field={@rename_form[:name]}
              type="text"
              autofocus
              phx-keydown="cancel_rename_group"
              phx-key="Escape"
            />
          </div>
          <%!-- pt-1 is the padding above the input in its fieldset, so both line up. --%>
          <div class="pt-1">
            <.button type="submit" variant="primary" size="field">{gettext("Save")}</.button>
          </div>
        </.form>

        <div
          :if={@can_edit && @group && not @renaming}
          class="flex shrink-0 items-center gap-1 opacity-100 transition-opacity md:opacity-0 md:group-hover/header:opacity-100 md:focus-within:opacity-100"
        >
          <button
            id={"#{@id}-rename-button"}
            type="button"
            phx-click="start_rename_group"
            phx-value-id={@group.id}
            title={gettext("Rename group")}
            class="rounded-md p-1.5 text-gray-500 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-400 dark:hover:bg-slate-700 dark:hover:text-white"
          >
            <.icon name="hero-pencil-square" class="size-4" />
          </button>
          <button
            id={"#{@id}-delete"}
            type="button"
            phx-click="delete_group"
            phx-value-id={@group.id}
            data-confirm={
              gettext("Delete the group %{name}? Its flows stay, without a group.",
                name: @group.name
              )
            }
            title={gettext("Delete group")}
            class="rounded-md p-1.5 text-gray-500 hover:bg-red-50 hover:text-red-600 dark:text-gray-400 dark:hover:bg-red-950/40 dark:hover:text-red-400"
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        </div>
      </header>

      <div id={@list_id} class="border-t border-gray-200 dark:border-slate-700">
        <p :if={@flows == []} class="px-6 py-4 text-sm text-gray-500 dark:text-gray-400">
          <%= cond do %>
            <% not @can_edit -> %>
              {gettext("No flows in this group.")}
            <% @group -> %>
              {gettext("No flows here yet. Drag one in, or move it from its menu.")}
            <% true -> %>
              {gettext("Every flow is in a group.")}
          <% end %>
        </p>
        <.flow_list :if={@flows != []} flows={@flows} can_edit={@can_edit} groups={@groups} />
      </div>
    </section>
    """
  end

  attr :flows, :list, required: true
  attr :can_edit, :boolean, required: true
  attr :groups, :list, required: true

  defp flow_list(assigns) do
    ~H"""
    <ul role="list" class="divide-y divide-gray-200 dark:divide-slate-700">
      <li
        :for={flow <- @flows}
        id={"flow-#{flow.id}"}
        data-flow-id={flow.id}
        draggable={to_string(@can_edit)}
        class="group/row relative flex items-center hover:bg-gray-50 dark:hover:bg-slate-700/50 transition-colors"
      >
        <.link
          navigate={~p"/flows/#{flow.id}"}
          draggable="false"
          class="flex min-w-0 flex-1 items-center gap-4 px-6 py-4"
        >
          <div class="rounded-lg bg-primary/10 p-2 text-primary">
            <.icon name="hero-bolt" class="size-5" />
          </div>
          <div class="min-w-0">
            <p class="truncate text-sm font-medium text-gray-900 dark:text-white">{flow.name}</p>
            <p class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
              {length(flow.nodes || [])} {gettext("nodes")} • {length(flow.connections || [])} {gettext(
                "connections"
              )} • {gettext("Updated")} {Calendar.strftime(flow.updated_at, "%b %d, %Y")}
            </p>
          </div>
        </.link>

        <div :if={@can_edit && @groups != []} class="relative pr-2">
          <button
            id={"flow-#{flow.id}-move"}
            type="button"
            phx-click={JS.toggle(to: "#flow-#{flow.id}-menu")}
            title={gettext("Move to group")}
            aria-haspopup="menu"
            class="rounded-md p-2 text-gray-400 hover:bg-gray-100 hover:text-gray-900 dark:hover:bg-slate-700 dark:hover:text-white"
          >
            <.icon name="hero-folder-arrow-down" class="size-5" />
          </button>
          <div
            id={"flow-#{flow.id}-menu"}
            role="menu"
            phx-click-away={JS.hide(to: "#flow-#{flow.id}-menu")}
            class="hidden absolute right-2 top-full z-30 mt-1 w-56 rounded-lg border border-gray-200 bg-white p-1 shadow-lg dark:border-slate-700 dark:bg-slate-800"
          >
            <p class="px-3 pb-1 pt-2 text-xs font-medium text-gray-500 dark:text-gray-400">
              {gettext("Move to group")}
            </p>
            <button
              :for={{id, name} <- [{nil, gettext("No group")} | @groups]}
              id={"flow-#{flow.id}-move-#{id || "none"}"}
              type="button"
              role="menuitem"
              phx-click={
                JS.hide(to: "#flow-#{flow.id}-menu")
                |> JS.push("move_flow", value: %{flow: flow.id, group: id || ""})
              }
              class={menu_item_class()}
            >
              <.icon
                name={if(id, do: "hero-folder", else: "hero-inbox")}
                class="size-4 text-gray-400"
              />
              <span class="flex-1 truncate">{name}</span>
              <.icon :if={flow.group_id == id} name="hero-check-mini" class="size-4 text-primary" />
            </button>
          </div>
        </div>

        <.icon name="hero-chevron-right-mini" class="mr-4 size-5 shrink-0 text-gray-400" />
      </li>
    </ul>
    """
  end

  defp section_class,
    do:
      "rounded-xl border border-gray-200 bg-white shadow-sm dark:border-slate-700 dark:bg-slate-800"

  defp menu_item_class,
    do:
      "flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 dark:text-gray-200 dark:hover:bg-slate-700"
end
