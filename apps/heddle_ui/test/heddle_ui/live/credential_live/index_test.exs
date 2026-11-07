defmodule HeddleUI.CredentialLive.IndexTest do
  use HeddleUI.ConnCase, async: false

  import HeddleCore.AccountsFixtures
  import Phoenix.LiveViewTest

  alias HeddleCore.Credentials

  setup %{conn: conn} do
    %{conn: log_in_user(conn, system_admin_fixture())}
  end

  defp add(lv, name, token) do
    lv
    |> form("#credential-form", %{
      "credential" => %{"name" => name, "kind" => "slack", "values" => %{"token" => token}}
    })
    |> render_submit()
  end

  test "is only for admins" do
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(user_fixture())

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/credentials")
  end

  test "adds a credential and never shows the secret", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/credentials")

    html = add(lv, "main", "xoxb-secret")

    assert has_element?(lv, "#credentials [id^=credentials-]", "main")
    refute html =~ "xoxb-secret"
    assert Credentials.fetch("main", "slack") == {:ok, %{"token" => "xoxb-secret"}}
  end

  test "shows the fields of the chosen service", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/credentials")

    assert has_element?(lv, "#credential-value-token")

    lv |> form("#credential-form", %{"credential" => %{"kind" => "smtp"}}) |> render_change()

    assert has_element?(lv, "#credential-value-host")
    refute has_element?(lv, "#credential-value-token")
    assert has_element?(lv, ~s(#credential_kind option[value="smtp"][selected]))
  end

  test "saves a credential of the chosen service", %{conn: conn} do
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

    assert {:ok, %{"host" => "smtp.x.co"}} = Credentials.fetch("mail", "smtp")
  end

  test "says what's missing", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/credentials")

    assert add(lv, "main", "") =~ "Bot token can&#39;t be blank"
  end

  test "edits without showing the secret, and keeps it when left blank", %{conn: conn} do
    {:ok, credential} =
      Credentials.create_credential(%{
        name: "main",
        kind: "slack",
        values: %{"token" => "xoxb-old"}
      })

    {:ok, lv, _html} = live(conn, ~p"/credentials")

    html = lv |> element("#edit-credentials-#{credential.id}") |> render_click()
    refute html =~ "xoxb-old"

    lv
    |> form("#credential-form", %{
      "credential" => %{"name" => "renamed", "values" => %{"token" => ""}}
    })
    |> render_submit()

    assert Credentials.fetch("renamed", "slack") == {:ok, %{"token" => "xoxb-old"}}
  end

  test "deletes a credential", %{conn: conn} do
    {:ok, credential} =
      Credentials.create_credential(%{name: "main", kind: "slack", values: %{"token" => "x"}})

    {:ok, lv, _html} = live(conn, ~p"/credentials")

    lv |> element("#delete-credentials-#{credential.id}") |> render_click()

    refute has_element?(lv, "#credentials-#{credential.id}")
    assert has_element?(lv, "#credentials-empty")
  end

  describe "a database credential" do
    test "picks its engine and never shows the password again", %{conn: conn} do
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
               Credentials.fetch("shop", "sql")

      refute render(lv) =~ "s3cret"
    end
  end
end
