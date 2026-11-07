defmodule HeddleNodes.Services.Sql.SqlServer do
  @moduledoc """
  Microsoft SQL Server and Azure SQL.
  """

  @behaviour HeddleNodes.Services.Sql.Engine

  alias HeddleNodes.Services.Sql.Options

  @impl true
  def connect(values) do
    options =
      [
        hostname: Options.host(values),
        port: Options.port(values, 1433),
        database: values["database"],
        username: values["username"],
        password: values["password"],
        ssl: Options.ssl(values) != nil,
        ssl_opts: Options.ssl(values) || [],
        use_elixir_calendar_types: true
      ] ++ Options.pool()

    Options.start(Tds.Protocol, options, &Tds.start_link/1)
  end

  @impl true
  def query(conn, sql, params) do
    case Tds.query(conn, sql, to_params(params), Options.timeout()) do
      {:ok, result} ->
        {:ok,
         %{
           columns: result.columns || [],
           rows: Enum.map(result.rows || [], &read_uuids/1),
           count: result.num_rows
         }}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  rescue
    error in [DBConnection.EncodeError, ArgumentError] -> {:error, Exception.message(error)}
  end

  defp to_params(params) do
    params
    |> Enum.with_index(1)
    |> Enum.map(fn {value, position} ->
      %Tds.Parameter{name: placeholder(position), value: to_param(value), type: type(value)}
    end)
  end

  defp to_param(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp to_param(value), do: value

  # The driver can't guess the type of a NULL.
  defp type(nil), do: :string
  defp type(_value), do: nil

  # A uniqueidentifier comes as 16 raw bytes, and a run can't do anything with those.
  defp read_uuids(row) do
    Enum.map(row, fn
      <<a::little-32, b::little-16, c::little-16, d::binary-2, e::binary-6>> = value ->
        if String.printable?(value), do: value, else: uuid_text(a, b, c, d, e)

      value ->
        value
    end)
  end

  defp uuid_text(a, b, c, d, e) do
    [<<a::32>>, <<b::16>>, <<c::16>>, d, e]
    |> Enum.map_join("-", &Base.encode16(&1, case: :lower))
  end

  @impl true
  def transaction(conn, fun), do: Options.transaction(conn, fun)

  @impl true
  def placeholder(position), do: "@#{position}"

  @impl true
  def quote_name(name), do: "[#{String.replace(name, "]", "]]")}]"

  @impl true
  def strings, do: [?']

  # OFFSET needs an ORDER BY, even one that orders nothing.
  @impl true
  def paginate(sql, order_by?, limit, offset) do
    order = if order_by?, do: "", else: " ORDER BY (SELECT NULL)"

    "#{sql}#{order} OFFSET #{offset} ROWS FETCH NEXT #{limit} ROWS ONLY"
  end

  @impl true
  def insert(table, columns, rows) do
    "INSERT INTO #{table} (#{Enum.map_join(columns, ", ", &quote_name/1)}) OUTPUT INSERTED.* " <>
      "VALUES #{Options.tuples(rows)}"
  end

  @impl true
  def upsert(table, columns, rows, keys) do
    names = Enum.map_join(columns, ", ", &quote_name/1)
    match = Enum.map_join(keys, " AND ", &"t.#{quote_name(&1)} = s.#{quote_name(&1)}")
    inserted = Enum.map_join(columns, ", ", &"s.#{quote_name(&1)}")

    "MERGE INTO #{table} AS t USING (VALUES #{Options.tuples(rows)}) AS s (#{names}) " <>
      "ON #{match} #{update(columns -- keys)}" <>
      "WHEN NOT MATCHED THEN INSERT (#{names}) VALUES (#{inserted}) OUTPUT INSERTED.*;"
  end

  defp update([]), do: ""

  defp update(columns) do
    changes = Enum.map_join(columns, ", ", &"#{quote_name(&1)} = s.#{quote_name(&1)}")

    "WHEN MATCHED THEN UPDATE SET #{changes} "
  end

  @impl true
  def tables do
    {"SELECT TABLE_SCHEMA + '.' + TABLE_NAME AS name FROM INFORMATION_SCHEMA.TABLES ORDER BY 1",
     []}
  end

  @impl true
  def columns(table) do
    {schema, name} = Options.schema_and_table(table)

    {"SELECT COLUMN_NAME AS name, DATA_TYPE AS type, " <>
       "CAST(CASE IS_NULLABLE WHEN 'YES' THEN 1 ELSE 0 END AS bit) AS nullable, " <>
       "COLUMN_DEFAULT AS [default] FROM INFORMATION_SCHEMA.COLUMNS " <>
       "WHERE TABLE_NAME = @1 AND TABLE_SCHEMA = COALESCE(@2, SCHEMA_NAME()) " <>
       "ORDER BY ORDINAL_POSITION", [name, schema]}
  end
end
