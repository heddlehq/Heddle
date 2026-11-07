defmodule HeddleNodes.Nodes.DynamoDB.GetItem do
  use Bobbin.Node

  alias HeddleNodes.Services.DynamoDB

  definition do
    DynamoDB.definition(
      "Get Item",
      "Reads an item by its key.",
      [DynamoDB.table_field(), DynamoDB.key_field()]
    )
  end

  @impl true
  def handler(context, _input) do
    DynamoDB.run(context, fn dynamodb ->
      with {:ok, table} <- DynamoDB.table(context),
           {:ok, key} <- DynamoDB.item(context, "item_key"),
           {:ok, body} <- DynamoDB.call(dynamodb, "GetItem", %{TableName: table, Key: key}) do
        case body do
          %{"Item" => item} -> {:ok, %{"item" => DynamoDB.from_item(item), "found" => true}}
          _nothing -> {:ok, %{"item" => nil, "found" => false}}
        end
      end
    end)
  end
end
