defmodule HeddleNodes.Nodes.MongoDB.UpdateDocuments do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.MongoDB

  definition do
    MongoDB.definition(
      "Update Documents",
      ~s(Changes the documents that match, with an update like {"$set": {"status": "done"}}.),
      [
        MongoDB.collection_field(),
        MongoDB.filter_field(""),
        %{type: :textarea, name: :update, label: "Update", default: ""},
        %{
          type: :select,
          name: :which,
          label: "Which documents",
          options: [
            %{label: "All that match", value: "all"},
            %{label: "Only the first", value: "first"}
          ],
          default: "all"
        },
        %{
          type: :select,
          name: :upsert,
          label: "When nothing matches",
          options: [
            %{label: "Do nothing", value: "no"},
            %{label: "Add a document", value: "yes"}
          ],
          default: "no"
        }
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    MongoDB.run(context, fn conn ->
      with {:ok, collection} <- MongoDB.collection(context),
           {:ok, filter} <- required(MongoDB.filter(context)),
           {:ok, update} <- MongoDB.document(context, "update"),
           :ok <- check(update),
           options = [upsert: context["upsert"] == "yes"],
           {:ok, result} <- update(conn, collection, filter, update, context["which"], options) do
        {:ok,
         %{
           "matched" => result.matched_count,
           "modified" => result.modified_count,
           "upserted_ids" => Integration.to_value(result.upserted_ids || [])
         }}
      end
    end)
  end

  defp required({:ok, filter}) when map_size(filter) == 0 do
    {:error,
     "Filter is empty. To change every document on purpose, write {\"_id\": {\"$exists\": true}}."}
  end

  defp required(result), do: result

  defp check(update) when map_size(update) == 0, do: {:error, "Update is empty."}
  defp check(_update), do: :ok

  defp update(conn, collection, filter, update, "first", options) do
    MongoDB.describe(Mongo.update_one(conn, collection, filter, update, options))
  end

  defp update(conn, collection, filter, update, _all, options) do
    MongoDB.describe(Mongo.update_many(conn, collection, filter, update, options))
  end
end
