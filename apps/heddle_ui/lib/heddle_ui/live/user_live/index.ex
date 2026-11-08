defmodule HeddleUI.UserLive.Index do
  use HeddleUI, :live_view

  on_mount {HeddleUI.UserAuth, :require_system_admin}

  alias HeddleCore.Accounts
  alias HeddleCore.Accounts.Invite
  alias HeddleCore.Workspaces
  alias HeddleUI.Components.Invites

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    workspace_id = scope.workspace && scope.workspace.id

    {:ok,
     socket
     |> assign(:page_title, gettext("Users"))
     |> assign(:users, Accounts.list_users())
     |> assign(:current_invite, nil)
     |> assign(
       :invite_form,
       to_form(%{"workspace_id" => workspace_id, "role" => "editor"}, as: :invite)
     )}
  end

  @impl true
  def handle_event("generate_invite", %{"invite" => params}, socket) do
    scope = socket.assigns.current_scope

    with %{} = workspace <- Workspaces.get_workspace(params["workspace_id"]),
         {:ok, invite} <- Accounts.create_invite(scope, workspace, params["role"]) do
      {:noreply,
       socket
       |> assign(:current_invite, invite)
       |> assign(:invite_form, to_form(params, as: :invite))
       |> put_flash(
         :info,
         gettext("Invite link generated. It expires in %{days} days.",
           days: Invite.invite_validity_days()
         )
       )}
    else
      _error -> {:noreply, put_flash(socket, :error, gettext("Failed to generate invite."))}
    end
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    {:noreply, redirect(socket, to: ~p"/users?locale=#{locale}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 md:p-8 w-full max-w-7xl mx-auto">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">{gettext("Users")}</h1>
        <p class="text-sm text-gray-500 dark:text-gray-400 mt-1">
          {gettext("Manage users and invite new people. Invites expire in %{days} days.",
            days: Invite.invite_validity_days()
          )}
        </p>
      </div>

      <div class="space-y-8">
        <div class="bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-xl shadow-sm overflow-hidden">
          <div class="p-6 border-b border-gray-100 dark:border-slate-700/50">
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
              {gettext("Invite link")}
            </h2>
            <p class="text-sm text-gray-500 dark:text-gray-400 mt-1">
              {gettext(
                "Generate a link that creates an account and joins a workspace. If you already have a valid one for the same workspace and role, the same link is shown."
              )}
            </p>
          </div>
          <div class="p-6 space-y-4">
            <.form
              for={@invite_form}
              id="user-invite-form"
              phx-submit="generate_invite"
              class="flex flex-wrap items-end gap-3"
            >
              <div class="min-w-48">
                <.input
                  field={@invite_form[:workspace_id]}
                  type="select"
                  label={gettext("Workspace")}
                  options={
                    Enum.map(@workspaces, fn {workspace, _role} -> {workspace.name, workspace.id} end)
                  }
                />
              </div>
              <div class="min-w-40">
                <.input
                  field={@invite_form[:role]}
                  type="select"
                  label={gettext("Role")}
                  options={Invites.role_options()}
                />
              </div>
              <.button
                id="generate-invite"
                type="submit"
                variant="primary"
                size="field"
                class="mb-3"
              >
                <.icon name="hero-envelope" class="size-4" />
                {gettext("Generate invite link")}
              </.button>
            </.form>
            <Invites.invite_link :if={@current_invite} invite={@current_invite} />
          </div>
        </div>

        <div class="bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-xl shadow-sm overflow-hidden">
          <div class="p-6 border-b border-gray-100 dark:border-slate-700/50">
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
              {gettext("All users")}
            </h2>
            <p class="text-sm text-gray-500 dark:text-gray-400 mt-1">
              {length(@users)} {gettext("users")}
            </p>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200 dark:divide-slate-700">
              <thead class="bg-gray-50 dark:bg-slate-900/50">
                <tr>
                  <th
                    scope="col"
                    class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider"
                  >
                    {gettext("Username")}
                  </th>
                  <th
                    scope="col"
                    class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider"
                  >
                    {gettext("Email")}
                  </th>
                  <th
                    scope="col"
                    class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider"
                  >
                    {gettext("Admin")}
                  </th>
                  <th
                    scope="col"
                    class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider"
                  >
                    {gettext("Joined")}
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white dark:bg-slate-800 divide-y divide-gray-200 dark:divide-slate-700">
                <%= for user <- @users do %>
                  <tr class="hover:bg-gray-50 dark:hover:bg-slate-700/50">
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900 dark:text-white">
                      {user.username}
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                      {user.email}
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                      <%= if user.is_system_admin do %>
                        <span class="text-primary">{gettext("Yes")}</span>
                      <% else %>
                        {gettext("No")}
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                      {Calendar.strftime(user.inserted_at, "%Y-%m-%d")}
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
