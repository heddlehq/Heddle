defmodule HeddleNodes.Nodes.AI.Classify do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.AI

  definition do
    AI.definition(
      "Classify",
      "Picks the category that fits a text. Use a Condition on result.category to branch.",
      "hero-tag-solid",
      :text,
      [
        AI.text_field(),
        %{type: :text, name: :categories, label: "Categories, separated by commas", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    AI.run(context, :text, fn options ->
      with {:ok, categories} <- AI.list(context, "categories"),
           {:ok, reply} <- AI.ask(options, task(categories), Integration.field(context, "text")) do
        pick(reply, categories)
      end
    end)
  end

  defp task(categories) do
    "Pick the category that fits the text best. " <>
      "Reply with exactly one of these, and nothing else: #{Enum.join(categories, ", ")}."
  end

  defp pick(reply, categories) do
    wanted = normalize(reply)

    case Enum.find(categories, &(normalize(&1) == wanted)) do
      nil -> {:error, "The model answered with something else: #{reply}"}
      category -> {:ok, %{"category" => category}}
    end
  end

  defp normalize(text) do
    text |> String.trim() |> String.trim(".") |> String.trim("\"") |> String.downcase()
  end
end
