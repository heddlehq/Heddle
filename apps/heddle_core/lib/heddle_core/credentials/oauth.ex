defmodule HeddleCore.Credentials.OAuth do
  @moduledoc """
  Credentials that connect through OAuth 2.0, with Heddle as the client.

  A credential kind connects this way when it has `:oauth2`, with the service's
  `authorize_url`, `token_url` and `scopes` (integration manifests declare them). A
  system admin registers an app with the service and gives Heddle its client id and
  secret. Then anyone who can edit credentials connects an account: the service sends
  them back with a code, and Heddle keeps the tokens it gets for it, encrypted.

  The access token is renewed with the refresh token before it expires, and when the
  service refuses it (see `HeddleCore.Credentials.fetch/4`).
  """

  import Ecto.Query, warn: false

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Credentials
  alias HeddleCore.Credentials.OAuthApp
  alias HeddleCore.Repo

  # Renewed this long before it expires, so a run doesn't start with a token that
  # stops working halfway.
  @margin_seconds 120

  @doc "The fields a credential of an OAuth 2.0 kind keeps."
  def fields do
    [
      %{name: "access_token", label: "Access token", secret: true, required: true},
      %{name: "refresh_token", label: "Refresh token", secret: true},
      %{name: "expires_at", label: "Expires at"}
    ]
  end

  @doc "The app registered for `kind`, or nil."
  def get_app(kind), do: Repo.get_by(OAuthApp, kind: kind)

  @doc "Whether an app is registered for `kind`."
  def app?(kind), do: Repo.exists?(from a in OAuthApp, where: a.kind == ^kind)

  @doc "Registers the app for `kind`. Only system admins can."
  def put_app(%Scope{} = scope, kind, client_id, client_secret) do
    client_id = String.trim(client_id || "")
    client_secret = String.trim(client_secret || "")

    cond do
      not Scope.system_admin?(scope) ->
        {:error, :forbidden}

      client_id == "" or client_secret == "" ->
        {:error, "Give the client ID and the client secret."}

      true ->
        app = get_app(kind) || %OAuthApp{kind: kind}

        app
        |> Ecto.Changeset.change(
          client_id: client_id,
          client_secret: Credentials.seal("oauth_app:" <> kind, %{"secret" => client_secret})
        )
        |> Repo.insert_or_update()
    end
  end

  defp client(kind) do
    case get_app(kind) do
      nil ->
        {:error,
         "No app is registered for this service yet. A system admin registers it on the Credentials page."}

      app ->
        {:ok, %{"secret" => secret}} =
          Credentials.unseal("oauth_app:" <> kind, app.client_secret)

        {:ok, app.client_id, secret}
    end
  end

  @doc """
  Where to send the person to connect an account of `kind`, with `state` and the PKCE
  `verifier` the callback checks.
  """
  def authorize_url(kind, redirect_uri, state, verifier) do
    with %{oauth2: oauth} <- Credentials.kind(kind) || {:error, "Unknown service."},
         {:ok, client_id, _secret} <- client(kind) do
      params =
        Map.merge(oauth[:authorize_params] || %{}, %{
          "response_type" => "code",
          "client_id" => client_id,
          "redirect_uri" => redirect_uri,
          "state" => state,
          "code_challenge" => challenge(verifier),
          "code_challenge_method" => "S256"
        })

      params =
        case oauth[:scopes] || [] do
          [] -> params
          scopes -> Map.put(params, "scope", Enum.join(scopes, " "))
        end

      {:ok, oauth.authorize_url <> separator(oauth.authorize_url) <> URI.encode_query(params)}
    end
  end

  defp separator(url), do: if(String.contains?(url, "?"), do: "&", else: "?")

  @doc "A random PKCE verifier."
  def verifier, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  defp challenge(verifier),
    do: :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

  @doc "Trades the `code` the service sent back for the values of a credential."
  def exchange(kind, code, redirect_uri, verifier) do
    token_request(kind, %{
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => redirect_uri,
      "code_verifier" => verifier
    })
  end

  @doc """
  Renews `values`, a credential's, if its access token expires soon or `force`. Returns
  `{:ok, values, changed?}`.
  """
  def ensure_fresh(kind, values, force \\ false) do
    cond do
      values["refresh_token"] in [nil, ""] -> {:ok, values, false}
      force or expiring?(values["expires_at"]) -> renew(kind, values)
      true -> {:ok, values, false}
    end
  end

  defp expiring?(expires_at) do
    case Integer.parse(to_string(expires_at || "")) do
      {at, ""} -> at - System.system_time(:second) < @margin_seconds
      _other -> false
    end
  end

  defp renew(kind, values) do
    with {:ok, renewed} <-
           token_request(kind, %{
             "grant_type" => "refresh_token",
             "refresh_token" => values["refresh_token"]
           }) do
      # Services that don't send a new refresh token keep taking the old one.
      renewed =
        if renewed["refresh_token"] in [nil, ""],
          do: Map.put(renewed, "refresh_token", values["refresh_token"]),
          else: renewed

      {:ok, renewed, true}
    end
  end

  defp token_request(kind, form) do
    with %{oauth2: oauth} <- Credentials.kind(kind) || {:error, "Unknown service."},
         {:ok, client_id, secret} <- client(kind) do
      {auth, form} =
        case oauth[:token_auth] do
          "basic" -> {[auth: {:basic, "#{client_id}:#{secret}"}], form}
          _body -> {[], Map.merge(form, %{"client_id" => client_id, "client_secret" => secret})}
        end

      # Most services take a form, and some (Notion) JSON.
      body = if oauth[:token_body] == "json", do: [json: form], else: [form: Map.to_list(form)]
      options = auth ++ body

      options =
        Keyword.merge(
          [retry: false, headers: [{"accept", "application/json"}]],
          Keyword.merge(options, Application.get_env(:heddle_core, :oauth_req_options, []))
        )

      case Req.post(oauth.token_url, options) do
        {:ok, %{status: 200, body: %{"access_token" => token} = body}} ->
          {:ok, values(token, body)}

        {:ok, %{body: %{"error" => error} = body}} ->
          {:error, "The service refused it: #{body["error_description"] || error}"}

        {:ok, %{status: status}} ->
          {:error, "The service answered #{status}."}

        {:error, reason} ->
          {:error, "Could not reach the service: #{Exception.message(reason)}"}
      end
    end
  end

  defp values(token, body) do
    expires_at =
      case body["expires_in"] do
        seconds when is_integer(seconds) -> to_string(System.system_time(:second) + seconds)
        _none -> ""
      end

    %{
      "access_token" => token,
      "refresh_token" => body["refresh_token"] || "",
      "expires_at" => expires_at
    }
  end
end
