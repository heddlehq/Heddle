defmodule HeddleNodes.Nodes.Slack do
  use Bobbin.Node

  alias HeddleNodes.Integration

  @url "https://slack.com/api/chat.postMessage"

  definition do
    %{
      name: "Slack",
      title: "Slack",
      category: :integration,
      color: "bg-orange-500/15 text-orange-700 dark:text-orange-300",
      description: "Sends a message to a Slack channel.",
      icon: "hero-chat-bubble-left-right-solid",
      inputs: [:exec],
      outputs: Integration.outputs(),
      show: true,
      ui_fields: [
        Integration.credential_field("slack"),
        %{type: :text, name: :channel, label: "Channel", default: ""},
        %{type: :text, name: :text, label: "Message", default: ""}
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    with {:ok, %{"token" => token}} <- Integration.credential(context, "slack"),
         {:ok, reply} <- post(token, context) do
      Integration.success(context, Map.take(reply, ["channel", "ts"]))
    else
      {:error, message} -> Integration.failure(context, message)
    end
  end

  defp post(token, context) do
    message = %{
      channel: Integration.field(context, "channel"),
      text: Integration.field(context, "text")
    }

    case Req.post(@url, Integration.req_options(auth: {:bearer, token}, json: message)) do
      {:ok, %{status: 200, body: %{"ok" => true} = reply}} -> {:ok, reply}
      {:ok, %{body: %{"error" => error}}} -> {:error, "Slack refused it: #{error}"}
      {:ok, %{status: status}} -> {:error, "Slack answered #{status}"}
      {:error, reason} -> {:error, "Could not reach Slack: #{Exception.message(reason)}"}
    end
  end
end
