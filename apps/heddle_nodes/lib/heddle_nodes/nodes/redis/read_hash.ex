defmodule HeddleNodes.Nodes.Redis.ReadHash do
  use Bobbin.Node

  alias HeddleNodes.Services.Redis

  definition do
    Redis.definition("Read Hash", "Returns the fields of a hash.", [Redis.key_field()])
  end

  @impl true
  def handler(context, _input) do
    Redis.run(context, fn conn ->
      with {:ok, key} <- Redis.key(context),
           {:ok, pairs} <- Redis.command(conn, ["HGETALL", key]) do
        {:ok, %{"key" => key, "fields" => to_map(pairs)}}
      end
    end)
  end

  defp to_map(pairs) do
    pairs |> Enum.chunk_every(2) |> Map.new(fn [field, value] -> {field, value} end)
  end
end
