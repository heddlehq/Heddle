defmodule HeddleNodes.Nodes.Slack.DeleteMessage do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Slack

  definition do
    Slack.definition(
      "Delete Message",
      "Deletes a message the bot sent.",
      [
        %{type: :text, name: :channel, label: "Channel ID", default: "{{result.channel}}"},
        %{type: :text, name: :ts, label: "Message timestamp", default: "{{result.ts}}"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Slack.run(context, fn token ->
      message = %{
        channel: Integration.field(context, "channel"),
        ts: Integration.field(context, "ts")
      }

      with {:ok, reply} <- Slack.post(token, "chat.delete", message) do
        {:ok, Map.take(reply, ["channel", "ts"])}
      end
    end)
  end
end
