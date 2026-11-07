defmodule HeddleNodes.Services.S3 do
  @moduledoc """
  Signed requests to S3 or a compatible service, for the S3 nodes.
  """

  alias HeddleNodes.Integration

  @service %{title: "S3", category: :s3, credential: "s3", icon: "logo-s3"}

  def definition(action, description, fields) do
    Integration.definition(@service, action, description, fields)
  end

  def run(context, fun), do: Integration.run(context, "s3", fun)

  def bucket_field, do: %{type: :text, name: :bucket, label: "Bucket", default: ""}
  def key_field, do: %{type: :text, name: :key, label: "File path", default: ""}

  def request(s3, method, url, options \\ []) do
    request =
      options
      |> Keyword.merge(method: method, url: url, aws_sigv4: signature(s3), decode_body: false)
      |> Integration.req_options()

    case Req.request(request) do
      {:ok, %{status: status} = response} when status in 200..299 -> {:ok, response}
      {:ok, %{status: status, body: body}} -> {:error, "S3 answered #{status}#{code(body)}"}
      {:error, reason} -> {:error, "Could not reach S3: #{Exception.message(reason)}"}
    end
  end

  def signature(s3) do
    [
      access_key_id: s3["access_key_id"],
      secret_access_key: s3["secret_access_key"],
      region: region(s3),
      service: :s3
    ]
  end

  def object_url(s3, context) do
    bucket_url(s3, Integration.field(context, "bucket")) <>
      "/" <> encode_key(Integration.field(context, "key"))
  end

  # A custom endpoint means MinIO, R2 and the like, which take the bucket in the path.
  def bucket_url(s3, bucket) do
    case String.trim_trailing(s3["endpoint"] || "", "/") do
      "" -> "https://#{bucket}.s3.#{region(s3)}.amazonaws.com"
      endpoint -> "#{endpoint}/#{bucket}"
    end
  end

  def encode_key(key) do
    key
    |> String.split("/")
    |> Enum.map_join("/", &URI.encode(&1, fn char -> URI.char_unreserved?(char) end))
  end

  defp region(s3) do
    case s3["region"] do
      region when region in [nil, ""] -> "us-east-1"
      region -> region
    end
  end

  defp code(body) when is_binary(body) do
    case Regex.run(~r{<Code>(.*?)</Code>}, body, capture: :all_but_first) do
      [code] -> ": #{code}"
      _other -> ""
    end
  end

  defp code(_body), do: ""
end
