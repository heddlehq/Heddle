defmodule HeddleUI.FlowLive.VersionsTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.FlowsFixtures
  import HeddleCore.AccountsFixtures

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Flows
  alias HeddleCore.Flows.Versions

  @start %{"id" => "1", "type" => "Start", "label" => "Start", "controls" => %{}}
  @output %{"id" => "2", "type" => "Output", "label" => "Output", "controls" => %{}}

  setup %{conn: conn} do
    admin = system_admin_fixture()
    Process.put(:heddle_owner, admin)
    %{conn: log_in_user(conn, admin), user: admin, scope: Scope.for_user(admin)}
  end

  defp graph(nodes), do: %{"nodes" => nodes, "connections" => [], "comments" => []}

  test "a new flow isn't published until someone publishes it", %{conn: conn} do
    flow = flow_fixture(%{nodes: [@start], published: false})
    {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

    assert has_element?(lv, "#flow-publish-status[data-status='unpublished']")

    lv |> element("#publish-flow") |> render_click()
    assert has_element?(lv, "#publish-modal")

    lv |> form("#publish-form", publish: %{note: "First"}) |> render_submit()
    render_hook(lv, "publish_graph_data", %{"data" => graph([@start, @output])})

    flow = Flows.get_flow!(flow.id)
    assert %{number: 1, note: "First", nodes: [_, _]} = Versions.published_version(flow)
    assert length(flow.nodes) == 2
    refute has_element?(lv, "#publish-modal")
    assert has_element?(lv, "#flow-publish-status[data-status='published']")
  end

  test "a change on the canvas isn't what production runs", %{conn: conn} do
    flow = flow_fixture(%{nodes: [@start]})
    {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")

    assert has_element?(lv, "#flow-publish-status[data-status='published']")

    render_hook(lv, "graph_changed", %{})
    assert has_element?(lv, "#flow-publish-status[data-status='changed']")
  end

  test "the history lists versions, and one can be previewed", %{conn: conn, scope: scope} do
    flow = flow_fixture(%{nodes: [@start]})
    {:ok, flow} = Flows.update_flow(scope, flow, %{nodes: [@output]})
    {:ok, second} = Versions.publish(scope, flow, %{"note" => "Swap"})

    {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")
    lv |> element("#open-versions") |> render_click()

    assert has_element?(lv, "#version-history")
    assert has_element?(lv, "#version-live-#{second.id}")
    assert render(lv) =~ "Swap"

    lv |> element("#version-preview-#{second.id}") |> render_click()
    assert has_element?(lv, "#version-preview-canvas-#{second.id}")

    assert %{diff: %{"1" => "removed", "2" => "added"}, nodes: nodes} =
             render_hook(lv, "version_preview_ready", %{}) |> then(fn _ -> preview(lv) end)

    # The removed node is drawn where it was, as a ghost.
    assert Enum.map(nodes, & &1["id"]) |> Enum.sort() == ["1", "2"]

    lv |> element("#version-preview-close") |> render_click()
    refute has_element?(lv, "#version-preview-layer")
  end

  test "restoring a version puts it on the canvas", %{conn: conn, scope: scope} do
    flow = flow_fixture(%{nodes: [@start]})
    first_id = flow.published_version_id
    {:ok, _flow} = Flows.update_flow(scope, flow, %{nodes: [@output]})

    {:ok, lv, _html} = live(conn, ~p"/flows/#{flow.id}")
    lv |> element("#open-versions") |> render_click()
    lv |> element("#version-restore-#{first_id}") |> render_click()

    assert_push_event(lv, "load_graph_data", %{nodes: [%{"id" => "1"}]})
    assert [%{"id" => "1"}] = Flows.get_flow!(flow.id).nodes
  end

  test "a viewer sees the history, and can't publish or restore", %{scope: scope} do
    flow = flow_fixture(%{nodes: [@start]})
    viewer = user_fixture()
    member_fixture(HeddleCore.Workspaces.get_workspace(flow.workspace_id), viewer, "viewer")
    {:ok, _flow} = Flows.update_flow(scope, flow, %{nodes: [@output]})

    {:ok, lv, _html} = live(build_conn() |> log_in_user(viewer), ~p"/flows/#{flow.id}")

    refute has_element?(lv, "#publish-flow")
    lv |> element("#open-versions") |> render_click()
    assert has_element?(lv, "#version-history")
    refute has_element?(lv, "[id^='version-restore-']")

    render_hook(lv, "version_restore", %{"id" => flow.published_version_id})
    render_hook(lv, "publish_graph_data", %{"data" => graph([])})

    assert [%{"id" => "2"}] = Flows.get_flow!(flow.id).nodes
    assert Flows.get_flow!(flow.id).published_version_id == flow.published_version_id
  end

  # What the preview canvas asks for when it mounts.
  defp preview(lv) do
    :sys.get_state(lv.pid).socket.assigns
    |> HeddleUI.FlowLive.VersionsManager.preview_graph()
  end
end
