defmodule HeddleWorker.FormValidationTest do
  use HeddleWorker.WorkerCase, async: true

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Forms

  @fields Jason.encode!([
            %{"key" => "name", "label" => "Name", "type" => "text", "required" => true},
            %{"key" => "email", "label" => "Email", "type" => "text", "required" => true}
          ])

  @schema ~s({"name": {"type": "string", "min": 2}, "email": {"type": "email", "lowercase": true}})

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    scope = user_scope_fixture(user)

    flow =
      flow_fixture(
        user: user,
        workspace: workspace,
        nodes: [
          %{
            "id" => "form",
            "type" => "Form Trigger",
            "label" => "Form",
            "controls" => %{"title" => "Join", "fields" => @fields, "accepting" => "yes"}
          },
          %{
            "id" => "check",
            "type" => "Validate",
            "label" => "Check",
            "controls" => %{"validation_data" => "{{form}}", "validation_schema" => @schema}
          },
          %{"id" => "ok", "type" => "Output", "label" => "Ok", "controls" => %{}},
          %{"id" => "bad", "type" => "Output", "label" => "Bad", "controls" => %{}}
        ],
        connections: [
          %{"source" => "form", "sourceOutput" => "exec", "target" => "check"},
          %{"source" => "check", "sourceOutput" => "valid", "target" => "ok"},
          %{"source" => "check", "sourceOutput" => "invalid", "target" => "bad"}
        ]
      )

    {:ok, form} = Forms.link(scope, flow, "form")
    %{token: form.token, flow: flow}
  end

  # Sends the form while the worker runs what it queued, as it would on its own.
  defp send_form(token, values) do
    sending = Task.async(fn -> Forms.submit(token, values, timeout: 5_000, poll: 10) end)

    assert_enqueued([worker: FlowExecutionWorker], 2_000)
    [job] = all_enqueued(worker: FlowExecutionWorker)
    :ok = FlowExecutionWorker.perform(job)

    {Task.await(sending, 6_000), Executions.get_execution!(job.args["execution_id"])}
  end

  test "the form shows what the Validate refused, by field", %{token: token} do
    {answer, execution} = send_form(token, %{"name" => "A", "email" => "nope"})

    assert {:error, :rejected, _page, issues, values} = answer
    assert values == %{"name" => "A", "email" => "nope"}

    assert [
             %{"path" => "email", "code" => "invalid_format"},
             %{"path" => "name", "code" => "too_small", "params" => %{"limit" => 2}}
           ] = issues

    # The run went on through invalid, and ended.
    assert execution.status == "succeeded"
    assert [_form, %{"node_id" => "check"}, %{"node_id" => "bad"}] = execution.logs
  end

  test "what the Validate takes is sent, and the run goes on with it", %{token: token} do
    {answer, execution} = send_form(token, %{"name" => "Ana", "email" => "Ana@Example.com"})

    assert {:ok, _page} = answer
    assert execution.result["result"] == %{"name" => "Ana", "email" => "ana@example.com"}
    assert [_form, %{"node_id" => "check"}, %{"node_id" => "ok"}] = execution.logs
  end
end
