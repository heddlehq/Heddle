defmodule HeddleNodes.Nodes.MongoDB.ListCollections do
  use Bobbin.Node

  alias HeddleNodes.Services.MongoDB

  definition do
    MongoDB.definition("List Collections", "Returns the names of the collections.", [])
  end

  @impl true
  def handler(context, _input) do
    MongoDB.run(context, fn conn ->
      with {:ok, names} <- MongoDB.documents(Mongo.show_collections(conn)) do
        {:ok, %{"collections" => Enum.sort(names)}}
      end
    end)
  end
end
