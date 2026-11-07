defmodule HeddleNodes.Services.Cassandra do
  @moduledoc """
  Apache Cassandra and ScyllaDB, for the Cassandra nodes.

  A statement is prepared first, so a value can be converted to the type of its column,
  as a run mostly holds text.
  """

  alias HeddleNodes.Connections
  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Sql.{Options, Statement}

  @timeout :timer.minutes(2)
  @connect_timeout :timer.seconds(15)
  @max_rows 10_000
  @service %{
    title: "Cassandra",
    category: :database,
    group: "Cassandra",
    credential: "cassandra",
    icon: "logo-cassandra"
  }

  def definition(action, description, fields) do
    Integration.definition(@service, action, description, fields)
  end

  def run(context, fun) do
    Integration.run(context, "cassandra", fn values ->
      Connections.with_connection(values, fn -> connect(values) end, fun)
    end)
  end

  defp connect(values) do
    options =
      [
        nodes: hosts(values),
        sync_connect: @connect_timeout,
        target_pools: 1,
        pool_size: 2
      ] ++ keyspace(values) ++ authentication(values) ++ encryption(values)

    with :ok <- Connections.check(fn -> check(options) end) do
      Xandra.Cluster.start_link(options)
    end
  end

  defp check(options) do
    case Xandra.Cluster.start_link(options) do
      {:ok, cluster} ->
        Xandra.Cluster.stop(cluster)
        :ok

      {:error, :sync_connect_timeout} ->
        {:error, "no node of the cluster answered."}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp hosts(values) do
    values["hosts"]
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp keyspace(values) do
    case String.trim(values["keyspace"] || "") do
      "" -> []
      keyspace -> [keyspace: keyspace]
    end
  end

  defp authentication(%{"username" => username, "password" => password}) when username != "" do
    [authentication: {Xandra.Authenticator.Password, username: username, password: password}]
  end

  defp authentication(_values), do: []

  defp encryption(%{"ssl" => "verify"} = values) do
    host = values |> hosts() |> hd() |> String.split(":") |> hd()

    [encryption: true, transport_options: Integration.tls_options(host)]
  end

  defp encryption(%{"ssl" => "require"}) do
    [encryption: true, transport_options: [verify: :verify_none]]
  end

  defp encryption(_values), do: []

  @doc """
  Binds what a field holds and runs it.
  """
  def execute(conn, template, context) do
    with {:ok, cql, params} <- Statement.bind(template, context, fn _position -> "?" end),
         {:ok, prepared} <- prepare(conn, cql),
         {:ok, params} <- coerce(prepared.bound_columns, params) do
      conn
      |> Xandra.Cluster.execute(prepared, params,
        timeout: @timeout,
        page_size: @max_rows + 1,
        decimal_format: :decimal
      )
      |> answer()
    end
  end

  defp prepare(conn, cql) do
    case Xandra.Cluster.prepare(conn, cql, timeout: @timeout) do
      {:ok, prepared} -> {:ok, prepared}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  defp answer({:ok, %Xandra.Page{} = page}) do
    rows = Enum.to_list(page)

    if length(rows) > @max_rows do
      {:error, "The query returned more than #{@max_rows} rows. Use a LIMIT."}
    else
      {:ok, %{"rows" => Enum.map(rows, &Integration.to_value/1), "count" => length(rows)}}
    end
  end

  defp answer({:ok, _void}), do: {:ok, %{"rows" => [], "count" => 0}}
  defp answer({:error, error}), do: {:error, Exception.message(error)}

  defp coerce(columns, params) do
    columns
    |> Enum.zip(params)
    |> Enum.reduce_while({:ok, []}, fn {{_keyspace, _table, name, type}, value}, {:ok, values} ->
      case to_type(type, value) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        :error -> {:halt, {:error, "#{inspect(value)} doesn't fit the column #{name}."}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp to_type(_type, nil), do: {:ok, nil}

  defp to_type(type, value) when type in [:int, :bigint, :smallint, :tinyint, :counter, :varint],
    do: Options.to_integer(value)

  defp to_type(type, value) when type in [:double, :float], do: Options.to_float(value)
  defp to_type(:decimal, value), do: Options.to_decimal(value)
  defp to_type(:boolean, value), do: Options.to_boolean(value)
  defp to_type(:timestamp, value), do: Options.to_datetime(value)
  defp to_type(:date, value), do: Options.parse(value, &Date.from_iso8601/1)

  defp to_type(type, value) when type in [:text, :varchar, :ascii],
    do: {:ok, Options.to_text(value)}

  defp to_type({:set, [type]}, value) when is_list(value),
    do: to_items(type, value, &MapSet.new/1)

  defp to_type({:list, [type]}, value) when is_list(value), do: to_items(type, value, & &1)
  defp to_type(_type, value), do: {:ok, value}

  defp to_items(type, values, wrap) do
    items = Enum.map(values, &to_type(type, &1))

    if Enum.all?(items, &match?({:ok, _item}, &1)) do
      {:ok, wrap.(Enum.map(items, fn {:ok, item} -> item end))}
    else
      :error
    end
  end
end
