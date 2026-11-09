defmodule HeddleUI.DashboardLive.IndexTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Executions

  describe "mount" do
    test "requires authentication", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/")
      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/users/log-in"
    end

    test "shows the figures, the chart and the flows of the workspace", %{conn: conn} do
      admin = system_admin_fixture()
      flow = flow_fixture(%{name: "Test Flow", user: admin})

      {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/")

      assert has_element?(lv, "h1", "Dashboard")
      assert has_element?(lv, "#stat-runs")
      assert has_element?(lv, "#stat-success-rate")
      assert has_element?(lv, "#stat-failures")
      assert has_element?(lv, "#stat-duration")
      assert has_element?(lv, "#dashboard-activity-empty")
      assert has_element?(lv, "#dashboard-flow-#{flow.id}", "Test Flow")
      assert has_element?(lv, "#dashboard-flows-link", "Manage Flows")
      assert has_element?(lv, "#dashboard-attention-empty")
    end

    test "shows the latest runs and the flows that failed", %{conn: conn} do
      admin = system_admin_fixture()
      flow = flow_fixture(%{name: "Billing", user: admin})
      ok = execution_fixture(%{flow: flow})
      failed = execution_fixture(%{flow: flow})
      {:ok, _} = Executions.mark_failed(failed, "boom")
      {:ok, _} = Executions.update_execution(ok, %{status: "running"})

      {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/")

      assert has_element?(lv, "#dashboard-run-#{failed.public_id}", "Billing")
      assert has_element?(lv, "#dashboard-run-#{ok.public_id}")
      assert has_element?(lv, "#dashboard-attention-#{flow.id}", "Billing")
      assert has_element?(lv, "#dashboard-live", "1 running")
      refute has_element?(lv, "#dashboard-activity-empty")
      assert has_element?(lv, "#stat-runs", "2")
    end

    test "keeps up with new runs", %{conn: conn} do
      admin = system_admin_fixture()
      flow = flow_fixture(%{user: admin})

      {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/")
      assert has_element?(lv, "#dashboard-recent-runs-empty")

      execution = execution_fixture(%{flow: flow})
      send(lv.pid, :refresh)

      assert has_element?(lv, "#dashboard-run-#{execution.public_id}")
    end

    test "shows nothing of another workspace", %{conn: conn} do
      admin = system_admin_fixture()
      other = user_fixture()
      flow = flow_fixture(%{name: "Elsewhere", user: other, workspace: workspace_fixture(other)})
      execution = execution_fixture(%{flow: flow})

      {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/")

      refute has_element?(lv, "#dashboard-flow-#{flow.id}")
      refute has_element?(lv, "#dashboard-run-#{execution.public_id}")
    end

    test "tells someone in no workspace to ask for one", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/")

      assert html =~ "Ask an admin to add you"
      assert has_element?(lv, "#dashboard-no-workspace")
      refute has_element?(lv, "#dashboard-stats")
      refute has_element?(lv, "#dashboard-flows-link")
    end

    test "shows empty states when the workspace has no flows", %{conn: conn} do
      admin = system_admin_fixture()

      {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/")

      assert has_element?(lv, "#dashboard-flows-empty", "No flows")
      assert has_element?(lv, "#dashboard-recent-runs-empty")
    end
  end
end
