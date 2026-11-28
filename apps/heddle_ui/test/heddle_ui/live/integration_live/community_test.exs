defmodule HeddleUI.IntegrationLive.CommunityTest do
  use HeddleUI.ConnCase, async: false

  import HeddleCore.AccountsFixtures
  import Phoenix.LiveViewTest

  alias HeddleCore.Integrations
  alias HeddleUI.Integrations.Catalog

  defp manifest(version) do
    """
    id: acme
    name: Acme
    version: #{version}
    base_url: https://api.acme.test/
    credential:
      fields: [{name: api_key, label: API key, secret: true}]
      auth: {type: bearer, token: "{{credential.api_key}}"}
    actions:
      - name: Create Ticket
        fields: [{name: title, label: Title}]
        request: {method: POST, path: tickets, body: {title: "{{fields.title}}"}}
    """
  end

  defp publish(version) do
    Catalog.put(%{
      "acme" => %{
        "id" => "acme",
        "name" => "Acme",
        "version" => version,
        "description" => "Tickets",
        "actions" => ["Create Ticket"],
        "manifest" => manifest(version)
      }
    })
  end

  setup %{conn: conn} do
    HeddleNodes.Community.reset()
    publish("1.0.0")

    on_exit(fn ->
      HeddleNodes.Community.reset()
      Catalog.clear()
    end)

    admin = user_fixture()
    workspace = workspace_fixture(admin)
    %{conn: log_in_user(conn, admin), admin: admin, workspace: workspace}
  end

  test "an admin installs a community integration, whose nodes then run", %{
    conn: conn,
    admin: admin
  } do
    {:ok, lv, _html} = live(conn, ~p"/integrations")

    assert has_element?(lv, "#integration-acme", "Community")
    assert has_element?(lv, "#integration-acme", "Not verified")

    lv |> element("#install-acme") |> render_click()

    assert has_element?(lv, "#integration-acme", "Installed")
    assert Integrations.installed(user_scope_fixture(admin)) == ["acme"]
    assert %{version: "1.0.0"} = Integrations.get_community("acme")

    assert %{name: "Acme: Create Ticket", community: "acme"} =
             HeddleNodes.Nodes.get_node("Acme: Create Ticket")

    assert HeddleNodes.Nodes.get_node_module("Acme: Create Ticket")
    assert Enum.any?(HeddleCore.Credentials.kinds(), &(&1.id == "acme"))
  end

  test "an editor can't install one", %{workspace: workspace} do
    editor = user_fixture()
    member_fixture(workspace, editor, "editor")
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(editor)

    {:ok, lv, _html} = live(conn, ~p"/integrations")

    assert has_element?(lv, "#integration-acme")
    refute has_element?(lv, "#install-acme")
    assert has_element?(lv, "#install-slack")
  end

  test "a system admin updates the instance to a newer version", %{workspace: workspace} do
    {:ok, lv, _html} =
      live(
        log_in_user(Phoenix.ConnTest.build_conn(), system_admin_in(workspace)),
        ~p"/integrations"
      )

    lv |> element("#install-acme") |> render_click()

    publish("1.1.0")

    {:ok, lv, _html} =
      live(
        log_in_user(Phoenix.ConnTest.build_conn(), system_admin_in(workspace)),
        ~p"/integrations"
      )

    lv |> element("#update-acme") |> render_click()

    assert %{version: "1.1.0"} = Integrations.get_community("acme")
    refute has_element?(lv, "#update-acme")
  end

  test "a manifest can't take an official integration's place", %{conn: conn} do
    Catalog.put(%{
      "slack" => %{
        "id" => "slack",
        "name" => "Slack",
        "version" => "9.0.0",
        "manifest" =>
          String.replace(manifest("9.0.0"), ["id: acme", "name: Acme"], fn
            "id: acme" -> "id: slack"
            "name: Acme" -> "name: Slack"
          end)
      }
    })

    {:ok, lv, _html} = live(conn, ~p"/integrations")

    refute has_element?(lv, "#integration-slack", "Community")
  end

  test "an editor installs an official manifest, downloaded from the catalog", %{
    workspace: workspace
  } do
    yaml = File.read!(Path.expand("../../../support/fixtures/notion.yaml", __DIR__))

    Catalog.put(%{
      "notion" => %{
        "id" => "notion",
        "name" => "Notion",
        "version" => "1.0.0",
        "manifest" => yaml
      }
    })

    editor = user_fixture()
    member_fixture(workspace, editor, "editor")
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(editor)

    {:ok, lv, _html} = live(conn, ~p"/integrations")

    assert has_element?(lv, "#integration-notion", "Official")
    refute has_element?(lv, "#integration-notion", "Not verified")

    lv |> element("#install-notion") |> render_click()

    assert has_element?(lv, "#integration-notion", "Installed")
    assert %{official: true, community: nil} = HeddleNodes.Nodes.get_node("Notion: Search")
  end

  defp system_admin_in(workspace) do
    admin = system_admin_fixture()
    member_fixture(workspace, admin, "admin")
    admin
  end
end
