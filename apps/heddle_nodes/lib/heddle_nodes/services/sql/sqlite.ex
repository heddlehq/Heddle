defmodule HeddleNodes.Services.Sql.SQLite do
  @moduledoc """
  SQLite. The database of the credential is the path of a file on the server.
  """

  @behaviour HeddleNodes.Services.Sql.Engine

  alias HeddleNodes.Services.Sql.Options

  @impl true
  def connect(values) do
    case String.trim(values["database"] || "") do
      "" -> {:error, "Write the path of the SQLite file in the credential's Database field."}
      path -> open(path)
    end
  end

  # One connection: SQLite writes one at a time, so more would only wait for each other.
  # The journal mode stays as it is, because the file may belong to another program.
  defp open(path) do
    options = [database: path, busy_timeout: 5000, pool_size: 1]

    Options.start(Exqlite.Connection, options, &Exqlite.start_link/1)
  end

  @impl true
  def query(conn, sql, params) do
    DBConnection.run(conn, fn conn ->
      case Exqlite.query(conn, sql, Enum.map(params, &to_param/1), Options.timeout()) do
        {:ok, result} ->
          rows = result.rows || []

          {:ok, %{columns: result.columns || [], rows: rows, count: count(conn, sql, rows)}}

        {:error, error} ->
          {:error, Exception.message(error)}
      end
    end)
  rescue
    error in [DBConnection.EncodeError, ArgumentError] -> {:error, Exception.message(error)}
  end

  # A statement that returns nothing only says what it changed if it's asked.
  defp count(conn, sql, []) do
    if sql =~ ~r/\A\s*(INSERT|UPDATE|DELETE|REPLACE)\b/i do
      {:ok, %{rows: [[changes]]}} = Exqlite.query(conn, "SELECT changes()", [])
      changes
    else
      0
    end
  end

  defp count(_conn, _sql, rows), do: length(rows)

  defp to_param(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp to_param(true), do: 1
  defp to_param(false), do: 0
  defp to_param(value), do: value

  @impl true
  def transaction(conn, fun), do: Options.transaction(conn, fun)

  @impl true
  def placeholder(position), do: "?#{position}"

  @impl true
  def quote_name(name), do: Options.quote(name, ?")

  @impl true
  def strings, do: [?']

  @impl true
  def paginate(sql, _order_by?, limit, offset), do: "#{sql} LIMIT #{limit} OFFSET #{offset}"

  @impl true
  def insert(table, columns, rows) do
    Options.insert(table, columns, rows, &quote_name/1) <> " RETURNING *"
  end

  @impl true
  def upsert(table, columns, rows, keys) do
    Options.insert(table, columns, rows, &quote_name/1) <>
      Options.on_conflict(columns, keys, &quote_name/1) <> " RETURNING *"
  end

  @impl true
  def tables do
    {"SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' " <>
       "ORDER BY 1", []}
  end

  @impl true
  def columns(table) do
    {_schema, name} = Options.schema_and_table(table)

    {"SELECT name, type, \"notnull\" = 0 AND pk = 0 AS nullable, dflt_value AS \"default\" " <>
       "FROM pragma_table_info(?1)", [name]}
  end
end
