defmodule HeddleUI.CredentialOAuthControllerTest do
  use HeddleUI.ConnCase, async: false

  import HeddleCore.AccountsFixtures
  import Phoenix.LiveViewTest

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Credentials
  alias HeddleCore.Credentials.OAuth

  setup %{conn: conn} do
    admin = system_admin_fixture()
    workspace = ensure_workspace(admin)
    scope = Scope.for_user(HeddleCore.Accounts.get_user!(admin.id))

    # Notion is downloaded from the catalog; this is the YAML HeddleNodes.Official pins.
    yaml = File.read!(Path.expand("../../support/fixtures/notion.yaml", __DIR__))

    :ok =
      HeddleCore.Integrations.install_community(scope, %{
        "integration" => "notion",
        "version" => "1.0.0",
        "manifest" => yaml
      })

    HeddleNodes.Community.refresh()
    on_exit(&HeddleNodes.Community.reset/0)

    %{conn: log_in_user(conn, admin), scope: scope, workspace: workspace}
  end

  defp register_app(scope), do: {:ok, _app} = OAuth.put_app(scope, "notion", "cid", "csecret")

  test "Notion connects through OAuth 2.0, with its own fields" do
    assert %{oauth2: %{token_auth: "basic", token_body: "json"}, fields: fields} =
             Credentials.kind("notion")

    assert Enum.map(fields, & &1.name) == ["access_token", "refresh_token", "expires_at"]
  end

  test "the page asks for the app first, and then offers to connect", %{conn: conn, scope: scope} do
    {:ok, lv, _html} = live(conn, ~p"/credentials")

    lv |> form("#credential-form", %{"credential" => %{"kind" => "notion"}}) |> render_change()

    assert has_element?(lv, "#credential-oauth-no-app")
    assert has_element?(lv, "#credential-save[disabled]")
    assert has_element?(lv, "#oauth-app-form", "/integrations/oauth/callback")

    lv
    |> form("#oauth-app-form", %{"app" => %{"client_id" => "cid", "client_secret" => "cs"}})
    |> render_submit()

    refute has_element?(lv, "#credential-oauth-no-app")
    assert OAuth.app?("notion")
    assert %{client_id: "cid"} = OAuth.get_app("notion")
    refute OAuth.get_app("notion").client_secret =~ "cs"

    assert {:error, {:redirect, %{to: "/integrations/oauth/start?" <> query}}} =
             lv
             |> form("#credential-form", %{
               "credential" => %{"kind" => "notion", "name" => "docs"}
             })
             |> render_submit()

    assert %{"kind" => "notion", "name" => "docs"} = URI.decode_query(query)
    _ = scope
  end

  test "connects an account and keeps its tokens", %{conn: conn, scope: scope, workspace: ws} do
    register_app(scope)

    conn = get(conn, ~p"/integrations/oauth/start?kind=notion&name=docs")
    location = redirected_to(conn, 302)
    assert location =~ "https://api.notion.com/v1/oauth/authorize?"

    params = location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert %{"client_id" => "cid", "owner" => "user", "code_challenge_method" => "S256"} = params

    Req.Test.stub(OAuth, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == [
               "Basic " <> Base.encode64("cid:csecret")
             ]

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert %{"grant_type" => "authorization_code", "code" => "c0de"} = Jason.decode!(body)
      Req.Test.json(conn, %{"access_token" => "at1", "token_type" => "bearer"})
    end)

    conn = get(conn, ~p"/integrations/oauth/callback?code=c0de&state=#{params["state"]}")
    assert redirected_to(conn) == "/credentials"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "docs connected"

    assert {:ok, %{"access_token" => "at1"}} = Credentials.fetch(ws.id, "docs", "notion")
  end

  test "refuses a callback whose state doesn't match", %{conn: conn, scope: scope} do
    register_app(scope)
    conn = get(conn, ~p"/integrations/oauth/start?kind=notion&name=docs")
    conn = get(conn, ~p"/integrations/oauth/callback?code=c0de&state=other")

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
  end

  test "renews a token that expires soon, and keeps the new one", %{scope: scope, workspace: ws} do
    register_app(scope)
    soon = to_string(System.system_time(:second) + 10)

    {:ok, _credential} =
      Credentials.insert_credential(
        %{
          name: "docs",
          kind: "notion",
          values: %{"access_token" => "old", "refresh_token" => "rt", "expires_at" => soon}
        },
        ws.id
      )

    Req.Test.stub(OAuth, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert %{"grant_type" => "refresh_token", "refresh_token" => "rt"} = Jason.decode!(body)
      Req.Test.json(conn, %{"access_token" => "new", "expires_in" => 3600})
    end)

    assert {:ok, %{"access_token" => "new", "refresh_token" => "rt"}} =
             Credentials.fetch(ws.id, "docs", "notion")

    # Stored: the next read needs no request.
    Req.Test.stub(OAuth, fn _conn -> flunk("renewed twice") end)
    assert {:ok, %{"access_token" => "new"}} = Credentials.fetch(ws.id, "docs", "notion")
  end
end
