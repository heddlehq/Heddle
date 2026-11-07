defmodule HeddleNodes.Services.Sql.MySQL do
  @moduledoc """
  MySQL, MariaDB and what speaks their protocol.
  """

  @behaviour HeddleNodes.Services.Sql.Engine

  alias HeddleNodes.Services.Sql.Options

  @impl true
  def connect(values) do
    options =
      [
        hostname: Options.host(values),
        port: Options.port(values, 3306),
        database: values["database"],
        username: values["username"],
        password: values["password"],
        ssl: Options.ssl(values) != nil,
        ssl_opts: Options.ssl(values) || [],
        disconnect_on_error_codes: []
      ] ++ Options.pool()

    Options.start(MyXQL.Connection, options, &MyXQL.start_link/1)
  end

  @impl true
  def query(conn, sql, params) do
    case MyXQL.query(conn, sql, Enum.map(params, &to_param/1), Options.timeout()) do
      {:ok, result} ->
        {:ok,
         %{
           columns: result.columns || [],
           rows: result.rows || [],
           count: result.num_rows,
           last_id: result.last_insert_id
         }}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  rescue
    error in [DBConnection.EncodeError, ArgumentError] -> {:error, Exception.message(error)}
  end

  defp to_param(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp to_param(value), do: value

  @impl true
  def transaction(conn, fun), do: Options.transaction(conn, fun)

  @impl true
  def placeholder(_position), do: "?"

  @impl true
  def quote_name(name), do: Options.quote(name, ?`)

  @impl true
  def strings, do: [?', ?"]

  @impl true
  def paginate(sql, _order_by?, limit, offset), do: "#{sql} LIMIT #{limit} OFFSET #{offset}"

  @impl true
  def insert(table, columns, rows), do: Options.insert(table, columns, rows, &quote_name/1)

  @impl true
  def upsert(table, columns, rows, keys) do
    updated = columns -- keys
    changes = Enum.map_join(updated, ", ", &"#{quote_name(&1)} = VALUES(#{quote_name(&1)})")
    # Updating a key to itself keeps the row as it is, when there's nothing else to update.
    changes =
      if updated == [], do: "#{quote_name(hd(keys))} = #{quote_name(hd(keys))}", else: changes

    insert(table, columns, rows) <> " ON DUPLICATE KEY UPDATE #{changes}"
  end

  @impl true
  def tables do
    {"SELECT table_name AS name FROM information_schema.tables " <>
       "WHERE table_schema = DATABASE() ORDER BY 1", []}
  end

  @impl true
  def columns(table) do
    {schema, name} = Options.schema_and_table(table)

    {"SELECT column_name AS name, column_type AS type, is_nullable = 'YES' AS nullable, " <>
       "column_default AS `default` FROM information_schema.columns " <>
       "WHERE table_name = ? AND table_schema = COALESCE(?, DATABASE()) " <>
       "ORDER BY ordinal_position", [name, schema]}
  end
end
