defmodule HeddleNodes.Nodes.AI.Translate do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.AI

  definition do
    AI.definition(
      "Translate",
      "Translates a text into another language.",
      "hero-language-solid",
      :text,
      [
        AI.text_field(),
        %{type: :text, name: :language, label: "Language", default: "Portuguese"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    AI.run(context, :text, fn options ->
      language = Integration.field(context, "language")
      task = "Translate the text into #{language}. Reply with only the translation."

      AI.ask(options, task, Integration.field(context, "text"))
    end)
  end
end
