defmodule HeddleNodes.Nodes.Elasticsearch.UpdateDocument do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Elasticsearch

  definition do
    Elasticsearch.definition(
      "Update Document",
      "Changes some fields of a document, and leaves the others as they are.",
      [
        Elasticsearch.index_field(),
        Elasticsearch.id_field(),
        %{type: :textarea, name: :changes, label: "New values", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Elasticsearch.run(context, fn es ->
      with {:ok, path} <- Elasticsearch.document_path(context, "_update"),
           {:ok, changes} <- changes(context),
           {:ok, body} <- Elasticsearch.call(es, :post, path, json: %{doc: changes}) do
        {:ok, %{"id" => body["_id"], "outcome" => body["result"]}}
      end
    end)
  end

  defp changes(context) do
    case Integration.json(context, "changes") do
      {:ok, %{} = changes} when map_size(changes) > 0 -> {:ok, changes}
      {:ok, _other} -> {:error, "New values: give an object, from field to value."}
      {:error, message} -> {:error, message}
    end
  end
end
