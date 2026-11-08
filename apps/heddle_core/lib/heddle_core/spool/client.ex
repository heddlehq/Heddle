defmodule HeddleCore.Spool.Client do
  @moduledoc """
  What the Spool nodes call, through the `:spool_client` config of `:heddle_nodes`.

  A run reaches only the tables of its flow's workspace: the runner pins
  `workspace_id` in every node's context, and nothing a node or a field sets can
  change it. Tables are found by name, ignoring case.

  Every function returns `{:ok, result}`, ready for a run's context, or
  `{:error, message}`.
  """

  import Ecto.Query

  alias HeddleCore.Repo
  alias HeddleCore.Spool.{Rows, Table}

  @doc "Adds rows, each a map from column name to value."
  def insert(workspace_id, table, rows) do
    with {:ok, table} <- table(workspace_id, table),
         {:ok, rows} <- Rows.insert(table, rows) do
      {:ok, %{"rows" => rows, "count" => length(rows)}}
    end
  end

  @doc "Finds rows by `filter`, with `:order`, `:limit` and `:offset`."
  def find(workspace_id, table, filter, opts \\ []) do
    with {:ok, table} <- table(workspace_id, table),
         {:ok, rows} <- Rows.find(table, filter, opts) do
      {:ok, %{"rows" => rows, "count" => length(rows)}}
    end
  end

  @doc "Changes the rows `filter` finds."
  def update(workspace_id, table, filter, values) do
    with {:ok, table} <- table(workspace_id, table) do
      Rows.update(table, filter, values)
    end
  end

  @doc "Deletes the rows `filter` finds."
  def delete(workspace_id, table, filter) do
    with {:ok, table} <- table(workspace_id, table) do
      Rows.delete(table, filter)
    end
  end

  @doc "Adds or changes rows by the value of the column `key`."
  def upsert(workspace_id, table, key, rows) do
    with {:ok, table} <- table(workspace_id, table) do
      Rows.upsert(table, key, rows)
    end
  end

  defp table(workspace_id, name) when is_integer(workspace_id) and is_binary(name) do
    name = String.trim(name)

    found =
      Repo.get_by(Table, workspace_id: workspace_id, name: name) ||
        Repo.one(
          from t in Table,
            where:
              t.workspace_id == ^workspace_id and
                fragment("lower(?)", t.name) == ^String.downcase(name),
            order_by: [asc: t.id],
            limit: 1
        )

    case found do
      nil when name == "" -> {:error, "say which table"}
      nil -> {:error, "this workspace has no Spool table named #{name}"}
      table -> {:ok, table}
    end
  end

  defp table(_workspace_id, _name), do: {:error, "this run has no workspace with Spool tables"}
end
