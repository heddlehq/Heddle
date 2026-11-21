defmodule HeddleWorker.ApprovalTest do
  use HeddleCore.DataCase, async: true
  use Oban.Testing, repo: HeddleCore.Repo

  import HeddleCore.AccountsFixtures
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

  setup do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    scope = user_scope_fixture(owner)

    flow =
      flow_fixture(%{
        user: owner,
        workspace: workspace,
        nodes: [
          node("start", "Start"),
          node("ask", "Approval", %{
            "approval_title" => "Refund {{amount}}?",
            "approval_details" => "Customer asked twice.",
            "approval_wait" => "2",
            "approval_unit" => "days"
          }),
          node("yes", "Variable", %{"var_name" => "went", "var_value" => "approved"}),
          node("no", "Variable", %{"var_name" => "went", "var_value" => "rejected"}),
          node("late", "Variable", %{"var_name" => "went", "var_value" => "late"})
        ],
        connections: [
          wire("start", "exec", "ask"),
          wire("ask", "approved", "yes"),
          wire("ask", "rejected", "no"),
          wire("ask", "timeout", "late")
        ]
      })

    %{flow: flow, scope: scope, workspace: workspace}
  end

  defp start(flow) do
    execution = execution_fixture(%{flow: flow, input: %{"amount" => "$40"}})
    :ok = FlowExecutionWorker.perform(%Oban.Job{args: %{"execution_id" => execution.id}})
    Executions.get_execution!(execution.id)
  end

  defp finish(execution, by) do
    job =
      Enum.find(all_enqueued(worker: @worker), fn job ->
        job.args["execution_id"] == execution.id and job.args["by"] == by
      end)

    :ok = FlowExecutionWorker.perform(%{job | args: job.args})
    Executions.get_execution!(execution.id)
  end

  test "waits on the Approvals page, and goes on through approved with who decided", %{
    flow: flow,
    scope: scope
  } do
    execution = start(flow)

    assert execution.status == "waiting"

    assert %{"title" => "Refund $40?", "details" => "Customer asked twice."} =
             execution.paused["wait"]["approval"]

    assert [listed] = Executions.list_approvals(scope)
    assert listed.id == execution.id

    assert {:ok, _execution} = Executions.decide(scope, execution.id, "approved", " fine ")
    assert {:error, :already_resumed} = Executions.decide(scope, execution.id, "rejected")

    finished = finish(execution, "call")

    assert finished.status == "succeeded"
    assert finished.result["variables"] == %{"went" => "approved"}
    assert Executions.list_approvals(scope) == []

    approval = Enum.find(finished.logs, &(&1["node_id"] == "ask"))
    assert approval["output"] == "approved"
  end

  test "a call to its address decides too, and anything but approved rejects", %{flow: flow} do
    execution = start(flow)
    request = %{"body" => %{}, "query_params" => %{"decision" => "maybe"}, "method" => "GET"}

    assert {:ok, _execution} = Executions.resume_by_call(execution.resume_token, request)

    assert finish(execution, "call").result["variables"] == %{"went" => "rejected"}
  end

  test "goes on through timeout when nobody decides in time", %{flow: flow} do
    execution = start(flow)

    assert finish(execution, "timeout").result["variables"] == %{"went" => "late"}
  end

  test "a viewer sees it and can't decide, and other workspaces don't see it", %{
    flow: flow,
    workspace: workspace
  } do
    execution = start(flow)

    viewer = user_fixture()
    member_fixture(workspace, viewer, "viewer")
    viewer_scope = user_scope_fixture(viewer)

    assert [_listed] = Executions.list_approvals(viewer_scope)
    assert {:error, :forbidden} = Executions.decide(viewer_scope, execution.id, "approved")

    stranger = user_scope_fixture()

    assert Executions.list_approvals(stranger) == []
    assert {:error, :not_found} = Executions.decide(stranger, execution.id, "approved")
  end
end
