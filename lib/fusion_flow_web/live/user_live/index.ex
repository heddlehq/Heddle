defmodule FusionFlowWeb.UserLive.Index do
  use FusionFlowWeb, :live_view

  alias FusionFlow.Accounts

  @impl true
  def mount(_params, _session, socket) do
    if not system_admin?(socket) do
      {:ok,
       socket
       |> put_flash(:error, gettext("You do not have permission to access this page."))
       |> redirect(to: ~p"/")}
    else
      {:ok,
       socket
       |> assign(:page_title, gettext("Users"))
       |> assign(:users, Accounts.list_users())
       |> assign(:invite_link, nil)}
    end
  end

  defp system_admin?(socket) do
    user = socket.assigns[:current_scope] && socket.assigns.current_scope.user
    user && FusionFlow.Accounts.User.system_admin?(user)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="users-index" phx-hook="CopyInviteLink" class="p-6 md:p-8 w-full max-w-7xl mx-auto">
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">{gettext("Users")}</h1>

          <p class="text-sm text-gray-500 dark:text-gray-400 mt-1">
            {length(@users)} {gettext("users")}
          </p>
        </div>

        <.button phx-click="generate_invite" variant="primary">
          <.icon name="hero-link" class="h-4 w-4 mr-1" /> {gettext("Invite via link")}
        </.button>
      </div>

      <%= if @invite_link do %>
        <div class="mb-6 p-4 bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-xl shadow-sm">
          <span class="label mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
            {gettext("Invite link (valid for 7 days)")}
          </span>
          <div class="flex gap-2">
            <input
              type="text"
              name="invite_link"
              id="invite-link-input"
              value={@invite_link}
              readonly
              class="flex-1 h-11 rounded-xl border border-gray-300 dark:border-slate-700 bg-slate-50 dark:bg-slate-800 px-5 py-3 text-sm text-gray-900 dark:text-white shadow-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
            />
            <.button
              phx-click="copy_invite_link"
              type="button"
              variant="outline"
              class="shrink-0 h-11 px-4 flex items-center justify-center"
            >
              <.icon name="hero-clipboard-document" class="h-4 w-4 mr-1" /> {gettext("Copy")}
            </.button>
          </div>
        </div>
      <% end %>

      <div class="bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-xl shadow-sm overflow-hidden">
        <%= if Enum.empty?(@users) do %>
          <div class="p-12 text-center text-gray-500 dark:text-gray-400">
            {gettext("No users yet.")}
          </div>
        <% else %>
          <table class="min-w-full divide-y divide-gray-200 dark:divide-slate-700">
            <thead class="bg-gray-50 dark:bg-slate-900/50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                  {gettext("Username")}
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                  {gettext("Email")}
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                  {gettext("Joined")}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200 dark:divide-slate-700">
              <%= for user <- @users do %>
                <tr class="hover:bg-gray-50 dark:hover:bg-slate-800/50">
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900 dark:text-white">
                    {user.username}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                    {user.email}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                    {format_date(user.inserted_at)}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("generate_invite", _params, socket) do
    current_user = socket.assigns.current_scope.user

    case Accounts.create_invite_token(current_user) do
      {:ok, encoded_token} ->
        base_url = FusionFlowWeb.Endpoint.url()
        invite_link = "#{base_url}/users/invite/#{encoded_token}"

        {:noreply,
         socket
         |> assign(:invite_link, invite_link)
         |> put_flash(:info, gettext("Invite link generated. Share it so others can register."))}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, gettext("Failed to generate invite link."))}
    end
  end

  @impl true
  def handle_event("copy_invite_link", _params, socket) do
    {:noreply, push_event(socket, "copy_invite_link", %{selector: "#invite-link-input"})}
  end

  @impl true
  def handle_event("invite_link_copied", _params, socket) do
    {:noreply,
     put_flash(socket, :info, gettext("Invite link copied to clipboard."))}
  end

  defp format_date(nil), do: "—"
  defp format_date(datetime), do: Calendar.strftime(datetime, "%d/%m/%Y %H:%M")
end
