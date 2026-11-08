defmodule HeddleUI.OAuthController do
  @moduledoc """
  The browser side of the OAuth flow: the page where a user approves a native app.
  """
  use HeddleUI, :controller

  alias HeddleCore.OAuth
  alias HeddleCore.Workspaces

  plug :put_view, html: HeddleUI.OAuthHTML

  @form_params ~w(client_id redirect_uri response_type state code_challenge code_challenge_method)

  def new(conn, params) do
    with_valid_request(conn, params, fn conn, client ->
      scope = conn.assigns.current_scope

      render(conn, :new,
        client: client,
        form_params: Map.take(params, @form_params),
        workspaces: Workspaces.list_workspaces(scope),
        current_workspace_id: scope.workspace && scope.workspace.id
      )
    end)
  end

  def create(conn, %{"decision" => "allow"} = params) do
    with_valid_request(conn, params, fn conn, client ->
      user = conn.assigns.current_scope.user

      # The app reaches one workspace, picked here, with the person's role in it.
      case OAuth.create_authorization_code(
             user,
             parse_id(params["workspace_id"]),
             client,
             params["redirect_uri"],
             params["code_challenge"]
           ) do
        {:ok, code} ->
          redirect_to_client(conn, params, code: code)

        {:error, :forbidden} ->
          redirect_to_client(conn, params, error: "access_denied")

        {:error, _changeset} ->
          redirect_to_client(conn, params, error: "server_error")
      end
    end)
  end

  def create(conn, params) do
    with_valid_request(conn, params, fn conn, _client ->
      redirect_to_client(conn, params, error: "access_denied")
    end)
  end

  # Runs on the POST as well: nothing the GET checked survives in the form.
  defp with_valid_request(conn, params, fun) do
    client = OAuth.get_client(params["client_id"])

    cond do
      # Without a trusted redirect there is nowhere safe to send an error.
      is_nil(client) or not OAuth.valid_redirect_uri?(params["redirect_uri"]) ->
        conn |> put_status(:bad_request) |> render(:invalid)

      params["response_type"] != "code" ->
        redirect_to_client(conn, params, error: "unsupported_response_type")

      params["code_challenge_method"] != "S256" or
          not OAuth.valid_code_challenge?(params["code_challenge"]) ->
        redirect_to_client(conn, params, error: "invalid_request")

      true ->
        fun.(conn, client)
    end
  end

  defp parse_id(id) do
    case Integer.parse(to_string(id)) do
      {id, ""} -> id
      _other -> nil
    end
  end

  defp redirect_to_client(conn, params, result) do
    query =
      result
      |> Keyword.put(:state, params["state"] || "")
      |> URI.encode_query()

    uri = params["redirect_uri"] |> URI.parse() |> URI.append_query(query) |> URI.to_string()

    redirect(conn, external: uri)
  end
end
