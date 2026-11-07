defmodule HeddleNodes.Services.MongoDB do
  @moduledoc """
  MongoDB and what speaks its protocol, like DocumentDB and Cosmos DB, for the MongoDB
  nodes. Filters and documents are JSON, and `{"$oid": "..."}` and `{"$date": "..."}`
  write the types JSON doesn't have.
  """

  alias HeddleNodes.Connections
  alias HeddleNodes.Integration

  @timeout :timer.minutes(2)
  @check_timeout :timer.seconds(15)
  @object_id ~r/\A[0-9a-fA-F]{24}\z/
  @max_documents 10_000
  @service %{
    title: "MongoDB",
    category: :database,
    group: "MongoDB",
    credential: "mongodb",
    icon: "logo-mongodb"
  }

  def definition(action, description, fields) do
    Integration.definition(@service, action, description, fields)
  end

  def collection_field, do: %{type: :text, name: :collection, label: "Collection", default: ""}

  def filter_field(default \\ "{}") do
    %{type: :textarea, name: :filter, label: "Filter", default: default}
  end

  def run(context, fun) do
    Integration.run(context, "mongodb", fn values ->
      Connections.with_connection(values, fn -> connect(values) end, &guarded(&1, fun))
    end)
  end

  defp guarded(conn, fun) do
    fun.(conn)
  rescue
    error in [Mongo.Error, Mongo.WriteError, DBConnection.ConnectionError] ->
      {:error, Exception.message(error)}
  end

  defp connect(values) do
    options = [
      url: values["url"],
      database: database(values),
      timeout: @timeout,
      pool_size: 5,
      connect_timeout: 10_000
    ]

    with :ok <- Connections.check(fn -> check(options) end), do: start(options)
  end

  defp database(values) do
    case String.trim(values["database"] || "") do
      "" -> nil
      database -> database
    end
  end

  defp start(options),
    do: options |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Mongo.start_link()

  defp check(options) do
    with {:ok, conn} <- start(options) do
      result = Mongo.command(conn, [ping: 1], checkout_timeout: @check_timeout)
      GenServer.stop(conn)

      case result do
        {:ok, _reply} -> :ok
        {:error, error} -> {:error, Exception.message(error)}
      end
    end
  end

  def collection(context) do
    case context |> Integration.field("collection") |> String.trim() do
      "" -> {:error, "Pick a collection."}
      collection -> {:ok, collection}
    end
  end

  @doc """
  Reads a filter. What a run brings into it is data: a webhook that sends
  `{"$ne": null}` as a password can't turn the filter into something else.
  """
  def filter(context) do
    read(context, "filter", &no_operators/1)
  end

  @doc """
  Reads a field with JSON that's written to the database.
  """
  def document(context, name) do
    read(context, name, fn _value -> :ok end)
  end

  defp read(context, name, check) do
    case String.trim(context[name] || "") do
      "" ->
        {:ok, %{}}

      _template ->
        with {:ok, value} <- Integration.json(context, name, check), do: {:ok, to_bson(value)}
    end
  end

  defp no_operators(value) do
    if operator?(value) do
      {:error, "A value from the run can't hold a query operator, like $ne."}
    else
      :ok
    end
  end

  defp operator?(%{} = value) do
    Enum.any?(value, fn {key, item} ->
      String.starts_with?(to_string(key), "$") or operator?(item)
    end)
  end

  defp operator?(value) when is_list(value), do: Enum.any?(value, &operator?/1)
  defp operator?(_value), do: false

  defp to_bson(%{"$oid" => id}) when is_binary(id), do: object_id(id)

  defp to_bson(%{"$date" => date}) when is_binary(date) do
    case DateTime.from_iso8601(date) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> date
    end
  end

  defp to_bson(%{} = map) do
    Map.new(map, fn
      {"_id", value} -> {"_id", to_id(value)}
      {key, value} -> {key, to_bson(value)}
    end)
  end

  defp to_bson(list) when is_list(list), do: Enum.map(list, &to_bson/1)
  defp to_bson(value), do: value

  # The _id a previous node returned is text, and a filter needs it back as an ObjectId.
  defp to_id(value) when is_binary(value) do
    if value =~ @object_id, do: object_id(value), else: value
  end

  defp to_id(%{"$oid" => _id} = value), do: to_bson(value)
  defp to_id(%{} = value), do: Map.new(value, fn {key, item} -> {key, to_id(item)} end)
  defp to_id(value) when is_list(value), do: Enum.map(value, &to_id/1)
  defp to_id(value), do: value

  defp object_id(id), do: BSON.ObjectId.decode!(id)

  @doc """
  Reads what a cursor returns, or the error it gives.
  """
  def documents({:error, error}), do: {:error, Exception.message(error)}

  def documents(cursor) do
    documents = Enum.take(cursor, @max_documents + 1)

    if length(documents) > @max_documents do
      {:error, "This returned more than #{@max_documents} documents. Use a limit."}
    else
      {:ok, Enum.map(documents, &Integration.to_value/1)}
    end
  end

  def describe({:error, error}), do: {:error, Exception.message(error)}
  def describe(result), do: result
end
