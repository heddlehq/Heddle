defmodule HeddleWorker.PollWorkerTest do
  # Swaps the credential store, which is global.
  use HeddleCore.DataCase, async: false

  alias HeddleCore.Executions
  alias HeddleCore.Integrations.Polls
  alias HeddleWorker.PollWorker

  import HeddleCore.FlowsFixtures

  @now ~U[2026-11-22 10:00:00Z]

  defmodule Vault do
    def fetch(_workspace_id, "bot", "slack"), do: {:ok, %{"token" => "xoxb"}}
  end

  setup do
    previous = Application.get_env(:heddle_nodes, :credentials_client)
    Application.put_env(:heddle_nodes, :credentials_client, Vault)
    on_exit(fn -> Application.put_env(:heddle_nodes, :credentials_client, previous) end)

    flow =
      flow_fixture(%{
        nodes: [
          %{
            "id" => "new",
            "type" => "Slack: New Message",
            "label" => "New Message",
            "controls" => %{"credential" => "bot", "channel" => "C1"},
            "position" => %{"x" => 0, "y" => 0}
          }
        ],
        connections: []
      })

    %{flow: flow}
  end

  defp slack(messages) do
    Req.Test.stub(HeddleNodes.Nodes.HttpRequest, fn conn ->
      Req.Test.json(conn, %{"ok" => true, "messages" => messages})
    end)
  end

  defp tick(at), do: PollWorker.perform(%Oban.Job{scheduled_at: at})

  defp started(flow) do
    flow
    |> Executions.list_executions_for_flow()
    |> Enum.map(& &1.input["item"]["text"])
    |> Enum.sort()
  end

  test "starts the flow once for each new item, after a first call that only looks",
       %{flow: flow} do
    slack([%{"ts" => "1", "text" => "old"}])
    assert :ok = tick(@now)
    assert started(flow) == []

    slack([
      %{"ts" => "3", "text" => "c"},
      %{"ts" => "2", "text" => "b"},
      %{"ts" => "1", "text" => "old"}
    ])

    assert :ok = tick(DateTime.add(@now, 60))
    assert started(flow) == ["b", "c"]

    [execution | _] = Executions.list_executions_for_flow(flow)
    assert %{"trigger" => "poll", "node_id" => "new"} = execution.input

    # Nothing new: no more runs.
    assert :ok = tick(DateTime.add(@now, 120))
    assert length(started(flow)) == 2
  end

  test "waits the trigger's interval between calls", %{flow: flow} do
    slack([])
    assert :ok = tick(@now)

    slack([%{"ts" => "9", "text" => "early"}])
    assert :ok = tick(DateTime.add(@now, 30))
    assert started(flow) == []
  end

  test "records a call the service refused", %{flow: flow} do
    Req.Test.stub(HeddleNodes.Nodes.HttpRequest, fn conn ->
      Req.Test.json(conn, %{"ok" => false, "error" => "channel_not_found"})
    end)

    assert :ok = tick(@now)
    assert %{error: "Slack refused it: channel_not_found"} = Polls.get(flow.id, "new")
  end
end
