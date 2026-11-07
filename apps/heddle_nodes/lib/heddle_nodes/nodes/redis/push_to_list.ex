defmodule HeddleNodes.Nodes.Redis.PushToList do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Redis

  definition do
    Redis.definition(
      "Push to List",
      "Adds a value to the end or the start of a list.",
      [
        Redis.key_field(),
        Redis.value_field(),
        %{
          type: :select,
          name: :side,
          label: "Add to",
          options: [%{label: "End", value: "end"}, %{label: "Start", value: "start"}],
          default: "end"
        }
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Redis.run(context, fn conn ->
      with {:ok, key} <- Redis.key(context),
           value = Integration.field(context, "value"),
           {:ok, length} <- Redis.command(conn, [command(context), key, value]) do
        {:ok, %{"key" => key, "length" => length}}
      end
    end)
  end

  defp command(%{"side" => "start"}), do: "LPUSH"
  defp command(_context), do: "RPUSH"
end
