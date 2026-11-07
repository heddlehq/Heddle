defmodule HeddleNodes.Nodes.DynamoDB.PutItem do
  use Bobbin.Node

  alias HeddleNodes.Services.DynamoDB

  definition do
    DynamoDB.definition(
      "Put Item",
      "Saves an item, and replaces the one with the same key.",
      [
        DynamoDB.table_field(),
        %{type: :textarea, name: :item_data, label: "Item", default: "{{result}}"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    DynamoDB.run(context, fn dynamodb ->
      with {:ok, table} <- DynamoDB.table(context),
           {:ok, item} <- DynamoDB.item(context, "item_data"),
           {:ok, _body} <- DynamoDB.call(dynamodb, "PutItem", %{TableName: table, Item: item}) do
        {:ok, %{"saved" => true}}
      end
    end)
  end
end
