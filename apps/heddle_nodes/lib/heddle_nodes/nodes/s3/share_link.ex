defmodule HeddleNodes.Nodes.S3.ShareLink do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.S3

  @max_expiry 604_800

  definition do
    S3.definition(
      "Share Link",
      "Creates a link that lets anyone download a file until it expires. It doesn't check the file exists.",
      [
        S3.bucket_field(),
        S3.key_field(),
        %{type: :text, name: :expires, label: "Expires in seconds, up to 604800", default: "3600"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    S3.run(context, fn s3 ->
      expires = min(Integration.number(context, "expires", 3600), @max_expiry)

      url =
        s3
        |> S3.signature()
        |> Keyword.merge(
          method: :get,
          url: S3.object_url(s3, context),
          datetime: DateTime.utc_now(),
          expires: expires
        )
        |> Req.Utils.aws_sigv4_url()

      {:ok, %{"url" => to_string(url), "expires_in" => expires}}
    end)
  end
end
