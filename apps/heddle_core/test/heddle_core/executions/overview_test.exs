defmodule HeddleCore.Executions.OverviewTest do
  use HeddleCore.DataCase, async: true

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Executions
  alias HeddleCore.Executions.Execution
  alias HeddleCore.Repo

  @now ~U[2026-11-09 12:00:00Z]

  defp run(flow, status, inserted_at, opts \\ []) do
    execution = execution_fixture(%{flow: flow})

    execution
    |> Ecto.Changeset.change(
      status: status,
      inserted_at: inserted_at,
      started_at: opts[:started_at],
      finished_at: opts[:finished_at]
    )
    |> Repo.update!()
  end

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    %{user: user, workspace: workspace, scope: user_scope_fixture(user)}
  end

  test "counts the runs of each day, oldest first", %{user: user, workspace: ws, scope: scope} do
    flow = flow_fixture(%{user: user, workspace: ws})
    run(flow, "succeeded", ~U[2026-11-09 08:00:00Z])
    run(flow, "failed", ~U[2026-11-09 09:00:00Z])
    run(flow, "running", ~U[2026-11-08 10:00:00Z])
    run(flow, "succeeded", ~U[2026-10-20 10:00:00Z])

    overview = Executions.overview(scope, days: 7, now: @now)

    assert length(overview.days) == 7
    assert hd(overview.days).date == ~D[2026-11-03]

    assert List.last(overview.days) == %{
             date: ~D[2026-11-09],
             succeeded: 1,
             failed: 1,
             other: 0
           }

    assert Enum.at(overview.days, 5).other == 1
    assert overview.totals.runs == 3
    assert overview.totals.success_rate == 50.0
  end

  test "compares with the days before and averages how long runs took", %{
    user: user,
    workspace: ws,
    scope: scope
  } do
    flow = flow_fixture(%{user: user, workspace: ws})

    run(flow, "succeeded", ~U[2026-11-09 08:00:00Z],
      started_at: ~U[2026-11-09 08:00:00Z],
      finished_at: ~U[2026-11-09 08:00:10Z]
    )

    run(flow, "succeeded", ~U[2026-11-09 08:00:00Z],
      started_at: ~U[2026-11-09 08:00:00Z],
      finished_at: ~U[2026-11-09 08:00:20Z]
    )

    run(flow, "failed", ~U[2026-10-30 08:00:00Z])

    overview = Executions.overview(scope, days: 7, now: @now)

    assert overview.totals.avg_duration == 15.0
    assert overview.totals.success_rate == 100.0
    assert overview.previous.runs == 1
    assert overview.previous.failed == 1
  end

  test "lists the flows that failed, the latest runs and what goes on now", %{
    user: user,
    workspace: ws,
    scope: scope
  } do
    failing = flow_fixture(%{name: "Failing", user: user, workspace: ws})
    fine = flow_fixture(%{name: "Fine", user: user, workspace: ws, published: false})
    run(failing, "failed", ~U[2026-11-09 08:00:00Z])
    run(failing, "succeeded", ~U[2026-11-09 07:00:00Z])
    run(fine, "succeeded", ~U[2026-11-09 06:00:00Z])
    run(fine, "waiting", ~U[2026-11-09 11:00:00Z])

    overview = Executions.overview(scope, days: 7, now: @now)

    assert [%{name: "Failing", failed: 1, runs: 2}] = overview.attention
    assert overview.active == %{queued: 0, running: 0, waiting: 1}
    assert overview.flows == %{total: 2, published: 1}

    assert [%Execution{status: "waiting"} | _rest] = overview.recent
    assert length(overview.recent) == 4

    by_name = Map.new(overview.latest_flows, &{&1.name, &1})
    assert by_name["Fine"].last_run.status == "waiting"
    refute by_name["Fine"].published?
    assert by_name["Failing"].published?
  end

  test "shows nothing of another workspace", %{scope: scope} do
    other = user_fixture()
    flow = flow_fixture(%{user: other, workspace: workspace_fixture(other)})
    run(flow, "failed", ~U[2026-11-09 08:00:00Z])

    overview = Executions.overview(scope, days: 7, now: @now)

    assert overview.totals.runs == 0
    assert overview.recent == []
    assert overview.attention == []
    assert overview.flows == %{total: 0, published: 0}
  end

  test "is empty for someone in no workspace" do
    scope = user_scope_fixture(user_fixture())

    overview = Executions.overview(scope, days: 7, now: @now)

    assert length(overview.days) == 7
    assert overview.totals.runs == 0
    assert overview.latest_flows == []
  end
end
