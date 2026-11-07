defmodule HeddleNodes.Nodes.Elasticsearch.GetDocument do
  use Bobbin.Node

  alias HeddleNodes.Services.Elasticsearch

  definition do
    Elasticsearch.definition(
      "Get Document",
      "Reads a document by its ID.",
      [Elasticsearch.index_field(), Elasticsearch.id_field()]
    )
  end

  @impl true
  def handler(context, _input) do
    Elasticsearch.run(context, fn es ->
      with {:ok, path} <- Elasticsearch.document_path(context),
           {:ok, body} <- Elasticsearch.call(es, :get, path) do
        {:ok, Map.put(body["_source"], "_id", body["_id"])}
      end
    end)
  end
end
