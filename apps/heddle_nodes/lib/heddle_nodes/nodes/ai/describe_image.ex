defmodule HeddleNodes.Nodes.AI.DescribeImage do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.AI

  definition do
    AI.definition(
      "Describe Image",
      "Answers a question about an image, or reads the text in it. The model must see images.",
      "hero-eye-solid",
      :vision,
      [
        AI.file_field(:image, "Image, or its URL"),
        %{type: :text, name: :question, label: "Question", default: "Describe this image."}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    AI.run(context, :vision, fn options ->
      with {:ok, image} <- Integration.media(context, "image") do
        AI.client().ask_about_image(image, Integration.field(context, "question"), options)
      end
    end)
  end
end
