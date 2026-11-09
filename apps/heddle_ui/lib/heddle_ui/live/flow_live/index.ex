defmodule HeddleUI.FlowLive.Index do
  use HeddleUI, :live_view

  on_mount {HeddleUI.UserAuth, {:require_workspace, :view}}

  alias HeddleCore.Flows
  alias HeddleCore.Flows.{Group, Groups}
  alias HeddleCore.Workspaces
  alias HeddleUI.Components.Flow.FlowGroups

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       can_edit: Workspaces.can?(socket.assigns.current_scope, :edit),
       page_title: gettext("Flows"),
       ai_configured: HeddleAI.LLM.configured?(),
       group_form: nil,
       renaming_group_id: nil,
       rename_form: nil
     )
     |> load()}
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    assign(socket, flows: Flows.list_flows(scope), groups: Groups.list_groups(scope))
  end

  @impl true
  def handle_event("create_flow", _params, socket) do
    case Flows.create_flow(socket.assigns.current_scope, %{
           name: "New Flow #{System.unique_integer([:positive])}",
           nodes: [],
           connections: []
         }) do
      {:ok, flow} ->
        {:noreply, push_navigate(socket, to: ~p"/flows/#{flow}")}

      {:error, :forbidden} ->
        {:noreply,
         put_flash(socket, :error, gettext("Your role in this workspace can't create flows."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to create flow."))}
    end
  end

  def handle_event("new_group", _params, socket) do
    {:noreply, assign(socket, :group_form, to_form(Groups.change_group(%Group{})))}
  end

  def handle_event("cancel_new_group", _params, socket) do
    {:noreply, assign(socket, :group_form, nil)}
  end

  def handle_event("create_group", %{"group" => params}, socket) do
    case Groups.create_group(socket.assigns.current_scope, params) do
      {:ok, _group} ->
        {:noreply, socket |> assign(:group_form, nil) |> load()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :group_form, to_form(changeset, action: :insert))}

      {:error, _reason} ->
        {:noreply, forbidden(socket)}
    end
  end

  def handle_event("start_rename_group", %{"id" => id}, socket) do
    case Groups.get_group(socket.assigns.current_scope, id) do
      nil ->
        {:noreply, load(socket)}

      group ->
        {:noreply,
         assign(socket,
           renaming_group_id: group.id,
           rename_form: to_form(Groups.change_group(group))
         )}
    end
  end

  def handle_event("cancel_rename_group", _params, socket) do
    {:noreply, assign(socket, renaming_group_id: nil, rename_form: nil)}
  end

  def handle_event("rename_group", %{"group_id" => id, "group" => params}, socket) do
    case Groups.rename_group(socket.assigns.current_scope, id, params) do
      {:ok, _group} ->
        {:noreply, socket |> assign(renaming_group_id: nil, rename_form: nil) |> load()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :rename_form, to_form(changeset, action: :update))}

      {:error, :not_found} ->
        {:noreply, socket |> assign(renaming_group_id: nil, rename_form: nil) |> load()}

      {:error, :forbidden} ->
        {:noreply, forbidden(socket)}
    end
  end

  def handle_event("delete_group", %{"id" => id}, socket) do
    case Groups.delete_group(socket.assigns.current_scope, id) do
      {:error, :forbidden} -> {:noreply, forbidden(socket)}
      _deleted_or_gone -> {:noreply, load(socket)}
    end
  end

  def handle_event("move_flow", %{"flow" => flow_id, "group" => group_id}, socket) do
    case Groups.move_flow(socket.assigns.current_scope, flow_id, group_id) do
      {:error, :forbidden} -> {:noreply, forbidden(socket)}
      _moved_or_gone -> {:noreply, load(socket)}
    end
  end

  defp forbidden(socket) do
    put_flash(socket, :error, gettext("Your role in this workspace can't change groups."))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 md:p-8 w-full max-w-7xl mx-auto">
      <div class="flex flex-wrap items-center justify-between gap-4 mb-8">
        <div>
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">{gettext("Flows")}</h1>

          <p class="text-sm text-gray-500 dark:text-gray-400 mt-1">
            {length(@flows)} {gettext("Flows available")}
          </p>
        </div>

        <div :if={@can_edit} class="flex items-center gap-2">
          <.button id="new-group" phx-click="new_group" variant="ghost">
            <.icon name="hero-folder-plus" class="h-4 w-4" /> {gettext("New group")}
          </.button>
          <.button
            :if={@ai_configured}
            id="create-flow-with-ai"
            navigate={~p"/flows/new/ai"}
            variant="outline"
          >
            <.icon name="hero-sparkles" class="h-4 w-4" /> {gettext("Create with AI")}
          </.button>
          <.button
            phx-click="create_flow"
            variant="primary"
          >
            <.icon name="hero-plus" class="h-4 w-4" /> {gettext("New Flow")}
          </.button>
        </div>
      </div>

      <.form
        :if={@group_form}
        for={@group_form}
        id="new-group-form"
        phx-submit="create_group"
        class="mb-4 flex flex-wrap items-start gap-2 rounded-xl border border-gray-200 bg-white p-4 shadow-sm dark:border-slate-700 dark:bg-slate-800"
      >
        <div class="min-w-48 flex-1">
          <.input
            field={@group_form[:name]}
            type="text"
            placeholder={gettext("Group name, like Sales or Billing")}
            autofocus
            phx-keydown="cancel_new_group"
            phx-key="Escape"
          />
        </div>
        <%!-- pt-1 is the padding above the input in its fieldset, so both line up. --%>
        <div class="flex items-center gap-2 pt-1">
          <.button type="submit" variant="primary" size="field">{gettext("Create group")}</.button>
          <.button type="button" phx-click="cancel_new_group" variant="ghost" size="field">
            {gettext("Cancel")}
          </.button>
        </div>
      </.form>

      <%= if @flows == [] and @groups == [] do %>
        <div class="bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-xl p-12 text-center shadow-sm">
          <div class="mx-auto w-16 h-16 bg-gray-100 dark:bg-slate-700 rounded-full flex items-center justify-center mb-4">
            <.icon name="hero-plus" class="w-8 h-8 text-gray-400" />
          </div>

          <h3 class="text-lg font-medium text-gray-900 dark:text-white mb-1">
            {gettext("No flows created yet")}
          </h3>

          <p class="text-gray-500 dark:text-gray-400 mb-6 max-w-sm mx-auto text-center">
            {gettext("Get started by creating your first workflow automation. It's easy!")}
          </p>

          <.button
            :if={@can_edit}
            phx-click="create_flow"
            variant="primary"
            class="px-6 py-3"
          >
            <.icon name="hero-plus" class="h-5 w-5" /> {gettext("Create your first flow")}
          </.button>
        </div>
      <% else %>
        <FlowGroups.flow_groups
          groups={@groups}
          flows={@flows}
          can_edit={@can_edit}
          renaming_group_id={@renaming_group_id}
          rename_form={@rename_form}
        />
      <% end %>
    </div>
    """
  end
end
