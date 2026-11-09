defmodule HeddleCore.Flows.Groups do
  @moduledoc """
  Groups that keep the flows of a workspace apart on the flows page.

  A flow is in one group or none. Everyone in the workspace sees them, and editors
  and up create, rename and delete them, and move flows between them. Deleting a
  group leaves its flows without one. A group of another workspace looks missing.
  """

  import Ecto.Query, warn: false

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Flows
  alias HeddleCore.Flows.{Flow, Group}
  alias HeddleCore.Repo
  alias HeddleCore.Workspaces

  @doc "The groups of the workspace the caller works in, by name."
  def list_groups(%Scope{workspace: %{id: workspace_id}} = scope) do
    if Workspaces.can?(scope, :view, workspace_id) do
      Repo.all(
        from g in Group,
          where: g.workspace_id == ^workspace_id,
          order_by: [asc: fragment("lower(?)", g.name), asc: g.id]
      )
    else
      []
    end
  end

  def list_groups(_scope), do: []

  @doc "A group of the caller's workspace, or nil."
  def get_group(%Scope{workspace: %{id: workspace_id}} = scope, id) do
    with true <- Workspaces.can?(scope, :view, workspace_id),
         {:ok, id} <- to_id(id) do
      Repo.get_by(Group, id: id, workspace_id: workspace_id)
    else
      _other -> nil
    end
  end

  def get_group(_scope, _id), do: nil

  @doc "A changeset to show a group's form."
  def change_group(%Group{} = group, attrs \\ %{}), do: Group.changeset(group, attrs)

  @doc "Creates a group in the caller's workspace. Editors and up."
  def create_group(%Scope{workspace: %{id: workspace_id}} = scope, attrs) do
    with :ok <- Workspaces.authorize(scope, :edit, workspace_id) do
      %Group{workspace_id: workspace_id}
      |> Group.changeset(attrs)
      |> Repo.insert()
    end
  end

  def create_group(_scope, _attrs), do: {:error, :forbidden}

  @doc "Renames a group of the caller's workspace. Editors and up."
  def rename_group(%Scope{} = scope, id, attrs) do
    with {:ok, group} <- fetch(scope, id) do
      group
      |> Group.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc "Deletes a group, and leaves its flows without one. Editors and up."
  def delete_group(%Scope{} = scope, id) do
    with {:ok, group} <- fetch(scope, id) do
      Repo.delete(group)
    end
  end

  @doc """
  Moves a flow the caller may edit to a group of its workspace, or to none with nil.
  Returns `{:ok, flow}`, or `{:error, :not_found}` when either isn't theirs to see.
  """
  def move_flow(%Scope{} = scope, flow_id, group_id) do
    with {:ok, flow} <- Flows.fetch_for(scope, :edit, flow_id),
         {:ok, group_id} <- group_of(flow, group_id) do
      flow
      |> Flow.group_changeset(group_id)
      |> Repo.update()
    end
  end

  defp group_of(_flow, blank) when blank in [nil, ""], do: {:ok, nil}

  defp group_of(%Flow{workspace_id: workspace_id}, id) do
    with {:ok, id} <- to_id(id),
         %Group{id: id} <- Repo.get_by(Group, id: id, workspace_id: workspace_id) do
      {:ok, id}
    else
      _other -> {:error, :not_found}
    end
  end

  # A group of another workspace, or one that's gone, is missing; one the caller sees
  # but can't change is forbidden.
  defp fetch(scope, id) do
    case get_group(scope, id) do
      nil ->
        {:error, :not_found}

      group ->
        with :ok <- Workspaces.authorize(scope, :edit, group.workspace_id), do: {:ok, group}
    end
  end

  defp to_id(id) when is_integer(id), do: {:ok, id}

  defp to_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> {:ok, id}
      _other -> :error
    end
  end

  defp to_id(_id), do: :error
end
