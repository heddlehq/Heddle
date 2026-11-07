defmodule HeddleNodes.Nodes.MongoDB.InsertDocuments do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.MongoDB

  definition do
    MongoDB.definition(
      "Insert Documents",
      "Adds one document or a list of them to a collection.",
      [
        MongoDB.collection_field(),
        %{type: :textarea, name: :documents, label: "Documents", default: "{{result}}"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    MongoDB.run(context, fn conn ->
      with {:ok, collection} <- MongoDB.collection(context),
           {:ok, documents} <- MongoDB.document(context, "documents"),
           {:ok, documents} <- list(documents),
           {:ok, result} <- MongoDB.describe(Mongo.insert_many(conn, collection, documents)) do
        {:ok,
         %{
           "ids" => Integration.to_value(result.inserted_ids),
           "count" => length(result.inserted_ids)
         }}
      end
    end)
  end

  defp list(%{} = document) when map_size(document) > 0, do: {:ok, [document]}
  defp list([%{} | _rest] = documents), do: {:ok, documents}
  defp list(_other), do: {:error, "Documents: give one object, or a list of objects."}
end
