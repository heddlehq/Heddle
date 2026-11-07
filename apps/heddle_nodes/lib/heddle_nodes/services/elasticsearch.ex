defmodule HeddleNodes.Services.Elasticsearch do
  @moduledoc """
  Elasticsearch and OpenSearch, for the Elasticsearch nodes.
  """

  alias HeddleNodes.Integration

  @timeout :timer.minutes(2)
  @service %{
    title: "Elasticsearch",
    category: :database,
    group: "Elasticsearch",
    credential: "elasticsearch",
    icon: "logo-elasticsearch"
  }

  def definition(action, description, fields) do
    Integration.definition(@service, action, description, fields)
  end

  # Called index_name because a For Each keeps the position of its item in `index`.
  def index_field, do: %{type: :text, name: :index_name, label: "Index", default: ""}

  def id_field(label \\ "Document ID") do
    %{type: :text, name: :document_id, label: label, default: ""}
  end

  def run(context, fun), do: Integration.run(context, "elasticsearch", fun)

  @doc """
  Returns the path of an index, with what comes after it.
  """
  def path(context, suffix \\ "") do
    case context |> Integration.field("index_name") |> String.trim() do
      "" -> {:error, "Pick an index."}
      index -> {:ok, "/#{encode(index)}#{suffix}"}
    end
  end

  @doc """
  Returns the path of a document.
  """
  def document_path(context, action \\ "_doc") do
    case context |> Integration.field("document_id") |> String.trim() do
      "" -> {:error, "Say which document."}
      id -> path(context, "/#{action}/#{encode(id)}")
    end
  end

  defp encode(value), do: URI.encode(value, &URI.char_unreserved?/1)

  def call(es, method, path, options \\ []) do
    request =
      options
      |> Keyword.merge(
        method: method,
        url: String.trim_trailing(es["url"], "/") <> path,
        receive_timeout: @timeout
      )
      |> Keyword.merge(authentication(es))
      |> Integration.req_options()

    case Req.request(request) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "Elasticsearch answered #{status}#{reason(body)}"}

      {:error, reason} ->
        {:error, "Could not reach Elasticsearch: #{Exception.message(reason)}"}
    end
  end

  defp authentication(%{"api_key" => key}) when key not in [nil, ""] do
    [headers: [authorization: "ApiKey #{key}"]]
  end

  defp authentication(%{"username" => username, "password" => password})
       when username not in [nil, ""] do
    [auth: {:basic, "#{username}:#{password}"}]
  end

  defp authentication(_es), do: []

  defp reason(%{"error" => %{"reason" => reason}}), do: ": #{reason}"
  defp reason(%{"error" => reason}) when is_binary(reason), do: ": #{reason}"
  defp reason(_body), do: ""
end
