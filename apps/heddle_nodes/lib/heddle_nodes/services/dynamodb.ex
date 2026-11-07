defmodule HeddleNodes.Services.DynamoDB do
  @moduledoc """
  Amazon DynamoDB, for the DynamoDB nodes.

  Items are plain JSON in a flow, and this writes the typed form the API takes.
  """

  alias HeddleNodes.Integration

  @timeout :timer.minutes(1)
  @service %{
    title: "DynamoDB",
    category: :database,
    group: "DynamoDB",
    credential: "dynamodb",
    icon: "logo-dynamodb"
  }

  def definition(action, description, fields) do
    Integration.definition(@service, action, description, fields)
  end

  def table_field, do: %{type: :text, name: :table, label: "Table", default: ""}

  def key_field do
    %{type: :textarea, name: :item_key, label: "Key", default: ~s({"id": "{{id}}"})}
  end

  def run(context, fun), do: Integration.run(context, "dynamodb", fun)

  def table(context) do
    case context |> Integration.field("table") |> String.trim() do
      "" -> {:error, "Pick a table."}
      table -> {:ok, table}
    end
  end

  @doc """
  Reads a field with an object and returns its typed form.
  """
  def item(context, name) do
    case Integration.json(context, name) do
      {:ok, %{} = item} when map_size(item) > 0 ->
        {:ok, to_item(item)}

      {:ok, _other} ->
        {:error, "#{name |> String.replace("_", " ") |> String.capitalize()}: give an object."}

      {:error, message} ->
        {:error, message}
    end
  end

  @doc """
  Calls an action of the API.
  """
  def call(dynamodb, action, body) do
    request =
      Integration.req_options(
        method: :post,
        url: url(dynamodb),
        headers: [
          {"x-amz-target", "DynamoDB_20120810.#{action}"},
          {"content-type", "application/x-amz-json-1.0"}
        ],
        body: Jason.encode!(body),
        aws_sigv4: signature(dynamodb),
        decode_body: false,
        receive_timeout: @timeout
      )

    case Req.request(request) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, "DynamoDB answered #{status}#{message(body)}"}

      {:error, reason} ->
        {:error, "Could not reach DynamoDB: #{Exception.message(reason)}"}
    end
  end

  defp url(dynamodb) do
    case String.trim(dynamodb["endpoint"] || "") do
      "" -> "https://dynamodb.#{region(dynamodb)}.amazonaws.com/"
      endpoint -> String.trim_trailing(endpoint, "/") <> "/"
    end
  end

  defp signature(dynamodb) do
    [
      access_key_id: dynamodb["access_key_id"],
      secret_access_key: dynamodb["secret_access_key"],
      region: region(dynamodb),
      service: :dynamodb
    ]
  end

  defp region(dynamodb) do
    case dynamodb["region"] do
      value when value in [nil, ""] -> "us-east-1"
      value -> value
    end
  end

  defp message(body) do
    case Jason.decode(body) do
      {:ok, %{"message" => message}} -> ": #{message}"
      {:ok, %{"Message" => message}} -> ": #{message}"
      _other -> ""
    end
  end

  def to_item(map), do: Map.new(map, fn {key, value} -> {key, to_attribute(value)} end)

  defp to_attribute(nil), do: %{"NULL" => true}
  defp to_attribute(value) when is_boolean(value), do: %{"BOOL" => value}
  defp to_attribute(value) when is_number(value), do: %{"N" => to_string(value)}
  defp to_attribute(value) when is_binary(value), do: %{"S" => value}
  defp to_attribute(value) when is_list(value), do: %{"L" => Enum.map(value, &to_attribute/1)}
  defp to_attribute(%{} = value), do: %{"M" => to_item(value)}

  def from_item(item), do: Map.new(item, fn {key, value} -> {key, from_attribute(value)} end)

  defp from_attribute(%{"S" => value}), do: value
  defp from_attribute(%{"N" => value}), do: to_number(value)
  defp from_attribute(%{"BOOL" => value}), do: value
  defp from_attribute(%{"NULL" => _true}), do: nil
  defp from_attribute(%{"L" => values}), do: Enum.map(values, &from_attribute/1)
  defp from_attribute(%{"M" => value}), do: from_item(value)
  defp from_attribute(%{"SS" => values}), do: values
  defp from_attribute(%{"NS" => values}), do: Enum.map(values, &to_number/1)
  defp from_attribute(%{"BS" => values}), do: values
  defp from_attribute(%{"B" => value}), do: value

  defp to_number(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _float -> String.to_float(value)
    end
  rescue
    ArgumentError -> value
  end
end
