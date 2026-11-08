defmodule HeddleUI.ApiKeyLive.IndexTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures

  alias HeddleCore.ApiKeys
  alias HeddleCore.ApiKeys.ApiKey

  describe "mount /api-keys" do
    test "redirects someone in no workspace to root with flash", %{conn: conn} do
      user = user_fixture()

      assert {:error, {:redirect, %{to: path}}} =
               conn
               |> log_in_user(user)
               |> live(~p"/api-keys")

      assert path == ~p"/"
    end

    test "renders API key management for system admin", %{conn: conn} do
      admin = system_admin_fixture()

      {:ok, lv, html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/api-keys")

      assert html =~ "API keys"
      assert html =~ "Create key"
      assert html =~ "Existing keys"
      assert html =~ "A key does no more than your role here"
      assert has_element?(lv, "#api-key-scope-toggle", "Toggle all")

      for scope <- ApiKey.scopes() do
        assert has_element?(lv, "input[name='api_key[scopes][]'][value='#{scope}']")
      end
    end
  end

  describe "create" do
    test "creates an API key and shows the token only once", %{conn: conn} do
      admin = system_admin_fixture()

      {:ok, lv, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/api-keys")

      html =
        lv
        |> form("#api-key-form", %{
          "api_key" => %{
            "name" => "Deploy key",
            "expires_in" => "30",
            "scopes" => ["flows:read", "flows:write"]
          }
        })
        |> render_submit()

      assert html =~ "Copy this token now"
      assert html =~ "hd_live_"
      # Its own id, so the browser doesn't keep the name typed in it.
      assert has_element?(lv, "#api-key-token[value^='hd_live_']")
      assert html =~ "Deploy key"
      assert html =~ "flows:read"
      assert html =~ "flows:write"

      [api_key] = ApiKeys.list_api_keys(HeddleCore.Accounts.Scope.for_user(admin))
      assert api_key.name == "Deploy key"
      assert api_key.scopes == ["flows:read", "flows:write"]
      assert api_key.expires_at != nil

      {:ok, _lv, html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/api-keys")

      refute html =~ "Copy this token now"
      refute html =~ "hd_live_"
      assert html =~ "Deploy key"
      assert html =~ api_key.prefix
    end
  end

  describe "revoke" do
    test "revokes an active API key", %{conn: conn} do
      admin = system_admin_fixture()

      {:ok, %{api_key: api_key}} =
        HeddleCore.AccountsFixtures.create_api_key(admin, %{name: "CI key"})

      {:ok, lv, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/api-keys")

      html =
        lv
        |> element("#api-key-#{api_key.id} button", "Revoke")
        |> render_click()

      assert html =~ "Revoked"
      refute has_element?(lv, "#api-key-#{api_key.id} button", "Revoke")
      assert ApiKey.revoked?(HeddleCore.Repo.get!(ApiKey, api_key.id))
    end
  end

  describe "roles" do
    test "offers only the scopes the person's role reaches", %{conn: conn} do
      admin = system_admin_fixture()
      viewer = user_fixture()
      member_fixture(ensure_workspace(admin), viewer, "viewer")

      {:ok, lv, _html} = conn |> log_in_user(viewer) |> live(~p"/api-keys")

      assert has_element?(lv, "input[value='workflows:read']")
      refute has_element?(lv, "input[value='workflows:write']")
      refute has_element?(lv, "input[value='executions:write']")
    end
  end
end
