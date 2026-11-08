defmodule HeddleWorker.DebuggingTest do
  use HeddleCore.DataCase, async: true
  use Oban.Testing, repo: HeddleCore.Repo

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Executions
  alias HeddleCore.Flows
  alias HeddleWorker.FlowExecutionWorker

  @worker "HeddleWorker.FlowExecutionWorker"

  defp node(id, type, controls \\ %{}) do
    %{"id" => id, "type" => type, "label" => type, "controls" => controls}
  end

  defp wire(source, output, target) do
    %{"source" => source, "sourceOutput" => output, "target" => target, "targetInput" => "exec"}
  end

  defp run(flow, input) do
    {:ok, execution} = Executions.create_execution(%{flow_id: flow.id, input: input})
    :ok = FlowExecutionWorker.perform(%Oban.Job{args: %{"execution_id" => execution.id}})
    Executions.get_execution!(execution.id)
  end

  setup do
    user = user_fixture()
    Process.put(:heddle_owner, user)
    %{scope: user_scope_fixture(user)}
  end

  test "a run from the editor tells whoever follows it about each step as it ends" do
    flow =
      flow_fixture(%{
        nodes: [
          node("start", "Start"),
          node("var", "Variable", %{"var_name" => "a", "var_value" => "1"})
        ],
        connections: [wire("start", "exec", "var")]
      })

    {:ok, execution} =
      Executions.create_execution(%{
        flow_id: flow.id,
        input: %{"trigger" => "manual", "debug" => true}
      })

    :ok = Executions.subscribe_to_execution(execution)
    :ok = FlowExecutionWorker.perform(%Oban.Job{args: %{"execution_id" => execution.id}})

    id = execution.id
    assert_receive {:execution_step, ^id, %{"node_id" => "start"}}
    assert_receive {:execution_step, ^id, %{"node_id" => "var", "data" => %{"output" => output}}}
    assert output == %{"variables" => %{"a" => "1"}}

    assert Executions.get_execution!(id).status == "succeeded"
  end

  test "any other run keeps quiet" do
    flow = flow_fixture(%{nodes: [node("start", "Start")], connections: []})
    {:ok, execution} = Executions.create_execution(%{flow_id: flow.id, input: %{}})

    :ok = Executions.subscribe_to_execution(execution)
    :ok = FlowExecutionWorker.perform(%Oban.Job{args: %{"execution_id" => execution.id}})

    refute_received {:execution_step, _id, _entry}
  end

  test "a failed run starts the error flow of its flow", %{scope: scope} do
    alerts =
      flow_fixture(%{
        name: "Alerts",
        nodes: [node("on_error", "Error Trigger")],
        connections: []
      })

    flow =
      flow_fixture(%{
        name: "Orders",
        nodes: [
          node("start", "Start"),
          node("boom", "Evaluate Code", %{
            "language" => "elixir",
            "code_elixir" => ~s(raise "boom")
          })
        ],
        connections: [wire("start", "exec", "boom")]
      })

    {:ok, flow} = Flows.update_flow_settings(scope, flow, %{error_flow_id: alerts.id})

    failed = run(flow, %{"trigger" => "manual"})
    assert failed.status == "failed"

    assert [job] =
             for(j <- all_enqueued(worker: @worker), j.args["execution_id"] != failed.id, do: j)

    error_run = Executions.get_execution!(job.args["execution_id"])

    assert error_run.flow_id == alerts.id

    assert %{"trigger" => "error", "error" => %{"node_id" => "boom", "message" => message}} =
             error_run.input

    assert message =~ "boom"

    :ok = FlowExecutionWorker.perform(job)
    assert Executions.get_execution!(error_run.id).status == "succeeded"
  end
end
