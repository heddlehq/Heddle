defmodule HeddleNodes.Nodes.DynamoDB.UpdateItem do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.DynamoDB

  definition do
    DynamoDB.definition(
      "Update Item",
      "Changes some attributes of an item, and leaves the others as they are.",
      [
        DynamoDB.table_field(),
        DynamoDB.key_field(),
        %{type: :textarea, name: :changes, label: "New values", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    DynamoDB.run(context, fn dynamodb ->
      with {:ok, table} <- DynamoDB.table(context),
           {:ok, key} <- DynamoDB.item(context, "item_key"),
           {:ok, changes} <- changes(context),
           {:ok, body} <- DynamoDB.call(dynamodb, "UpdateItem", request(table, key, changes)) do
        {:ok, %{"item" => DynamoDB.from_item(body["Attributes"] || %{})}}
      end
    end)
  end

  defp changes(context) do
    case Integration.json(context, "changes") do
      {:ok, %{} = changes} when map_size(changes) > 0 -> {:ok, Enum.with_index(changes)}
      {:ok, _other} -> {:error, "New values: give an object, from attribute to value."}
      {:error, message} -> {:error, message}
    end
  end

  # Names go through #n0 and values through :v0, so a reserved word like `name` works.
  defp request(table, key, changes) do
    %{
      TableName: table,
      Key: key,
      UpdateExpression: "SET " <> Enum.map_join(changes, ", ", &assignment/1),
      ExpressionAttributeNames: Map.new(changes, fn {{name, _value}, i} -> {"#n#{i}", name} end),
      ExpressionAttributeValues:
        changes
        |> Map.new(fn {{_name, value}, i} -> {"v#{i}", value} end)
        |> DynamoDB.to_item()
        |> Map.new(fn {name, value} -> {":" <> name, value} end),
      ReturnValues: "ALL_NEW"
    }
  end

  defp assignment({{_name, _value}, index}), do: "#n#{index} = :v#{index}"
end
