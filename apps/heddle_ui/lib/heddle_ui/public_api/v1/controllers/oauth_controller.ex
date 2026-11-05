defmodule HeddleUI.PublicAPI.V1.OAuthController do
  use HeddleUI, :controller

  alias HeddleCore.OAuth

  def token(conn, %{"grant_type" => "authorization_code"} = params) do
    case OAuth.exchange_code(params) do
      {:ok, %{access_token: token, scopes: scopes}} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> json(%{access_token: token, token_type: "Bearer", scope: Enum.join(scopes, " ")})

      {:error, :invalid_grant} ->
        error(conn, "invalid_grant")
    end
  end

  def token(conn, _params), do: error(conn, "unsupported_grant_type")

  defp error(conn, code) do
    conn
    |> put_status(:bad_request)
    |> put_resp_header("cache-control", "no-store")
    |> json(%{error: code})
  end
end
