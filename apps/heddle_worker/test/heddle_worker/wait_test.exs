defmodule HeddleWorker.WaitTest do
  use HeddleCore.DataCase, async: true
  use Oban.Testing, repo: HeddleCore.Repo

  import HeddleCore.FlowsFixtures

  alias HeddleCore.Executions
  alias HeddleWorker.FlowExecutionWorker

  @worker "HeddleWorker.FlowExecutionWorker"

  defp node(id, type, controls \\ %{}) do
    %{"id" => id, "type" => type, "label" => type, "controls" => controls}
  end

  defp wire(source, output, target) do
    %{"source" => source, "sourceOutput" => output, "target" => target, "targetInput" => "exec"}
  end

  defp wait_flow(wait_controls) do
    flow_fixture(%{
      nodes: [
        node("start", "Start"),
        node("wait", "Wait", wait_controls),
        node("after", "Variable", %{"var_name" => "went_on", "var_value" => "yes"}),
        node("late", "Variable", %{"var_name" => "went_on", "var_value" => "late"})
      ],
      connections: [
        wire("start", "exec", "wait"),
        wire("wait", "exec", "after"),
        wire("wait", "timeout", "late")
      ]
    })
  end

  defp start(flow) do
    execution = execution_fixture(%{flow: flow})
    :ok = FlowExecutionWorker.perform(%Oban.Job{args: %{"execution_id" => execution.id}})
    Executions.get_execution!(execution.id)
  end

  defp resume_jobs(execution) do
    for job <- all_enqueued(worker: @worker), job.args["execution_id"] == execution.id, do: job
  end

  defp perform(job), do: FlowExecutionWorker.perform(%{job | args: job.args})

  test "a run that waits is saved, and a job at the time it ends goes on with it" do
    execution = start(wait_flow(%{"wait_for" => "time", "amount" => "5", "unit" => "minutes"}))

    assert execution.status == "waiting"
    assert %{"wait_id" => wait_id, "wait" => %{"node_id" => "wait"}} = execution.paused
    assert Enum.map(execution.logs, & &1["node_id"]) == ["start"]

    assert [job] = resume_jobs(execution)
    assert job.args["wait_id"] == wait_id
    assert job.args["by"] == "time"
    assert_in_delta DateTime.diff(job.scheduled_at, DateTime.utc_now()), 300, 5

    assert :ok = perform(job)

    finished = Executions.get_execution!(execution.id)
    assert finished.status == "succeeded"
    assert finished.paused == nil
    assert finished.result["variables"] == %{"went_on" => "yes"}
    assert Enum.map(finished.logs, & &1["node_id"]) == ["start", "wait", "after"]
  end

  test "a call resumes it once, with the request, and the time limit then finds it gone" do
    execution = start(wait_flow(%{"wait_for" => "call", "amount" => "1", "unit" => "hours"}))

    assert execution.status == "waiting"
    assert [timeout] = resume_jobs(execution)
    assert timeout.args["by"] == "timeout"

    request = %{"body" => %{"ok" => true}, "query_params" => %{}, "method" => "POST"}
    assert {:ok, _execution} = Executions.resume_by_call(execution.resume_token, request)
    assert {:error, :already_resumed} = Executions.resume_by_call(execution.resume_token, request)

    call = Enum.find(resume_jobs(execution), &(&1.args["by"] == "call"))
    assert :ok = perform(call)
    assert :ok = perform(timeout)

    finished = Executions.get_execution!(execution.id)
    assert finished.status == "succeeded"

    assert finished.result["result"] == %{
             "body" => %{"ok" => true},
             "query_params" => %{},
             "method" => "POST"
           }

    assert finished.result["variables"] == %{"went_on" => "yes"}
    refute Map.has_key?(finished.result, "resume_url")
  end

  test "the time limit goes on through timeout when no call came" do
    execution = start(wait_flow(%{"wait_for" => "call", "amount" => "1", "unit" => "hours"}))
    assert [timeout] = resume_jobs(execution)

    assert :ok = perform(timeout)

    finished = Executions.get_execution!(execution.id)
    assert finished.result["variables"] == %{"went_on" => "late"}

    assert {:error, :finished} =
             Executions.resume_by_call(execution.resume_token, %{}, timeout: 0)
  end

  test "the flow reads the address that resumes it" do
    flow =
      flow_fixture(%{
        nodes: [
          node("start", "Start"),
          node("url", "Variable", %{"var_name" => "url", "var_value" => "{{resume_url}}"}),
          node("wait", "Wait", %{"wait_for" => "call", "amount" => ""})
        ],
        connections: [wire("start", "exec", "url"), wire("url", "exec", "wait")]
      })

    execution = start(flow)

    assert execution.paused["context"]["resume_url"] == Executions.resume_url(execution)
    assert Executions.resume_url(execution) =~ "/api/resume/#{execution.resume_token}"
    # Without a time limit nothing ends the wait but the call.
    assert resume_jobs(execution) == []
  end

  describe "claim_resume/3" do
    setup do
      %{execution: start(wait_flow(%{"wait_for" => "time", "amount" => "5"}))}
    end

    test "only one job takes a pause, and it can take it again on a retry", %{
      execution: execution
    } do
      wait_id = execution.paused["wait_id"]

      assert {:ok, %{status: "running"}} = Executions.claim_resume(execution.id, wait_id, 7)
      assert :error = Executions.claim_resume(execution.id, wait_id, 8)
      assert {:ok, _execution} = Executions.claim_resume(execution.id, wait_id, 7)
    end

    test "a job of another pause takes nothing", %{execution: execution} do
      assert :error = Executions.claim_resume(execution.id, "an-earlier-wait", 7)
    end
  end

  test "a call to a run that isn't waiting yet is told so, and an unknown address too" do
    execution = execution_fixture(%{flow: wait_flow(%{"wait_for" => "call"})})

    assert {:error, :not_waiting} =
             Executions.resume_by_call(execution.resume_token, %{}, timeout: 0)

    assert {:error, :not_found} = Executions.resume_by_call("nothing-here", %{})
  end
end
