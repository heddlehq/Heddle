defmodule HeddleWorker.SubflowTest do
  use HeddleCore.DataCase, async: true

  import HeddleCore.FlowsFixtures

  alias HeddleCore.Executions
  alias HeddleWorker.FlowExecutionWorker

  defp node(id, type, controls \\ %{}),
    do: %{"id" => id, "type" => type, "label" => id, "controls" => controls}

  defp link(source, target, output \\ "exec"),
    do: %{"source" => source, "sourceOutput" => output, "target" => target}

  defp code(code), do: %{"language" => "elixir", "code_elixir" => code}

  # A flow that doubles the `n` it gets.
  defp doubler(attrs \\ %{}) do
    flow_fixture(
      Map.merge(
        %{
          name: "Doubler",
          nodes: [
            node("trigger", "Subflow Trigger"),
            node("double", "Evaluate Code", code(~s(result["n"] * 2)))
          ],
          connections: [link("trigger", "double")]
        },
        attrs
      )
    )
  end

  defp caller(subflow, controls, attrs \\ %{}) do
    flow_fixture(
      Map.merge(
        %{
          name: "Caller",
          workspace: attrs[:workspace] || workspace_of(subflow),
          nodes: [
            node("start", "Start"),
            node(
              "call",
              "Subflow",
              Map.merge(%{"subflow_id" => to_string(subflow.id)}, controls)
            ),
            node("failed", "Output")
          ],
          connections: [link("start", "call"), link("call", "failed", "error")]
        },
        Map.delete(attrs, :workspace)
      )
    )
  end

  defp workspace_of(flow), do: HeddleCore.Repo.preload(flow, :workspace).workspace

  defp run(flow, input \\ %{}) do
    {:ok, execution} = Executions.create_execution(%{flow_id: flow.id, input: input})
    :ok = FlowExecutionWorker.perform(%Oban.Job{args: %{"execution_id" => execution.id}})
    Executions.get_execution!(execution.id)
  end

  defp runs_of(flow), do: Executions.list_executions_for_flow(flow)

  test "waits for the flow, and takes what it ended with" do
    doubler = doubler()
    caller = caller(doubler, %{"subflow_data" => ~s({"n": 21})})

    execution = run(caller)

    assert execution.status == "succeeded"
    assert execution.result["result"] == 42

    # It is a run of its own, from its Subflow Trigger, that knows who called it.
    assert [child] = runs_of(doubler)
    assert child.status == "succeeded"
    assert child.flow_version_id == doubler.published_version_id

    assert %{"trigger" => "subflow", "result" => %{"n" => 21}, "caller" => caller_info} =
             child.input

    assert caller_info["flow_id"] == caller.id
    assert caller_info["flow_name"] == "Caller"
    assert caller_info["execution_id"] == execution.public_id
    assert caller_info["chain"] == [caller.id]
  end

  test "sends what a placeholder points at" do
    doubler = doubler()
    caller = caller(doubler, %{"subflow_data" => "{{order}}"})

    assert %{status: "succeeded", result: %{"result" => 10}} =
             run(caller, %{"order" => %{"n" => 5}})
  end

  test "goes on at once without waiting, with the run it started" do
    doubler = doubler()
    caller = caller(doubler, %{"subflow_data" => ~s({"n": 1}), "subflow_mode" => "start"})

    execution = run(caller)

    assert execution.status == "succeeded"
    assert [child] = runs_of(doubler)
    assert child.status == "queued"

    assert execution.result["result"] == %{
             "execution_id" => child.public_id,
             "flow_id" => doubler.id,
             "flow_name" => "Doubler"
           }
  end

  test "goes through error when the flow fails" do
    broken =
      flow_fixture(%{
        name: "Broken",
        nodes: [
          node("trigger", "Subflow Trigger"),
          node("boom", "Evaluate Code", code("1 + nil"))
        ],
        connections: [link("trigger", "boom")]
      })

    execution = run(caller(broken, %{}))

    assert execution.status == "succeeded"
    assert execution.result["result"]["error"] =~ "Broken failed:"
    assert [%{status: "failed"}] = runs_of(broken)
  end

  test "refuses a flow that isn't published" do
    draft = doubler(%{published: false})

    execution = run(caller(draft, %{"subflow_data" => ~s({"n": 1})}))

    assert execution.result["result"]["error"] ==
             "Doubler isn't published, so it has nothing to run."

    assert runs_of(draft) == []
  end

  test "refuses a flow of another workspace" do
    other = doubler(%{user: HeddleCore.AccountsFixtures.user_fixture()})
    mine = flow_fixture(%{name: "Mine"})

    execution =
      run(caller(other, %{"subflow_data" => ~s({"n": 1})}, %{workspace: workspace_of(mine)}))

    assert execution.result["result"]["error"] ==
             "The flow picked isn't in this workspace any more."

    assert runs_of(other) == []
  end

  test "stops a flow that would end up calling itself" do
    # Ping calls Pong, which calls Ping again.
    ping = flow_fixture(%{name: "Ping", published: false})
    pong = caller(ping, %{"subflow_data" => "{{result}}"}, %{name: "Pong"})

    {:ok, _flow} =
      HeddleCore.Flows.update_flow(ping, %{
        nodes: [
          node("trigger", "Subflow Trigger") |> Map.put("position", %{"x" => 0, "y" => 0}),
          node("call", "Subflow", %{"subflow_id" => to_string(pong.id)})
          |> Map.put("position", %{"x" => 200, "y" => 0})
        ],
        connections: [link("trigger", "call")]
      })

    {:ok, _version} =
      HeddleCore.Flows.Versions.publish_draft(HeddleCore.Flows.saved_draft(ping), nil)

    execution = run(pong)

    # Pong ran Ping, whose call back to Pong was refused. Nothing takes that error in
    # Ping, so it failed, and Pong went on through its error output.
    message = "Pong is already running in this chain of flows, so it would call itself."
    assert [%{status: "failed"} = ping_run] = runs_of(ping)
    assert ping_run.error["message"] == message

    assert execution.status == "succeeded"
    assert execution.result["result"]["error"] == "Ping failed: " <> message
  end

  test "asks for a flow when none is picked" do
    assert {:ok, %{"result" => %{"error" => "Pick the flow to run."}}, "error"} =
             HeddleNodes.Nodes.Subflow.handler(%{"workspace_id" => 1, "subflow_id" => " "}, nil)
  end

  test "a flow can't be published with a Subflow that picked no flow" do
    flow = flow_fixture(%{published: false})

    assert {:error, %Ecto.Changeset{} = changeset} =
             HeddleCore.Flows.update_flow(flow, %{nodes: [node("call", "Subflow")]})

    assert {"contains a Subflow with no flow picked", _} = changeset.errors[:nodes]
  end
end
