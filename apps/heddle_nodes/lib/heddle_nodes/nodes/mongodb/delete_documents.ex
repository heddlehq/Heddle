defmodule HeddleNodes.Nodes.MongoDB.DeleteDocuments do
  use Bobbin.Node

  alias HeddleNodes.Services.MongoDB

  definition do
    MongoDB.definition(
      "Delete Documents",
      "Deletes the documents that match a filter.",
      [MongoDB.collection_field(), MongoDB.filter_field("")]
    )
  end

  @impl true
  def handler(context, _input) do
    MongoDB.run(context, fn conn ->
      with {:ok, collection} <- MongoDB.collection(context),
           {:ok, filter} <- MongoDB.filter(context),
           :ok <- check(filter),
           {:ok, result} <- MongoDB.describe(Mongo.delete_many(conn, collection, filter)) do
        {:ok, %{"count" => result.deleted_count}}
      end
    end)
  end

  defp check(filter) when map_size(filter) == 0 do
    {:error,
     "Filter is empty. To delete every document on purpose, write {\"_id\": {\"$exists\": true}}."}
  end

  defp check(_filter), do: :ok
end
