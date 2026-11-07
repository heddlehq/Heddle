defmodule HeddleNodes.Services.Sql do
  @moduledoc """
  The SQL nodes, on any relational database.

  The nodes don't know which database they talk to: the credential picks the engine,
  and each engine in `HeddleNodes.Services.Sql.*` answers `Engine`. Databases that
  speak the protocol of one of these work through it: CockroachDB, TimescaleDB,
  Redshift, Neon and Supabase as PostgreSQL, and MariaDB, TiDB and PlanetScale as MySQL.
  """

  alias HeddleNodes.Connections
  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Sql.{MySQL, Oracle, Postgres, SQLite, SqlServer, Statement}

  @engines %{
    "postgres" => Postgres,
    "mysql" => MySQL,
    "sqlserver" => SqlServer,
    "sqlite" => SQLite,
    "oracle" => Oracle
  }
  # What a run can hold: a context goes to JSON and to the database after each node.
  @max_rows 10_000
  # SQL Server takes at most 2100 parameters in a statement.
  @max_params 2000
  @service %{
    title: "SQL",
    category: :database,
    group: "SQL",
    credential: "sql",
    icon: "hero-circle-stack-solid"
  }

  def definition(action, description, fields) do
    Integration.definition(@service, action, description, fields)
  end

  def table_field, do: %{type: :text, name: :table, label: "Table", default: ""}

  def where_field(default \\ "") do
    %{type: :textarea, name: :where, label: "Where", default: default}
  end

  def rows_field do
    %{type: :textarea, name: :rows, label: "Rows", default: "{{result}}"}
  end

  @doc """
  Calls `fun` with the engine of the node's credential and a connection to it.
  """
  def run(context, fun) do
    Integration.run(context, "sql", fn values ->
      with {:ok, engine} <- engine(values) do
        Connections.with_connection(values, fn -> engine.connect(values) end, fn conn ->
          fun.(engine, conn)
        end)
      end
    end)
  end

  defp engine(values) do
    case @engines[values["engine"]] do
      nil -> {:error, "This credential has no database engine."}
      engine -> {:ok, engine}
    end
  end

  @doc """
  Binds what a field holds and runs it.
  """
  def execute(engine, conn, template, context) do
    with {:ok, sql, params} <- bind(engine, template, context) do
      query(engine, conn, sql, params)
    end
  end

  def bind(engine, template, context, offset \\ 0) do
    Statement.bind(template, context, &engine.placeholder/1, offset, engine.strings())
  end

  @doc """
  Runs a statement and returns its rows as maps of values a run can keep.
  """
  def query(engine, conn, sql, params) do
    with {:ok, result} <- engine.query(conn, sql, params) do
      answer(result)
    end
  end

  defp answer(%{rows: rows}) when length(rows) > @max_rows do
    {:error,
     "The query returned #{length(rows)} rows, and a run holds #{@max_rows}. Use a LIMIT."}
  end

  defp answer(result) do
    rows = Enum.map(result.rows, &to_row(result.columns, &1))
    answer = %{"rows" => rows, "count" => result.count}

    case result[:last_id] do
      id when id in [nil, 0] -> {:ok, answer}
      id -> {:ok, Map.put(answer, "last_id", id)}
    end
  end

  defp to_row(columns, values) do
    columns
    |> Enum.zip(values)
    |> Map.new(fn {column, value} -> {column, Integration.to_value(value)} end)
  end

  @doc """
  Quotes a table's name, which can come with its schema.
  """
  def table(engine, context) do
    case Integration.field(context, "table") |> String.trim() do
      "" -> {:error, "Pick a table."}
      name -> {:ok, name |> String.split(".") |> Enum.map_join(".", &engine.quote_name/1)}
    end
  end

  @doc """
  Reads a Where that can't be empty, so a blank field never hits every row.
  """
  def required_where(context) do
    case String.trim(context["where"] || "") do
      "" -> {:error, "Where is empty. To hit every row on purpose, write 1 = 1."}
      where -> {:ok, where}
    end
  end

  @doc """
  Reads a field with a list of names, separated by commas.
  """
  def names(context, field) do
    context
    |> Integration.field(field)
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Reads the rows of a node. Each is a map from column to value.

  Returns `{:ok, columns, rows}`, with every row as a list in the order of `columns`.
  """
  def rows(context) do
    case Integration.json(context, "rows") do
      {:ok, %{"rows" => rows}} when is_list(rows) -> to_rows(rows)
      {:ok, %{} = row} -> to_rows([row])
      {:ok, rows} when is_list(rows) -> to_rows(rows)
      {:ok, _other} -> {:error, "Rows: give one object, or a list of objects."}
      {:error, message} -> {:error, message}
    end
  end

  defp to_rows([]), do: {:error, "There are no rows to write."}

  defp to_rows(rows) do
    if Enum.all?(rows, &is_map/1) do
      columns = rows |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()

      {:ok, columns, Enum.map(rows, fn row -> Enum.map(columns, &Map.get(row, &1)) end)}
    else
      {:error, "Rows: each row must be an object, from column to value."}
    end
  end

  @doc """
  Writes `rows` in as many statements as the parameters allow, all or nothing.

  `statement` gets the placeholders of a batch of rows and returns the SQL.
  """
  def write_rows(engine, conn, columns, rows, statement) do
    size = max(div(@max_params, max(length(columns), 1)), 1)

    engine.transaction(conn, fn conn ->
      rows
      |> Enum.chunk_every(size)
      |> Enum.reduce_while({:ok, %{"rows" => [], "count" => 0}}, fn batch, {:ok, total} ->
        marks = marks(engine, batch)

        case query(engine, conn, statement.(marks), List.flatten(batch)) do
          {:ok, answer} -> {:cont, {:ok, merge(total, answer)}}
          {:error, message} -> {:halt, {:error, message}}
        end
      end)
    end)
  end

  defp merge(total, answer) do
    answer
    |> Map.update!("rows", &(total["rows"] ++ &1))
    |> Map.update!("count", &(total["count"] + &1))
  end

  defp marks(engine, rows) do
    {marks, _next} =
      Enum.map_reduce(rows, 1, fn row, next ->
        count = length(row)

        {Enum.map(next..(next + count - 1)//1, &engine.placeholder/1), next + count}
      end)

    marks
  end
end
