defmodule HeddleWorker.PackageRunsTest do
  use HeddleCore.DataCase, async: true
  use Oban.Testing, repo: HeddleCore.Repo

  import HeddleCore.FlowsFixtures

  alias HeddleCore.Executions
  alias HeddleCore.Repo
  alias HeddleWorker.FlowExecutionWorker
  alias HeddleWorker.PackageRuns

  @trigger "Subflow Trigger"

  defp node(id, type, controls \\ %{}),
    do: %{"id" => id, "type" => type, "label" => id, "controls" => controls}

  defp link(source, target),
    do: %{"source" => source, "sourceOutput" => "exec", "target" => target}

  # A flow that starts at the trigger and leaves what it got as `result`.
  defp triggered(name, controls, attrs \\ %{}) do
    flow_fixture(
      Map.merge(
        %{
          name: name,
          nodes: [
            node("trigger", @trigger, controls),
            node("echo", "Evaluate Code", %{"language" => "elixir", "code_elixir" => "result"})
          ],
          connections: [link("trigger", "echo")]
        },
        attrs
      )
    )
  end

  defp workspace_of(flow), do: Repo.preload(flow, :workspace).workspace

  defp request(flow, attrs \\ %{}),
    do: Map.merge(%{workspace_id: flow.workspace_id, node_type: @trigger}, attrs)

  defp perform(execution),
    do: FlowExecutionWorker.perform(%Oban.Job{args: %{"execution_id" => execution.id}})

  defp by_public_id(public_id), do: Executions.get_execution_by_public_id!(public_id)

  describe "start_runs/1" do
    test "starts the flows of the workspace whose trigger matches, with the data" do
      billing = triggered("Billing", %{"name" => " Billing "})
      workspace = workspace_of(billing)
      _sales = triggered("Sales", %{"name" => "Sales"}, %{workspace: workspace})
      _elsewhere = triggered("Billing elsewhere", %{"name" => "Billing"})

      assert {:ok, [run]} =
               PackageRuns.start_runs(
                 request(billing, %{match: %{"name" => "Billing"}, data: %{"n" => 1}})
               )

      assert %{"flow_id" => flow_id, "flow_name" => "Billing", "run_id" => run_id} = run
      assert flow_id == billing.id

      execution = by_public_id(run_id)
      assert execution.input["trigger"] == "package"
      assert execution.input["node_id"] == "trigger"
      assert execution.input["result"] == %{"n" => 1}

      assert :ok = perform(execution)
      assert %{status: "succeeded", result: %{"n" => 1}} = by_public_id(run_id)
    end

    test "starts none when no flow has the trigger" do
      flow = triggered("Billing", %{"name" => "Billing"})

      assert {:ok, []} = PackageRuns.start_runs(request(flow, %{match: %{"name" => "Other"}}))
      assert {:ok, []} = PackageRuns.start_runs(request(flow, %{node_type: "Nothing"}))
    end

    test "stops a chain of flows that start each other" do
      flow = triggered("Loop", %{})

      Process.put({HeddleWorker.Subflow, :current}, %{
        execution_id: nil,
        chain: Enum.to_list(1..8)
      })

      assert {:error, "Flows can start each other 8 levels deep" <> _} =
               PackageRuns.start_runs(request(flow))

      # A run for later starts a chain of its own.
      at = DateTime.add(DateTime.utc_now(), 3600)
      assert {:ok, [run]} = PackageRuns.start_runs(request(flow, %{at: at}))
      assert by_public_id(run["run_id"]).input["caller"]["chain"] == []
    end

    test "a run for later is queued for then, and can be cancelled before it begins" do
      flow = triggered("Later", %{})
      at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

      assert {:ok, [%{"run_id" => run_id}]} = PackageRuns.start_runs(request(flow, %{at: at}))
      execution = by_public_id(run_id)

      assert_enqueued(
        worker: FlowExecutionWorker,
        args: %{execution_id: execution.id},
        scheduled_at: at
      )

      other = triggered("Other", %{})
      assert {:error, :not_found} = PackageRuns.cancel_run(other.workspace_id, run_id)
      assert :ok = PackageRuns.cancel_run(flow.workspace_id, run_id)
      assert {:error, :not_found} = PackageRuns.cancel_run(flow.workspace_id, run_id)

      # Its job finds nothing to run.
      assert :ok = perform(execution)
    end
  end

  describe "lanes" do
    test "runs of a lane run one at a time, in order" do
      flow = triggered("Agent", %{})
      lane = %{lane: "jido/agent/ana"}

      {:ok, [first]} = PackageRuns.start_runs(request(flow, lane))
      {:ok, [second]} = PackageRuns.start_runs(request(flow, lane))
      {:ok, [third]} = PackageRuns.start_runs(request(flow, lane))
      {:ok, [elsewhere]} = PackageRuns.start_runs(request(flow, %{lane: "jido/agent/bia"}))

      first = by_public_id(first["run_id"])
      second = by_public_id(second["run_id"])
      third = by_public_id(third["run_id"])

      # The first takes the lane, as if it were still running.
      assert {:ok, %{status: "running"}} = Executions.admit(first)

      assert :ok = perform(third)
      assert :ok = perform(second)
      assert %{status: "queued", lane_held: true} = Repo.reload(second)
      assert %{status: "queued", lane_held: true} = Repo.reload(third)

      # Another lane doesn't wait.
      assert :ok = perform(by_public_id(elsewhere["run_id"]))
      assert %{status: "succeeded"} = by_public_id(elsewhere["run_id"])

      # The first ends, and only the oldest held one is queued again.
      {:ok, _first} = Executions.mark_succeeded(Repo.reload(first), %{})
      assert %{lane_held: false} = Repo.reload(second)
      assert %{lane_held: true} = Repo.reload(third)
      assert_enqueued(worker: FlowExecutionWorker, args: %{execution_id: second.id})

      assert :ok = perform(Repo.reload(second))
      assert %{status: "succeeded"} = Repo.reload(second)
      assert %{lane_held: false} = Repo.reload(third)

      assert :ok = perform(Repo.reload(third))
      assert %{status: "succeeded"} = Repo.reload(third)
    end

    test "a run that fails lets the next one go too" do
      flow = triggered("Agent", %{})
      {:ok, [first]} = PackageRuns.start_runs(request(flow, %{lane: "l"}))
      {:ok, [second]} = PackageRuns.start_runs(request(flow, %{lane: "l"}))

      {:ok, first} = Executions.admit(by_public_id(first["run_id"]))
      :ok = perform(by_public_id(second["run_id"]))

      {:ok, _first} = Executions.mark_failed(first, %{"message" => "boom"})
      assert %{lane_held: false} = by_public_id(second["run_id"])
    end

    test "a lane is a workspace's own" do
      flow = triggered("Agent", %{})
      other = triggered("Agent", %{})

      {:ok, [mine]} = PackageRuns.start_runs(request(flow, %{lane: "l"}))
      {:ok, [theirs]} = PackageRuns.start_runs(request(other, %{lane: "l"}))

      {:ok, _mine} = Executions.admit(by_public_id(mine["run_id"]))
      assert :ok = perform(by_public_id(theirs["run_id"]))
      assert %{status: "succeeded"} = by_public_id(theirs["run_id"])
    end
  end
end
