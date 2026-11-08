defmodule HeddleUI.Agent.SessionTest do
  # Not async: the session and its tasks share the connection of the test.
  use HeddleUI.ConnCase, async: false

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Executions
  alias HeddleCore.Flows
  alias HeddleUI.Agent
  alias HeddleUI.FakeHarnessModel

  @start %{
    "id" => "start",
    "type" => "Start",
    "label" => "Start",
    "controls" => %{},
    "position" => %{"x" => 0, "y" => 0}
  }

  setup do
    Application.put_env(:heddle_ai, :harness_model, FakeHarnessModel)
    on_exit(fn -> Application.delete_env(:heddle_ai, :harness_model) end)

    user = user_fixture()
    Process.put(:heddle_owner, user)
    flow = flow_fixture(%{nodes: [@start]})
    scope = Scope.for_user(user)
    :ok = Agent.subscribe(scope, flow.id)

    on_exit(fn ->
      HeddleUI.AgentHelpers.stop_all()
    end)

    %{scope: scope, flow: flow, id: to_string(flow.id)}
  end

  defp idle, do: assert_receive({:agent_event, %{type: "status", status: "idle"}}, 2000)

  defp asked do
    assert_receive {:agent_event, %{type: "permission", permission: %{flow_name: _name}}}, 2000
  end

  # The worker isn't part of this app, so this finishes the run the way it would.
  defp finish_run(flow) do
    assert_eventually(fn -> queued(flow) != nil end)

    {:ok, execution} = flow |> queued() |> Executions.mark_running()
    {:ok, execution} = Executions.mark_succeeded(execution, %{"result" => 5}, %{logs: []})
    Executions.broadcast_execution_updated(execution)
  end

  defp queued(flow) do
    flow |> Executions.list_executions_for_flow() |> Enum.find(&(&1.status == "queued"))
  end

  defp assert_eventually(check, attempts \\ 100) do
    cond do
      check.() ->
        :ok

      attempts == 0 ->
        flunk("It never happened")

      true ->
        _ = :erlang.yield()
        Process.sleep(10)
        assert_eventually(check, attempts - 1)
    end
  end

  test "investigates, fixes and tests from a message that only says it is broken",
       %{scope: scope, flow: flow, id: id} do
    FakeHarnessModel.script([
      {:tool, "get_flow", %{flow_id: id}},
      {:tool, "update_flow", %{flow_id: id, name: "Fixed"}},
      {:tool, "test_flow", %{flow_id: id}},
      "It was the name. I changed it and the test passed."
    ])

    assert :ok = Agent.send_message(scope, flow.id, "ta dando erro")

    asked()
    assert :ok = Agent.decide(scope, flow.id, "once")
    finish_run(flow)
    idle()

    transcript = Agent.transcript(scope, flow.id)

    assert [
             %{role: "user", text: "ta dando erro"},
             %{role: "tool", name: "get_flow", status: "ok"},
             %{role: "tool", name: "update_flow", status: "ok"},
             %{role: "tool", name: "test_flow", status: "ok", output: output},
             %{role: "assistant", text: "It was the name." <> _rest}
           ] = transcript.items

    assert %{"status" => "succeeded"} = Jason.decode!(output)
    assert Flows.get_flow!(flow.id).name == "Fixed"
    assert transcript.status == "idle"
  end

  defp failed_run(flow, message) do
    {:ok, execution} =
      flow |> then(&execution_fixture(%{flow: &1})) |> Executions.mark_failed(message)

    execution
  end

  # Executions are stamped by the second.
  defp a_second_later(execution) do
    inserted_at = DateTime.add(execution.inserted_at, 1)

    {:ok, _execution} =
      execution |> Ecto.Changeset.change(inserted_at: inserted_at) |> HeddleCore.Repo.update()
  end

  test "reads a new failure by itself and hands it to the model", %{scope: scope, flow: flow} do
    execution = failed_run(flow, "syntax error before: asdf")
    FakeHarnessModel.script(["Found it."])

    :ok = Agent.send_message(scope, flow.id, "ta dando erro")
    idle()

    assert [
             %{role: "user", text: "ta dando erro"},
             %{role: "tool", name: "get_execution", status: "ok", output: output},
             %{role: "assistant"}
           ] = Agent.transcript(scope, flow.id).items

    assert output =~ execution.public_id

    message = FakeHarnessModel.last_message()
    assert message =~ "ta dando erro"
    assert message =~ "FAILED"
    assert message =~ execution.public_id
    assert message =~ "asdf"
  end

  test "a failure after a success beats the success in the conversation",
       %{scope: scope, flow: flow, id: id} do
    FakeHarnessModel.script([
      {:tool, "test_flow", %{flow_id: id}},
      "It works.",
      "Now it doesn't."
    ])

    :ok = Agent.send_message(scope, flow.id, "test it")
    asked()
    :ok = Agent.decide(scope, flow.id, "once")
    finish_run(flow)
    idle()

    later = failed_run(flow, "boom")
    a_second_later(later)
    :ok = Agent.send_message(scope, flow.id, "ta dando erro")
    idle()

    assert FakeHarnessModel.last_message() =~ later.public_id
  end

  test "reads each failure only once", %{scope: scope, flow: flow} do
    failed_run(flow, "boom")
    FakeHarnessModel.script(["One.", "Two."])

    :ok = Agent.send_message(scope, flow.id, "one")
    idle()
    :ok = Agent.send_message(scope, flow.id, "two")
    idle()

    assert 1 ==
             Agent.transcript(scope, flow.id).items |> Enum.count(&(&1.role == "tool"))

    assert FakeHarnessModel.last_message() =~ "FAILED"
  end

  test "keeps the state out of what the person sees", %{scope: scope, flow: flow} do
    FakeHarnessModel.script(["Ok."])

    :ok = Agent.send_message(scope, flow.id, "hi")
    idle()

    assert [%{text: "hi"} | _rest] = Agent.transcript(scope, flow.id).items
    assert FakeHarnessModel.last_message() =~ "<current_state>"
  end

  test "remembers the conversation between messages", %{scope: scope, flow: flow} do
    FakeHarnessModel.script(["First.", "Second."])

    :ok = Agent.send_message(scope, flow.id, "one")
    idle()
    :ok = Agent.send_message(scope, flow.id, "two")
    idle()

    assert [_one, %{text: "First."}, _two, %{text: "Second."}] =
             Agent.transcript(scope, flow.id).items
  end

  test "asks only once after being told to always allow", %{scope: scope, flow: flow, id: id} do
    FakeHarnessModel.script([
      {:tool, "test_flow", %{flow_id: id}},
      {:tool, "test_flow", %{flow_id: id}},
      "Done."
    ])

    :ok = Agent.send_message(scope, flow.id, "test it twice")

    asked()
    :ok = Agent.decide(scope, flow.id, "always")
    finish_run(flow)

    finish_run(flow)
    idle()

    refute_received {:agent_event, %{type: "permission", permission: %{flow_name: _name}}}
  end

  test "asks before publishing, even after being told to always allow runs", %{
    scope: scope,
    flow: flow,
    id: id
  } do
    FakeHarnessModel.script([
      {:tool, "test_flow", %{flow_id: id}},
      {:tool, "publish_flow", %{flow_id: id}},
      "Published."
    ])

    :ok = Agent.send_message(scope, flow.id, "test it and publish it")

    asked()
    :ok = Agent.decide(scope, flow.id, "always")
    finish_run(flow)

    assert_receive {:agent_event,
                    %{type: "permission", permission: %{action: "publish", flow_name: _name}}},
                   2000

    published_before = Flows.get_flow!(flow.id).published_version_id
    :ok = Agent.decide(scope, flow.id, "once")
    idle()

    assert Flows.get_flow!(flow.id).published_version_id != published_before
  end

  test "gives a refusal to the model instead of running", %{scope: scope, flow: flow, id: id} do
    FakeHarnessModel.script([{:tool, "test_flow", %{flow_id: id}}, "Ok, I won't."])

    :ok = Agent.send_message(scope, flow.id, "test it")

    asked()
    :ok = Agent.decide(scope, flow.id, "deny")
    idle()

    assert Executions.list_executions_for_flow(flow) == []

    assert %{status: "error", output: output} =
             Enum.find(Agent.transcript(scope, flow.id).items, &(&1.role == "tool"))

    assert output =~ "refused"
  end

  describe "conversations" do
    test "a new one forgets the old and keeps it saved", %{scope: scope, flow: flow} do
      FakeHarnessModel.script(["First."])
      :ok = Agent.send_message(scope, flow.id, "one")
      idle()

      assert :ok = Agent.new_conversation(scope, flow.id)

      assert Agent.transcript(scope, flow.id).items == []
      assert [%{title: "one"}] = Agent.conversations(scope, flow.id)
    end

    test "an old one comes back with what was said", %{scope: scope, flow: flow} do
      FakeHarnessModel.script(["The answer.", "Continuing."])
      :ok = Agent.send_message(scope, flow.id, "my question")
      idle()
      [%{id: id}] = Agent.conversations(scope, flow.id)
      :ok = Agent.new_conversation(scope, flow.id)

      assert :ok = Agent.open_conversation(scope, flow.id, id)

      assert [%{text: "my question"}, %{text: "The answer."}] =
               Agent.transcript(scope, flow.id).items

      :ok = Agent.send_message(scope, flow.id, "and now?")
      idle()

      assert [%{id: ^id}] = Agent.conversations(scope, flow.id)
      assert length(Agent.transcript(scope, flow.id).items) == 4
    end

    test "survives the end of the process", %{scope: scope, flow: flow} do
      FakeHarnessModel.script(["Saved."])
      :ok = Agent.send_message(scope, flow.id, "hi")
      idle()
      [%{id: id}] = Agent.conversations(scope, flow.id)

      HeddleUI.AgentHelpers.stop_all()

      assert :ok = Agent.open_conversation(scope, flow.id, id)
      assert [_user, %{text: "Saved."}] = Agent.transcript(scope, flow.id).items
    end

    test "a new one waits for the work to end", %{scope: scope, flow: flow} do
      FakeHarnessModel.script([:hang])
      :ok = Agent.send_message(scope, flow.id, "go")
      HeddleUI.AgentHelpers.wait_for_script()

      assert {:error, :busy} = Agent.new_conversation(scope, flow.id)
      assert [%{text: "go"}] = Agent.transcript(scope, flow.id).items
    end

    test "only the latest state reaches the model", %{scope: scope, flow: flow} do
      FakeHarnessModel.script(["One.", "Two."])
      :ok = Agent.send_message(scope, flow.id, "one")
      idle()
      :ok = Agent.send_message(scope, flow.id, "two")
      idle()

      contents = FakeHarnessModel.all_messages()

      assert Enum.count(contents, &String.contains?(&1, "</current_state>")) == 1
    end
  end

  test "takes no second message while it works", %{scope: scope, flow: flow} do
    FakeHarnessModel.script([:hang])

    assert :ok = Agent.send_message(scope, flow.id, "go")
    assert {:error, :busy} = Agent.send_message(scope, flow.id, "and this")
    HeddleUI.AgentHelpers.wait_for_script()
  end

  test "can be stopped and goes on after", %{scope: scope, flow: flow} do
    FakeHarnessModel.script([:hang, "Back."])

    :ok = Agent.send_message(scope, flow.id, "go")
    assert_eventually(fn -> FakeHarnessModel.remaining() == ["Back."] end)

    assert :ok = Agent.stop(scope, flow.id)
    idle()

    :ok = Agent.send_message(scope, flow.id, "again")
    idle()

    assert %{role: "assistant", text: "Back."} = List.last(Agent.transcript(scope, flow.id).items)
  end

  test "stopping while it waits for an answer doesn't leave the question open",
       %{scope: scope, flow: flow, id: id} do
    FakeHarnessModel.script([{:tool, "test_flow", %{flow_id: id}}])

    :ok = Agent.send_message(scope, flow.id, "test")
    asked()

    :ok = Agent.stop(scope, flow.id)
    idle()

    assert Agent.transcript(scope, flow.id).permission == nil
  end

  test "survives a turn that crashes", %{scope: scope, flow: flow} do
    FakeHarnessModel.script([:crash, "Fine now."])

    :ok = Agent.send_message(scope, flow.id, "go")
    assert_receive {:agent_event, %{type: "failed", message: _message}}, 2000
    idle()

    :ok = Agent.send_message(scope, flow.id, "again")
    idle()

    assert %{text: "Fine now."} = List.last(Agent.transcript(scope, flow.id).items)
  end

  test "shows a provider error in the conversation", %{scope: scope, flow: flow} do
    FakeHarnessModel.script([{:error, RuntimeError.exception("no credits")}])

    :ok = Agent.send_message(scope, flow.id, "go")
    idle()

    assert %{role: "error", text: "no credits"} =
             List.last(Agent.transcript(scope, flow.id).items)
  end

  test "keeps its key only for the turn, however it ends", %{scope: scope, flow: flow} do
    FakeHarnessModel.script(["Ok.", :hang])

    :ok = Agent.send_message(scope, flow.id, "go")
    idle()

    assert HeddleCore.Repo.all_by(HeddleCore.ApiKeys.ApiKey, user_id: scope.user.id) == []

    :ok = Agent.send_message(scope, flow.id, "again")
    assert_eventually(fn -> FakeHarnessModel.remaining() == [] end)
    :ok = Agent.stop(scope, flow.id)
    idle()

    assert HeddleCore.Repo.all_by(HeddleCore.ApiKeys.ApiKey, user_id: scope.user.id) == []
  end

  test "is a conversation per person and flow", %{scope: scope, flow: flow} do
    FakeHarnessModel.script(["Ok."])

    :ok = Agent.send_message(scope, flow.id, "go")
    idle()

    other = Scope.for_user(user_fixture())

    assert Agent.transcript(other, flow.id).items == []
  end
end
