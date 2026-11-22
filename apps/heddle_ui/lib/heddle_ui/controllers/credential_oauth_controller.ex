defmodule HeddleUI.CredentialOAuthController do
  @moduledoc """
  Connects an account of a service as a credential, through OAuth 2.0: sends the
  person to the service, and takes the code it sends back. See
  `HeddleCore.Credentials.OAuth`.

  What the callback needs (the service, the name, the PKCE verifier) waits in the
  session under a random `state`, which the service hands back.
  """

  use HeddleUI, :controller

  alias HeddleCore.Credentials
  alias HeddleCore.Credentials.OAuth
  alias HeddleCore.Workspaces

  @session_key "credential_oauth"

  def start(conn, %{"kind" => kind, "name" => name} = params) do
    scope = conn.assigns.current_scope
    name = String.trim(name)
    shared = params["shared"] == "true"

    cond do
      not (Workspaces.can?(scope, :edit) or
               (shared and HeddleCore.Accounts.Scope.system_admin?(scope))) ->
        back(conn, :error, gettext("Your role in this workspace can't add credentials."))

      name == "" ->
        back(conn, :error, gettext("Give the credential a name."))

      true ->
        state = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
        verifier = OAuth.verifier()

        case OAuth.authorize_url(kind, callback_url(), state, verifier) do
          {:ok, url} ->
            conn
            |> put_session(@session_key, %{
              "state" => state,
              "verifier" => verifier,
              "kind" => kind,
              "name" => name,
              "shared" => shared
            })
            |> redirect(external: url)

          {:error, message} ->
            back(conn, :error, message)
        end
    end
  end

  def callback(conn, params) do
    pending = get_session(conn, @session_key)
    conn = delete_session(conn, @session_key)

    cond do
      is_nil(pending) or params["state"] != pending["state"] ->
        back(conn, :error, gettext("This connection expired. Try again."))

      params["error"] ->
        back(
          conn,
          :error,
          gettext("The service didn't allow the connection: %{error}", error: params["error"])
        )

      true ->
        with {:ok, values} <-
               OAuth.exchange(
                 pending["kind"],
                 params["code"],
                 callback_url(),
                 pending["verifier"]
               ),
             {:ok, _credential} <-
               Credentials.create_credential(conn.assigns.current_scope, %{
                 "name" => pending["name"],
                 "kind" => pending["kind"],
                 "shared" => pending["shared"],
                 "values" => values
               }) do
          back(conn, :info, gettext("%{name} connected.", name: pending["name"]))
        else
          {:error, %Ecto.Changeset{}} ->
            back(conn, :error, gettext("A credential with this name already exists."))

          {:error, :forbidden} ->
            back(conn, :error, gettext("Your role in this workspace can't add credentials."))

          {:error, message} ->
            back(conn, :error, message)
        end
    end
  end

  @doc "Where the service sends the person back: what an admin registers with it."
  def callback_url, do: HeddleUI.Endpoint.url() <> "/integrations/oauth/callback"

  defp back(conn, kind, message) do
    conn |> put_flash(kind, message) |> redirect(to: ~p"/credentials")
  end
end
