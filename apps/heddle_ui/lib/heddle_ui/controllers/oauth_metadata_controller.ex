defmodule HeddleUI.OAuthMetadataController do
  @moduledoc """
  Authorization server metadata (RFC 8414). Clients use it to learn whether this
  server supports signing in through the browser.
  """
  use HeddleUI, :controller

  def show(conn, _params) do
    json(conn, %{
      issuer: url(~p"/"),
      authorization_endpoint: url(~p"/oauth/authorize"),
      token_endpoint: url(~p"/api/v1/oauth/token"),
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"]
    })
  end
end
