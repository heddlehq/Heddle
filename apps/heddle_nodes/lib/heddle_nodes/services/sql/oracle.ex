defmodule HeddleNodes.Services.Sql.Oracle do
  @moduledoc """
  Oracle Database. The database of the credential is its service name, or `:SID`.
  """

  @behaviour HeddleNodes.Services.Sql.Engine

  alias HeddleNodes.Services.Sql.Options

  @impl true
  def connect(values) do
    options =
      [
        hostname: Options.host(values),
        port: Options.port(values, 1521),
        database: values["database"],
        username: values["username"],
        password: values["password"],
        socket_options: socket_options(values),
        parameters: [autocommit: 0]
      ] ++ Options.pool()

    Options.start(Jamdb.Oracle, options, &Jamdb.Oracle.start_link/1)
  end

  defp socket_options(values) do
    case Options.ssl(values) do
      nil -> []
      options -> [ssl: options]
    end
  end

  # Committing each statement on its own would undo the savepoint of a transaction, so
  # autocommit is off and a statement outside of one gets a transaction of its own.
  @impl true
  def query(conn, sql, params) do
    Options.transaction(conn, &run(&1, sql, params))
  end

  defp run(conn, sql, params) do
    query = %Jamdb.Oracle.Query{statement: uncached(sql)}

    case DBConnection.prepare_execute(conn, query, to_params(params), Options.timeout()) do
      {:ok, _query, result} ->
        rows = result[:rows] || []

        {:ok,
         %{columns: column_names(result), rows: rows, count: result[:num_rows] || length(rows)}}

      {:error, error} ->
        {:error, describe(error)}
    end
  rescue
    error in [DBConnection.EncodeError, ArgumentError] -> {:error, Exception.message(error)}
  end

  # The driver keeps a cursor per text of a statement, and running the same DROP or
  # CREATE again through it answers for the first time it ran.
  defp uncached(sql) do
    if sql =~ ~r/\A\s*(CREATE|DROP|ALTER|TRUNCATE)\b/i do
      "/* #{System.unique_integer([:positive])} */ #{sql}"
    else
      sql
    end
  end

  # The driver hands the server's text over as a printed charlist.
  defp describe(error) do
    error
    |> Exception.message()
    |> String.trim_leading("~c\"")
    |> String.trim_trailing("\"")
    |> String.replace("\\n", "")
    |> String.replace("\\\"", "\"")
    |> String.trim()
  end

  defp column_names(result) do
    Enum.map(result[:columns] || [], &(&1 |> to_string() |> String.downcase()))
  end

  defp to_params(params) do
    Enum.map(params, fn
      value when is_map(value) or is_list(value) -> Jason.encode!(value)
      value -> value
    end)
  end

  @impl true
  def transaction(conn, fun), do: Options.transaction(conn, fun)

  @impl true
  def placeholder(position), do: ":#{position}"

  # Oracle keeps a name written without quotes in capitals, so `items` means ITEMS.
  @impl true
  def quote_name(name) do
    name = if name == String.downcase(name), do: String.upcase(name), else: name

    Options.quote(name, ?")
  end

  @impl true
  def strings, do: [?']

  @impl true
  def paginate(sql, _order_by?, limit, offset) do
    "#{sql} OFFSET #{offset} ROWS FETCH NEXT #{limit} ROWS ONLY"
  end

  # Oracle has no VALUES with several rows, so they come from a SELECT.
  @impl true
  def insert(table, columns, rows) do
    "INSERT INTO #{table} (#{Enum.map_join(columns, ", ", &quote_name/1)}) #{selects(rows)}"
  end

  @impl true
  def upsert(table, columns, rows, keys) do
    names = Enum.map_join(columns, ", ", &quote_name/1)
    match = Enum.map_join(keys, " AND ", &"t.#{quote_name(&1)} = s.#{quote_name(&1)}")
    inserted = Enum.map_join(columns, ", ", &"s.#{quote_name(&1)}")

    "MERGE INTO #{table} t USING (#{selects(rows, columns)}) s ON (#{match}) " <>
      "#{update(columns -- keys)}WHEN NOT MATCHED THEN INSERT (#{names}) VALUES (#{inserted})"
  end

  defp update([]), do: ""

  defp update(columns) do
    changes = Enum.map_join(columns, ", ", &"t.#{quote_name(&1)} = s.#{quote_name(&1)}")

    "WHEN MATCHED THEN UPDATE SET #{changes} "
  end

  defp selects(rows, columns \\ nil) do
    Enum.map_join(rows, " UNION ALL ", fn row ->
      "SELECT #{select_list(row, columns)} FROM dual"
    end)
  end

  defp select_list(row, nil), do: Enum.join(row, ", ")

  defp select_list(row, columns) do
    row
    |> Enum.zip(columns)
    |> Enum.map_join(", ", fn {mark, column} -> "#{mark} AS #{quote_name(column)}" end)
  end

  @impl true
  def tables, do: {"SELECT table_name AS name FROM user_tables ORDER BY 1", []}

  @impl true
  def columns(table) do
    {_schema, name} = Options.schema_and_table(table)

    {"SELECT column_name AS name, data_type AS type, " <>
       "CASE nullable WHEN 'Y' THEN 1 ELSE 0 END AS nullable, data_default AS \"default\" " <>
       "FROM user_tab_columns WHERE table_name = :1 ORDER BY column_id", [name]}
  end
end
