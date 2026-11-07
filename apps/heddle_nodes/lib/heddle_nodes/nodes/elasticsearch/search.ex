defmodule HeddleNodes.Nodes.Elasticsearch.Search do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Elasticsearch

  definition do
    Elasticsearch.definition(
      "Search",
      ~s(Searches an index, with a query like {"match": {"title": "{{term}}"}}.),
      [
        Elasticsearch.index_field(),
        %{type: :textarea, name: :search, label: "Query", default: ~s({"match_all": {}})},
        %{type: :text, name: :limit, label: "Limit", default: "100"},
        %{type: :text, name: :offset, label: "Skip", default: "0"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Elasticsearch.run(context, fn es ->
      with {:ok, path} <- Elasticsearch.path(context, "/_search"),
           {:ok, query} <- Integration.json(context, "search"),
           {:ok, body} <- Elasticsearch.call(es, :post, path, json: body(context, query)) do
        {:ok,
         %{
           "documents" => Enum.map(body["hits"]["hits"], &document/1),
           "total" => body["hits"]["total"]["value"]
         }}
      end
    end)
  end

  defp body(context, query) do
    %{
      query: query,
      size: Integration.number(context, "limit", 100),
      from: Integration.number(context, "offset", 0)
    }
  end

  defp document(hit) do
    Map.merge(hit["_source"] || %{}, %{"_id" => hit["_id"], "_score" => hit["_score"]})
  end
end
