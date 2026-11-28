defmodule HeddleWorker.PackageWaitTest do
  # The node registry is global: one test at a time.
  use HeddleCore.DataCase, async: false
  use Oban.Testing, repo: HeddleCore.Repo

  import HeddleCore.FlowsFixtures

  alias HeddleCore.Executions
  alias HeddleWorker.FlowExecutionWorker

  @worker "HeddleWorker.FlowExecutionWorker"
  @registry {HeddleNodes.Packages, :nodes}

  defmodule Ask do
    @moduledoc "Waits for an answer, like a package that asks another flow."
    use Bobbin.Node

    definition do
      %{
        name: "Test: Ask",
        title: "Ask",
        category: :ai,
        inputs: [:exec],
        outputs: ["success", "timeout", "error"],
        ui_fields: []
      }
    end

    @impl true
    def handler(_context, _input), do: Bobbin.Node.wait_for_call("ask/1", timeout: 3600)
  end

  setup do
    previous = :persistent_term.get(@registry, nil)
    _loaded = HeddleNodes.Packages.definitions()
    state = :persistent_term.get(@registry)
    definition = Map.put(Ask.definition(), :module, Ask)

    :persistent_term.put(@registry, %{
      definitions: state.definitions ++ [definition],
      modules: Map.put(state.modules, definition.name, Ask)
    })

    on_exit(fn ->
      if previous,
        do: :persistent_term.put(@registry, previous),
        else: :persistent_term.erase(@registry)
    end)
  end

  defp node(id, type, controls \\ %{}),
    do: %{"id" => id, "type" => type, "label" => type, "controls" => controls}

  defp wire(source, output, target),
    do: %{
      "source" => source,
      "sourceOutput" => output,
      "target" => target,
      "targetInput" => "exec"
    }

  defp ask_flow do
    flow_fixture(%{
      nodes: [
        node("start", "Start"),
        node("ask", "Test: Ask"),
        node("replied", "Evaluate Code", %{
          "language" => "elixir",
          "code_elixir" => ~s(result["reply"])
        }),
        node("late", "Variable", %{"var_name" => "went_on", "var_value" => "late"})
      ],
      connections: [
        wire("start", "exec", "ask"),
        wire("ask", "success", "replied"),
        wire("ask", "timeout", "late")
      ]
    })
  end

  defp start(flow) do
    execution = execution_fixture(%{flow: flow})
    :ok = FlowExecutionWorker.perform(%Oban.Job{args: %{"execution_id" => execution.id}})
    Executions.get_execution!(execution.id)
  end

  defp job(execution, by) do
    Enum.find(all_enqueued(worker: @worker), fn job ->
      job.args["execution_id"] == execution.id and job.args["by"] == by
    end)
  end

  defp perform(job), do: FlowExecutionWorker.perform(job)

  test "the answer with its key resumes the run through the node's output" do
    flow = ask_flow()
    execution = start(flow)
    assert execution.status == "waiting"
    assert execution.paused["wait"]["key"] == "ask/1"

    assert {:error, :not_waiting} =
             Executions.resume_run(flow.workspace_id, execution.id, "ask/2", %{}, timeout: 0)

    assert :ok =
             Executions.resume_run(flow.workspace_id, execution.id, "ask/1", %{"reply" => "yes"})

    assert :ok = perform(job(execution, "call"))

    finished = Executions.get_execution!(execution.id)
    assert finished.status == "succeeded"
    assert Enum.map(finished.logs, & &1["node_id"]) == ["start", "ask", "replied"]
    assert finished.result["result"] == "yes"
  end

  test "the time limit goes on through timeout" do
    execution = start(ask_flow())

    assert :ok = perform(job(execution, "timeout"))
    assert Executions.get_execution!(execution.id).result["variables"] == %{"went_on" => "late"}
  end

  test "only the run's workspace resumes it" do
    execution = start(ask_flow())
    other = flow_fixture()

    assert {:error, :not_found} =
             Executions.resume_run(other.workspace_id, execution.id, "ask/1", %{}, timeout: 0)

    assert {:error, :not_found} =
             Executions.resume_run(other.workspace_id, "not-a-uuid", "ask/1", %{}, timeout: 0)
  end

  test "a Wait isn't resumed by a package's call" do
    flow =
      flow_fixture(%{
        nodes: [node("start", "Start"), node("wait", "Wait", %{"wait_for" => "call"})],
        connections: [wire("start", "exec", "wait")]
      })

    execution = start(flow)
    assert execution.status == "waiting"

    assert {:error, :not_waiting} =
             Executions.resume_run(flow.workspace_id, execution.id, "ask/1", %{}, timeout: 0)
  end
end
