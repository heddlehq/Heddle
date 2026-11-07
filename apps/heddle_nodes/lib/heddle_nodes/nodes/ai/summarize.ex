defmodule HeddleNodes.Nodes.AI.Summarize do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.AI

  definition do
    AI.definition(
      "Summarize",
      "Summarizes a text, in the language it's written in.",
      "hero-document-text-solid",
      :text,
      [
        AI.text_field(),
        %{
          type: :select,
          name: :format,
          label: "Format",
          options: [
            %{label: "Short paragraph", value: "paragraph"},
            %{label: "Bullet points", value: "bullets"}
          ],
          default: "paragraph"
        }
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    AI.run(context, :text, fn options ->
      AI.ask(options, task(context["format"]), Integration.field(context, "text"))
    end)
  end

  defp task("bullets") do
    "Summarize the text as a few bullet points, in its language. Reply with only the summary."
  end

  defp task(_format) do
    "Summarize the text in a short paragraph, in its language. Reply with only the summary."
  end
end
