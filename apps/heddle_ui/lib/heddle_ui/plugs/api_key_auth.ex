defmodule HeddleUI.Plugs.ApiKeyAuth do
  @moduledoc """
  Authenticates public API requests with a Heddle API key.
  """

  import Plug.Conn

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.ApiKeys
  alias HeddleCore.ApiKeys.ApiKey
  alias HeddleUI.ApiError

  def init(opts), do: opts

  def call(conn, opts) do
    required_scopes = Keyword.get(opts, :scopes, [])

    with {:ok, token} <- fetch_token(conn),
         {:ok, %ApiKey{} = api_key} <- ApiKeys.authenticate(token),
         # Its owner left the workspace, or it was deleted: the key opens nothing.
         %Scope{role: role} = scope when not is_nil(role) <- Scope.for_api_key(api_key) do
      if ApiKey.allows?(api_key, required_scopes) do
        conn
        |> assign(:api_key, api_key)
        |> assign(:current_scope, scope)
        |> HeddleUI.Plugs.RateLimit.call([])
        |> HeddleUI.Plugs.ApiAuditLog.call([])
      else
        forbidden(conn)
      end
    else
      _ -> unauthorized(conn)
    end
  end

  defp fetch_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] when token != "" ->
        {:ok, token}

      _ ->
        case get_req_header(conn, "x-heddle-api-key") do
          [token | _] when token != "" -> {:ok, token}
          _ -> :error
        end
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:unauthorized, Jason.encode!(ApiError.format(:unauthorized, "Unauthorized")))
    |> halt()
  end

  defp forbidden(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:forbidden, Jason.encode!(ApiError.format(:forbidden, "Forbidden")))
    |> halt()
  end
end
