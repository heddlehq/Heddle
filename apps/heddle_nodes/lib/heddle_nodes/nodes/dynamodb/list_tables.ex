defmodule HeddleNodes.Nodes.DynamoDB.ListTables do
  use Bobbin.Node

  alias HeddleNodes.Services.DynamoDB

  definition do
    DynamoDB.definition("List Tables", "Returns the names of the tables.", [])
  end

  @impl true
  def handler(context, _input) do
    DynamoDB.run(context, fn dynamodb ->
      with {:ok, body} <- DynamoDB.call(dynamodb, "ListTables", %{}) do
        {:ok, %{"tables" => body["TableNames"]}}
      end
    end)
  end
end
