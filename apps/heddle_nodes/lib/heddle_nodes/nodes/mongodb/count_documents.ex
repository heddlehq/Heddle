defmodule HeddleNodes.Nodes.MongoDB.CountDocuments do
  use Bobbin.Node

  alias HeddleNodes.Services.MongoDB

  definition do
    MongoDB.definition(
      "Count Documents",
      "Returns how many documents match a filter.",
      [MongoDB.collection_field(), MongoDB.filter_field()]
    )
  end

  @impl true
  def handler(context, _input) do
    MongoDB.run(context, fn conn ->
      with {:ok, collection} <- MongoDB.collection(context),
           {:ok, filter} <- MongoDB.filter(context),
           {:ok, count} <- MongoDB.describe(Mongo.count_documents(conn, collection, filter)) do
        {:ok, %{"count" => count}}
      end
    end)
  end
end
