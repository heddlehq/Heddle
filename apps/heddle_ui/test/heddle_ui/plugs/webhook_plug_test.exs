defmodule HeddleUI.Plugs.WebhookPlugTest do
  use HeddleUI.ConnCase, async: true
  use Oban.Testing, repo: HeddleCore.Repo

  import HeddleCore.FlowsFixtures

  alias HeddleCore.Executions
  alias HeddleCore.Webhooks

  @flow_execution_worker "HeddleWorker.FlowExecutionWorker"

  describe "call/2" do
    test "creates an execution, enqueues the worker, and returns accepted", %{conn: conn} do
      path = unique_webhook_path()
      slug = Webhooks.normalize_path(path)
      flow = webhook_flow_fixture(path: path, method: "POST")

      :ok = Webhooks.register_flow(flow)

      conn =
        post(conn, "/api/flows/#{flow.id}/webhook/#{slug}?source=api", %{
          "value" => 999
        })

      assert %{
               "status" => "accepted",
               "execution_id" => public_id,
               "execution_status" => "queued"
             } = json_response(conn, 202)

      assert [execution] = Executions.list_executions_for_flow(flow)
      assert public_id == execution.public_id
      assert execution.status == "queued"
      assert execution.input["trigger"] == "webhook"
      assert get_in(execution.input, ["request", "body"]) == %{"value" => 999}
      assert get_in(execution.input, ["request", "method"]) == "POST"
      assert get_in(execution.input, ["request", "query_params"]) == %{"source" => "api"}

      assert get_in(execution.input, ["request", "path"]) ==
               "/api/flows/#{flow.id}/webhook/#{slug}"

      assert_enqueued(
        worker: @flow_execution_worker,
        queue: :executions,
        args: %{execution_id: execution.id}
      )
    end

    test "rejects requests with the wrong method", %{conn: conn} do
      path = unique_webhook_path()
      slug = Webhooks.normalize_path(path)
      flow = webhook_flow_fixture(path: path, method: "POST")

      :ok = Webhooks.register_flow(flow)

      conn = get(conn, "/api/flows/#{flow.id}/webhook/#{slug}")

      assert %{"error" => "Method not allowed. Expected POST"} = json_response(conn, 405)
      assert [] = Executions.list_executions_for_flow(flow)
    end

    test "returns not found for unknown webhooks", %{conn: conn} do
      flow = flow_fixture()

      conn = post(conn, "/api/flows/#{flow.id}/webhook/missing", %{})

      assert %{"error" => "Webhook not found"} = json_response(conn, 404)
    end
  end

  describe "a flow with Respond to Webhook" do
    setup do
      path = unique_webhook_path()
      flow = responding_flow_fixture(path)
      :ok = Webhooks.register_flow(flow)

      %{flow: flow, url: "/api/flows/#{flow.id}/webhook/#{Webhooks.normalize_path(path)}"}
    end

    # Stands in for the worker, which runs elsewhere.
    defp when_it_runs(flow, fun) do
      Task.async(fn ->
        execution = next_execution(flow)
        fun.(execution)
      end)
    end

    defp next_execution(flow) do
      case Executions.list_executions_for_flow(flow) do
        [execution | _] ->
          execution

        [] ->
          Process.sleep(2)
          next_execution(flow)
      end
    end

    test "answers with what the flow says", %{conn: conn, flow: flow, url: url} do
      task =
        when_it_runs(flow, fn execution ->
          Executions.put_response(execution, %{
            "status" => 201,
            "body" => ~s({"ok":true}),
            "content_type" => "application/json"
          })
        end)

      conn = post(conn, url, %{})
      Task.await(task)

      assert json_response(conn, 201) == %{"ok" => true}
    end

    test "answers 202 when the run ends without responding", %{conn: conn, flow: flow, url: url} do
      task = when_it_runs(flow, &Executions.mark_succeeded(&1, %{}))

      conn = post(conn, url, %{})
      Task.await(task)

      assert %{"status" => "accepted"} = json_response(conn, 202)
    end

    test "answers 500 when the run fails", %{conn: conn, flow: flow, url: url} do
      task = when_it_runs(flow, &Executions.mark_failed(&1, %{"message" => "boom"}))

      conn = post(conn, url, %{})
      Task.await(task)

      assert %{"error" => error, "execution_id" => _id} = json_response(conn, 500)
      assert error =~ "failed"
    end

    test "answers 504 when the flow takes too long", %{conn: conn, url: url} do
      conn = post(conn, url, %{})

      assert %{"error" => error} = json_response(conn, 504)
      assert error =~ "in time"
    end
  end

  defp responding_flow_fixture(path) do
    flow_fixture(%{
      nodes: [
        %{
          "id" => "1",
          "type" => "Webhook",
          "label" => "Webhook",
          "controls" => %{"path" => path, "method" => "POST"}
        },
        %{"id" => "2", "type" => "Respond to Webhook", "label" => "Reply", "controls" => %{}}
      ],
      connections: [
        %{"source" => "1", "sourceOutput" => "exec", "target" => "2", "targetInput" => "exec"}
      ]
    })
  end

  describe "versions" do
    test "a flow that isn't published has no webhook", %{conn: conn} do
      path = unique_webhook_path()
      flow = webhook_flow_fixture(path: path, method: "POST", published: false)

      :ok = Webhooks.register_flow(flow)
      conn = post(conn, "/api/flows/#{flow.id}/webhook/#{Webhooks.normalize_path(path)}", %{})

      assert %{"error" => "Flow not found"} = json_response(conn, 404)
      assert [] = Executions.list_executions_for_flow(flow)
    end

    test "a webhook runs what the flow publishes, not its draft", %{conn: conn} do
      path = unique_webhook_path()
      slug = Webhooks.normalize_path(path)
      flow = webhook_flow_fixture(path: path, method: "POST")
      published_id = flow.published_version_id

      # A change to the draft doesn't reach production, not even the webhook's path.
      {:ok, _flow} =
        HeddleCore.Flows.update_flow(flow, %{
          nodes: [
            %{
              "id" => "1",
              "type" => "Webhook",
              "label" => "Webhook",
              "controls" => %{"path" => "/webhook/elsewhere", "method" => "POST"}
            }
          ],
          connections: []
        })

      conn = post(conn, "/api/flows/#{flow.id}/webhook/#{slug}", %{"value" => 1})

      assert json_response(conn, 202)
      assert [execution] = Executions.list_executions_for_flow(flow)
      assert execution.flow_version_id == published_id
    end
  end

  defp webhook_flow_fixture(opts) do
    path = Keyword.fetch!(opts, :path)
    method = Keyword.fetch!(opts, :method)

    flow_fixture(%{
      published: Keyword.get(opts, :published, true),
      published: Keyword.get(opts, :published, true),
      nodes: [
        %{
          "id" => "1",
          "type" => "Webhook",
          "label" => "Webhook",
          "controls" => %{"path" => path, "method" => method}
        },
        %{"id" => "2", "type" => "Output", "label" => "Output", "controls" => %{}}
      ],
      connections: [
        %{"source" => "1", "sourceOutput" => "exec", "target" => "2", "targetInput" => "exec"}
      ]
    })
  end

  defp unique_webhook_path do
    "/webhook/test-#{System.unique_integer([:positive])}"
  end
end
