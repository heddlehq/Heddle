defmodule HeddleNodes.Nodes.S3 do
  use Bobbin.Node

  alias HeddleNodes.Integration

  definition do
    %{
      name: "S3",
      title: "S3",
      category: :integration,
      color: "bg-orange-500/15 text-orange-700 dark:text-orange-300",
      description: "Reads, writes, lists or deletes files in a bucket on S3 or a compatible service.",
      icon: "hero-archive-box-solid",
      inputs: [:exec],
      outputs: Integration.outputs(),
      show: true,
      ui_fields: [
        Integration.credential_field("s3"),
        %{
          type: :select,
          name: :operation,
          label: "Operation",
          options: [
            %{label: "Read file", value: "get"},
            %{label: "Write file", value: "put"},
            %{label: "List files", value: "list"},
            %{label: "Delete file", value: "delete"}
          ],
          default: "get"
        },
        %{type: :text, name: :bucket, label: "Bucket", default: ""},
        %{type: :text, name: :key, label: "File path, or prefix to list", default: ""},
        %{type: :text, name: :content, label: "Content to write", default: "{{result}}"}
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    with {:ok, s3} <- Integration.credential(context, "s3"),
         {:ok, result} <- run(context["operation"] || "get", s3, context) do
      Integration.success(context, result)
    else
      {:error, message} -> Integration.failure(context, message)
    end
  end

  defp run("get", s3, context) do
    with {:ok, %{body: body}} <- request(s3, context, :get, object_url(s3, context)) do
      {:ok, Integration.to_text(body)}
    end
  end

  defp run("put", s3, context) do
    url = object_url(s3, context)

    with {:ok, _response} <- request(s3, context, :put, url, body: Integration.field(context, "content")) do
      {:ok, %{"key" => Integration.field(context, "key")}}
    end
  end

  defp run("delete", s3, context) do
    with {:ok, _response} <- request(s3, context, :delete, object_url(s3, context)) do
      {:ok, %{"key" => Integration.field(context, "key")}}
    end
  end

  defp run("list", s3, context) do
    params = ["list-type": 2, prefix: Integration.field(context, "key")]

    with {:ok, %{body: body}} <- request(s3, context, :get, bucket_url(s3, context), params: params) do
      {:ok, %{"keys" => keys(body)}}
    end
  end

  defp run(operation, _s3, _context), do: {:error, "Unknown operation: #{operation}"}

  defp request(s3, _context, method, url, options \\ []) do
    signature = [
      access_key_id: s3["access_key_id"],
      secret_access_key: s3["secret_access_key"],
      region: region(s3),
      service: :s3
    ]

    request =
      options
      |> Keyword.merge(method: method, url: url, aws_sigv4: signature, decode_body: false)
      |> Integration.req_options()

    case Req.request(request) do
      {:ok, %{status: status} = response} when status in 200..299 -> {:ok, response}
      {:ok, %{status: status, body: body}} -> {:error, "S3 answered #{status}#{code(body)}"}
      {:error, reason} -> {:error, "Could not reach S3: #{Exception.message(reason)}"}
    end
  end

  defp object_url(s3, context) do
    key =
      context
      |> Integration.field("key")
      |> String.split("/")
      |> Enum.map_join("/", &URI.encode(&1, fn char -> URI.char_unreserved?(char) end))

    bucket_url(s3, context) <> "/" <> key
  end

  # A custom endpoint means MinIO, R2 and the like, which take the bucket in the path.
  defp bucket_url(s3, context) do
    bucket = Integration.field(context, "bucket")

    case String.trim_trailing(s3["endpoint"] || "", "/") do
      "" -> "https://#{bucket}.s3.#{region(s3)}.amazonaws.com"
      endpoint -> "#{endpoint}/#{bucket}"
    end
  end

  defp region(s3) do
    case s3["region"] do
      region when region in [nil, ""] -> "us-east-1"
      region -> region
    end
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

  defp code(body) when is_binary(body) do
    case Regex.run(~r{<Code>(.*?)</Code>}, body, capture: :all_but_first) do
      [code] -> ": #{code}"
      _other -> ""
    end
  end

  defp code(_body), do: ""
end
