defmodule HeddleCore.Spool.Rows do
  @moduledoc """
  Reads and writes the rows of a Spool table that was already found and allowed.

  `HeddleCore.Spool` calls it for people, after checking their role, and
  `HeddleCore.Spool.Client` for runs, in the workspace the runner pinned. Values come
  and go by column name, see `HeddleCore.Spool.Column`, and every result is ready for
  a run's context.
  """

  import Ecto.Query, except: [update: 2, update: 3]

  alias HeddleCore.Repo
  alias HeddleCore.Spool
  alias HeddleCore.Spool.{Column, Query, Row, Table}

  @doc "How many rows `table` has."
  def count(%Table{id: id}) do
    Repo.aggregate(from(r in Row, where: r.table_id == ^id), :count)
  end

  @doc """
  Adds rows, each a map from column name to value. All of them go in, or none.

  Returns `{:ok, rows}` or `{:error, message}`.
  """
  def insert(%Table{} = table, values) when is_list(values) do
    with :ok <- room(table, length(values)),
         {:ok, entries} <- entries(table, values) do
      {_count, rows} = Repo.insert_all(Row, entries, returning: true)
      {:ok, Enum.map(rows, &Column.to_row(table.columns, &1))}
    end
  end

  defp entries(table, values) do
    now = DateTime.utc_now()

    Enum.reduce_while(values, {:ok, []}, fn row, {:ok, acc} ->
      with {:ok, data} <- Column.to_data(table.columns, row),
           :ok <- fits(data) do
        {:cont,
         {:ok, [%{table_id: table.id, data: data, inserted_at: now, updated_at: now} | acc]}}
      else
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  @doc """
  Finds rows by `filter` (see `HeddleCore.Spool.Query`), with `:order`, `:limit` and
  `:offset`. The limit can't pass the one Spool has.

  Returns `{:ok, rows}` or `{:error, message}`.
  """
  def find(%Table{} = table, filter, opts \\ []) do
    limit = opts |> Keyword.get(:limit, 100) |> min(Spool.limit(:max_find)) |> max(1)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)

    with {:ok, query} <- Query.filter(base(table), table.columns, filter),
         {:ok, query} <- Query.order(query, table.columns, Keyword.get(opts, :order, "")) do
      safely(fn ->
        query
        |> limit(^limit)
        |> offset(^offset)
        |> Repo.all()
        |> Enum.map(&Column.to_row(table.columns, &1))
      end)
    end
  end

  @doc """
  Changes the rows `filter` finds: each column in `values` takes its value, and a nil
  clears it. The filter can't be empty, so a mistake doesn't change every row.

  Returns `{:ok, %{"count" => count, "ids" => ids}}` or `{:error, message}`.
  """
  def update(%Table{} = table, filter, values) do
    with :ok <- some_filter(filter),
         {:ok, data} <- Column.to_data(table.columns, values, keep_nil: true),
         :ok <- some_values(data),
         :ok <- fits(data),
         {:ok, query} <- Query.filter(base(table), table.columns, filter) do
      {set, cleared} = Enum.split_with(data, fn {_id, value} -> not is_nil(value) end)
      set = Map.new(set)
      cleared = Enum.map(cleared, &elem(&1, 0))
      now = DateTime.utc_now()

      safely(fn ->
        {count, ids} =
          query
          |> select([r], r.id)
          |> Ecto.Query.update([r],
            set: [
              data: fragment("(? - ?::text[]) || ?", r.data, ^cleared, type(^set, :map)),
              updated_at: ^now
            ]
          )
          |> Repo.update_all([])

        %{"count" => count, "ids" => Enum.sort(ids)}
      end)
    end
  end

  @doc """
  Deletes the rows `filter` finds. The filter can't be empty.

  Returns `{:ok, %{"count" => count, "ids" => ids}}` or `{:error, message}`.
  """
  def delete(%Table{} = table, filter) do
    with :ok <- some_filter(filter),
         {:ok, query} <- Query.filter(base(table), table.columns, filter) do
      safely(fn ->
        {count, ids} = query |> select([r], r.id) |> Repo.delete_all()
        %{"count" => count, "ids" => Enum.sort(ids)}
      end)
    end
  end

  @doc """
  Adds or changes rows by the value of the column `key`: a row with the same value
  takes the new values, and one without such a row is added. Runs at a time per table,
  so two runs can't both add the same key.

  Returns `{:ok, %{"rows" => rows, "inserted" => n, "updated" => n}}` or
  `{:error, message}`.
  """
  def upsert(%Table{} = table, key, values) when is_list(values) do
    with {:ok, column} <- key_column(table, key) do
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock($1)", [table.id])

        Enum.reduce(values, %{"rows" => [], "inserted" => 0, "updated" => 0}, fn row, acc ->
          case upsert_one(table, column, row) do
            {:ok, :inserted, row} ->
              %{acc | "rows" => [row | acc["rows"]], "inserted" => acc["inserted"] + 1}

            {:ok, :updated, row} ->
              %{acc | "rows" => [row | acc["rows"]], "updated" => acc["updated"] + 1}

            {:error, message} ->
              Repo.rollback(message)
          end
        end)
        |> Map.update!("rows", &Enum.reverse/1)
      end)
    end
  end

  defp key_column(table, key) do
    case Column.find(table.columns, to_string(key || "")) do
      nil -> {:error, "the table has no column #{key} to match rows by"}
      %{"type" => "json"} -> {:error, "a json column can't be the key"}
      column -> {:ok, column}
    end
  end

  defp upsert_one(table, column, values) do
    with {:ok, data} <- Column.to_data(table.columns, values, keep_nil: true),
         {:ok, key} <- key_value(data, column),
         :ok <- fits(data) do
      existing =
        Repo.one(
          from r in base(table),
            where: fragment("? @> ?", r.data, type(^%{column["id"] => key}, :map)),
            order_by: [asc: r.id],
            limit: 1
        )

      case existing do
        nil ->
          with :ok <- room(table, 1) do
            now = DateTime.utc_now()

            row =
              Repo.insert!(%Row{
                table_id: table.id,
                data: Map.reject(data, fn {_id, value} -> is_nil(value) end),
                inserted_at: now,
                updated_at: now
              })

            {:ok, :inserted, Column.to_row(table.columns, row)}
          end

        %Row{} = row ->
          merged =
            row.data |> Map.merge(data) |> Map.reject(fn {_id, value} -> is_nil(value) end)

          row = row |> Ecto.Changeset.change(data: merged) |> Repo.update!()
          {:ok, :updated, Column.to_row(table.columns, row)}
      end
    end
  end

  defp key_value(data, column) do
    case Map.get(data, column["id"]) do
      nil -> {:error, "each row needs a value for #{column["name"]}, the key"}
      key -> {:ok, key}
    end
  end

  @doc """
  A page of rows for people, newest first, with `:search`, `:page` and `:per_page`.

  Returns `%{rows: rows, total: total}`.
  """
  def page(%Table{} = table, opts \\ []) do
    per_page = Keyword.get(opts, :per_page, 50)
    page = opts |> Keyword.get(:page, 1) |> max(1)
    query = Query.search(base(table), Keyword.get(opts, :search))

    rows =
      query
      |> order_by([r], desc: r.id)
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> Repo.all()
      |> Enum.map(&Column.to_row(table.columns, &1))

    %{rows: rows, total: Repo.aggregate(query, :count)}
  end

  @doc "Changes one row: each column in `values` takes its value, and a nil clears it."
  def update_one(%Table{} = table, row_id, values) do
    with {:ok, data} <- Column.to_data(table.columns, values, keep_nil: true),
         %Row{} = row <- Repo.get_by(Row, id: row_id, table_id: table.id) do
      merged = row.data |> Map.merge(data) |> Map.reject(fn {_id, value} -> is_nil(value) end)

      with :ok <- fits(merged) do
        row = row |> Ecto.Changeset.change(data: merged) |> Repo.update!()
        {:ok, Column.to_row(table.columns, row)}
      end
    else
      nil -> {:error, "this row no longer exists"}
      error -> error
    end
  end

  @doc """
  Makes the rows hold `new_columns` instead of `old_columns`: the values of a removed
  column go, and those of a column whose type changed are converted. Runs inside the
  transaction that changes the table.

  Returns `:ok` or `{:error, message}` naming rows whose value can't be converted.
  """
  def migrate(%Table{id: id}, old_columns, new_columns) do
    new_ids = MapSet.new(new_columns, & &1["id"])
    removed = for column <- old_columns, column["id"] not in new_ids, do: column["id"]
    old_types = Map.new(old_columns, &{&1["id"], &1["type"]})

    retyped =
      Enum.filter(new_columns, fn column ->
        Map.has_key?(old_types, column["id"]) and old_types[column["id"]] != column["type"]
      end)

    if removed != [] do
      from(r in Row, where: r.table_id == ^id)
      |> Ecto.Query.update([r], set: [data: fragment("? - ?::text[]", r.data, ^removed)])
      |> Repo.update_all([])
    end

    Enum.reduce_while(retyped, :ok, fn column, :ok ->
      case retype(id, column) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp retype(table_id, %{"id" => column_id, "type" => type, "name" => name}) do
    rows =
      Repo.all(
        from r in Row,
          where: r.table_id == ^table_id and fragment("jsonb_exists(?, ?)", r.data, ^column_id),
          select: {r.id, r.data}
      )

    {changes, failed} =
      Enum.reduce(rows, {[], []}, fn {row_id, data}, {changes, failed} ->
        case Column.cast(type, data[column_id]) do
          {:ok, value} -> {[{row_id, Map.put(data, column_id, value)} | changes], failed}
          :error -> {changes, [row_id | failed]}
        end
      end)

    if failed == [] do
      Enum.each(changes, fn {row_id, data} ->
        from(r in Row, where: r.id == ^row_id) |> Repo.update_all(set: [data: data])
      end)

      :ok
    else
      ids = failed |> Enum.sort() |> Enum.take(5) |> Enum.join(", ")
      {:error, "#{name} can't become #{type}: rows #{ids} hold values that aren't"}
    end
  end

  @doc "Every row of `table`, oldest first, to export. Call it inside a transaction."
  def stream(%Table{} = table) do
    base(table)
    |> order_by([r], asc: r.id)
    |> Repo.stream(max_rows: 500)
    |> Stream.map(&Column.to_row(table.columns, &1))
  end

  defp base(%Table{id: id}), do: from(r in Row, where: r.table_id == ^id)

  defp room(table, adding) do
    max = Spool.limit(:max_rows)

    if count(table) + adding > max,
      do: {:error, "the table #{table.name} can't hold more than #{max} rows"},
      else: :ok
  end

  defp fits(data) do
    max = Spool.limit(:max_row_bytes)

    if byte_size(Jason.encode!(data)) > max,
      do: {:error, "a row can't take more than #{div(max, 1024)} KB"},
      else: :ok
  end

  defp some_filter(filter) when is_map(filter) and map_size(filter) > 0, do: :ok

  defp some_filter(_filter),
    do: {:error, ~s(say which rows with a filter, like {"id": 12})}

  defp some_values(data) when map_size(data) > 0, do: :ok
  defp some_values(_data), do: {:error, "say which columns change"}

  # A filter is checked before it runs, but the database has the last word.
  defp safely(fun) do
    {:ok, fun.()}
  rescue
    error in Postgrex.Error -> {:error, Exception.message(error)}
  end
end
