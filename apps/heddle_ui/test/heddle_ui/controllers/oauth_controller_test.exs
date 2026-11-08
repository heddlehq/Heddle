defmodule HeddleUI.OAuthControllerTest do
  use HeddleUI.ConnCase, async: true

  alias HeddleCore.ApiKeys

  @verifier String.duplicate("a", 64)
  @redirect_uri "http://127.0.0.1:53124/callback"

  defp challenge do
    :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  end

  defp params(overrides \\ %{}) do
    Map.merge(
      %{
        "client_id" => "treadle",
        "redirect_uri" => @redirect_uri,
        "response_type" => "code",
        "state" => "abc123",
        "code_challenge" => challenge(),
        "code_challenge_method" => "S256"
      },
      overrides
    )
  end

  defp callback_query(conn) do
    location = redirected_to(conn)
    assert String.starts_with?(location, @redirect_uri <> "?")
    location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end

  describe "metadata" do
    test "advertises the flow", %{conn: conn} do
      body = conn |> get("/.well-known/oauth-authorization-server") |> json_response(200)

      assert String.ends_with?(body["authorization_endpoint"], "/oauth/authorize")
      assert String.ends_with?(body["token_endpoint"], "/api/v1/oauth/token")
      assert body["code_challenge_methods_supported"] == ["S256"]
    end
  end

  describe "without a session" do
    test "the consent page sends the user to log in first", %{conn: conn} do
      HeddleCore.AccountsFixtures.user_fixture(%{is_system_admin: true})

      conn = get(conn, ~p"/oauth/authorize?#{params()}")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_return_to) =~ "/oauth/authorize?"
    end
  end

  describe "with a session" do
    setup :register_and_log_in_user

    setup %{user: user} do
      %{workspace: HeddleCore.AccountsFixtures.workspace_fixture(user)}
    end

    test "shows what the app is asking for", %{conn: conn} do
      html = conn |> get(~p"/oauth/authorize?#{params()}") |> html_response(200)

      assert html =~ "Treadle"
      assert html =~ "Create and change workflows"
      assert html =~ ~s(id="oauth-workspace")
    end

    test "approving for a workspace the person isn't in is denied", %{conn: conn} do
      other =
        HeddleCore.AccountsFixtures.workspace_fixture(HeddleCore.AccountsFixtures.user_fixture())

      form = Map.merge(params(), %{"decision" => "allow", "workspace_id" => other.id})

      conn = post(conn, ~p"/oauth/authorize", form)

      assert %{"error" => "access_denied"} = callback_query(conn)
    end

    test "refuses to render for an unknown client or a non-loopback redirect", %{conn: conn} do
      assert conn
             |> get(~p"/oauth/authorize?#{params(%{"client_id" => "evil"})}")
             |> html_response(400)

      conn =
        get(conn, ~p"/oauth/authorize?#{params(%{"redirect_uri" => "https://evil.example/cb"})}")

      assert html_response(conn, 400) =~ "isn&#39;t valid"
    end

    test "reports a bad challenge to the client", %{conn: conn} do
      conn = get(conn, ~p"/oauth/authorize?#{params(%{"code_challenge_method" => "plain"})}")

      assert %{"error" => "invalid_request", "state" => "abc123"} = callback_query(conn)
    end

    test "approving delivers a code that the token endpoint trades for a key",
         %{conn: conn, workspace: workspace} do
      form = Map.merge(params(), %{"decision" => "allow", "workspace_id" => workspace.id})
      conn = post(conn, ~p"/oauth/authorize", form)
      assert %{"code" => code, "state" => "abc123"} = callback_query(conn)

      body =
        build_conn()
        |> post(~p"/api/v1/oauth/token", %{
          "grant_type" => "authorization_code",
          "code" => code,
          "code_verifier" => @verifier,
          "redirect_uri" => @redirect_uri,
          "client_id" => "treadle"
        })
        |> json_response(200)

      assert body["token_type"] == "Bearer"
      assert {:ok, _api_key} = ApiKeys.authenticate(body["access_token"])

      assert build_conn()
             |> put_req_header("authorization", "Bearer " <> body["access_token"])
             |> get(~p"/api/v1/workflows")
             |> json_response(200)
    end

    test "cancelling issues no code", %{conn: conn} do
      conn = post(conn, ~p"/oauth/authorize", Map.put(params(), "decision", "deny"))

      assert %{"error" => "access_denied"} = query = callback_query(conn)
      refute Map.has_key?(query, "code")
    end

    test "the POST re-checks the redirect", %{conn: conn} do
      forged = params(%{"redirect_uri" => "https://evil.example/cb", "decision" => "allow"})

      assert conn |> post(~p"/oauth/authorize", forged) |> html_response(400)
    end
  end

  describe "token endpoint" do
    test "follows the OAuth error format", %{conn: conn} do
      bad_code = %{
        "grant_type" => "authorization_code",
        "code" => "nope",
        "code_verifier" => @verifier,
        "redirect_uri" => @redirect_uri,
        "client_id" => "treadle"
      }

      assert %{"error" => "invalid_grant"} =
               conn |> post(~p"/api/v1/oauth/token", bad_code) |> json_response(400)

      assert %{"error" => "unsupported_grant_type"} =
               conn
               |> post(~p"/api/v1/oauth/token", %{"grant_type" => "password"})
               |> json_response(400)
    end
  end
end
