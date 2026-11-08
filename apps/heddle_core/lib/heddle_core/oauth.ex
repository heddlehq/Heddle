defmodule HeddleCore.OAuth do
  @moduledoc """
  OAuth 2.0 authorization code flow with PKCE, for native apps.

  Heddle is the authorization server. A native client such as Treadle sends the user
  to the browser, receives a code on a loopback address (RFC 8252) and exchanges it
  for an access token. The access token is an API key, so the public API needs no
  second way to authenticate and the user can revoke it on the API keys page.
  """

  import Ecto.Query, warn: false

  alias HeddleCore.Accounts.User
  alias HeddleCore.ApiKeys
  alias HeddleCore.ApiKeys.ApiKey
  alias HeddleCore.OAuth.AuthorizationCode
  alias HeddleCore.Repo
  alias HeddleCore.Workspaces

  @code_ttl_seconds 60
  @code_bytes 32
  @verifier_length 43..128
  @loopback_hosts ["127.0.0.1", "::1", "localhost"]

  @clients %{
    "treadle" => %{
      id: "treadle",
      name: "Treadle",
      scopes: ~w(
        workflows:read
        workflows:write
        workflows:delete
        nodes:read
        executions:read
        executions:write
      )
    }
  }

  def get_client(client_id) when is_binary(client_id), do: Map.get(@clients, client_id)
  def get_client(_client_id), do: nil

  @doc """
  Only loopback addresses are accepted: with no client secret, the redirect is what
  keeps a code from being delivered to anyone but the app on the user's machine.
  """
  def valid_redirect_uri?(uri) when is_binary(uri) do
    case URI.new(uri) do
      {:ok, %URI{scheme: "http", host: host, port: port, fragment: nil, userinfo: nil}}
      when host in @loopback_hosts and is_integer(port) ->
        true

      _ ->
        false
    end
  end

  def valid_redirect_uri?(_uri), do: false

  @doc """
  A S256 challenge is the base64url SHA-256 of the verifier: 43 characters, no padding.
  """
  def valid_code_challenge?(challenge) when is_binary(challenge) do
    byte_size(challenge) == 43 and challenge =~ ~r/\A[A-Za-z0-9_-]+\z/
  end

  def valid_code_challenge?(_challenge), do: false

  @doc """
  Issues a single-use code for a request the user approved. Only its hash is stored.
  """
  def create_authorization_code(%User{} = user, workspace_id, client, redirect_uri, challenge) do
    case Workspaces.role_of(user, workspace_id) do
      nil -> {:error, :forbidden}
      role -> insert_code(user, workspace_id, role, client, redirect_uri, challenge)
    end
  end

  # The token gets no more than the person can do in that workspace.
  defp insert_code(%User{id: user_id}, workspace_id, role, client, redirect_uri, code_challenge) do
    code = @code_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    now = DateTime.utc_now(:second)

    Repo.delete_all(from c in AuthorizationCode, where: c.expires_at < ^now)

    attrs = %{
      user_id: user_id,
      workspace_id: workspace_id,
      code_hash: ApiKeys.hash_token(code),
      client_id: client.id,
      redirect_uri: redirect_uri,
      code_challenge: code_challenge,
      scopes: Enum.filter(client.scopes, &(&1 in ApiKey.scopes_for(role))),
      expires_at: DateTime.add(now, @code_ttl_seconds, :second)
    }

    with {:ok, _record} <-
           %AuthorizationCode{} |> AuthorizationCode.create_changeset(attrs) |> Repo.insert() do
      {:ok, code}
    end
  end

  @doc """
  Trades a code for an access token.

  The code is spent before anything else is checked, so a failed attempt can't be
  retried with a different verifier.
  """
  def exchange_code(%{
        "code" => code,
        "code_verifier" => verifier,
        "redirect_uri" => redirect_uri,
        "client_id" => client_id
      })
      when is_binary(code) and is_binary(verifier) and is_binary(redirect_uri) and
             is_binary(client_id) do
    with {:ok, record} <- spend_code(code),
         true <- record.client_id == client_id,
         true <- record.redirect_uri == redirect_uri,
         true <- verifier_matches?(verifier, record.code_challenge),
         %User{} = user <- Repo.get(User, record.user_id),
         {:ok, %{token: token}} <- create_access_token(user, record) do
      {:ok, %{access_token: token, scopes: record.scopes}}
    else
      _ -> {:error, :invalid_grant}
    end
  end

  def exchange_code(_params), do: {:error, :invalid_grant}

  defp spend_code(code) do
    hash = ApiKeys.hash_token(code)
    now = DateTime.utc_now(:second)

    query =
      from c in AuthorizationCode,
        where: c.code_hash == ^hash and is_nil(c.used_at) and c.expires_at > ^now,
        select: c

    case Repo.update_all(query, set: [used_at: now]) do
      {1, [record]} -> {:ok, record}
      _ -> :error
    end
  end

  defp verifier_matches?(verifier, challenge) do
    if String.length(verifier) in @verifier_length do
      computed = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
      byte_size(computed) == byte_size(challenge) and :crypto.hash_equals(computed, challenge)
    else
      false
    end
  end

  defp create_access_token(user, %AuthorizationCode{} = record) do
    name = "#{get_client(record.client_id).name} (browser sign-in)"
    ApiKeys.create_api_key(user, record.workspace_id, %{name: name, scopes: record.scopes})
  end
end
