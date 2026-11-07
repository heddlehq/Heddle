defmodule HeddleNodes.Nodes.AI.ExtractData do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.AI

  definition do
    AI.definition(
      "Extract Data",
      "Reads the fields you name out of a text, like an email or an invoice.",
      "hero-document-magnifying-glass-solid",
      :text,
      [
        AI.text_field(),
        %{type: :text, name: :fields, label: "Fields, separated by commas", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    AI.run(context, :text, fn options ->
      with {:ok, fields} <- AI.list(context, "fields"),
           {:ok, reply} <- AI.ask(options, task(fields), Integration.field(context, "text")),
           {:ok, data} <- decode(reply) do
        {:ok, Map.new(fields, &{&1, data[&1]})}
      end
    end)
  end

  defp task(fields) do
    "Extract these fields from the text: #{Enum.join(fields, ", ")}. " <>
      "Reply with a single JSON object with exactly these keys, and nothing else. " <>
      "Use null for what the text doesn't say. Don't guess."
  end

  defp decode(reply) do
    cleaned =
      reply
      |> String.trim()
      |> String.replace(~r/\A```(?:json)?\s*/, "")
      |> String.replace(~r/\s*```\z/, "")

    case Jason.decode(cleaned) do
      {:ok, %{} = data} -> {:ok, data}
      _other -> {:error, "The reply is not a JSON object: #{reply}"}
    end
  end
end
