defmodule HeddleNodes.Nodes.AI.GenerateImage do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.AI

  definition do
    AI.definition(
      "Generate Image",
      "Creates an image from a prompt. Works with Nano Banana on Google, GPT Image on OpenAI and Grok Imagine on xAI.",
      "hero-photo-solid",
      :image,
      [
        %{type: :text, name: :prompt, label: "Prompt", default: ""},
        AI.aspect_ratio_field()
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    AI.run(context, :image, fn options ->
      options = Keyword.put(options, :aspect_ratio, AI.optional(context, "aspect_ratio"))

      with {:ok, {data, type}} <-
             AI.client().generate_image(Integration.field(context, "prompt"), options) do
        {:ok, Integration.to_file(data, type)}
      end
    end)
  end
end
