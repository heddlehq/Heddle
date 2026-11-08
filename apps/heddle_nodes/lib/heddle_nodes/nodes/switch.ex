defmodule HeddleNodes.Nodes.Switch do
  @moduledoc """
  Sends the run down the output of the first case equal to a value.

  Its outputs are fixed, so every client draws them from the definition alone. More
  cases are another Switch on `otherwise`.
  """

  use Bobbin.Node

  alias HeddleNodes.Template

  @cases ["case_1", "case_2", "case_3", "case_4"]

  definition do
    %{
      name: "Switch",
      title: "Switch",
      category: :flow_control,
      color: "bg-amber-500/15 text-amber-700 dark:text-amber-300",
      description:
        "Sends the run down the output of the first case equal to the value, or down otherwise when none is.",
      icon: "hero-arrows-right-left-solid",
      inputs: [:exec],
      outputs: ["case 1", "case 2", "case 3", "case 4", "otherwise"],
      show: true,
      # Not value: a node's fields hide the context keys with the same name.
      ui_fields: [
        %{type: :text, name: :switch_value, label: "Value", default: "{{result}}"},
        %{type: :text, name: :case_1, label: "Case 1", default: ""},
        %{type: :text, name: :case_2, label: "Case 2", default: ""},
        %{type: :text, name: :case_3, label: "Case 3", default: ""},
        %{type: :text, name: :case_4, label: "Case 4", default: ""}
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    value = context["switch_value"] |> Template.render(context) |> String.trim()

    output =
      @cases
      |> Enum.with_index(1)
      |> Enum.find_value("otherwise", fn {field, number} ->
        if matches?(context[field], value, context), do: "case #{number}"
      end)

    {:ok, context, output}
  end

  # An empty case is one nobody filled in, not a case for an empty value.
  defp matches?(case_value, value, context) when is_binary(case_value) do
    case String.trim(case_value) do
      "" -> false
      expected -> Template.render(expected, context) == value
    end
  end

  defp matches?(_case_value, _value, _context), do: false
end
