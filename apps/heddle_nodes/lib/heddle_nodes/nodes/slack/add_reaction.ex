defmodule HeddleNodes.Nodes.Slack.AddReaction do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Slack

  definition do
    Slack.definition(
      "Add Reaction",
      "Adds an emoji reaction to a message.",
      [
        %{type: :text, name: :channel, label: "Channel ID", default: "{{result.channel}}"},
        %{type: :text, name: :ts, label: "Message timestamp", default: "{{result.ts}}"},
        %{type: :text, name: :emoji, label: "Emoji name, like thumbsup", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Slack.run(context, fn token ->
      reaction = %{
        channel: Integration.field(context, "channel"),
        timestamp: Integration.field(context, "ts"),
        name: context |> Integration.field("emoji") |> String.trim(":")
      }

      with {:ok, _reply} <- Slack.post(token, "reactions.add", reaction) do
        {:ok, %{"emoji" => reaction.name}}
      end
    end)
  end
end
