defmodule HeddleNodes.Nodes.AIAgent do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.AI
  alias HeddleNodes.Template

  definition do
    %{
      name: "AI Agent",
      title: "AI Agent",
      category: :ai,
      color: "bg-fuchsia-500/15 text-fuchsia-700 dark:text-fuchsia-300",
      description:
        "Works on a task with the LLM. Nodes connected to tools are steps it can use: it fills in the fields you left blank.",
      icon: "hero-sparkles-solid",
      inputs: [:exec],
      outputs: ["success", "error", "tools"],
      show: true,
      ui_fields: [
        AI.credential_field(),
        %{type: :text, name: :prompt, label: "Prompt", default: ""},
        %{type: :text, name: :system, label: "System prompt", default: ""},
        %{
          type: :select,
          name: :output,
          label: "Reply as",
          options: [%{label: "Text", value: "text"}, %{label: "JSON", value: "json"}],
          default: "text"
        },
        %{type: :text, name: :memory_key, label: "Memory key", default: ""},
        %{
          type: :select,
          name: :temperature,
          label: "Creativity",
          options: [
            %{label: "The model's default", value: ""},
            %{label: "Precise", value: "0.2"},
            %{label: "Balanced", value: "0.7"},
            %{label: "Creative", value: "1.0"}
          ],
          default: ""
        },
        AI.model_field(:text),
        %{type: :text, name: :max_steps, label: "Max steps", default: "10"}
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    case AI.plan(context, :text) do
      {:ok, options} -> {:agent, request(context, options)}
      {:error, message} -> Integration.failure(context, message)
    end
  end

  defp request(context, options) do
    %{
      prompt: Template.render(context["prompt"], context),
      system: text(context, "system"),
      output: context["output"] || "text",
      memory_key: text(context, "memory_key"),
      credential: options[:credential],
      model: options[:model],
      temperature: number(context["temperature"], &Float.parse/1),
      max_steps: number(context["max_steps"], &Integer.parse/1)
    }
  end

  defp text(context, name) do
    case String.trim(Template.render(context[name], context)) do
      "" -> nil
      value -> value
    end
  end

  defp number(value, parse) when is_binary(value) do
    case parse.(String.trim(value)) do
      {number, ""} -> number
      _other -> nil
    end
  end

  defp number(_value, _parse), do: nil
end
