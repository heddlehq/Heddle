defmodule HeddleUI.IntegrationLive.Index do
  @moduledoc """
  The integrations a workspace can install. Only installed ones show in the node
  sidebar of the editor, see `HeddleUI.Integrations`.
  """

  use HeddleUI, :live_view

  on_mount {HeddleUI.UserAuth, {:require_workspace, :view}}

  import HeddleUI.Components.Modals.CreateIntegrationModal

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Workspaces
  alias HeddleUI.Integrations
  alias HeddleUI.Integrations.Catalog

  @community_color "bg-violet-500/15 text-violet-700 dark:text-violet-300"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Integrations"))
     |> assign(:can_edit, Workspaces.can?(socket.assigns.current_scope, :edit))
     |> assign(:can_manage, Workspaces.can?(socket.assigns.current_scope, :manage))
     |> assign(:system_admin, Scope.system_admin?(socket.assigns.current_scope))
     |> assign(:query, "")
     |> assign(:filter, "all")
     |> assign(:create, nil)
     |> load()}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, :query, query)}
  end

  def handle_event("filter", %{"filter" => filter}, socket)
      when filter in ["all", "installed", "community"] do
    {:noreply, assign(socket, :filter, filter)}
  end

  def handle_event("open_create", _params, socket) do
    if socket.assigns.can_manage do
      {:noreply, assign_create(socket, template())}
    else
      {:noreply, put_flash(socket, :error, forbidden_message())}
    end
  end

  def handle_event("close_create", _params, socket) do
    {:noreply, assign(socket, :create, nil)}
  end

  def handle_event("check_manifest", %{"integration" => %{"manifest" => yaml}}, socket) do
    {:noreply, assign_create(socket, yaml)}
  end

  def handle_event("create_integration", %{"integration" => %{"manifest" => yaml}}, socket) do
    case Integrations.create(socket.assigns.current_scope, yaml) do
      {:ok, manifest} ->
        {:noreply,
         socket
         |> assign(:create, nil)
         |> load()
         |> put_flash(:info, gettext("%{name} created and installed.", name: manifest.name))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, forbidden_message())}

      {:error, problems} when is_list(problems) ->
        {:noreply, assign_create(socket, yaml, {:error, problems})}

      _error ->
        {:noreply, put_flash(socket, :error, gettext("This integration couldn't be created."))}
    end
  end

  def handle_event("install", %{"id" => id}, socket) do
    case Integrations.install(socket.assigns.current_scope, id) do
      :ok ->
        {:noreply,
         socket
         |> load()
         |> put_flash(:info, gettext("%{name} installed.", name: title(id)))}

      _error ->
        {:noreply, put_flash(socket, :error, forbidden_message())}
    end
  end

  def handle_event("install_community", %{"id" => id}, socket) do
    case Integrations.install_community(socket.assigns.current_scope, id) do
      :ok ->
        {:noreply,
         socket |> load() |> put_flash(:info, gettext("%{name} installed.", name: title(id)))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, forbidden_message())}

      _error ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext(
             "This integration couldn't be installed. Its manifest is invalid or takes the name of an official one."
           )
         )}
    end
  end

  def handle_event("update_community", %{"id" => id}, socket) do
    case Integrations.update_community(socket.assigns.current_scope, id) do
      :ok ->
        {:noreply,
         socket |> load() |> put_flash(:info, gettext("%{name} updated.", name: title(id)))}

      _error ->
        {:noreply, put_flash(socket, :error, gettext("This integration couldn't be updated."))}
    end
  end

  def handle_event("uninstall", %{"id" => id}, socket) do
    case Integrations.uninstall(socket.assigns.current_scope, id) do
      :ok ->
        {:noreply,
         socket
         |> load()
         |> put_flash(:info, gettext("%{name} removed.", name: title(id)))}

      {:error, {:in_use, _flows}} ->
        {:noreply,
         socket
         |> load()
         |> put_flash(:error, gettext("Flows still use %{name}.", name: title(id)))}

      _error ->
        {:noreply, put_flash(socket, :error, forbidden_message())}
    end
  end

  defp assign_create(socket, yaml, check \\ nil) do
    assign(socket, :create, %{
      form: to_form(%{"manifest" => yaml}, as: :integration),
      check: check || Integrations.check_new(yaml)
    })
  end

  defp forbidden_message, do: gettext("Your role in this workspace can't change integrations.")

  defp title(id) do
    case HeddleNodes.Integrations.get(id) || Catalog.get(id) do
      nil -> id
      %{title: title} -> title
      %{"name" => name} -> name
    end
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    installed = Integrations.installed_ids(scope)

    catalog = Catalog.all()

    known =
      Enum.map(HeddleNodes.Integrations.all(), fn integration ->
        installed? = MapSet.member?(installed, integration.id)
        flows = if installed?, do: Integrations.flows_using(scope, integration.id), else: []
        latest = integration.community && catalog[integration.id]["version"]

        Map.merge(integration, %{
          installed?: installed?,
          flows: flows,
          action_names: Enum.map(integration.nodes, &action_name/1),
          update: if(latest && latest != integration.version, do: latest)
        })
      end)

    ids = MapSet.new(known, & &1.id)

    published =
      for {id, entry} <- catalog, not MapSet.member?(ids, id) do
        %{
          id: id,
          title: entry["name"] || id,
          category: id,
          icon: entry["icon"] || "hero-puzzle-piece",
          color: @community_color,
          community: true,
          version: entry["version"],
          action_names: entry["actions"] || [],
          description: entry["description"],
          installed?: false,
          flows: [],
          update: nil
        }
      end

    integrations = Enum.sort_by(known ++ published, &String.downcase(&1.title))
    assign(socket, :integrations, integrations)
  end

  defp visible(integrations, query, filter) do
    query = query |> String.trim() |> String.downcase()

    Enum.filter(integrations, fn integration ->
      (filter == "all" or (filter == "installed" and integration.installed?) or
         (filter == "community" and integration.community)) and
        (query == "" or String.contains?(String.downcase(integration.title), query) or
           Enum.any?(integration.action_names, &String.contains?(String.downcase(&1), query)))
    end)
  end

  defp action_name(node), do: node.name |> String.split(": ", parts: 2) |> List.last()

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:shown, visible(assigns.integrations, assigns.query, assigns.filter))
      |> assign(:installed_count, Enum.count(assigns.integrations, & &1.installed?))

    ~H"""
    <div class="p-6 md:p-8 w-full max-w-7xl mx-auto space-y-6">
      <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">{gettext("Integrations")}</h1>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {gettext(
              "Services the flows of this workspace can reach. The editor's node sidebar shows only the installed ones."
            )}
          </p>
        </div>
        <.button
          :if={@can_manage}
          id="create-integration"
          variant="primary"
          phx-click="open_create"
          class="shrink-0"
        >
          <.icon name="hero-plus" class="size-4" /> {gettext("Create integration")}
        </.button>
      </div>

      <.create_integration_modal
        :if={@create}
        form={@create.form}
        check={@create.check}
      />

      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div
          id="integration-filters"
          class="inline-flex rounded-lg border border-gray-200 bg-white p-1 text-sm dark:border-slate-800 dark:bg-slate-900"
        >
          <button
            :for={
              {value, label, count} <- [
                {"all", pgettext("integrations filter", "All"), length(@integrations)},
                {"installed", pgettext("integrations filter", "Installed"), @installed_count},
                {"community", pgettext("integrations filter", "Community"),
                 Enum.count(@integrations, & &1.community)}
              ]
            }
            id={"integration-filter-#{value}"}
            type="button"
            phx-click="filter"
            phx-value-filter={value}
            class={[
              "flex items-center gap-2 rounded-md px-3 py-1.5 font-medium transition",
              if(@filter == value,
                do: "bg-gray-100 text-gray-900 dark:bg-slate-800 dark:text-white",
                else: "text-gray-500 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
              )
            ]}
          >
            {label}
            <span class="rounded-full bg-gray-200 px-1.5 text-xs text-gray-600 dark:bg-slate-700 dark:text-gray-300">
              {count}
            </span>
          </button>
        </div>

        <form id="integration-search" phx-change="search" class="relative sm:w-72">
          <.icon
            name="hero-magnifying-glass"
            class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-gray-400 dark:text-slate-500"
          />
          <input
            type="search"
            name="query"
            value={@query}
            placeholder={gettext("Search integrations")}
            autocomplete="off"
            phx-debounce="150"
            class="w-full rounded-lg border border-gray-200 bg-white py-2 pl-9 pr-3 text-sm text-gray-900 placeholder:text-gray-400 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-100 dark:placeholder:text-slate-500"
          />
        </form>
      </div>

      <div
        :if={@shown == []}
        id="integrations-empty"
        class="flex flex-col items-center gap-3 rounded-xl border border-dashed border-gray-300 px-6 py-12 text-center dark:border-slate-700"
      >
        <.icon name="hero-puzzle-piece" class="size-6 text-gray-400" />
        <p class="text-sm text-gray-500 dark:text-gray-400">
          {if(@filter == "installed" and @query == "",
            do: gettext("No integrations installed yet."),
            else: gettext("No integrations found.")
          )}
        </p>
      </div>

      <div id="integrations" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <div
          :for={integration <- @shown}
          id={"integration-#{integration.id}"}
          class={[
            "flex flex-col rounded-xl border bg-white p-5 shadow-sm transition dark:bg-slate-900",
            if(integration.installed?,
              do: "border-primary/30 dark:border-primary/30",
              else: "border-gray-200 dark:border-slate-800"
            )
          ]}
        >
          <div class="flex items-start gap-3">
            <span class={[
              "size-10 shrink-0 rounded-lg flex items-center justify-center",
              integration.color
            ]}>
              <.icon name={integration.icon} class="size-5" />
            </span>
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <p class="truncate font-semibold text-gray-900 dark:text-white">
                  {integration.title}
                </p>
                <span
                  :if={integration.installed?}
                  class="inline-flex items-center gap-1 rounded-full bg-emerald-500/10 px-2 py-0.5 text-[11px] font-medium text-emerald-700 dark:text-emerald-300"
                >
                  <.icon name="hero-check-mini" class="size-3" /> {gettext("Installed")}
                </span>
              </div>
              <p :if={not integration.community} class="text-xs text-gray-500 dark:text-gray-400">
                {HeddleNodes.Nodes.category_label(integration.category)} · {gettext("Official")}
              </p>
              <p
                :if={integration.community}
                class="flex items-center gap-1 text-xs text-gray-500 dark:text-gray-400"
              >
                <span class="font-medium text-violet-600 dark:text-violet-300">
                  {gettext("Community")}
                </span>
                · v{integration.version} ·
                <span title={
                  gettext("Not reviewed by Heddle. It sends what its nodes get to its service.")
                }>
                  {gettext("Not verified")}
                </span>
              </p>
            </div>
          </div>

          <div class="mt-4 flex flex-wrap gap-1.5">
            <span
              :for={name <- Enum.take(integration.action_names, 4)}
              class="rounded-md bg-gray-100 px-2 py-0.5 text-xs text-gray-600 dark:bg-slate-800 dark:text-gray-300"
            >
              {name}
            </span>
            <span
              :if={length(integration.action_names) > 4}
              class="rounded-md px-1 py-0.5 text-xs text-gray-400 dark:text-gray-500"
            >
              {gettext("+%{count} more", count: length(integration.action_names) - 4)}
            </span>
          </div>

          <div class="mt-auto flex items-center justify-between gap-2 pt-5">
            <p class="text-xs text-gray-500 dark:text-gray-400">
              <%= if integration.flows != [] do %>
                <span title={Enum.map_join(integration.flows, ", ", & &1.name)}>
                  {ngettext("Used by 1 flow", "Used by %{count} flows", length(integration.flows))}
                </span>
              <% else %>
                {ngettext("1 action", "%{count} actions", length(integration.action_names))}
              <% end %>
            </p>

            <div :if={@can_edit} class="flex gap-1">
              <.button
                :if={integration.update && @system_admin}
                id={"update-#{integration.id}"}
                variant="ghost"
                phx-click="update_community"
                phx-value-id={integration.id}
                data-confirm={
                  gettext("Every workspace that has it will run version %{version}. Update?",
                    version: integration.update
                  )
                }
              >
                {gettext("Update to v%{version}", version: integration.update)}
              </.button>
              <.button
                :if={not integration.installed? and integration.community and @can_manage}
                id={"install-#{integration.id}"}
                variant="primary"
                phx-click="install_community"
                phx-value-id={integration.id}
                data-confirm={
                  gettext(
                    "Community integrations aren't reviewed by Heddle, and their nodes send what they get to their service. Install it?"
                  )
                }
              >
                {gettext("Install")}
              </.button>
              <.button
                :if={not integration.installed? and not integration.community}
                id={"install-#{integration.id}"}
                variant="primary"
                phx-click="install"
                phx-value-id={integration.id}
              >
                {gettext("Install")}
              </.button>
              <.button
                :if={integration.installed?}
                id={"uninstall-#{integration.id}"}
                variant="ghost"
                phx-click="uninstall"
                phx-value-id={integration.id}
                disabled={integration.flows != []}
                title={
                  if(integration.flows != [],
                    do: gettext("Remove it from the flows that use it first."),
                    else: gettext("Remove")
                  )
                }
                data-confirm={
                  if(integration.flows == [],
                    do: gettext("Its nodes will leave the sidebar. Remove it?")
                  )
                }
              >
                {gettext("Remove")}
              </.button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
