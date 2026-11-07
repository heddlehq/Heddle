defmodule HeddleNodes.Nodes.S3.Download do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.S3

  definition do
    S3.definition(
      "Download File",
      "Reads a file from a bucket.",
      [
        S3.bucket_field(),
        S3.key_field()
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    S3.run(context, fn s3 ->
      with {:ok, %{body: body}} <- S3.request(s3, :get, S3.object_url(s3, context)) do
        {:ok, Integration.to_text(body)}
      end
    end)
  end
end
