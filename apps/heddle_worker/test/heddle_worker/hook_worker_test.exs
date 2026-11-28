defmodule HeddleWorker.HookWorkerTest do
  # Swaps the credential store and installs a community integration, both global.
  use HeddleWorker.WorkerCase, async: false

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures
  import HeddleCore.IntegrationsFixtures

  alias HeddleCore.Flows.Versions
  alias HeddleCore.Integrations.Hooks
  alias HeddleWorker.HookWorker

  defmodule Vault do
    def fetch(_workspace_id, "forge", "forge"), do: {:ok, %{"token" => "t0k"}}
  end

  setup do
    previous = Application.get_env(:heddle_nodes, :credentials_client)
    Application.put_env(:heddle_nodes, :credentials_client, Vault)
    on_exit(fn -> Application.put_env(:heddle_nodes, :credentials_client, previous) end)
    on_exit(&HeddleNodes.Community.reset/0)

    user = user_fixture()
    workspace = workspace_fixture(user)
    install_forge(user_scope_fixture(user))

    %{user: user, workspace: workspace, calls: start_supervised!({Agent, fn -> [] end})}
  end

  defp push_node(repo, type \\ "Forge: New Push") do
    %{
      "id" => "push",
      "type" => type,
      "label" => "New Push",
      "controls" => %{"credential" => "forge", "repo" => repo},
      "position" => %{"x" => 0, "y" => 0}
    }
  end

  defp forge(calls) do
    Req.Test.stub(HeddleNodes.Nodes.HttpRequest, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      Agent.update(calls, &(&1 ++ [{conn.method, conn.request_path, body}]))

      # Like Trello, the service checks the address before it answers.
      if conn.method == "POST" do
        url = Jason.decode!(body)["url"]
        assert %{error: nil} = Hooks.get_by_token(url |> String.split("/") |> List.last())
      end

      case conn.method do
        "POST" -> Req.Test.json(conn, %{"id" => 42})
        "DELETE" -> Plug.Conn.send_resp(conn, 204, "")
      end
    end)
  end

  defp calls(calls), do: Agent.get(calls, & &1)

  defp sync(flow), do: HookWorker.perform(%Oban.Job{args: %{"flow_id" => flow.id}})

  test "publishing schedules the hooks of the flow", %{user: user, workspace: workspace} do
    flow = flow_fixture(%{user: user, workspace: workspace, nodes: [push_node("acme")]})
    assert_enqueued(worker: HookWorker, args: %{"flow_id" => flow.id})
  end

  test "registers the address with the service and keeps what it answers", %{
    user: user,
    workspace: workspace,
    calls: calls
  } do
    forge(calls)
    flow = flow_fixture(%{user: user, workspace: workspace, nodes: [push_node("acme")]})

    assert :ok = sync(flow)

    hook = Hooks.get(flow.id, "push")
    assert %{type: "Forge: New Push", manual: false, error: nil} = hook
    assert {:ok, %{"id" => "42", "secret" => secret, "url" => url}} = Hooks.webhook(hook)
    assert url == Hooks.url(hook)

    assert [{"POST", "/repos/acme/hooks", body}] = calls(calls)
    assert Jason.decode!(body) == %{"url" => url, "secret" => secret}

    # Published again with nothing changed: the service hears nothing.
    assert :ok = sync(flow)
    assert length(calls(calls)) == 1
  end

  test "a changed field stops the old webhook and registers a new one, at the same address",
       %{user: user, workspace: workspace, calls: calls} do
    forge(calls)
    flow = flow_fixture(%{user: user, workspace: workspace, nodes: [push_node("acme")]})
    :ok = sync(flow)
    token = Hooks.get(flow.id, "push").token

    {:ok, flow} = HeddleCore.Flows.update_flow(flow, %{nodes: [push_node("other")]})
    {:ok, _version} = Versions.publish_draft(flow, user.id)
    assert :ok = sync(flow)

    assert [
             {"POST", "/repos/acme/hooks", _},
             {"DELETE", "/repos/acme/hooks/42", _},
             {"POST", "/repos/other/hooks", _}
           ] = calls(calls)

    assert Hooks.get(flow.id, "push").token == token
  end

  test "a node the flow no longer has is stopped", %{
    user: user,
    workspace: workspace,
    calls: calls
  } do
    forge(calls)
    flow = flow_fixture(%{user: user, workspace: workspace, nodes: [push_node("acme")]})
    :ok = sync(flow)

    {:ok, flow} = HeddleCore.Flows.update_flow(flow, %{nodes: []})
    {:ok, _version} = Versions.publish_draft(flow, user.id)
    assert :ok = sync(flow)

    assert List.last(calls(calls)) == {"DELETE", "/repos/acme/hooks/42", ""}
    assert Hooks.get(flow.id, "push") == nil
  end

  test "deleting the flow stops its hooks", %{user: user, workspace: workspace, calls: calls} do
    forge(calls)
    flow = flow_fixture(%{user: user, workspace: workspace, nodes: [push_node("acme")]})
    :ok = sync(flow)

    {:ok, _flow} = HeddleCore.Flows.delete_flow(flow)

    assert [%{args: args}] =
             all_enqueued(worker: HookWorker, args: %{"workspace_id" => workspace.id})

    assert :ok = HookWorker.perform(%Oban.Job{args: args})

    assert List.last(calls(calls)) == {"DELETE", "/repos/acme/hooks/42", ""}
  end

  test "a trigger with no register step is pasted by hand", %{user: user, workspace: workspace} do
    node = %{push_node("x", "Forge: New Payment") | "controls" => %{"credential" => "forge"}}
    flow = flow_fixture(%{user: user, workspace: workspace, nodes: [node]})

    assert :ok = sync(flow)
    assert %{manual: true, error: nil} = Hooks.get(flow.id, "push")
  end

  test "a service that refuses is recorded, and tried again", %{
    user: user,
    workspace: workspace,
    calls: calls
  } do
    Req.Test.stub(HeddleNodes.Nodes.HttpRequest, fn conn ->
      conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "no"})
    end)

    flow = flow_fixture(%{user: user, workspace: workspace, nodes: [push_node("acme")]})

    assert {:error, message} = sync(flow)
    assert message =~ "Forge: New Push"
    assert %{error: error} = Hooks.get(flow.id, "push")
    assert error =~ "403"

    forge(calls)
    assert :ok = sync(flow)
    assert %{error: nil} = Hooks.get(flow.id, "push")
  end
end
