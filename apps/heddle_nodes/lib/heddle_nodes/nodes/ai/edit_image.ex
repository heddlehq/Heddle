defmodule HeddleNodes.Nodes.AI.EditImage do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.AI

  definition do
    AI.definition(
      "Edit Image",
      "Changes an image following your instructions. Works with Nano Banana on Google, GPT Image on OpenAI and Grok Imagine on xAI.",
      "hero-paint-brush-solid",
      :image,
      [
        AI.file_field(:image, "Image, or its URL"),
        %{type: :text, name: :prompt, label: "What to change", default: ""},
        AI.aspect_ratio_field()
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    AI.run(context, :image, fn options ->
      with {:ok, image} <- Integration.media(context, "image"),
           {:ok, {data, type}} <-
             AI.client().generate_image(
               Integration.field(context, "prompt"),
               Keyword.merge(options,
                 image: image,
                 aspect_ratio: AI.optional(context, "aspect_ratio")
               )
             ) do
        {:ok, Integration.to_file(data, type)}
      end
    end)
  end
end
