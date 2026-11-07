defmodule HeddleNodes.Nodes.MongoDB.FindDocuments do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.MongoDB

  definition do
    MongoDB.definition(
      "Find Documents",
      "Reads the documents of a collection that match a filter.",
      [
        MongoDB.collection_field(),
        MongoDB.filter_field(),
        %{type: :textarea, name: :fields, label: "Fields (empty for all)", default: ""},
        %{type: :textarea, name: :sort, label: "Sort", default: ""},
        %{type: :text, name: :limit, label: "Limit", default: "100"},
        %{type: :text, name: :offset, label: "Skip", default: "0"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    MongoDB.run(context, fn conn ->
      with {:ok, collection} <- MongoDB.collection(context),
           {:ok, filter} <- MongoDB.filter(context),
           {:ok, fields} <- MongoDB.document(context, "fields"),
           {:ok, sort} <- MongoDB.document(context, "sort"),
           options = [
             limit: Integration.number(context, "limit", 100),
             skip: Integration.number(context, "offset", 0),
             projection: fields,
             sort: sort
           ],
           {:ok, documents} <-
             MongoDB.documents(Mongo.find(conn, collection, filter, options)) do
        {:ok, %{"documents" => documents, "count" => length(documents)}}
      end
    end)
  end
end
