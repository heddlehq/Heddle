defmodule HeddleNodes.Nodes.Redis.FindKeys do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Redis

  @batch 500

  definition do
    Redis.definition(
      "Find Keys",
      "Returns the keys that match a pattern like user:*, without blocking the server.",
      [
        %{type: :text, name: :pattern, label: "Pattern", default: "*"},
        %{type: :text, name: :limit, label: "Limit", default: "1000"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Redis.run(context, fn conn ->
      pattern = Integration.field(context, "pattern")
      limit = Integration.number(context, "limit", 1000)

      with {:ok, keys} <- scan(conn, "0", pattern, limit, []) do
        {:ok, %{"keys" => keys, "count" => length(keys)}}
      end
    end)
  end

  defp scan(conn, cursor, pattern, limit, keys) do
    command = ["SCAN", cursor, "MATCH", pattern, "COUNT", @batch]

    with {:ok, [next, found]} <- Redis.command(conn, command) do
      keys = keys ++ found

      if next == "0" or length(keys) >= limit do
        {:ok, keys |> Enum.uniq() |> Enum.take(limit)}
      else
        scan(conn, next, pattern, limit, keys)
      end
    end
  end
end
