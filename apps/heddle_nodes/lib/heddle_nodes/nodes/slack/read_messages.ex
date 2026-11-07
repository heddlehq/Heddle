defmodule HeddleNodes.Nodes.Slack.ReadMessages do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Slack

  definition do
    Slack.definition(
      "Read Messages",
      "Returns the latest messages of a channel, newest first.",
      [
        %{type: :text, name: :channel, label: "Channel ID", default: ""},
        %{type: :text, name: :limit, label: "How many", default: "20"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Slack.run(context, fn token ->
      params = [
        channel: Integration.field(context, "channel"),
        limit: Integration.number(context, "limit", 20)
      ]

      with {:ok, reply} <- Slack.get(token, "conversations.history", params) do
        {:ok, Enum.map(reply["messages"], &Map.take(&1, ["user", "text", "ts", "thread_ts"]))}
      end
    end)
  end
end
