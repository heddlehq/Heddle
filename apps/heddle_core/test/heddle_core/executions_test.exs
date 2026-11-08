defmodule HeddleCore.ExecutionsTest do
  use HeddleCore.DataCase

  alias HeddleCore.Executions
  alias HeddleCore.Executions.Execution

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  describe "executions" do
    test "create_execution/1 creates a queued execution with defaults" do
      flow = flow_fixture()

      assert {:ok, %Execution{} = execution} =
               Executions.create_execution(%{flow_id: flow.id, input: %{"trigger" => "manual"}})

      assert execution.flow_id == flow.id
      assert execution.public_id =~ ~r/^[a-z0-9]+-[a-z0-9]+-[a-z0-9]+-[a-z0-9]{4}$/
      assert execution.status == "queued"
      assert execution.input == %{"trigger" => "manual"}
      assert execution.result == nil
      assert execution.error == nil
      assert execution.logs == []
      assert execution.started_at == nil
      assert execution.finished_at == nil
    end

    test "create_execution/1 keeps generating unique ids past the word combinations" do
      flow = flow_fixture()

      public_ids =
        for _ <- 1..2000 do
          {:ok, execution} = Executions.create_execution(%{flow_id: flow.id})
          execution.public_id
        end

      assert public_ids |> Enum.uniq() |> length() == 2000
      assert Enum.all?(public_ids, &(&1 =~ ~r/-[a-z0-9]{4}$/))
    end

    test "get_execution_by_public_id!/1 returns an execution by readable id" do
      execution = execution_fixture()

      assert found_execution = Executions.get_execution_by_public_id!(execution.public_id)
      assert found_execution.id == execution.id
    end

    test "get_execution_by_flow_and_public_id/2 returns execution for flow and public id" do
      flow = flow_fixture()
      execution = execution_fixture(%{flow: flow})

      assert found_execution =
               Executions.get_execution_by_flow_and_public_id(flow.id, execution.public_id)

      assert found_execution.id == execution.id
    end

    test "get_execution_by_flow_and_public_id/2 returns nil for mismatched flow" do
      flow = flow_fixture()
      other_flow = flow_fixture(%{name: "Other Flow"})
      execution = execution_fixture(%{flow: flow})

      assert Executions.get_execution_by_flow_and_public_id(other_flow.id, execution.public_id) ==
               nil
    end

    test "create_execution/1 rejects unknown states" do
      flow = flow_fixture()

      assert {:error, changeset} =
               Executions.create_execution(%{flow_id: flow.id, status: "paused"})

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "create_execution/1 rejects duplicate public ids" do
      flow = flow_fixture()
      public_id = "blue-orbit-run"

      assert {:ok, _execution} =
               Executions.create_execution(%{flow_id: flow.id, public_id: public_id})

      assert {:error, changeset} =
               Executions.create_execution(%{flow_id: flow.id, public_id: public_id})

      assert %{public_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "list_executions_for_flow/1 returns only executions for the given flow" do
      flow = flow_fixture()
      other_flow = flow_fixture(%{name: "Other Flow"})
      execution = execution_fixture(%{flow: flow})
      _other_execution = execution_fixture(%{flow: other_flow})

      assert [listed_execution] = Executions.list_executions_for_flow(flow)
      assert listed_execution.id == execution.id
    end

    test "mark_running/2 moves an execution into running state" do
      execution = execution_fixture()

      assert {:ok, running_execution} = Executions.mark_running(execution)

      assert running_execution.status == "running"
      assert %DateTime{} = running_execution.started_at
      assert running_execution.finished_at == nil
    end

    test "mark_succeeded/3 stores result and terminal timestamp" do
      execution =
        execution_fixture()
        |> then(fn execution ->
          {:ok, execution} = Executions.mark_running(execution)
          execution
        end)

      assert {:ok, succeeded_execution} =
               Executions.mark_succeeded(execution, %{"value" => 42}, %{
                 logs: [%{"node_id" => "output", "status" => "success"}]
               })

      assert succeeded_execution.status == "succeeded"
      assert succeeded_execution.result == %{"value" => 42}
      assert succeeded_execution.error == nil
      assert succeeded_execution.logs == [%{"node_id" => "output", "status" => "success"}]
      assert %DateTime{} = succeeded_execution.finished_at
    end

    test "mark_failed/3 stores normalized error and terminal timestamp" do
      execution = execution_fixture()

      assert {:ok, failed_execution} =
               Executions.mark_failed(execution, "No Start node found", %{
                 logs: [%{"node_id" => "start", "status" => "error"}]
               })

      assert failed_execution.status == "failed"
      assert failed_execution.error == %{"message" => "No Start node found"}
      assert failed_execution.logs == [%{"node_id" => "start", "status" => "error"}]
      assert %DateTime{} = failed_execution.finished_at
    end

    test "append_log/2 adds structured log entries" do
      execution = execution_fixture()

      assert {:ok, execution} =
               Executions.append_log(execution, %{"node_id" => "start", "status" => "success"})

      assert execution.logs == [%{"node_id" => "start", "status" => "success"}]
    end
  end

  describe "webhook_input/1" do
    test "fills in what a real request would have" do
      assert %{
               "trigger" => "webhook",
               "request" => %{"method" => "POST", "headers" => %{}, "body" => %{"x" => 1}}
             } = Executions.webhook_input(%{"body" => %{"x" => 1}})
    end
  end

  describe "save_and_run/3" do
    setup do
      # In the full umbrella suite the HeddleCore.Oban instance is already
      # started; running this file in isolation it isn't, so start it on demand.
      unless oban_running?(HeddleCore.Oban) do
        start_supervised!({Oban, name: HeddleCore.Oban, repo: Repo, testing: :manual})
      end

      :ok
    end

    test "saves the flow graph and enqueues a manual execution" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      flow = flow_fixture(%{user: user, name: "Original"})

      assert {:ok, %{flow: saved_flow, execution: %Execution{} = execution}} =
               Executions.save_and_run(scope, flow, %{name: "Renamed"})

      assert saved_flow.id == flow.id
      assert saved_flow.name == "Renamed"
      assert execution.flow_id == flow.id
      assert execution.status == "queued"
      assert execution.input == %{"trigger" => "manual"}

      # the Oban job was inserted (Oban runs in :manual testing mode)
      assert Repo.aggregate(Oban.Job, :count, :id) == 1
    end

    test "returns a :save error without creating an execution when the graph is invalid" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      flow = flow_fixture(%{user: user, name: "Original"})

      assert {:error, :save, context} = Executions.save_and_run(scope, flow, %{name: ""})

      assert %Ecto.Changeset{} = context.reason
      # no partial flow/execution is reported and nothing was enqueued
      refute Map.has_key?(context, :flow)
      assert Repo.aggregate(Oban.Job, :count, :id) == 0
      assert Executions.list_executions_for_flow(flow.id) == []
    end
  end

  describe "error flows" do
    setup do
      unless oban_running?(HeddleCore.Oban) do
        start_supervised!({Oban, name: HeddleCore.Oban, repo: Repo, testing: :manual})
      end

      user = user_fixture()

      node = %{"id" => "api", "type" => "Start", "label" => "Call the API", "controls" => %{}}
      flow = flow_fixture(%{user: user, name: "Orders", nodes: [node]})
      error_flow = flow_fixture(%{user: user, name: "Alerts"})

      %{scope: user_scope_fixture(user), flow: flow, error_flow: error_flow}
    end

    test "a failed run starts the error flow of its flow, with what failed", context do
      {:ok, flow} =
        HeddleCore.Flows.update_flow_settings(context.scope, context.flow, %{
          error_flow_id: context.error_flow.id
        })

      {:ok, failed} = Executions.create_execution(%{flow_id: flow.id, input: %{}})

      assert {:ok, run} =
               Executions.start_error_flow(failed, %{"message" => "boom", "node_id" => "api"})

      assert run.flow_id == context.error_flow.id

      assert %{
               "trigger" => "error",
               "error" => %{"message" => "boom", "node_label" => "Call the API"},
               "execution" => %{"flow_name" => "Orders", "url" => url}
             } = run.input

      assert url =~ "/flows/#{flow.id}?execution=#{failed.public_id}"
    end

    test "nothing starts without an error flow, or from a run of an error flow", context do
      {:ok, failed} = Executions.create_execution(%{flow_id: context.flow.id, input: %{}})
      assert Executions.start_error_flow(failed, %{"message" => "boom"}) == :none

      {:ok, flow} =
        HeddleCore.Flows.update_flow_settings(context.scope, context.flow, %{
          error_flow_id: context.error_flow.id
        })

      {:ok, failed} =
        Executions.create_execution(%{flow_id: flow.id, input: %{"trigger" => "error"}})

      assert Executions.start_error_flow(failed, %{"message" => "boom"}) == :none
    end

    test "a flow can't be its own error flow, nor one of someone else", context do
      assert {:error, %Ecto.Changeset{}} =
               HeddleCore.Flows.update_flow_settings(context.scope, context.flow, %{
                 error_flow_id: context.flow.id
               })

      other = flow_fixture(%{user: user_fixture()})

      assert {:error, :error_flow_not_found} =
               HeddleCore.Flows.update_flow_settings(context.scope, context.flow, %{
                 error_flow_id: other.id
               })

      assert {:ok, %{error_flow_id: nil}} =
               HeddleCore.Flows.update_flow_settings(context.scope, context.flow, %{
                 error_flow_id: ""
               })
    end
  end

  describe "replay_input/2" do
    test "runs again from a step with the context it got, from the editor" do
      execution = %Execution{
        logs: [
          %{"node_id" => "start", "data" => %{"input" => %{}}},
          %{"node_id" => "api", "data" => %{"input" => %{"name" => "Ana"}}}
        ]
      }

      assert Executions.replay_input(execution, 1) ==
               {:ok, %{"name" => "Ana", "replay_from" => "api", "debug" => true}}
    end

    test "refuses a step that kept only part of its context, or none" do
      execution = %Execution{
        logs: [
          %{"node_id" => "a", "data" => %{"input" => %{}, "truncated" => true}},
          %{"node_id" => "b", "data" => %{"omitted" => true}}
        ]
      }

      assert Executions.replay_input(execution, 0) == {:error, :incomplete}
      assert Executions.replay_input(execution, 1) == {:error, :incomplete}
      assert Executions.replay_input(execution, 2) == {:error, :not_found}
    end

    test "rerun_input/1 takes the input of the run, as a run from the editor" do
      assert Executions.rerun_input(%Execution{input: %{"trigger" => "manual"}}) ==
               %{"trigger" => "manual", "debug" => true}
    end
  end

  defp oban_running?(name) do
    Oban.config(name)
    true
  rescue
    _ -> false
  end

  describe "webhook responses" do
    @response %{"status" => 201, "body" => "ok", "content_type" => "text/plain"}

    test "await_response/2 returns what the flow answered" do
      execution = execution_fixture()
      :ok = Executions.put_response(execution, @response)

      assert Executions.await_response(execution, timeout: 200, poll: 5) == {:ok, @response}
    end

    test "await_response/2 sees a response that comes later" do
      execution = execution_fixture()

      Task.start_link(fn -> Executions.put_response(execution, @response) end)

      assert Executions.await_response(execution, timeout: 1000, poll: 5) == {:ok, @response}
    end

    test "await_response/2 stops when the run fails" do
      execution = execution_fixture()
      {:ok, _execution} = Executions.mark_failed(execution, %{"message" => "boom"})

      assert Executions.await_response(execution, timeout: 200, poll: 5) == {:error, :failed}
    end

    test "await_response/2 stops when the run ends without answering" do
      execution = execution_fixture()
      {:ok, _execution} = Executions.mark_succeeded(execution, %{})

      assert Executions.await_response(execution, timeout: 200, poll: 5) ==
               {:error, :no_response}
    end

    test "await_response/2 gives up after the timeout" do
      execution = execution_fixture()

      assert Executions.await_response(execution, timeout: 20, poll: 5) == {:error, :timeout}
    end

    test "a response survives the run finishing" do
      execution = execution_fixture()
      :ok = Executions.put_response(execution, @response)
      {:ok, _execution} = Executions.mark_succeeded(execution, %{})

      assert Executions.get_execution!(execution.id).response == @response
    end
  end
end
