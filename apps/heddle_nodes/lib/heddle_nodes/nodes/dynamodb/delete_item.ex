defmodule HeddleNodes.Nodes.DynamoDB.DeleteItem do
  use Bobbin.Node

  alias HeddleNodes.Services.DynamoDB

  definition do
    DynamoDB.definition(
      "Delete Item",
      "Deletes an item by its key.",
      [DynamoDB.table_field(), DynamoDB.key_field()]
    )
  end

  @impl true
  def handler(context, _input) do
    DynamoDB.run(context, fn dynamodb ->
      with {:ok, table} <- DynamoDB.table(context),
           {:ok, key} <- DynamoDB.item(context, "item_key"),
           {:ok, _body} <- DynamoDB.call(dynamodb, "DeleteItem", %{TableName: table, Key: key}) do
        {:ok, %{"deleted" => true}}
      end
    end)
  end
end
