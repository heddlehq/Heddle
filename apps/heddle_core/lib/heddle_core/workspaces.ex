defmodule HeddleCore.Workspaces do
  @moduledoc """
  Workspaces, who is in them, and what each person may do there.

  This is the one place that decides access. Contexts ask `authorize/3` before they
  read or change what a workspace owns, and scope their queries by the workspace, so a
  missing check shows nothing instead of everything. See `HeddleCore.Workspaces.Role`
  for what each role allows.
  """

  import Ecto.Query, warn: false

  alias HeddleCore.Accounts.{Scope, User}
  alias HeddleCore.Repo
  alias HeddleCore.Workspaces.{Member, Role, Workspace}

  ## Access

  @doc """
  The role the caller has in the workspace with `workspace_id`, or nil.

  An API key reaches only its own workspace.
  """
  def role(%Scope{api_key: %{workspace_id: id}, role: role}, id) when not is_nil(id), do: role
  def role(%Scope{api_key: %{}}, _workspace_id), do: nil
  def role(%Scope{workspace: %Workspace{id: id}, role: role}, id), do: role
  def role(%Scope{user: %User{} = user}, workspace_id), do: role_of(user, workspace_id)
  def role(_scope, _workspace_id), do: nil

  @doc "Whether the caller may do `action` in the workspace with `workspace_id`."
  def can?(scope, action, workspace_id) do
    not is_nil(workspace_id) and Role.allows?(role(scope, workspace_id), action)
  end

  @doc "Whether the caller may do `action` in the workspace they work in."
  def can?(%Scope{workspace: %Workspace{id: id}} = scope, action), do: can?(scope, action, id)
  def can?(_scope, _action), do: false

  @doc "Returns `:ok`, or `{:error, :forbidden}` for `with` pipelines."
  def authorize(scope, action, workspace_id) do
    if can?(scope, action, workspace_id), do: :ok, else: {:error, :forbidden}
  end

  @doc "The role `user` has in the workspace with `workspace_id`, or nil."
  def role_of(%User{is_system_admin: true}, workspace_id) when not is_nil(workspace_id) do
    if Repo.exists?(from w in Workspace, where: w.id == ^workspace_id), do: "admin"
  end

  def role_of(%User{id: user_id}, workspace_id) when not is_nil(workspace_id) do
    Repo.one(
      from m in Member,
        where: m.user_id == ^user_id and m.workspace_id == ^workspace_id,
        select: m.role
    )
  end

  def role_of(_user, _workspace_id), do: nil

  @doc """
  The workspace `user` works in, with their role there: the one they last chose, or
  else the first they joined. Returns nil when they are in none.
  """
  def current(%User{} = user) do
    with id when not is_nil(id) <- user.current_workspace_id,
         %Workspace{} = workspace <- Repo.get(Workspace, id),
         role when not is_nil(role) <- role_of(user, id) do
      {workspace, role}
    else
      _other -> first_joined(user)
    end
  end

  defp first_joined(%User{} = user) do
    joined =
      Repo.one(
        from w in Workspace,
          join: m in Member,
          on: m.workspace_id == w.id and m.user_id == ^user.id,
          order_by: [asc: m.inserted_at, asc: m.id],
          limit: 1,
          select: {w, m.role}
      )

    cond do
      joined -> joined
      User.system_admin?(user) -> any_workspace()
      true -> nil
    end
  end

  defp any_workspace do
    case Repo.one(from w in Workspace, order_by: [asc: w.id], limit: 1) do
      nil -> nil
      workspace -> {workspace, "admin"}
    end
  end

  ## Workspaces

  def get_workspace(nil), do: nil
  def get_workspace(id), do: Repo.get(Workspace, id)

  @doc """
  The workspaces the caller can open, by name, each with their role there. System
  admins can open all of them.
  """
  def list_workspaces(%Scope{user: %User{is_system_admin: true}}) do
    Repo.all(from w in Workspace, order_by: [asc: fragment("lower(?)", w.name), asc: w.id])
    |> Enum.map(&{&1, "admin"})
  end

  def list_workspaces(%Scope{user: %User{id: user_id}}) do
    Repo.all(
      from w in Workspace,
        join: m in Member,
        on: m.workspace_id == w.id and m.user_id == ^user_id,
        order_by: [asc: fragment("lower(?)", w.name), asc: w.id],
        select: {w, m.role}
    )
  end

  def list_workspaces(_scope), do: []

  @doc """
  Every workspace, with how many members and flows it has, for system admins.
  """
  def list_all_workspaces(%Scope{} = scope) do
    if Scope.system_admin?(scope) do
      members =
        from m in Member, group_by: m.workspace_id, select: %{id: m.workspace_id, n: count()}

      flows =
        from f in "flows", group_by: f.workspace_id, select: %{id: f.workspace_id, n: count()}

      Repo.all(
        from w in Workspace,
          left_join: m in subquery(members),
          on: m.id == w.id,
          left_join: f in subquery(flows),
          on: f.id == w.id,
          order_by: [asc: fragment("lower(?)", w.name), asc: w.id],
          select: %{workspace: w, members: coalesce(m.n, 0), flows: coalesce(f.n, 0)}
      )
    else
      []
    end
  end

  def change_workspace(%Workspace{} = workspace, attrs \\ %{}) do
    Workspace.changeset(workspace, attrs)
  end

  @doc """
  Creates a workspace, with the caller as its admin. Only system admins create them.
  """
  def create_workspace(%Scope{user: %User{} = user} = scope, attrs) do
    if Scope.system_admin?(scope) do
      insert_workspace(user, attrs)
    else
      {:error, :forbidden}
    end
  end

  def create_workspace(_scope, _attrs), do: {:error, :forbidden}

  @doc """
  Gives the first admin of an instance a workspace to start in, unless one exists.
  """
  def ensure_first_workspace(%User{} = user) do
    if Repo.exists?(Workspace) do
      :ok
    else
      with {:ok, _workspace} <- insert_workspace(user, %{"name" => "Default"}), do: :ok
    end
  end

  defp insert_workspace(%User{} = user, attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
    slug = attrs["name"] |> Workspace.slugify() |> available_slug()

    Repo.transact(fn ->
      with {:ok, workspace} <-
             %Workspace{}
             |> Workspace.changeset(Map.put(attrs, "slug", slug))
             |> Repo.insert(),
           {:ok, _member} <- insert_member(workspace.id, user.id, "admin") do
        {:ok, workspace}
      end
    end)
  end

  defp available_slug(base) do
    taken =
      Repo.all(
        from w in Workspace,
          where: w.slug == ^base or like(w.slug, ^"#{base}-%"),
          select: w.slug
      )
      |> MapSet.new()

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  @doc "Renames a workspace. Its admins can."
  def update_workspace(%Scope{} = scope, %Workspace{} = workspace, attrs) do
    with :ok <- authorize(scope, :manage, workspace.id) do
      attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

      workspace
      |> Workspace.changeset(Map.take(attrs, ["name"]))
      |> Repo.update()
    end
  end

  @doc """
  Deletes a workspace with everything in it: flows and their runs, credentials, API
  keys and invites. Only system admins can.
  """
  def delete_workspace(%Scope{} = scope, %Workspace{} = workspace) do
    if Scope.system_admin?(scope) do
      Repo.transact(fn ->
        # One by one, so each flow's webhooks stop answering and its cache is dropped.
        from(f in HeddleCore.Flows.Flow, where: f.workspace_id == ^workspace.id)
        |> Repo.all()
        |> Enum.each(&HeddleCore.Flows.delete_flow/1)

        Repo.delete(workspace)
      end)
    else
      {:error, :forbidden}
    end
  end

  @doc """
  Makes `workspace` the one the caller works in. Returns the new scope.
  """
  def switch_workspace(%Scope{api_key: nil, user: %User{} = user} = scope, %Workspace{} = ws) do
    case role_of(user, ws.id) do
      nil ->
        {:error, :forbidden}

      role ->
        {1, _rows} =
          Repo.update_all(from(u in User, where: u.id == ^user.id),
            set: [current_workspace_id: ws.id]
          )

        user = %{user | current_workspace_id: ws.id}
        {:ok, %{scope | user: user, workspace: ws, role: role}}
    end
  end

  def switch_workspace(_scope, _workspace), do: {:error, :forbidden}

  ## Members

  @doc "The members of a workspace, admins first. Every member can see them."
  def list_members(%Scope{} = scope, %Workspace{id: id}) do
    if can?(scope, :view, id) do
      Repo.all(
        from m in Member,
          join: u in assoc(m, :user),
          where: m.workspace_id == ^id,
          order_by: [
            asc:
              fragment(
                "array_position(?, ?)",
                type(^Role.all(), {:array, :string}),
                m.role
              ),
            asc: fragment("lower(?)", u.username)
          ],
          preload: [user: u]
      )
    else
      []
    end
  end

  def get_member(%Workspace{id: workspace_id}, member_id) do
    Repo.one(
      from m in Member,
        where: m.id == ^member_id and m.workspace_id == ^workspace_id,
        preload: [:user]
    )
  end

  @doc """
  Adds someone who already has an account, found by email or username.
  """
  def add_member(%Scope{} = scope, %Workspace{} = workspace, identifier, role) do
    with :ok <- authorize(scope, :manage, workspace.id),
         :ok <- valid_role(role),
         %User{} = user <- find_user(identifier) || {:error, :user_not_found} do
      case insert_member(workspace.id, user.id, role) do
        {:ok, member} -> {:ok, Repo.preload(member, :user)}
        {:error, %Ecto.Changeset{}} -> {:error, :already_member}
      end
    end
  end

  defp find_user(identifier) when is_binary(identifier) do
    case String.trim(identifier) do
      "" ->
        nil

      value ->
        Repo.one(
          from u in User,
            where:
              fragment("lower(?)", u.email) == ^String.downcase(value) or u.username == ^value,
            limit: 1
        )
    end
  end

  defp find_user(_identifier), do: nil

  @doc """
  Puts `user` in a workspace, as when they accept an invite. Someone already in it
  keeps the role they have.
  """
  def join(%User{id: user_id}, workspace_id, role) do
    with :ok <- valid_role(role) do
      case Repo.get_by(Member, workspace_id: workspace_id, user_id: user_id) do
        nil -> insert_member(workspace_id, user_id, role)
        member -> {:ok, member}
      end
    end
  end

  defp insert_member(workspace_id, user_id, role) do
    %Member{workspace_id: workspace_id, user_id: user_id}
    |> Member.changeset(%{role: role})
    |> Repo.insert()
  end

  @doc "Changes a member's role. A workspace always keeps one admin."
  def change_role(%Scope{} = scope, %Member{} = member, role) do
    with :ok <- authorize(scope, :manage, member.workspace_id),
         :ok <- valid_role(role),
         :ok <- keeps_an_admin(member, role) do
      member
      |> Member.changeset(%{role: role})
      |> Repo.update()
    end
  end

  @doc """
  Takes someone out of a workspace. Admins can remove anyone, and anyone can leave.
  A workspace always keeps one admin.
  """
  def remove_member(%Scope{user: %User{id: user_id}} = scope, %Member{} = member) do
    allowed? = member.user_id == user_id or can?(scope, :manage, member.workspace_id)

    with true <- allowed? || {:error, :forbidden},
         :ok <- keeps_an_admin(member, nil) do
      Repo.delete(member)
    end
  end

  def remove_member(_scope, _member), do: {:error, :forbidden}

  defp keeps_an_admin(%Member{role: "admin"} = member, new_role) when new_role != "admin" do
    admins =
      Repo.aggregate(
        from(m in Member, where: m.workspace_id == ^member.workspace_id and m.role == "admin"),
        :count
      )

    if admins > 1, do: :ok, else: {:error, :last_admin}
  end

  defp keeps_an_admin(_member, _new_role), do: :ok

  defp valid_role(role), do: if(Role.valid?(role), do: :ok, else: {:error, :invalid_role})
end
