defmodule HeddleNodes.Nodes.Redis.PublishMessage do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Redis

  definition do
    Redis.definition(
      "Publish Message",
      "Sends a message to a channel, and returns how many subscribers got it.",
      [
        %{type: :text, name: :channel, label: "Channel", default: ""},
        Redis.value_field("Message")
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Redis.run(context, fn conn ->
      with {:ok, channel} <- Redis.key(context, "channel"),
           message = Integration.field(context, "value"),
           {:ok, count} <- Redis.command(conn, ["PUBLISH", channel, message]) do
        {:ok, %{"subscribers" => count}}
      end
    end)
  end
end
