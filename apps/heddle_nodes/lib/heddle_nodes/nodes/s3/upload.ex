defmodule HeddleNodes.Nodes.S3.Upload do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.S3

  definition do
    S3.definition(
      "Upload File",
      "Writes a file to a bucket. The content can come from a Download node.",
      [
        S3.bucket_field(),
        S3.key_field(),
        %{type: :text, name: :content, label: "Content", default: "{{result}}"},
        %{type: :text, name: :content_type, label: "Content type, like text/csv", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    S3.run(context, fn s3 ->
      options = [body: Integration.content(context, "content"), headers: headers(context)]

      with {:ok, _response} <- S3.request(s3, :put, S3.object_url(s3, context), options) do
        {:ok, %{"key" => Integration.field(context, "key")}}
      end
    end)
  end

  defp headers(context) do
    case Integration.field(context, "content_type") do
      "" -> []
      type -> [content_type: type]
    end
  end
end
