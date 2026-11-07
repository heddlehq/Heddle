defmodule HeddleNodes.Nodes.Elasticsearch.IndexDocument do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Elasticsearch

  definition do
    Elasticsearch.definition(
      "Index Document",
      "Saves a document in an index, and replaces the one with the same ID.",
      [
        Elasticsearch.index_field(),
        Elasticsearch.id_field("Document ID (empty to generate one)"),
        %{type: :textarea, name: :document, label: "Document", default: "{{result}}"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Elasticsearch.run(context, fn es ->
      with {:ok, document} <- document(context),
           {:ok, method, path} <- target(context),
           {:ok, body} <- Elasticsearch.call(es, method, path, json: document) do
        {:ok, %{"id" => body["_id"], "outcome" => body["result"]}}
      end
    end)
  end

  defp document(context) do
    case Integration.json(context, "document") do
      {:ok, %{} = document} -> {:ok, document}
      {:ok, _other} -> {:error, "Document: give an object."}
      {:error, message} -> {:error, message}
    end
  end

  defp target(context) do
    case String.trim(Integration.field(context, "document_id")) do
      "" -> with {:ok, path} <- Elasticsearch.path(context, "/_doc"), do: {:ok, :post, path}
      _id -> with {:ok, path} <- Elasticsearch.document_path(context), do: {:ok, :put, path}
    end
  end
end
