defmodule HeddleNodes.Nodes.Slack.SendMessage do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Slack

  definition do
    Slack.definition(
      "Send Message",
      "Sends a message to a channel. Give a thread timestamp to reply in that thread.",
      [
        %{type: :text, name: :channel, label: "Channel", default: ""},
        %{type: :text, name: :text, label: "Message", default: ""},
        %{
          type: :text,
          name: :thread_ts,
          label: "Thread timestamp, to reply in a thread",
          default: ""
        }
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Slack.run(context, fn token ->
      message = %{
        channel: Integration.field(context, "channel"),
        text: Integration.field(context, "text")
      }

      with {:ok, reply} <- Slack.post(token, "chat.postMessage", thread(message, context)) do
        {:ok, Map.take(reply, ["channel", "ts"])}
      end
    end)
  end

  defp thread(message, context) do
    case Integration.field(context, "thread_ts") do
      "" -> message
      thread_ts -> Map.put(message, :thread_ts, thread_ts)
    end
  end
end
