defmodule HeddleNodes.Services.Slack do
  @moduledoc """
  The Slack Web API, for the Slack nodes.
  """

  alias HeddleNodes.Integration

  @api "https://slack.com/api/"
  @page_size 200
  @service %{
    title: "Slack",
    category: :slack,
    credential: "slack",
    icon: "logo-slack"
  }

  def definition(action, description, fields) do
    Integration.definition(@service, action, description, fields)
  end

  def run(context, fun) do
    Integration.run(context, "slack", fn %{"token" => token} -> fun.(token) end)
  end

  def post(token, method, body) do
    reply(Req.post(@api <> method, Integration.req_options(auth: {:bearer, token}, json: body)))
  end

  # Slack's read methods don't take JSON.
  def get(token, method, params) do
    reply(
      Req.get(@api <> method, Integration.req_options(auth: {:bearer, token}, params: params))
    )
  end

  @doc """
  Returns every page of a list method, under `key`.
  """
  def get_all(token, method, key, params, cursor \\ "") do
    page = Keyword.merge(params, limit: @page_size, cursor: cursor)

    with {:ok, reply} <- get(token, method, page) do
      case get_in(reply, ["response_metadata", "next_cursor"]) do
        next when next in [nil, ""] ->
          {:ok, reply[key]}

        next ->
          with {:ok, rest} <- get_all(token, method, key, params, next) do
            {:ok, reply[key] ++ rest}
          end
      end
    end
  end

  def upload(url, content) do
    case Req.post(url, Integration.req_options(body: content)) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} -> {:error, "Slack answered #{status}"}
      {:error, reason} -> {:error, unreachable(reason)}
    end
  end

  defp reply({:ok, %{status: 200, body: %{"ok" => true} = reply}}), do: {:ok, reply}
  defp reply({:ok, %{body: %{"error" => error}}}), do: {:error, "Slack refused it: #{error}"}
  defp reply({:ok, %{status: status}}), do: {:error, "Slack answered #{status}"}
  defp reply({:error, reason}), do: {:error, unreachable(reason)}

  defp unreachable(reason), do: "Could not reach Slack: #{Exception.message(reason)}"
end
