defmodule HeddleNodes.Nodes.Redis.ReadList do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Redis

  definition do
    Redis.definition(
      "Read List",
      "Returns the first items of a list, without taking them out.",
      [Redis.key_field(), %{type: :text, name: :limit, label: "Limit", default: "100"}]
    )
  end

  @impl true
  def handler(context, _input) do
    Redis.run(context, fn conn ->
      limit = Integration.number(context, "limit", 100)

      with {:ok, key} <- Redis.key(context),
           {:ok, items} <- Redis.command(conn, ["LRANGE", key, 0, limit - 1]) do
        {:ok, %{"key" => key, "items" => items, "count" => length(items)}}
      end
    end)
  end
end
