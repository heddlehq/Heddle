defmodule HeddleNodes.Services.Sql.Postgres do
  @moduledoc """
  PostgreSQL, and what speaks its protocol.

  Postgrex is strict about the types of parameters, and a run mostly holds text: a
  webhook sends `"42"` for an integer column. So a statement is prepared first, and
  each value is converted to the type the database asked for.
  """

  @behaviour HeddleNodes.Services.Sql.Engine

  alias HeddleNodes.Services.Sql.Options

  @uuid 2950
  @uuid_array 2951
  @integers [20, 21, 23]
  @floats [700, 701]
  @numeric 1700
  @boolean 16
  @date 1082
  @time 1083
  @timestamp 1114
  @timestamptz 1184
  @json [114, 3802]
  # Array types, and the type of what they hold.
  @arrays %{
    1000 => @boolean,
    1005 => 21,
    1007 => 23,
    1016 => 20,
    1021 => 700,
    1022 => 701,
    1231 => @numeric,
    @uuid_array => @uuid
  }
  @texts [18, 19, 25, 1042, 1043]
  @text_arrays [1009, 1014, 1015]

  @impl true
  def connect(values) do
    options =
      [
        hostname: Options.host(values),
        port: Options.port(values, 5432),
        database: values["database"],
        username: values["username"],
        password: values["password"],
        types: Postgrex.DefaultTypes
      ] ++ ssl(values) ++ Options.pool()

    Options.start(Postgrex.Protocol, Postgrex.Utils.default_opts(options), &Postgrex.start_link/1)
  end

  defp ssl(values) do
    case Options.ssl(values) do
      nil -> [ssl: false]
      options -> [ssl: options]
    end
  end

  @impl true
  def query(conn, sql, params) do
    DBConnection.run(conn, fn conn ->
      with {:ok, query} <- Postgrex.prepare(conn, "", sql, Options.timeout()),
           {:ok, params} <- coerce(query.param_oids, params),
           {:ok, _query, result} <- execute(conn, query, params) do
        {:ok, to_result(query, result)}
      else
        {:error, %_{} = error} -> {:error, Exception.message(error)}
        {:error, message} -> {:error, message}
      end
    end)
  rescue
    error in [DBConnection.EncodeError, ArgumentError] -> {:error, Exception.message(error)}
  end

  defp execute(conn, query, params) do
    case Postgrex.execute(conn, query, params, Options.timeout()) do
      {:ok, query, result} -> {:ok, query, result}
      {:error, error} -> {:error, error}
    end
  end

  defp to_result(query, result) do
    uuids = Enum.map(query.result_oids || [], &(&1 in [@uuid, @uuid_array]))

    %{
      columns: result.columns || [],
      rows: Enum.map(result.rows || [], &read_uuids(&1, uuids)),
      count: result.num_rows
    }
  end

  defp read_uuids(row, uuids) do
    row
    |> Enum.zip(uuids)
    |> Enum.map(fn
      {value, true} -> uuid_text(value)
      {value, false} -> value
    end)
  end

  defp uuid_text(values) when is_list(values), do: Enum.map(values, &uuid_text/1)

  defp uuid_text(<<a::binary-4, b::binary-2, c::binary-2, d::binary-2, e::binary-6>>) do
    [a, b, c, d, e] |> Enum.map_join("-", &Base.encode16(&1, case: :lower))
  end

  defp uuid_text(value), do: value

  defp coerce(oids, params) do
    oids
    |> Enum.zip(params)
    |> Enum.reduce_while({:ok, []}, fn {oid, value}, {:ok, values} ->
      case to_type(oid, value) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        :error -> {:halt, {:error, "#{inspect(value)} doesn't fit the type of its column."}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp to_type(_oid, nil), do: {:ok, nil}
  defp to_type(oid, value) when oid in @integers, do: Options.to_integer(value)
  defp to_type(oid, value) when oid in @floats, do: Options.to_float(value)
  defp to_type(@numeric, value), do: Options.to_decimal(value)
  defp to_type(@boolean, value), do: Options.to_boolean(value)
  defp to_type(@date, value), do: Options.parse(value, &Date.from_iso8601/1)
  defp to_type(@time, value), do: Options.parse(value, &Time.from_iso8601/1)
  defp to_type(@timestamp, value), do: Options.parse(value, &NaiveDateTime.from_iso8601/1)
  defp to_type(@timestamptz, value), do: Options.to_datetime(value)
  defp to_type(@uuid, value), do: uuid_binary(value)
  defp to_type(oid, value) when oid in @json, do: {:ok, Options.from_json(value)}
  defp to_type(oid, value) when oid in @texts, do: {:ok, Options.to_text(value)}

  defp to_type(oid, value) when oid in @text_arrays and is_list(value) do
    {:ok, Enum.map(value, &Options.to_text/1)}
  end

  defp to_type(oid, value) when is_map_key(@arrays, oid) and is_list(value) do
    items = Enum.map(value, &to_type(@arrays[oid], &1))

    if Enum.all?(items, &match?({:ok, _item}, &1)) do
      {:ok, Enum.map(items, fn {:ok, item} -> item end)}
    else
      :error
    end
  end

  defp to_type(_oid, value), do: {:ok, value}

  defp uuid_binary(<<_::binary-16>> = value), do: {:ok, value}

  defp uuid_binary(value) when is_binary(value) do
    value |> String.replace("-", "") |> Base.decode16(case: :mixed)
  end

  defp uuid_binary(_value), do: :error

  @impl true
  def transaction(conn, fun), do: Options.transaction(conn, fun)

  @impl true
  def placeholder(position), do: "$#{position}"

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
    {"SELECT table_schema || '.' || table_name AS name FROM information_schema.tables " <>
       "WHERE table_schema NOT IN ('pg_catalog', 'information_schema') ORDER BY 1", []}
  end

  @impl true
  def columns(table) do
    {schema, name} = Options.schema_and_table(table)

    {"SELECT column_name AS name, data_type AS type, is_nullable = 'YES' AS nullable, " <>
       "column_default AS \"default\" FROM information_schema.columns " <>
       "WHERE table_name = $1 AND table_schema = COALESCE($2, current_schema()) " <>
       "ORDER BY ordinal_position", [name, schema]}
  end
end
