defmodule HeddleWorker.PackageAgainTest do
  # The node registry is global: one test at a time.
  use HeddleCore.DataCase, async: false
  use Oban.Testing, repo: HeddleCore.Repo

  import HeddleCore.FlowsFixtures
  import HeddleCore.AccountsFixtures

  alias HeddleCore.Executions
  alias HeddleWorker.FlowExecutionWorker

  @worker "HeddleWorker.FlowExecutionWorker"
  @registry {HeddleNodes.Packages, :nodes}

  defmodule Approve do
    @moduledoc """
    Brings its own model, whose tool needs a person's approval: it waits, and is
    called again with the decision.
    """
    use Bobbin.Node

    definition do
      %{
        name: "Test: Approve",
        title: "Approve",
        category: :ai,
        inputs: [:exec],
        outputs: ["success", "error", "tools"],
        ui_fields: []
      }
    end

    @impl true
    def handler(%{"resumed" => %{"request" => request, "wait" => wait}} = context, _input) do
      decision = request["decision"]

      {:ok, Map.put(context, "result", %{"decision" => decision, "data" => wait["data"]}),
       "success"}
    end

    def handler(_context, _input) do
      {:with_tools,
       fn _tools, _call ->
         Bobbin.Node.wait_for_approval("Send the refund?",
           details: "R$ 50",
           again: true,
           data: %{"tool" => "refund"}
         )
       end}
    end
  end

  setup do
    previous = :persistent_term.get(@registry, nil)
    _loaded = HeddleNodes.Packages.definitions()
    state = :persistent_term.get(@registry)
    definition = Map.put(Approve.definition(), :module, Approve)

    :persistent_term.put(@registry, %{
      definitions: state.definitions ++ [definition],
      modules: Map.put(state.modules, definition.name, Approve)
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

  test "a tool waits for an approval, and the node is called again with the decision" do
    user = user_fixture()

    flow =
      flow_fixture(%{
        user: user,
        nodes: [
          node("start", "Start"),
          node("agent", "Test: Approve")
        ],
        connections: [wire("start", "exec", "agent")]
      })

    scope = user_scope_fixture(user)
    execution = execution_fixture(%{flow: flow})
    :ok = FlowExecutionWorker.perform(%Oban.Job{args: %{"execution_id" => execution.id}})

    waiting = Executions.get_execution!(execution.id)
    assert waiting.status == "waiting"
    assert waiting.paused["wait"]["approval"]["title"] == "Send the refund?"
    assert waiting.paused["wait"]["again"] == true

    assert [%{id: id}] = Executions.list_approvals(scope)
    assert id == execution.id
    assert {:ok, _execution} = Executions.decide(scope, execution.id, "approved")

    job =
      Enum.find(
        all_enqueued(worker: @worker),
        &(&1.args["execution_id"] == execution.id and &1.args["by"] == "call")
      )

    assert :ok = FlowExecutionWorker.perform(job)

    finished = Executions.get_execution!(execution.id)
    assert finished.status == "succeeded"

    assert finished.result["result"] == %{
             "decision" => "approved",
             "data" => %{"tool" => "refund"}
           }

    refute Map.has_key?(finished.result, "resumed")
  end
end
