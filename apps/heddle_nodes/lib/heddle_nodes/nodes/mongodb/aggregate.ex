defmodule HeddleNodes.Nodes.MongoDB.Aggregate do
  use Bobbin.Node

  alias HeddleNodes.Services.MongoDB

  definition do
    MongoDB.definition(
      "Aggregate",
      "Runs an aggregation pipeline on a collection.",
      [
        MongoDB.collection_field(),
        %{type: :textarea, name: :pipeline, label: "Pipeline", default: "[]"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    MongoDB.run(context, fn conn ->
      with {:ok, collection} <- MongoDB.collection(context),
           {:ok, pipeline} <- MongoDB.document(context, "pipeline"),
           :ok <- check(pipeline),
           {:ok, documents} <-
             MongoDB.documents(Mongo.aggregate(conn, collection, pipeline)) do
        {:ok, %{"documents" => documents, "count" => length(documents)}}
      end
    end)
  end

  defp check(pipeline) when is_list(pipeline), do: :ok
  defp check(_pipeline), do: {:error, "Pipeline: give a list of stages."}
end
