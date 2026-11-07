defmodule HeddleNodes.Nodes.Redis.DeleteKeys do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Redis

  definition do
    Redis.definition(
      "Delete Keys",
      "Deletes one key, or several separated by commas.",
      [%{type: :text, name: :keys, label: "Keys", default: ""}]
    )
  end

  @impl true
  def handler(context, _input) do
    Redis.run(context, fn conn ->
      case keys(context) do
        [] ->
          {:error, "Pick a key."}

        keys ->
          with {:ok, count} <- Redis.command(conn, ["DEL" | keys]) do
            {:ok, %{"count" => count}}
          end
      end
    end)
  end

  defp keys(context) do
    context
    |> Integration.field("keys")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
