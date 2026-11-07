defmodule HeddleNodes.Nodes.S3.Copy do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.S3

  definition do
    S3.definition(
      "Copy File",
      "Copies a file inside the service, without downloading it.",
      [
        S3.bucket_field(),
        S3.key_field(),
        %{type: :text, name: :target_bucket, label: "Target bucket", default: ""},
        %{type: :text, name: :target_key, label: "Target file path", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    S3.run(context, fn s3 ->
      target = Integration.field(context, "target_key")

      url =
        S3.bucket_url(s3, Integration.field(context, "target_bucket")) <>
          "/" <> S3.encode_key(target)

      with {:ok, _response} <-
             S3.request(s3, :put, url, headers: [{"x-amz-copy-source", source(context)}]) do
        {:ok, %{"key" => target}}
      end
    end)
  end

  defp source(context) do
    bucket = Integration.field(context, "bucket")

    "/#{bucket}/#{S3.encode_key(Integration.field(context, "key"))}"
  end
end
