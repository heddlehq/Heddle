defmodule HeddleNodes.Nodes.Slack.ListChannels do
  use Bobbin.Node

  alias HeddleNodes.Services.Slack

  definition do
    Slack.definition(
      "List Channels",
      "Returns the channels of the workspace, with the IDs the other Slack nodes take.",
      [
        %{
          type: :select,
          name: :types,
          label: "Channels",
          options: [
            %{label: "Public", value: "public_channel"},
            %{label: "Private", value: "private_channel"},
            %{label: "Public and private", value: "public_channel,private_channel"}
          ],
          default: "public_channel"
        }
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Slack.run(context, fn token ->
      params = [types: context["types"] || "public_channel", exclude_archived: true]

      with {:ok, channels} <- Slack.get_all(token, "conversations.list", "channels", params) do
        {:ok, Enum.map(channels, &Map.take(&1, ["id", "name"]))}
      end
    end)
  end
end
