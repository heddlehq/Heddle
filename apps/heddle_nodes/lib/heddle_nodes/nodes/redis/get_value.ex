defmodule HeddleNodes.Nodes.Redis.GetValue do
  use Bobbin.Node

  alias HeddleNodes.Services.Redis

  definition do
    Redis.definition("Get Value", "Reads the value of a key.", [Redis.key_field()])
  end

  @impl true
  def handler(context, _input) do
    Redis.run(context, fn conn ->
      with {:ok, key} <- Redis.key(context),
           {:ok, value} <- Redis.command(conn, ["GET", key]) do
        {:ok, %{"key" => key, "value" => value, "found" => value != nil}}
      end
    end)
  end
end
