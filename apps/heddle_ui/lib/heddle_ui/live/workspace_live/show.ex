defmodule HeddleUI.WorkspaceLive.Show do
  @moduledoc """
  The workspace a person works in: its members and their roles, invites, and its name.

  Every member can see who is in it. Admins add people, change roles and invites.
  """

  use HeddleUI, :live_view

  on_mount {HeddleUI.UserAuth, {:require_workspace, :view}}

  alias HeddleCore.Accounts
  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Workspaces
  alias HeddleCore.Workspaces.Role
  alias HeddleUI.Components.Invites
  alias HeddleUI.Layouts

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    workspace = scope.workspace

    {:ok,
     socket
     |> assign(:page_title, workspace.name)
     |> assign(:workspace, workspace)
     |> assign(:manage, Workspaces.can?(scope, :manage))
     |> assign(:system_admin, Scope.system_admin?(scope))
     |> assign(:new_invite, nil)
     |> assign(:name_form, to_form(Workspaces.change_workspace(workspace)))
     |> assign(:add_form, to_form(%{"identifier" => "", "role" => "editor"}, as: :member))
     |> assign(:invite_form, to_form(%{"role" => "editor"}, as: :invite))
     |> assign(:delete_form, to_form(%{"name" => ""}, as: :delete))
     |> load()}
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    workspace = socket.assigns.workspace

    socket
    |> assign(:members, Workspaces.list_members(scope, workspace))
    |> assign(:invites, Accounts.list_open_invites(scope, workspace))
  end

  @impl true
  def handle_event("rename", %{"workspace" => params}, socket) do
    case Workspaces.update_workspace(
           socket.assigns.current_scope,
           socket.assigns.workspace,
           params
         ) do
      {:ok, workspace} ->
        {:noreply,
         socket
         |> assign(:workspace, workspace)
         |> assign(:page_title, workspace.name)
         |> assign(:name_form, to_form(Workspaces.change_workspace(workspace)))
         |> put_flash(:info, gettext("Workspace renamed."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :name_form, to_form(changeset, action: :validate))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("add_member", %{"member" => params}, socket) do
    %{current_scope: scope, workspace: workspace} = socket.assigns

    case Workspaces.add_member(scope, workspace, params["identifier"], params["role"]) do
      {:ok, member} ->
        {:noreply,
         socket
         |> assign(
           :add_form,
           to_form(%{"identifier" => "", "role" => params["role"]}, as: :member)
         )
         |> load()
         |> put_flash(:info, gettext("%{name} joined the workspace.", name: member.user.username))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:add_form, to_form(params, as: :member))
         |> put_flash(:error, error_message(reason))}
    end
  end

  def handle_event("change_role", %{"member_id" => id, "role" => role}, socket) do
    with %{} = member <- Workspaces.get_member(socket.assigns.workspace, id),
         {:ok, _member} <- Workspaces.change_role(socket.assigns.current_scope, member, role) do
      {:noreply, socket |> load() |> put_flash(:info, gettext("Role changed."))}
    else
      {:error, reason} -> {:noreply, socket |> load() |> put_flash(:error, error_message(reason))}
      nil -> {:noreply, load(socket)}
    end
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    with %{} = member <- Workspaces.get_member(socket.assigns.workspace, id),
         {:ok, _member} <- Workspaces.remove_member(scope, member) do
      if member.user_id == scope.user.id do
        {:noreply,
         socket
         |> put_flash(:info, gettext("You left %{name}.", name: socket.assigns.workspace.name))
         |> push_navigate(to: ~p"/")}
      else
        {:noreply, socket |> load() |> put_flash(:info, gettext("Removed from the workspace."))}
      end
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_message(reason))}
      nil -> {:noreply, load(socket)}
    end
  end

  def handle_event("create_invite", %{"invite" => %{"role" => role}}, socket) do
    %{current_scope: scope, workspace: workspace} = socket.assigns

    case Accounts.create_invite(scope, workspace, role) do
      {:ok, invite} ->
        {:noreply,
         socket
         |> assign(:new_invite, invite)
         |> assign(:invite_form, to_form(%{"role" => role}, as: :invite))
         |> load()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("revoke_invite", %{"id" => id}, socket) do
    with %{} = invite <- Accounts.get_invite(id),
         true <- invite.workspace_id == socket.assigns.workspace.id,
         {:ok, _invite} <- Accounts.revoke_invite(socket.assigns.current_scope, invite) do
      new_invite = socket.assigns.new_invite
      new_invite = if new_invite && new_invite.id == invite.id, do: nil, else: new_invite

      {:noreply,
       socket
       |> assign(:new_invite, new_invite)
       |> load()
       |> put_flash(:info, gettext("Invite canceled."))}
    else
      _other -> {:noreply, put_flash(socket, :error, error_message(:forbidden))}
    end
  end

  def handle_event("delete_workspace", %{"delete" => %{"name" => name}}, socket) do
    %{current_scope: scope, workspace: workspace} = socket.assigns

    if name == workspace.name do
      case Workspaces.delete_workspace(scope, workspace) do
        {:ok, _workspace} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("%{name} was deleted.", name: workspace.name))
           |> push_navigate(to: ~p"/workspaces")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, error_message(reason))}
      end
    else
      {:noreply,
       put_flash(socket, :error, gettext("Type the name of the workspace to delete it."))}
    end
  end

  defp error_message(:forbidden), do: gettext("Only the admins of this workspace can do that.")

  defp error_message(:last_admin),
    do: gettext("A workspace needs at least one admin. Make someone else admin first.")

  defp error_message(:user_not_found),
    do:
      gettext(
        "Nobody has an account with that email or username. Send them an invite link instead."
      )

  defp error_message(:already_member), do: gettext("They are already in this workspace.")
  defp error_message(:invalid_role), do: gettext("Pick a role.")
  defp error_message(_reason), do: gettext("Something went wrong. Try again.")

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :roles, Role.all())

    ~H"""
    <div class="p-6 md:p-8 w-full max-w-5xl mx-auto space-y-8">
      <div class="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div class="flex min-w-0 items-center gap-4">
          <div class="size-12 shrink-0 rounded-xl bg-primary/10 text-primary flex items-center justify-center text-lg font-bold">
            {String.first(@workspace.name) |> String.upcase()}
          </div>
          <div class="min-w-0">
            <h1 id="workspace-name" class="text-2xl font-bold text-gray-900 dark:text-white">
              {@workspace.name}
            </h1>
            <p class="text-sm text-gray-500 dark:text-gray-400">
              {gettext("You are %{role} here.", role: Layouts.role_label(@current_scope.role))}
              {Layouts.role_description(@current_scope.role)}
            </p>
          </div>
        </div>
        <.form
          :if={@manage}
          for={@name_form}
          id="workspace-rename-form"
          phx-submit="rename"
          class="flex w-full items-end gap-3 md:w-auto"
        >
          <div class="min-w-0 flex-1 md:w-64 md:flex-none">
            <.input field={@name_form[:name]} type="text" label={gettext("Name")} required />
          </div>
          <.button id="rename-workspace" type="submit" variant="outline" size="field" class="mb-3">
            {gettext("Rename")}
          </.button>
        </.form>
      </div>

      <section class="bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 rounded-xl shadow-sm">
        <div class="px-6 py-5 border-b border-gray-100 dark:border-slate-800 flex items-center justify-between">
          <div>
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">{gettext("Members")}</h2>
            <p class="text-sm text-gray-500 dark:text-gray-400">
              {ngettext("1 person", "%{count} people", length(@members))}
            </p>
          </div>
        </div>
        <ul id="workspace-members" class="divide-y divide-gray-100 dark:divide-slate-800">
          <li
            :for={member <- @members}
            id={"member-#{member.id}"}
            class="px-6 py-4 flex flex-wrap items-center gap-4"
          >
            <div class="size-9 shrink-0 rounded-full bg-gray-100 dark:bg-slate-800 text-gray-600 dark:text-gray-300 flex items-center justify-center text-sm font-semibold">
              {String.first(member.user.username || member.user.email) |> String.upcase()}
            </div>
            <div class="min-w-0 flex-1">
              <p class="text-sm font-medium text-gray-900 dark:text-white truncate">
                {member.user.username}
                <span
                  :if={member.user_id == @current_scope.user.id}
                  class="ml-1 text-xs font-normal text-gray-500 dark:text-gray-400"
                >
                  {gettext("(you)")}
                </span>
              </p>
              <p class="text-xs text-gray-500 dark:text-gray-400 truncate">{member.user.email}</p>
            </div>
            <%= if @manage do %>
              <form id={"member-role-#{member.id}"} phx-change="change_role">
                <input type="hidden" name="member_id" value={member.id} />
                <label for={"member-role-select-#{member.id}"} class="sr-only">
                  {gettext("Role")}
                </label>
                <select
                  id={"member-role-select-#{member.id}"}
                  name="role"
                  class="rounded-lg border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm text-gray-800 dark:text-gray-200 py-1.5 pl-3 pr-8 focus:ring-2 focus:ring-primary focus:border-primary"
                >
                  <option :for={role <- @roles} value={role} selected={role == member.role}>
                    {Layouts.role_label(role)}
                  </option>
                </select>
              </form>
            <% else %>
              <span class="rounded-full bg-gray-100 dark:bg-slate-800 px-2.5 py-1 text-xs font-medium text-gray-700 dark:text-gray-300">
                {Layouts.role_label(member.role)}
              </span>
            <% end %>
            <.button
              :if={@manage or member.user_id == @current_scope.user.id}
              id={"remove-member-#{member.id}"}
              type="button"
              variant="ghost"
              phx-click="remove_member"
              phx-value-id={member.id}
              data-confirm={
                if member.user_id == @current_scope.user.id,
                  do: gettext("Leave this workspace? You'll lose access to its flows."),
                  else: gettext("Remove %{name} from this workspace?", name: member.user.username)
              }
              title={
                if member.user_id == @current_scope.user.id,
                  do: gettext("Leave"),
                  else: gettext("Remove")
              }
            >
              <.icon
                name={
                  if member.user_id == @current_scope.user.id,
                    do: "hero-arrow-right-start-on-rectangle",
                    else: "hero-user-minus"
                }
                class="size-4"
              />
            </.button>
          </li>
        </ul>
      </section>

      <div :if={@manage} class="grid gap-6 md:grid-cols-2">
        <section class="bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 rounded-xl shadow-sm p-6 space-y-4">
          <div>
            <h2 class="text-base font-semibold text-gray-900 dark:text-white">
              {gettext("Add someone")}
            </h2>
            <p class="text-sm text-gray-500 dark:text-gray-400">
              {gettext("For people who already have an account here.")}
            </p>
          </div>
          <.form for={@add_form} id="add-member-form" phx-submit="add_member" class="space-y-3">
            <.input
              field={@add_form[:identifier]}
              type="text"
              label={gettext("Email or username")}
              autocomplete="off"
              required
            />
            <.input
              field={@add_form[:role]}
              type="select"
              label={gettext("Role")}
              options={Invites.role_options()}
            />
            <.button id="add-member" type="submit" variant="primary">
              <.icon name="hero-user-plus" class="h-4 w-4" /> {gettext("Add")}
            </.button>
          </.form>
        </section>

        <section class="bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 rounded-xl shadow-sm p-6 space-y-4">
          <div>
            <h2 class="text-base font-semibold text-gray-900 dark:text-white">
              {gettext("Invite by link")}
            </h2>
            <p class="text-sm text-gray-500 dark:text-gray-400">
              {gettext("For someone new: the link creates their account and brings them in.")}
            </p>
          </div>
          <.form for={@invite_form} id="invite-form" phx-submit="create_invite" class="space-y-3">
            <.input
              field={@invite_form[:role]}
              type="select"
              label={gettext("Role")}
              options={Invites.role_options()}
            />
            <.button id="create-invite" type="submit" variant="primary">
              <.icon name="hero-link" class="h-4 w-4" /> {gettext("Get invite link")}
            </.button>
          </.form>
          <Invites.invite_link :if={@new_invite} invite={@new_invite} />
        </section>
      </div>

      <section
        :if={@manage and @invites != []}
        id="open-invites"
        class="bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 rounded-xl shadow-sm"
      >
        <div class="px-6 py-4 border-b border-gray-100 dark:border-slate-800">
          <h2 class="text-base font-semibold text-gray-900 dark:text-white">
            {gettext("Open invites")}
          </h2>
        </div>
        <ul class="divide-y divide-gray-100 dark:divide-slate-800">
          <li
            :for={invite <- @invites}
            id={"invite-#{invite.id}"}
            class="px-6 py-3 flex items-center gap-4 text-sm"
          >
            <span class="rounded-full bg-gray-100 dark:bg-slate-800 px-2.5 py-1 text-xs font-medium text-gray-700 dark:text-gray-300">
              {Layouts.role_label(invite.role)}
            </span>
            <span class="flex-1 text-gray-600 dark:text-gray-300">
              {gettext("By %{name}, until %{date}",
                name: invite.invited_by_user && invite.invited_by_user.username,
                date: Calendar.strftime(invite.expires_at, "%Y-%m-%d")
              )}
            </span>
            <.button
              id={"revoke-invite-#{invite.id}"}
              type="button"
              variant="ghost"
              phx-click="revoke_invite"
              phx-value-id={invite.id}
            >
              {gettext("Cancel")}
            </.button>
          </li>
        </ul>
      </section>

      <section class="rounded-xl border border-gray-200 dark:border-slate-800 p-6">
        <h2 class="text-base font-semibold text-gray-900 dark:text-white">{gettext("Roles")}</h2>
        <dl class="mt-4 grid gap-4 sm:grid-cols-2">
          <div :for={role <- @roles}>
            <dt class="text-sm font-medium text-gray-900 dark:text-white">
              {Layouts.role_label(role)}
            </dt>
            <dd class="text-sm text-gray-500 dark:text-gray-400">{Layouts.role_description(role)}</dd>
          </div>
        </dl>
      </section>

      <section
        :if={@system_admin}
        id="workspace-danger-zone"
        class="rounded-xl border border-red-200 dark:border-red-900/50 p-6 space-y-4"
      >
        <div>
          <h2 class="text-base font-semibold text-red-700 dark:text-red-400">
            {gettext("Delete workspace")}
          </h2>
          <p class="text-sm text-gray-600 dark:text-gray-400">
            {gettext(
              "Deletes its flows and their runs, credentials, API keys and invites. This can't be undone."
            )}
          </p>
        </div>
        <.form
          for={@delete_form}
          id="delete-workspace-form"
          phx-submit="delete_workspace"
          class="flex max-w-xl items-end gap-3"
        >
          <div class="min-w-0 flex-1">
            <.input
              field={@delete_form[:name]}
              type="text"
              label={gettext("Type %{name} to confirm", name: @workspace.name)}
              autocomplete="off"
            />
          </div>
          <.button
            id="delete-workspace"
            type="submit"
            variant="danger"
            size="field"
            class="mb-3"
          >
            {gettext("Delete")}
          </.button>
        </.form>
      </section>
    </div>
    """
  end
end
