defmodule HeddleNodes.Nodes.AIAgent do
  use Bobbin.Node

  alias HeddleNodes.Template

  definition do
    %{
      name: "AI Agent",
      title: "AI Agent",
      category: :ai,
      color: "bg-fuchsia-500/15 text-fuchsia-700 dark:text-fuchsia-300",
      description: "Asks the LLM configured for this instance and keeps its reply in result.",
      icon: "hero-sparkles-solid",
      inputs: [:exec],
      outputs: ["success", "error"],
      show: true,
      ui_fields: [
        %{
          type: :text,
          name: :prompt,
          label: "Prompt",
          default: ""
        },
        %{
          type: :text,
          name: :system,
          label: "System prompt",
          default: ""
        }
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    prompt = Template.render(context["prompt"], context)

    if String.trim(prompt) == "" do
      failure(context, "The prompt is empty.")
    else
      case llm().run(prompt, tools: [], system: system_prompt(context)) do
        {:ok, text} -> {:ok, Map.put(context, "result", text), "success"}
        {:error, message} -> failure(context, message)
      end
    end
  end

  defp system_prompt(context) do
    case String.trim(Template.render(context["system"], context)) do
      "" -> nil
      system -> system
    end
  end

  defp failure(context, message) do
    {:ok, Map.put(context, "result", %{"error" => message}), "error"}
  end

  # heddle_ai depends on this app, so the LLM comes from config and not from an alias.
  defp llm, do: Application.fetch_env!(:heddle_nodes, :llm_client)
end
