defmodule HeddleNodes.Nodes.Slack.UpdateMessage do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Slack

  definition do
    Slack.definition(
      "Update Message",
      "Changes the text of a message the bot sent.",
      [
        %{type: :text, name: :channel, label: "Channel ID", default: "{{result.channel}}"},
        %{type: :text, name: :ts, label: "Message timestamp", default: "{{result.ts}}"},
        %{type: :text, name: :text, label: "New message", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Slack.run(context, fn token ->
      update = %{
        channel: Integration.field(context, "channel"),
        ts: Integration.field(context, "ts"),
        text: Integration.field(context, "text")
      }

      with {:ok, reply} <- Slack.post(token, "chat.update", update) do
        {:ok, Map.take(reply, ["channel", "ts"])}
      end
    end)
  end
end
