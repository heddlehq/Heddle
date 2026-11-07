defmodule HeddleNodes.Nodes.Elasticsearch.DeleteDocument do
  use Bobbin.Node

  alias HeddleNodes.Services.Elasticsearch

  definition do
    Elasticsearch.definition(
      "Delete Document",
      "Deletes a document by its ID.",
      [Elasticsearch.index_field(), Elasticsearch.id_field()]
    )
  end

  @impl true
  def handler(context, _input) do
    Elasticsearch.run(context, fn es ->
      with {:ok, path} <- Elasticsearch.document_path(context),
           {:ok, body} <- Elasticsearch.call(es, :delete, path) do
        {:ok, %{"id" => body["_id"], "outcome" => body["result"]}}
      end
    end)
  end
end
