defmodule HeddleNodes.Nodes.Redis.SetValue do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Redis

  definition do
    Redis.definition(
      "Set Value",
      "Saves a value in a key, for good or for some seconds.",
      [
        Redis.key_field(),
        Redis.value_field(),
        %{type: :text, name: :seconds, label: "Expires after (seconds)", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Redis.run(context, fn conn ->
      with {:ok, key} <- Redis.key(context),
           {:ok, "OK"} <- Redis.command(conn, command(context, key)) do
        {:ok, %{"key" => key}}
      end
    end)
  end

  defp command(context, key) do
    value = Integration.field(context, "value")

    case Integration.number(context, "seconds", nil) do
      nil -> ["SET", key, value]
      seconds -> ["SET", key, value, "EX", seconds]
    end
  end
end
