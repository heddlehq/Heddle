defmodule HeddleNodes.Nodes.DynamoDB.QueryItems do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.DynamoDB

  definition do
    DynamoDB.definition(
      "Query Items",
      "Reads the items of a partition key, with a condition like pk = :pk.",
      [
        DynamoDB.table_field(),
        %{type: :text, name: :index_name, label: "Index (optional)", default: ""},
        %{type: :text, name: :condition, label: "Key condition", default: ""},
        %{
          type: :textarea,
          name: :condition_values,
          label: "Values",
          default: ~s({":pk": "{{id}}"})
        },
        %{type: :text, name: :limit, label: "Limit", default: "100"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    DynamoDB.run(context, fn dynamodb ->
      with {:ok, table} <- DynamoDB.table(context),
           {:ok, values} <- DynamoDB.item(context, "condition_values"),
           {:ok, body} <- DynamoDB.call(dynamodb, "Query", request(context, table, values)) do
        items = Enum.map(body["Items"], &DynamoDB.from_item/1)

        {:ok, %{"items" => items, "count" => length(items)}}
      end
    end)
  end

  defp request(context, table, values) do
    request = %{
      TableName: table,
      KeyConditionExpression: Integration.field(context, "condition"),
      ExpressionAttributeValues: values,
      Limit: Integration.number(context, "limit", 100)
    }

    case String.trim(Integration.field(context, "index_name")) do
      "" -> request
      index -> Map.put(request, :IndexName, index)
    end
  end
end
