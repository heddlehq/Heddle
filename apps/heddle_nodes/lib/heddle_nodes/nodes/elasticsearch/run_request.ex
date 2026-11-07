defmodule HeddleNodes.Nodes.Elasticsearch.RunRequest do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Elasticsearch

  definition do
    Elasticsearch.definition(
      "Run Request",
      "Calls any endpoint of the API, like /_cat/indices or /products/_bulk.",
      [
        %{
          type: :select,
          name: :method,
          label: "Method",
          options: ["GET", "POST", "PUT", "DELETE"],
          default: "GET"
        },
        %{type: :text, name: :path, label: "Path", default: "/"},
        %{type: :textarea, name: :payload, label: "Payload (JSON)", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Elasticsearch.run(context, fn es ->
      path = "/" <> String.trim_leading(Integration.field(context, "path"), "/")

      with {:ok, options} <- payload(context) do
        Elasticsearch.call(es, method(context), path, options)
      end
    end)
  end

  defp method(%{"method" => "POST"}), do: :post
  defp method(%{"method" => "PUT"}), do: :put
  defp method(%{"method" => "DELETE"}), do: :delete
  defp method(_context), do: :get

  defp payload(context) do
    if String.trim(context["payload"] || "") == "" do
      {:ok, []}
    else
      with {:ok, payload} <- Integration.json(context, "payload"), do: {:ok, [json: payload]}
    end
  end
end
