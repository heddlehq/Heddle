defmodule HeddleNodes.Nodes.S3.List do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.S3

  definition do
    S3.definition(
      "List Files",
      "Returns the paths of the files in a bucket, up to 1000.",
      [
        S3.bucket_field(),
        %{type: :text, name: :prefix, label: "Only paths starting with", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    S3.run(context, fn s3 ->
      url = S3.bucket_url(s3, Integration.field(context, "bucket"))
      params = ["list-type": 2, prefix: Integration.field(context, "prefix")]

      with {:ok, %{body: body}} <- S3.request(s3, :get, url, params: params) do
        {:ok, %{"keys" => keys(body)}}
      end
    end)
  end

  defp keys(xml) do
    ~r{<Key>(.*?)</Key>}
    |> Regex.scan(xml, capture: :all_but_first)
    |> Enum.map(fn [key] -> unescape(key) end)
  end

  defp unescape(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&amp;", "&")
  end
end
