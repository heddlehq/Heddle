defmodule HeddleNodes.Nodes.RespondToWebhook do
  use Bobbin.Node

  alias HeddleNodes.Template

  definition do
    %{
      name: "Respond to Webhook",
      title: "Respond to Webhook",
      category: :flow_control,
      color: "bg-amber-500/15 text-amber-700 dark:text-amber-300",
      description:
        "Answers the webhook call with this status and body. The caller waits for it, and the flow goes on after.",
      icon: "hero-arrow-uturn-left-solid",
      inputs: [:exec],
      outputs: [:exec],
      show: true,
      # Not status and body: a node's fields hide the context keys with the same
      # name, and body is what the webhook received.
      ui_fields: [
        %{
          type: :text,
          name: :response_status,
          label: "Status",
          default: "200"
        },
        %{
          type: :text,
          name: :response_body,
          label: "Body",
          default: "{{result}}"
        }
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    body = Template.render(context["response_body"], context)

    response = %{
      "status" => status(Template.render(context["response_status"], context)),
      "body" => body,
      "content_type" => content_type(body)
    }

    {:respond, response, context}
  end

  defp status(value) do
    case Integer.parse(String.trim(value)) do
      {status, ""} when status in 100..599 -> status
      _other -> 200
    end
  end

  defp content_type(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) or is_list(decoded) -> "application/json"
      _other -> "text/plain"
    end
  end
end
