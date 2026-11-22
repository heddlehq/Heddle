defmodule HeddleUI.IntegrationLive.IndexTest do
  use HeddleUI.ConnCase, async: false

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures
  import Phoenix.LiveViewTest

  alias HeddleCore.Integrations

  setup %{conn: conn} do
    user = user_fixture()
    workspace = workspace_fixture(user, %{role: "editor"})
    %{conn: log_in_user(conn, user), user: user, workspace: workspace}
  end

  test "installs and removes an integration", %{conn: conn, user: user} do
    {:ok, lv, html} = live(conn, ~p"/integrations")

    assert html =~ "Google Sheets"
    refute has_element?(lv, "#integration-slack", "Installed")

    lv |> element("#install-slack") |> render_click()

    assert has_element?(lv, "#integration-slack", "Installed")
    assert Integrations.installed(user_scope_fixture(user)) == ["slack"]

    lv |> element("#uninstall-slack") |> render_click()

    refute has_element?(lv, "#uninstall-slack")
    assert Integrations.installed(user_scope_fixture(user)) == []
  end

  test "an integration a flow uses is installed and can't be removed", %{
    conn: conn,
    user: user,
    workspace: workspace
  } do
    flow_fixture(%{
      user: user,
      workspace: workspace,
      name: "Alerts",
      nodes: [
        %{
          "id" => "1",
          "type" => "Slack: Send Message",
          "position" => %{"x" => 0, "y" => 0},
          "controls" => %{}
        }
      ]
    })

    {:ok, lv, _html} = live(conn, ~p"/integrations")

    assert has_element?(lv, "#integration-slack", "Used by 1 flow")
    assert has_element?(lv, "#uninstall-slack[disabled]")
  end

  test "filters to the installed ones and searches", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/integrations")
    lv |> element("#install-redis") |> render_click()

    lv |> element("#integration-filter-installed") |> render_click()
    assert has_element?(lv, "#integration-redis")
    refute has_element?(lv, "#integration-slack")

    lv |> element("#integration-filter-all") |> render_click()
    lv |> form("#integration-search", %{"query" => "sheets"}) |> render_change()
    assert has_element?(lv, "#integration-google_sheets")
    refute has_element?(lv, "#integration-redis")
  end

  test "a viewer sees them without changing them", %{workspace: workspace} do
    viewer = user_fixture()
    member_fixture(workspace, viewer, "viewer")
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(viewer)

    {:ok, lv, _html} = live(conn, ~p"/integrations")

    assert has_element?(lv, "#integration-slack")
    refute has_element?(lv, "#install-slack")
  end
end
