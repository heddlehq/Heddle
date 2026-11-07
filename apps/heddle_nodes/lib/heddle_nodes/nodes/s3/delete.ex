defmodule HeddleNodes.Nodes.S3.Delete do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.S3

  definition do
    S3.definition(
      "Delete File",
      "Deletes a file from a bucket.",
      [
        S3.bucket_field(),
        S3.key_field()
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    S3.run(context, fn s3 ->
      with {:ok, _response} <- S3.request(s3, :delete, S3.object_url(s3, context)) do
        {:ok, %{"key" => Integration.field(context, "key")}}
      end
    end)
  end
end
