defmodule HeddleUI.FlowLive.GroupsTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Flows
  alias HeddleCore.Flows.Groups

  setup %{conn: conn} do
    admin = system_admin_fixture()
    Process.put(:heddle_owner, admin)
    scope = user_scope_fixture(admin)
    flow = flow_fixture(%{name: "Lead scoring"})

    %{conn: log_in_user(conn, admin), scope: scope, flow: flow}
  end

  test "without groups, the flows show as a plain list", %{conn: conn, flow: flow} do
    {:ok, lv, _html} = live(conn, ~p"/flows")

    assert has_element?(lv, "#flow-group-none #flow-#{flow.id}")
    refute has_element?(lv, "#flow-group-none header")
    refute has_element?(lv, "#flow-#{flow.id}-move")
  end

  test "creates a group, and says what's wrong with a name", %{conn: conn, scope: scope} do
    {:ok, lv, _html} = live(conn, ~p"/flows")

    lv |> element("#new-group") |> render_click()
    assert has_element?(lv, "#new-group-form")

    html = lv |> form("#new-group-form", group: %{name: " "}) |> render_submit()
    assert html =~ "can&#39;t be blank"

    lv |> form("#new-group-form", group: %{name: "Sales"}) |> render_submit()

    refute has_element?(lv, "#new-group-form")
    assert [group] = Groups.list_groups(scope)
    assert has_element?(lv, "#flow-group-#{group.id}", "Sales")
    assert has_element?(lv, "#flow-group-none", "No group")
  end

  test "moves a flow from the menu of its row", %{conn: conn, scope: scope, flow: flow} do
    {:ok, group} = Groups.create_group(scope, %{"name" => "Sales"})
    {:ok, lv, _html} = live(conn, ~p"/flows")

    assert has_element?(lv, "#flow-group-none #flow-#{flow.id}")

    lv |> element("#flow-#{flow.id}-move-#{group.id}") |> render_click()

    assert has_element?(lv, "#flow-group-#{group.id} #flow-#{flow.id}")
    refute has_element?(lv, "#flow-group-none #flow-#{flow.id}")
    assert Flows.get_flow(scope, flow.id).group_id == group.id

    lv |> element("#flow-#{flow.id}-move-none") |> render_click()
    assert has_element?(lv, "#flow-group-none #flow-#{flow.id}")
  end

  test "moves a flow dropped on a group", %{conn: conn, scope: scope, flow: flow} do
    {:ok, group} = Groups.create_group(scope, %{"name" => "Sales"})
    {:ok, lv, _html} = live(conn, ~p"/flows")

    render_hook(lv, "move_flow", %{"flow" => to_string(flow.id), "group" => to_string(group.id)})

    assert has_element?(lv, "#flow-group-#{group.id} #flow-#{flow.id}")
  end

  test "renames and deletes a group, and its flows stay", %{
    conn: conn,
    scope: scope,
    flow: flow
  } do
    {:ok, group} = Groups.create_group(scope, %{"name" => "Sales"})
    {:ok, _flow} = Groups.move_flow(scope, flow.id, group.id)
    {:ok, lv, _html} = live(conn, ~p"/flows")

    lv |> element("#flow-group-#{group.id}-rename-button") |> render_click()

    lv
    |> form("#flow-group-#{group.id}-rename", group: %{name: "Leads"})
    |> render_submit()

    assert has_element?(lv, "#flow-group-#{group.id}", "Leads")

    lv |> element("#flow-group-#{group.id}-delete") |> render_click()

    refute has_element?(lv, "#flow-group-#{group.id}")
    assert has_element?(lv, "#flow-group-none #flow-#{flow.id}")
  end

  test "a viewer sees the groups and can't change them", %{conn: conn, scope: scope, flow: flow} do
    {:ok, group} = Groups.create_group(scope, %{"name" => "Sales"})
    {:ok, _flow} = Groups.move_flow(scope, flow.id, group.id)

    viewer = user_fixture()
    member_fixture(scope.workspace, viewer, "viewer")

    {:ok, lv, _html} = conn |> log_in_user(viewer) |> live(~p"/flows")

    assert has_element?(lv, "#flow-group-#{group.id} #flow-#{flow.id}")
    refute has_element?(lv, "#new-group")
    refute has_element?(lv, "#flow-group-#{group.id}-delete")
    refute has_element?(lv, "#flow-#{flow.id}-move")

    render_hook(lv, "move_flow", %{"flow" => to_string(flow.id), "group" => ""})
    assert Flows.get_flow(scope, flow.id).group_id == group.id
  end
end
