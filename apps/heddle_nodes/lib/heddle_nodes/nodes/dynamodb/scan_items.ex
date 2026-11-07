defmodule HeddleNodes.Nodes.DynamoDB.ScanItems do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.DynamoDB

  definition do
    DynamoDB.definition(
      "Scan Items",
      "Reads the items of a table, one after the other. Query is cheaper when it can be used.",
      [DynamoDB.table_field(), %{type: :text, name: :limit, label: "Limit", default: "100"}]
    )
  end

  @impl true
  def handler(context, _input) do
    DynamoDB.run(context, fn dynamodb ->
      with {:ok, table} <- DynamoDB.table(context),
           request = %{TableName: table, Limit: Integration.number(context, "limit", 100)},
           {:ok, body} <- DynamoDB.call(dynamodb, "Scan", request) do
        items = Enum.map(body["Items"], &DynamoDB.from_item/1)

        {:ok, %{"items" => items, "count" => length(items)}}
      end
    end)
  end
end
