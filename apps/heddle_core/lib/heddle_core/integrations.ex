defmodule HeddleCore.Integrations do
  @moduledoc """
  Which integrations each workspace installed.

  This app only knows integrations by id. What each one holds is in
  `HeddleNodes.Integrations`, which also counts the ones the flows of a workspace
  already use as installed. Removing an integration a flow uses is refused, so a flow
  never shows a node its workspace doesn't have.
  """

  import Ecto.Query, warn: false

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Flows.Flow
  alias HeddleCore.Integrations.Installed
  alias HeddleCore.Repo
  alias HeddleCore.Workspaces

  @doc "The ids of the integrations the caller's workspace installed."
  def installed(%Scope{workspace: %{id: id}} = scope) do
    if Workspaces.can?(scope, :view, id) do
      Repo.all(from i in Installed, where: i.workspace_id == ^id, select: i.integration)
    else
      []
    end
  end

  def installed(_scope), do: []

  @doc "The types of the nodes in the flows of the caller's workspace."
  def used_node_types(%Scope{workspace: %{id: id}} = scope) do
    if Workspaces.can?(scope, :view, id) do
      Repo.query!(
        """
        SELECT DISTINCT node->>'type'
        FROM flows, jsonb_array_elements(
          CASE jsonb_typeof(flows.nodes) WHEN 'array' THEN flows.nodes ELSE '[]'::jsonb END
        ) AS node
        WHERE flows.workspace_id = $1 AND node->>'type' IS NOT NULL
        """,
        [id]
      ).rows
      |> List.flatten()
    else
      []
    end
  end

  def used_node_types(_scope), do: []

  @doc "The flows of the caller's workspace with a node of one of `types`, by name."
  def flows_using(%Scope{workspace: %{id: id}} = scope, types) when is_list(types) do
    if Workspaces.can?(scope, :view, id) do
      Repo.all(
        from f in Flow,
          where: f.workspace_id == ^id,
          where:
            fragment(
              "EXISTS (SELECT 1 FROM jsonb_array_elements(CASE jsonb_typeof(?) WHEN 'array' THEN ? ELSE '[]'::jsonb END) AS n WHERE n->>'type' = ANY(?))",
              f.nodes,
              f.nodes,
              ^types
            ),
          order_by: f.name,
          select: %{id: f.id, name: f.name}
      )
    else
      []
    end
  end

  def flows_using(_scope, _types), do: []

  @doc "Installs the integration `id` in the caller's workspace. Editors can."
  def install(%Scope{workspace: %{id: workspace_id}} = scope, id) when is_binary(id) do
    with :ok <- Workspaces.authorize(scope, :edit, workspace_id) do
      %Installed{}
      |> Installed.changeset(%{workspace_id: workspace_id, integration: id})
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:workspace_id, :integration])
      |> case do
        {:ok, _installed} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  def install(_scope, _id), do: {:error, :forbidden}

  @doc """
  Removes the integration `id`, whose nodes are `node_types`, from the caller's
  workspace. Refused with `{:error, {:in_use, flows}}` while a flow uses one of them.
  """
  def uninstall(%Scope{workspace: %{id: workspace_id}} = scope, id, node_types)
      when is_binary(id) do
    with :ok <- Workspaces.authorize(scope, :edit, workspace_id),
         [] <- flows_using(scope, node_types) do
      Repo.delete_all(
        from i in Installed, where: i.workspace_id == ^workspace_id and i.integration == ^id
      )

      :ok
    else
      flows when is_list(flows) -> {:error, {:in_use, flows}}
      error -> error
    end
  end

  def uninstall(_scope, _id, _node_types), do: {:error, :forbidden}
end
