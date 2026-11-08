defmodule HeddleUI.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use HeddleUI, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :locale, :string, default: nil
  attr :current_path, :string, default: nil, doc: "the path of the page being rendered"

  slot :inner_block, required: false

  def app(assigns) do
    assigns =
      assigns
      |> assign_new(:locale, fn -> Gettext.get_locale(HeddleUI.Gettext) end)
      |> assign(:section, nav_section(assigns.current_path))

    ~H"""
    <div class="flex h-screen w-full bg-gray-50 dark:bg-slate-950 overflow-hidden">
      <%= if @current_scope && @current_scope.user do %>
        <aside
          id="sidebar"
          class="w-20 lg:w-64 shrink-0 bg-white dark:bg-slate-900 border-r border-gray-200 dark:border-slate-800 flex flex-col z-20"
        >
          <div class="h-16 shrink-0 px-0 lg:px-5 flex items-center justify-center lg:justify-start">
            <.link
              navigate={~p"/"}
              class="flex items-center gap-2.5 rounded-lg transition-opacity hover:opacity-80"
            >
              <img src={~p"/images/logo.png"} alt="Heddle" class="size-9 lg:size-7 object-contain" />
              <span class="hidden lg:block text-lg font-semibold tracking-tight text-gray-900 dark:text-white">
                Heddle
              </span>
            </.link>
          </div>

          <.workspace_switcher scope={@current_scope} workspaces={assigns[:workspaces] || []} />

          <nav id="sidebar-nav" class="flex-1 w-full overflow-y-auto px-3 pb-4">
            <.nav_group id="nav-group-main">
              <.nav_link
                id="nav-dashboard"
                navigate={~p"/"}
                icon="hero-home"
                label={gettext("Dashboard")}
                active={@section == :dashboard}
              />
              <%= if @current_scope.workspace do %>
                <.nav_link
                  id="nav-flows"
                  navigate={~p"/flows"}
                  icon="hero-squares-2x2"
                  label={gettext("Flows")}
                  active={@section == :flows}
                />
                <.nav_link
                  id="nav-executions"
                  navigate={~p"/executions"}
                  icon="hero-queue-list"
                  label={gettext("Executions")}
                  active={@section == :executions}
                />
                <.nav_link
                  id="nav-spool"
                  navigate={~p"/spool"}
                  icon="hero-circle-stack"
                  label="Spool"
                  active={@section == :spool}
                />
              <% end %>
            </.nav_group>

            <.nav_group
              :if={@current_scope.workspace}
              id="nav-group-workspace"
              label={gettext("Workspace")}
            >
              <.nav_link
                id="nav-credentials"
                navigate={~p"/credentials"}
                icon="hero-lock-closed"
                label={gettext("Credentials")}
                active={@section == :credentials}
              />
              <.nav_link
                id="nav-api-keys"
                navigate={~p"/api-keys"}
                icon="hero-key"
                label={gettext("API keys")}
                active={@section == :api_keys}
              />
              <.nav_link
                id="nav-members"
                navigate={~p"/workspace"}
                icon="hero-user-group"
                label={gettext("Members")}
                active={@section == :workspace}
              />
            </.nav_group>

            <.nav_group
              :if={HeddleCore.Accounts.User.system_admin?(@current_scope.user)}
              id="nav-group-instance"
              label={gettext("Instance")}
            >
              <.nav_link
                id="nav-ai"
                navigate={~p"/ai"}
                icon="hero-cpu-chip"
                label={gettext("AI")}
                active={@section == :ai}
              />
              <.nav_link
                id="nav-workspaces"
                navigate={~p"/workspaces"}
                icon="hero-building-office-2"
                label={gettext("Workspaces")}
                active={@section == :workspaces}
              />
              <.nav_link
                id="nav-users"
                navigate={~p"/users"}
                icon="hero-users"
                label={gettext("Users")}
                active={@section == :users}
              />
            </.nav_group>
          </nav>

          <.user_menu user={@current_scope.user} section={@section} />
        </aside>
      <% end %>

      <main class="flex-1 overflow-auto relative flex flex-col">
        <%= if Map.has_key?(assigns, :inner_content) do %>
          {@inner_content}
        <% else %>
          {render_slot(assigns[:inner_block])}
        <% end %>
      </main>
      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} /> <.flash kind={:error} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp nav_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      aria-current={@active && "page"}
      class={[
        "flex items-center justify-center lg:justify-start gap-3 px-3 py-2 rounded-lg transition-colors duration-150 group",
        if(@active,
          do: "bg-primary/10 text-primary",
          else:
            "text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-slate-800 hover:text-gray-900 dark:hover:text-white"
        )
      ]}
    >
      <.icon
        name={@icon}
        class={[
          "w-6 h-6 lg:w-5 lg:h-5",
          if(@active,
            do: "text-primary",
            else: "text-gray-500 dark:text-gray-400 group-hover:text-primary"
          )
        ]}
      />
      <span class="hidden lg:block font-medium text-sm">{@label}</span>
    </.link>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, default: nil
  slot :inner_block, required: true

  # A part of the sidebar. A label names it on wide screens, a line on narrow ones.
  defp nav_group(assigns) do
    ~H"""
    <div id={@id} class={["space-y-0.5", @label && "pt-5"]}>
      <%= if @label do %>
        <p class="hidden lg:block px-3 pb-1.5 text-[11px] font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">
          {@label}
        </p>
        <div class="lg:hidden mx-auto mb-3 w-8 border-t border-gray-200 dark:border-slate-800" />
      <% end %>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :user, :map, required: true
  attr :section, :atom, default: nil

  # Who is signed in, with their preferences, their account and the way out.
  defp user_menu(assigns) do
    ~H"""
    <div class="shrink-0 w-full px-3 py-3 border-t border-gray-200 dark:border-slate-800">
      <div class="relative" id="user-menu-root">
        <button
          id="user-menu-button"
          type="button"
          aria-haspopup="menu"
          phx-click={
            JS.toggle(
              to: "#user-menu-dropdown",
              in:
                {"transition ease-out duration-100", "opacity-0 translate-y-1",
                 "opacity-100 translate-y-0"},
              out:
                {"transition ease-in duration-75", "opacity-100 translate-y-0",
                 "opacity-0 translate-y-1"}
            )
          }
          class="group w-full flex items-center justify-center lg:justify-start gap-3 p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-slate-800 transition-colors"
        >
          <span class="shrink-0 size-9 rounded-lg bg-primary text-primary-content flex items-center justify-center text-sm font-semibold">
            {initial(@user.username || @user.email)}
          </span>
          <span class="hidden lg:block min-w-0 flex-1 text-left">
            <span class="block text-sm font-medium text-gray-900 dark:text-white truncate">
              {@user.username || @user.email}
            </span>
            <span class="block text-xs text-gray-500 dark:text-gray-400 truncate">
              {@user.email}
            </span>
          </span>
          <.icon
            name="hero-chevron-up-down-mini"
            class="hidden lg:block size-4 shrink-0 text-gray-400 group-hover:text-gray-600 dark:group-hover:text-gray-300 transition-colors"
          />
        </button>

        <div
          id="user-menu-dropdown"
          role="menu"
          class="hidden absolute bottom-full left-0 mb-2 w-56 lg:w-full bg-white dark:bg-slate-900 rounded-xl shadow-xl border border-gray-200 dark:border-slate-700 overflow-hidden z-50"
          phx-click-away={JS.hide(to: "#user-menu-dropdown")}
        >
          <div class="p-1.5 space-y-0.5">
            <.user_menu_link
              id="user-menu-preferences"
              navigate={~p"/users/preferences"}
              icon="hero-adjustments-horizontal"
              label={gettext("Preferences")}
            />
            <.user_menu_link
              id="user-menu-settings"
              navigate={~p"/users/settings"}
              icon="hero-user-circle"
              label={gettext("Account")}
            />
            <div class="my-1 border-t border-gray-100 dark:border-slate-800" />
            <.link
              id="user-menu-log-out"
              href={~p"/users/log-out"}
              method="delete"
              class="flex items-center gap-3 px-3 py-2 text-sm text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg transition-colors"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> {gettext("Log out")}
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp user_menu_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      role="menuitem"
      class="flex items-center gap-3 px-3 py-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-slate-800 rounded-lg transition-colors"
    >
      <.icon name={@icon} class="size-4 text-gray-500 dark:text-gray-400" /> {@label}
    </.link>
    """
  end

  @doc "The `lang` of the page, from a Gettext locale: `pt_BR` is `pt-BR`."
  def html_lang(locale) when is_binary(locale), do: String.replace(locale, "_", "-")
  def html_lang(_locale), do: "en"

  @doc "The theme the signed-in person chose, which the root layout applies."
  def user_theme(%{user: %{theme: theme}}) when is_binary(theme), do: theme
  def user_theme(_scope), do: nil

  attr :scope, :map, required: true
  attr :workspaces, :list, required: true

  # The workspace the person works in, and the others they can open.
  defp workspace_switcher(assigns) do
    ~H"""
    <div class="w-full px-3 lg:px-4 mb-5">
      <%= if @scope.workspace do %>
        <div class="relative" id="workspace-switcher">
          <button
            id="workspace-switcher-button"
            type="button"
            aria-haspopup="menu"
            aria-label={gettext("Switch workspace")}
            phx-click={
              JS.toggle(
                to: "#workspace-menu",
                in:
                  {"transition ease-out duration-100", "opacity-0 -translate-y-1",
                   "opacity-100 translate-y-0"},
                out: {"transition ease-in duration-75", "opacity-100", "opacity-0"}
              )
            }
            class="w-full flex items-center justify-center lg:justify-start gap-3 p-2 rounded-xl border border-gray-200 dark:border-slate-800 hover:border-gray-300 dark:hover:border-slate-700 hover:bg-gray-50 dark:hover:bg-slate-800/60 transition-colors"
          >
            <span class="size-8 shrink-0 rounded-lg bg-primary/10 text-primary flex items-center justify-center text-sm font-bold">
              {initial(@scope.workspace.name)}
            </span>
            <span class="hidden lg:block min-w-0 flex-1 text-left">
              <span class="block text-sm font-semibold text-gray-900 dark:text-white truncate">
                {@scope.workspace.name}
              </span>
              <span class="block text-xs text-gray-500 dark:text-gray-400">
                {role_label(@scope.role)}
              </span>
            </span>
            <.icon
              name="hero-chevron-up-down-mini"
              class="hidden lg:block size-4 text-gray-400"
            />
          </button>
          <div
            id="workspace-menu"
            role="menu"
            class="hidden absolute left-0 top-full mt-2 w-64 bg-white dark:bg-slate-900 rounded-xl shadow-xl border border-gray-100 dark:border-slate-800 z-50 overflow-hidden"
            phx-click-away={JS.hide(to: "#workspace-menu")}
          >
            <p class="px-4 pt-3 pb-1 text-[11px] font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">
              {gettext("Workspaces")}
            </p>
            <div class="max-h-72 overflow-y-auto p-1.5">
              <button
                :for={{workspace, role} <- @workspaces}
                id={"switch-workspace-#{workspace.id}"}
                type="button"
                role="menuitem"
                phx-click={
                  JS.hide(to: "#workspace-menu")
                  |> JS.push("switch_workspace", value: %{id: workspace.id})
                }
                class="w-full flex items-center gap-3 px-2.5 py-2 rounded-lg text-left hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors"
              >
                <span class="size-7 shrink-0 rounded-md bg-gray-100 dark:bg-slate-800 text-gray-600 dark:text-gray-300 flex items-center justify-center text-xs font-bold">
                  {initial(workspace.name)}
                </span>
                <span class="min-w-0 flex-1">
                  <span class="block text-sm font-medium text-gray-900 dark:text-white truncate">
                    {workspace.name}
                  </span>
                  <span class="block text-xs text-gray-500 dark:text-gray-400">
                    {role_label(role)}
                  </span>
                </span>
                <.icon
                  :if={workspace.id == @scope.workspace.id}
                  name="hero-check-mini"
                  class="size-4 text-primary"
                />
              </button>
            </div>
            <div class="border-t border-gray-100 dark:border-slate-800 p-1.5">
              <.link
                navigate={~p"/workspace"}
                class="flex items-center gap-3 px-2.5 py-2 rounded-lg text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors"
              >
                <.icon name="hero-user-group" class="size-4" /> {gettext("Members and settings")}
              </.link>
              <.link
                :if={HeddleCore.Accounts.User.system_admin?(@scope.user)}
                navigate={~p"/workspaces"}
                class="flex items-center gap-3 px-2.5 py-2 rounded-lg text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors"
              >
                <.icon name="hero-plus" class="size-4" /> {gettext("New workspace")}
              </.link>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp initial(name),
    do: name |> to_string() |> String.trim() |> String.first() |> to_string() |> String.upcase()

  @doc "The name of a role, for people."
  def role_label("admin"), do: gettext("Admin")
  def role_label("editor"), do: gettext("Editor")
  def role_label("operator"), do: gettext("Operator")
  def role_label("viewer"), do: gettext("Viewer")
  def role_label(_role), do: ""

  @doc "What a role lets someone do, in one line."
  def role_description("admin"),
    do: gettext("Everything, plus members, invites and the workspace itself.")

  def role_description("editor"),
    do: gettext("Creates and changes flows and credentials, and uses the agent.")

  def role_description("operator"),
    do: gettext("Runs flows and sees their results, without changing them.")

  def role_description("viewer"), do: gettext("Sees flows, runs and members.")
  def role_description(_role), do: ""

  defp nav_section("/"), do: :dashboard
  defp nav_section("/ai"), do: :ai
  defp nav_section("/flows" <> _), do: :flows
  defp nav_section("/executions" <> _), do: :executions
  defp nav_section("/spool" <> _), do: :spool
  defp nav_section("/api-keys"), do: :api_keys
  defp nav_section("/credentials"), do: :credentials
  defp nav_section("/users"), do: :users
  defp nav_section("/workspace"), do: :workspace
  defp nav_section("/workspaces"), do: :workspaces
  defp nav_section(_path), do: nil
end
