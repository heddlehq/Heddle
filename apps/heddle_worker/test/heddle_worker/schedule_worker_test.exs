defmodule HeddleWorker.ScheduleWorkerTest do
  use HeddleCore.DataCase, async: true

  alias HeddleCore.Executions
  alias HeddleWorker.ScheduleWorker

  import HeddleCore.FlowsFixtures

  @nine ~U[2026-11-06 09:00:00Z]

  defp schedule_flow(cron) do
    flow_fixture(%{
      nodes: [
        %{
          "id" => "s",
          "type" => "Schedule",
          "label" => "Schedule",
          "controls" => %{"cron" => cron}
        }
      ],
      connections: []
    })
  end

  defp tick(at \\ @nine), do: ScheduleWorker.perform(%Oban.Job{scheduled_at: at})

  test "starts a flow that is due" do
    flow = schedule_flow("0 9 * * *")

    assert :ok = tick()

    assert [execution] = Executions.list_executions_for_flow(flow)
    assert execution.input == %{"trigger" => "schedule", "node_id" => "s"}
  end

  test "leaves a flow that isn't due" do
    flow = schedule_flow("0 18 * * *")

    assert :ok = tick()

    assert Executions.list_executions_for_flow(flow) == []
  end

  test "starts each Schedule node that is due" do
    node = fn id, cron ->
      %{"id" => id, "type" => "Schedule", "label" => id, "controls" => %{"cron" => cron}}
    end

    flow =
      flow_fixture(%{
        nodes: [node.("a", "0 9 * * *"), node.("b", "* * * * *"), node.("c", "0 18 * * *")],
        connections: []
      })

    assert :ok = tick()

    started = flow |> Executions.list_executions_for_flow() |> Enum.map(& &1.input["node_id"])
    assert Enum.sort(started) == ["a", "b"]
  end

  test "leaves flows without a Schedule node alone" do
    flow = flow_fixture()

    assert :ok = tick()

    assert Executions.list_executions_for_flow(flow) == []
  end
end
