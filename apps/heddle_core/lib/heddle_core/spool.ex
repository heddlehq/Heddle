defmodule HeddleCore.Spool do
  @moduledoc """
  Spool, the tables a workspace keeps inside Heddle.

  A table has a name, unique in its workspace, and typed columns (see
  `HeddleCore.Spool.Column`). Its rows live in Heddle's own database, so there is
  nothing to set up: a Form Trigger can save its answers in one, and a flow can keep
  what it needs between runs.

  People reach it here, with a scope: viewers and operators see tables and rows,
  editors change rows and columns, and admins delete tables. Runs reach it through
  `HeddleCore.Spool.Client`, only in their flow's workspace.

  How much a workspace keeps is limited by `limits/0`, from the `:spool` config of
  `:heddle_core`.
  """

  import Ecto.Query

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Repo
  alias HeddleCore.Spool.{Row, Rows, Table}
  alias HeddleCore.Workspaces

  @defaults [max_tables: 50, max_rows: 100_000, max_row_bytes: 65_536, max_find: 1_000]

  @doc """
  What a workspace can keep: `:max_tables`, `:max_rows` per table, `:max_row_bytes`
  per row, and `:max_find`, the most rows one search returns.
  """
  def limits, do: Keyword.merge(@defaults, Application.get_env(:heddle_core, :spool, []))

  @doc "One of `limits/0`."
  def limit(key), do: Keyword.fetch!(limits(), key)

  ## Tables

  @doc "The tables of the caller's workspace, by name, each with its `row_count`."
  def list_tables(%Scope{workspace: %{id: workspace_id}} = scope) do
    if Workspaces.can?(scope, :view, workspace_id) do
      counts =
        from r in Row,
          group_by: r.table_id,
          select: %{table_id: r.table_id, count: count(r.id)}

      Repo.all(
        from t in Table,
          left_join: c in subquery(counts),
          on: c.table_id == t.id,
          where: t.workspace_id == ^workspace_id,
          order_by: [asc: fragment("lower(?)", t.name)],
          select: %{t | row_count: coalesce(c.count, 0)}
      )
    else
      []
    end
  end

  def list_tables(_scope), do: []

  @doc "A table of the caller's workspace, or nil."
  def get_table(%Scope{workspace: %{id: workspace_id}} = scope, id) do
    with true <- Workspaces.can?(scope, :view, workspace_id),
         {:ok, id} <- to_id(id) do
      Repo.get_by(Table, id: id, workspace_id: workspace_id)
    else
      _other -> nil
    end
  end

  def get_table(_scope, _id), do: nil

  @doc "A changeset to show a table's form."
  def change_table(%Table{} = table, attrs \\ %{}), do: Table.changeset(table, attrs)

  @doc """
  Creates a table in the caller's workspace, from `name` and `columns`. Editors and up.
  """
  def create_table(%Scope{workspace: %{id: workspace_id}} = scope, attrs) do
    with :ok <- Workspaces.authorize(scope, :edit, workspace_id),
         :ok <- room_for_table(workspace_id) do
      %Table{workspace_id: workspace_id}
      |> Table.changeset(attrs)
      |> Repo.insert()
    end
  end

  def create_table(_scope, _attrs), do: {:error, :forbidden}

  defp room_for_table(workspace_id) do
    count = Repo.aggregate(from(t in Table, where: t.workspace_id == ^workspace_id), :count)
    max = limit(:max_tables)

    if count < max, do: :ok, else: {:error, {:limit, max}}
  end

  @doc """
  Renames a table or changes its columns. Editors and up.

  A column keeps its `id`, so renaming it rewrites nothing. A column left out takes
  its values with it, and a column whose type changes converts them: if one can't
  be, nothing changes and the changeset says which rows.
  """
  def update_table(%Scope{} = scope, %Table{} = table, attrs) do
    with :ok <- Workspaces.authorize(scope, :edit, table.workspace_id) do
      changeset = Table.changeset(table, attrs)

      if changeset.valid? do
        Repo.transaction(fn ->
          with {:ok, updated} <- Repo.update(changeset),
               :ok <- Rows.migrate(table, table.columns, updated.columns) do
            updated
          else
            {:error, %Ecto.Changeset{} = changeset} ->
              Repo.rollback(changeset)

            {:error, message} ->
              Repo.rollback(Ecto.Changeset.add_error(changeset, :columns, message))
          end
        end)
      else
        {:error, %{changeset | action: :update}}
      end
    end
  end

  @doc "Deletes a table and its rows. Admins only."
  def delete_table(%Scope{} = scope, %Table{} = table) do
    with :ok <- Workspaces.authorize(scope, :manage, table.workspace_id) do
      Repo.delete(table)
    end
  end

  ## Rows

  @doc """
  A page of the rows of `table`, newest first. Takes `:page`, `:per_page` and
  `:search`, and returns `%{rows: rows, total: total}`.
  """
  def list_rows(%Scope{} = scope, %Table{} = table, opts \\ []) do
    if Workspaces.can?(scope, :view, table.workspace_id),
      do: Rows.page(table, opts),
      else: %{rows: [], total: 0}
  end

  @doc "Adds a row from values by column name. Editors and up."
  def insert_row(%Scope{} = scope, %Table{} = table, values) do
    with :ok <- Workspaces.authorize(scope, :edit, table.workspace_id),
         {:ok, [row]} <- Rows.insert(table, [values]) do
      {:ok, row}
    end
  end

  @doc "Changes a row from values by column name, where nil clears one. Editors and up."
  def update_row(%Scope{} = scope, %Table{} = table, row_id, values) do
    with :ok <- Workspaces.authorize(scope, :edit, table.workspace_id),
         {:ok, row_id} <- to_id(row_id) do
      Rows.update_one(table, row_id, values)
    else
      :error -> {:error, "this row no longer exists"}
      error -> error
    end
  end

  @doc "Deletes a row. Editors and up."
  def delete_row(%Scope{} = scope, %Table{} = table, row_id) do
    with :ok <- Workspaces.authorize(scope, :edit, table.workspace_id),
         {:ok, row_id} <- to_id(row_id) do
      {count, _rows} =
        Repo.delete_all(from r in Row, where: r.id == ^row_id and r.table_id == ^table.id)

      if count == 1, do: :ok, else: {:error, "this row no longer exists"}
    else
      :error -> {:error, "this row no longer exists"}
      error -> error
    end
  end

  @doc """
  Calls `fun` with every row of `table` as a CSV line, oldest first, the header
  first. Returns what `fun` returned for the last line, or `{:error, :forbidden}`.

  `fun` takes the line and an accumulator that starts as `acc`, and returns
  `{:cont, acc}` or `{:halt, acc}`.
  """
  def export_csv(%Scope{} = scope, %Table{} = table, acc, fun) do
    with :ok <- Workspaces.authorize(scope, :view, table.workspace_id) do
      names = ["id" | Enum.map(table.columns, & &1["name"])] ++ ["created_at", "updated_at"]

      Repo.transaction(
        fn ->
          [names]
          |> Stream.concat(
            Stream.map(Rows.stream(table), fn row -> Enum.map(names, &row[&1]) end)
          )
          |> Stream.map(&csv_line/1)
          |> Enum.reduce_while(acc, fun)
        end,
        timeout: :infinity
      )
    end
  end

  defp csv_line(values), do: [Enum.map_join(values, ",", &csv_value/1), "\r\n"]

  defp csv_value(nil), do: ""
  defp csv_value(value) when is_map(value) or is_list(value), do: csv_value(Jason.encode!(value))
  defp csv_value(value) when is_number(value) or is_boolean(value), do: to_string(value)

  defp csv_value(value) do
    # A spreadsheet runs a cell that starts with =, +, - or @ as a formula.
    value = if String.starts_with?(value, ["=", "+", "-", "@"]), do: "'" <> value, else: value

    if String.contains?(value, [",", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(value, "\"", "\"\"") <> "\"",
      else: value
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
