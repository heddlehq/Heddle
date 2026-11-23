defmodule HeddleUI.IntegrationLive.CreateTest do
  use HeddleUI.ConnCase, async: false

  import HeddleCore.AccountsFixtures
  import Phoenix.LiveViewTest

  alias HeddleCore.Integrations
  alias HeddleUI.Integrations.Catalog

  @manifest """
  id: widgets
  name: Widgets
  version: 1.0.0
  icon: hero-cube
  base_url: https://api.widgets.test/
  credential:
    fields: [{name: api_key, label: API key, secret: true}]
    auth: {type: bearer, token: "{{credential.api_key}}"}
  actions:
    - name: List Widgets
      request: {method: GET, path: widgets}
  """

  setup %{conn: conn} do
    HeddleNodes.Community.reset()
    Catalog.put(%{})

    on_exit(fn ->
      HeddleNodes.Community.reset()
      Catalog.clear()
    end)

    admin = user_fixture()
    workspace = workspace_fixture(admin)
    %{conn: log_in_user(conn, admin), admin: admin, workspace: workspace}
  end

  defp open(lv) do
    lv |> element("#create-integration") |> render_click()
    lv
  end

  defp write(lv, yaml) do
    lv |> form("#create-integration-form", integration: %{manifest: yaml}) |> render_change()
    lv
  end

  test "an admin writes a manifest, which is installed and gives nodes", %{
    conn: conn,
    admin: admin
  } do
    {:ok, lv, _html} = live(conn, ~p"/integrations")

    lv |> open() |> write(@manifest)

    assert has_element?(lv, "#create-integration-valid", "Widgets")
    assert has_element?(lv, "#create-integration-valid", "List Widgets")

    lv |> form("#create-integration-form", integration: %{manifest: @manifest}) |> render_submit()

    refute has_element?(lv, "#create-integration-modal")
    assert has_element?(lv, "#integration-widgets", "Installed")
    assert Integrations.installed(user_scope_fixture(admin)) == ["widgets"]
    assert %{version: "1.0.0"} = Integrations.get_community("widgets")
    assert %{community: "widgets"} = HeddleNodes.Nodes.get_node("Widgets: List Widgets")
  end

  test "the editor starts with a manifest that works", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/integrations")

    lv |> open()

    assert has_element?(lv, "#create-integration-valid", "My Service")
    refute has_element?(lv, "#create-integration-submit[disabled]")
  end

  test "links to Bobbin's guide to write a manifest", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/integrations")

    lv |> open()

    assert has_element?(
             lv,
             ~s(#create-integration-docs[href="https://hexdocs.pm/bobbin/manifest.html"])
           )
  end

  test "what is wrong shows while writing, and nothing is created", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/integrations")

    lv |> open() |> write(String.replace(@manifest, "version: 1.0.0", "version: one"))

    assert has_element?(lv, "#create-integration-problems", "version")
    assert has_element?(lv, "#create-integration-submit[disabled]")

    lv |> write("id: [")
    assert has_element?(lv, "#create-integration-problems", "Invalid YAML")
    assert Integrations.get_community("widgets") == nil
  end

  test "an id already taken, or an official one, is refused", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/integrations")

    lv |> open() |> write(@manifest)
    lv |> form("#create-integration-form", integration: %{manifest: @manifest}) |> render_submit()

    lv |> open() |> write(@manifest)
    assert has_element?(lv, "#create-integration-problems", "widgets")

    slack =
      String.replace(@manifest, ["id: widgets", "name: Widgets"], fn
        "id: widgets" -> "id: slack"
        "name: Widgets" -> "name: Slack"
      end)

    lv |> write(slack)
    assert has_element?(lv, "#create-integration-problems", "official")
  end

  test "an editor can't create one", %{workspace: workspace} do
    editor = user_fixture()
    member_fixture(workspace, editor, "editor")
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(editor)

    {:ok, lv, _html} = live(conn, ~p"/integrations")

    refute has_element?(lv, "#create-integration")
    assert render_hook(lv, "open_create", %{}) =~ "can&#39;t change integrations"
    refute has_element?(lv, "#create-integration-modal")
  end
end
