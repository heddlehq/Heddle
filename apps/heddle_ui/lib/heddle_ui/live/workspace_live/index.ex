defmodule HeddleUI.WorkspaceLive.Index do
  @moduledoc "Every workspace of the instance, for system admins, who create them."

  use HeddleUI, :live_view

  on_mount {HeddleUI.UserAuth, :require_system_admin}

  alias HeddleCore.Workspaces
  alias HeddleCore.Workspaces.Workspace

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Workspaces"))
     |> assign(:form, to_form(Workspaces.change_workspace(%Workspace{})))
     |> load()}
  end

  defp load(socket) do
    assign(socket, :rows, Workspaces.list_all_workspaces(socket.assigns.current_scope))
  end

  @impl true
  def handle_event("create", %{"workspace" => params}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, workspace} <- Workspaces.create_workspace(scope, params),
         {:ok, _scope} <- Workspaces.switch_workspace(scope, workspace) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         gettext("%{name} is ready. Invite people to it.", name: workspace.name)
       )
       |> push_navigate(to: ~p"/workspace")}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Only system admins create workspaces."))}
    end
  end

  def handle_event("open", %{"id" => id}, socket) do
    with %Workspace{} = workspace <- Workspaces.get_workspace(id),
         {:ok, _scope} <- Workspaces.switch_workspace(socket.assigns.current_scope, workspace) do
      {:noreply, push_navigate(socket, to: ~p"/workspace")}
    else
      _other -> {:noreply, load(socket)}
    end
  end

  def handle_event("change_locale", %{"locale" => locale}, socket) do
    {:noreply, redirect(socket, to: ~p"/workspaces?locale=#{locale}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 md:p-8 w-full max-w-5xl mx-auto space-y-8">
      <div>
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">{gettext("Workspaces")}</h1>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {gettext(
            "Each team keeps its flows, credentials and API keys in a workspace, and nobody outside it sees them. System admins can open every one."
          )}
        </p>
      </div>

      <section class="bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 rounded-xl shadow-sm p-6">
        <h2 class="text-base font-semibold text-gray-900 dark:text-white">
          {gettext("New workspace")}
        </h2>
        <.form
          for={@form}
          id="workspace-form"
          phx-submit="create"
          class="mt-4 flex max-w-xl items-end gap-3"
        >
          <div class="min-w-0 flex-1">
            <.input
              field={@form[:name]}
              type="text"
              label={gettext("Name")}
              placeholder={gettext("Marketing, Finance, Operations…")}
              required
            />
          </div>
          <.button
            id="create-workspace"
            type="submit"
            variant="primary"
            size="field"
            class="mb-3"
          >
            <.icon name="hero-plus" class="size-4" /> {gettext("Create")}
          </.button>
        </.form>
      </section>

      <section class="bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 rounded-xl shadow-sm overflow-hidden">
        <table class="w-full text-left text-sm">
          <thead class="bg-gray-50 dark:bg-slate-800 text-xs uppercase text-gray-500 dark:text-gray-400">
            <tr>
              <th class="px-6 py-3">{gettext("Name")}</th>
              <th class="px-6 py-3">{gettext("Members")}</th>
              <th class="px-6 py-3">{gettext("Flows")}</th>
              <th class="px-6 py-3">{gettext("Created")}</th>
              <th class="px-6 py-3"></th>
            </tr>
          </thead>
          <tbody
            id="workspaces"
            class="divide-y divide-gray-100 dark:divide-slate-800 text-gray-800 dark:text-gray-200"
          >
            <tr :for={row <- @rows} id={"workspace-#{row.workspace.id}"}>
              <td class="px-6 py-4">
                <span class="font-medium">{row.workspace.name}</span>
                <span
                  :if={@current_scope.workspace && @current_scope.workspace.id == row.workspace.id}
                  class="ml-2 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary"
                >
                  {gettext("Current")}
                </span>
              </td>
              <td class="px-6 py-4 text-gray-600 dark:text-gray-300">{row.members}</td>
              <td class="px-6 py-4 text-gray-600 dark:text-gray-300">{row.flows}</td>
              <td class="px-6 py-4 text-xs text-gray-500 dark:text-gray-400">
                {Calendar.strftime(row.workspace.inserted_at, "%Y-%m-%d")}
              </td>
              <td class="px-6 py-4 text-right">
                <.button
                  id={"open-workspace-#{row.workspace.id}"}
                  type="button"
                  variant="ghost"
                  phx-click="open"
                  phx-value-id={row.workspace.id}
                >
                  {gettext("Open")}
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
        <p :if={@rows == []} class="px-6 py-10 text-center text-sm text-gray-500 dark:text-gray-400">
          {gettext("No workspaces yet.")}
        </p>
      </section>
    </div>
    """
  end
end
