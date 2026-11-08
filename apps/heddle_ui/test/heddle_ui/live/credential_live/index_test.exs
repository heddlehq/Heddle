defmodule HeddleUI.CredentialLive.IndexTest do
  use HeddleUI.ConnCase, async: false

  import HeddleCore.AccountsFixtures
  import Phoenix.LiveViewTest

  alias HeddleCore.Credentials

  setup %{conn: conn} do
    admin = system_admin_fixture()
    %{conn: log_in_user(conn, admin), ws: ensure_workspace(admin).id}
  end

  defp add(lv, name, token) do
    lv
    |> form("#credential-form", %{
      "credential" => %{"name" => name, "kind" => "slack", "values" => %{"token" => token}}
    })
    |> render_submit()
  end

  test "is only for people in a workspace" do
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(user_fixture())

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/credentials")
  end

  test "a viewer sees the names, with nothing to change them", %{ws: ws} do
    {:ok, _credential} =
      Credentials.insert_credential(%{name: "main", kind: "slack", values: %{"token" => "t"}}, ws)

    viewer = user_fixture()
    member_fixture(HeddleCore.Workspaces.get_workspace(ws), viewer, "viewer")
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(viewer)

    {:ok, lv, html} = live(conn, ~p"/credentials")

    assert html =~ "main"
    assert has_element?(lv, "#credentials-read-only")
    refute has_element?(lv, "#credential-form")
    refute html =~ "hero-trash"
  end

  test "a shared credential is marked, and only system admins share one", %{conn: conn, ws: ws} do
    {:ok, lv, _html} = live(conn, ~p"/credentials")

    lv
    |> form("#credential-form", %{
      "credential" => %{
        "name" => "openai",
        "kind" => "slack",
        "shared" => "true",
        "values" => %{"token" => "t"}
      }
    })
    |> render_submit()

    assert render(lv) =~ "Shared"
    assert Credentials.fetch(nil, "openai", "slack") == {:ok, %{"token" => "t"}}

    editor = user_fixture()
    member_fixture(HeddleCore.Workspaces.get_workspace(ws), editor, "editor")

    {:ok, editor_lv, _html} =
      live(Phoenix.ConnTest.build_conn() |> log_in_user(editor), ~p"/credentials")

    refute has_element?(editor_lv, "#credential-shared")
  end

  test "adds a credential and never shows the secret", %{conn: conn, ws: ws} do
    {:ok, lv, _html} = live(conn, ~p"/credentials")

    html = add(lv, "main", "xoxb-secret")

    assert has_element?(lv, "#credentials [id^=credentials-]", "main")
    refute html =~ "xoxb-secret"
    assert Credentials.fetch(ws, "main", "slack") == {:ok, %{"token" => "xoxb-secret"}}
  end

  test "shows the fields of the chosen service", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/credentials")

    assert has_element?(lv, "#credential-value-token")

    lv |> form("#credential-form", %{"credential" => %{"kind" => "smtp"}}) |> render_change()

    assert has_element?(lv, "#credential-value-host")
    refute has_element?(lv, "#credential-value-token")
    assert has_element?(lv, ~s(#credential_kind option[value="smtp"][selected]))
  end

  test "saves a credential of the chosen service", %{conn: conn, ws: ws} do
    {:ok, lv, _html} = live(conn, ~p"/credentials")

    lv |> form("#credential-form", %{"credential" => %{"kind" => "smtp"}}) |> render_change()

    lv
    |> form("#credential-form", %{
      "credential" => %{
        "name" => "mail",
        "values" => %{"host" => "smtp.x.co", "from" => "a@x.co"}
      }
    })
    |> render_submit()

    assert {:ok, %{"host" => "smtp.x.co"}} = Credentials.fetch(ws, "mail", "smtp")
  end

  test "says what's missing", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/credentials")

    assert add(lv, "main", "") =~ "Bot token can&#39;t be blank"
  end

  test "edits without showing the secret, and keeps it when left blank", %{conn: conn, ws: ws} do
    {:ok, credential} =
      Credentials.insert_credential(
        %{name: "main", kind: "slack", values: %{"token" => "xoxb-old"}},
        ws
      )

    {:ok, lv, _html} = live(conn, ~p"/credentials")

    html = lv |> element("#edit-credentials-#{credential.id}") |> render_click()
    refute html =~ "xoxb-old"

    lv
    |> form("#credential-form", %{
      "credential" => %{"name" => "renamed", "values" => %{"token" => ""}}
    })
    |> render_submit()

    assert Credentials.fetch(ws, "renamed", "slack") == {:ok, %{"token" => "xoxb-old"}}
  end

  test "deletes a credential", %{conn: conn, ws: ws} do
    {:ok, credential} =
      Credentials.insert_credential(%{name: "main", kind: "slack", values: %{"token" => "x"}}, ws)

    {:ok, lv, _html} = live(conn, ~p"/credentials")

    lv |> element("#delete-credentials-#{credential.id}") |> render_click()

    refute has_element?(lv, "#credentials-#{credential.id}")
    assert has_element?(lv, "#credentials-empty")
  end

  describe "a database credential" do
    test "picks its engine and never shows the password again", %{conn: conn, ws: ws} do
      {:ok, lv, _html} = live(conn, ~p"/credentials")

      lv
      |> form("#credential-form", %{"credential" => %{"kind" => "sql"}})
      |> render_change()

      assert has_element?(lv, "#credential-value-engine option[value=oracle]")
      assert has_element?(lv, "#credential-value-ssl")

      lv
      |> form("#credential-form", %{
        "credential" => %{
          "name" => "shop",
          "kind" => "sql",
          "values" => %{"engine" => "mysql", "database" => "shop", "password" => "s3cret"}
        }
      })
      |> render_submit()

      assert {:ok, %{"engine" => "mysql", "password" => "s3cret"}} =
               Credentials.fetch(ws, "shop", "sql")

      refute render(lv) =~ "s3cret"
    end
  end
end
