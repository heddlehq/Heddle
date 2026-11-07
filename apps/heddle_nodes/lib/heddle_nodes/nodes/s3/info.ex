defmodule HeddleNodes.Nodes.S3.Info do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.S3

  definition do
    S3.definition(
      "File Info",
      "Returns the size, type and date of a file, without reading it.",
      [
        S3.bucket_field(),
        S3.key_field()
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    S3.run(context, fn s3 ->
      with {:ok, response} <- S3.request(s3, :head, S3.object_url(s3, context)) do
        {:ok,
         %{
           "key" => Integration.field(context, "key"),
           "size" => response |> header("content-length") |> String.to_integer(),
           "type" => header(response, "content-type"),
           "modified" => header(response, "last-modified")
         }}
      end
    end)
  end

  defp header(response, name) do
    response |> Req.Response.get_header(name) |> List.first("0")
  end
end
