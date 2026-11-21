defmodule HeddleUI.ApprovalLiveTest do
  use HeddleUI.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Repo

  setup %{conn: conn} do
    user = user_fixture()
    workspace = workspace_fixture(user)
    %{conn: log_in_user(conn, user), user: user, workspace: workspace}
  end

  # What the worker leaves when a run reaches an Approval.
  defp waiting(user, workspace) do
    flow = flow_fixture(%{user: user, workspace: workspace, name: "Refunds"})

    flow
    |> then(&execution_fixture(%{flow: &1}))
    |> Ecto.Changeset.change(
      status: "waiting",
      paused: %{
        "wait_id" => "w1",
        "wait" => %{
          "node_id" => "ask",
          "call" => true,
          "approval" => %{"title" => "Refund $40 to Ana?", "details" => "Second request."}
        },
        "context" => %{},
        "frames" => []
      }
    )
    |> Repo.update!()
  end

  test "says when nothing waits", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/approvals")
    assert has_element?(lv, "#approvals-empty")
  end

  test "shows what waits and approves it with a comment", %{
    conn: conn,
    user: user,
    workspace: workspace
  } do
    execution = waiting(user, workspace)

    {:ok, lv, html} = live(conn, ~p"/approvals")
    assert html =~ "Refund $40 to Ana?"
    assert html =~ "Second request."
    assert html =~ "Refunds"

    lv
    |> form("#approval-form-#{execution.id}", %{execution: execution.id, comment: "ok"})
    |> render_change()

    assert lv |> element("#approve-#{execution.id}") |> render_click() =~ "Approved."
    refute has_element?(lv, "#approval-#{execution.id}")
  end

  test "a viewer sees it without the buttons", %{user: user, workspace: workspace} do
    execution = waiting(user, workspace)
    viewer = user_fixture()
    member_fixture(workspace, viewer, "viewer")

    {:ok, lv, _html} = live(log_in_user(build_conn(), viewer), ~p"/approvals")

    assert has_element?(lv, "#approval-#{execution.id}")
    refute has_element?(lv, "#approve-#{execution.id}")
  end
end
