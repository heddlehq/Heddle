defmodule HeddleNodes.Services.Sql.Options do
  @moduledoc """
  What the engines have in common: reading a credential, writing the statements that
  look the same in most dialects, and converting the values of a run.
  """

  alias HeddleNodes.Connections
  alias HeddleNodes.Integration

  @timeout :timer.minutes(2)
  @connect_timeout :timer.seconds(15)
  @pool_size 5
  # A plain number. Anything else, like 1e999999999, could make Decimal allocate without end.
  @decimal ~r/\A-?\d{1,100}(\.\d{1,100})?\z/

  def timeout, do: [timeout: @timeout]

  def pool do
    [
      pool_size: @pool_size,
      timeout: @timeout,
      connect_timeout: @connect_timeout,
      # Runs wait for a connection instead of failing when the pool is busy.
      queue_target: 10_000,
      queue_interval: 60_000
    ]
  end

  def host(values) do
    case String.trim(values["host"] || "") do
      "" -> "localhost"
      host -> host
    end
  end

  def port(values, default) do
    case Integer.parse(to_string(values["port"])) do
      {port, ""} -> port
      _other -> default
    end
  end

  @doc """
  Returns the TLS options of a credential, or nil when it doesn't use TLS.
  """
  def ssl(values) do
    case values["ssl"] do
      "verify" -> Integration.tls_options(host(values))
      "require" -> [verify: :verify_none]
      _off -> nil
    end
  end

  @doc """
  Tries a connection before starting the pool, to learn why it fails. See
  `HeddleNodes.Connections.check/1`.
  """
  def start(protocol, options, start_link) do
    check = fn ->
      case protocol.connect(options) do
        {:ok, state} ->
          protocol.disconnect(%RuntimeError{message: "checked"}, state)
          :ok

        {:error, error} ->
          {:error, Exception.message(error)}
      end
    end

    with :ok <- Connections.check(check), do: start_link.(options)
  end

  def transaction(conn, fun) do
    case DBConnection.transaction(conn, &commit_or_rollback(&1, fun), timeout()) do
      {:ok, result} -> {:ok, result}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, %_{} = error} -> {:error, Exception.message(error)}
      {:error, reason} -> {:error, "The transaction failed: #{inspect(reason)}"}
    end
  end

  defp commit_or_rollback(conn, fun) do
    case fun.(conn) do
      {:ok, result} -> result
      {:error, message} -> DBConnection.rollback(conn, message)
    end
  end

  def quote(name, quote) do
    <<quote, String.replace(name, <<quote>>, <<quote, quote>>)::binary, quote>>
  end

  def insert(table, columns, rows, quote_name) do
    "INSERT INTO #{table} (#{Enum.map_join(columns, ", ", quote_name)}) VALUES #{tuples(rows)}"
  end

  def tuples(rows) do
    Enum.map_join(rows, ", ", fn row -> "(#{Enum.join(row, ", ")})" end)
  end

  def on_conflict(columns, keys, quote_name) do
    target = Enum.map_join(keys, ", ", quote_name)

    case columns -- keys do
      [] ->
        " ON CONFLICT (#{target}) DO NOTHING"

      updated ->
        changes =
          Enum.map_join(updated, ", ", &"#{quote_name.(&1)} = EXCLUDED.#{quote_name.(&1)}")

        " ON CONFLICT (#{target}) DO UPDATE SET #{changes}"
    end
  end

  @doc """
  Splits a quoted table into its schema and name, without the quotes.
  """
  def schema_and_table(table) do
    case table |> String.split(".") |> Enum.map(&unquoted/1) do
      [schema, name] -> {schema, name}
      [name] -> {nil, name}
      parts -> {Enum.at(parts, -2), List.last(parts)}
    end
  end

  defp unquoted(name) do
    name
    |> String.trim(~s("))
    |> String.trim("`")
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
  end

  def to_text(value) when is_binary(value), do: value
  def to_text(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  def to_text(value), do: to_string(value)

  def to_integer(value) when is_integer(value), do: {:ok, value}
  def to_integer(value) when is_float(value) and trunc(value) == value, do: {:ok, trunc(value)}

  def to_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _other -> :error
    end
  end

  def to_integer(_value), do: :error

  def to_float(value) when is_number(value), do: {:ok, value / 1}

  def to_float(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _other -> :error
    end
  end

  def to_float(_value), do: :error

  def to_decimal(value) when is_integer(value), do: {:ok, Decimal.new(value)}
  def to_decimal(value) when is_float(value), do: {:ok, Decimal.from_float(value)}

  def to_decimal(value) when is_binary(value) do
    value = String.trim(value)

    if value =~ @decimal, do: {:ok, Decimal.new(value)}, else: :error
  end

  def to_decimal(_value), do: :error

  def to_boolean(value) when is_boolean(value), do: {:ok, value}
  def to_boolean(value) when value in ["true", "t", "1", 1], do: {:ok, true}
  def to_boolean(value) when value in ["false", "f", "0", 0], do: {:ok, false}
  def to_boolean(_value), do: :error

  def parse(value, parser) when is_binary(value) do
    case parser.(String.trim(value)) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _reason} -> :error
    end
  end

  def parse(_value, _parser), do: :error

  def to_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(String.trim(value)) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> naive_to_utc(value)
    end
  end

  def to_datetime(_value), do: :error

  defp naive_to_utc(value) do
    case NaiveDateTime.from_iso8601(String.trim(value)) do
      {:ok, naive} -> {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
      {:error, _reason} -> parse(value, &date_to_utc/1)
    end
  end

  defp date_to_utc(value) do
    with {:ok, date} <- Date.from_iso8601(value) do
      {:ok, DateTime.new!(date, ~T[00:00:00])}
    end
  end

  def from_json(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> value
    end
  end

  def from_json(value), do: value
end
