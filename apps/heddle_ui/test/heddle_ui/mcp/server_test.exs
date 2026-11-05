defmodule HeddleUI.MCP.ServerTest do
  use HeddleUI.ConnCase, async: false

  import HeddleCore.AccountsFixtures

  alias HeddleCore.ApiKeys
  alias HeddleCore.Executions
  alias HeddleCore.Flows
  alias HeddleCore.Accounts.Scope

  @all_scopes ~w(workflows:read workflows:write nodes:read executions:read executions:write)

  setup %{conn: conn} do
    user = system_admin_fixture()
    %{conn: conn, user: user, scope: Scope.for_user(user)}
  end

  defp token(user, scopes \\ @all_scopes) do
    {:ok, %{token: token}} = ApiKeys.create_api_key(user, %{name: "mcp", scopes: scopes})
    token
  end

  defp rpc(conn, token, session, method, params, id \\ 1) do
    conn =
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    conn = if session, do: put_req_header(conn, "mcp-session-id", session), else: conn

    body = %{jsonrpc: "2.0", method: method, params: params}
    body = if id, do: Map.put(body, :id, id), else: body

    post(conn, "/mcp", Jason.encode!(body))
  end

  defp open_session(conn, token) do
    response =
      rpc(conn, token, nil, "initialize", %{
        protocolVersion: "2025-06-18",
        capabilities: %{},
        clientInfo: %{name: "test", version: "1"}
      })

    [session] = get_resp_header(response, "mcp-session-id")
    rpc(conn, token, session, "notifications/initialized", %{}, nil)
    session
  end

  defp call(conn, token, tool, arguments \\ %{}) do
    session = open_session(conn, token)
    response = rpc(conn, token, session, "tools/call", %{name: tool, arguments: arguments}, 2)
    decode(response)["result"]
  end

  defp decode(response) do
    case Jason.decode(response.resp_body) do
      {:ok, body} ->
        body

      _sse ->
        response.resp_body
        |> String.split("\n")
        |> Enum.find_value(fn
          "data: " <> json when json != "" -> Jason.decode!(json)
          _line -> nil
        end)
    end
  end

  defp payload(%{"content" => [%{"text" => text} | _]}), do: Jason.decode!(text)
  defp text(%{"content" => [%{"text" => text} | _]}), do: text

  describe "authentication" do
    test "rejects a request without an API key", %{conn: conn} do
      conn = conn |> put_req_header("content-type", "application/json") |> post("/mcp", "{}")

      assert conn.status == 401
    end
  end

  describe "tools/list" do
    test "exposes the flow tools and no way to delete", %{conn: conn, user: user} do
      token = token(user)
      session = open_session(conn, token)

      names =
        conn
        |> rpc(token, session, "tools/list", %{}, 2)
        |> decode()
        |> get_in(["result", "tools"])
        |> Enum.map(& &1["name"])

      assert "update_flow" in names
      assert "run_flow" in names
      refute Enum.any?(names, &(&1 =~ "delete"))
    end
  end

  describe "reading" do
    test "lists only the caller's flows", %{conn: conn, user: user, scope: scope} do
      {:ok, flow} = Flows.create_flow(scope, %{name: "Mine", nodes: [], connections: []})

      other = Scope.for_user(system_admin_fixture())
      {:ok, _other} = Flows.create_flow(other, %{name: "Theirs", nodes: [], connections: []})

      result = call(conn, token(user), "list_flows")

      assert [%{"id" => id, "name" => "Mine"}] = payload(result)["flows"]
      assert id == flow.id
    end

    test "doesn't reveal another user's flow", %{conn: conn, user: user} do
      other = Scope.for_user(system_admin_fixture())
      {:ok, flow} = Flows.create_flow(other, %{name: "Theirs", nodes: [], connections: []})

      result = call(conn, token(user), "get_flow", %{flow_id: to_string(flow.id)})

      assert result["isError"]
      assert text(result) =~ "not found"
    end

    test "describes the available nodes", %{conn: conn, user: user} do
      assert text(call(conn, token(user), "list_nodes")) =~ "Logger"
    end
  end

  describe "scopes" do
    test "are enforced per tool", %{conn: conn, user: user} do
      result = call(conn, token(user, ["workflows:read"]), "list_nodes")

      assert result["isError"]
      assert text(result) =~ "nodes:read"
    end
  end

  describe "writing" do
    @logger %{
      "id" => "1",
      "type" => "Logger",
      "label" => "Log",
      "controls" => %{},
      "position" => %{"x" => 0, "y" => 0}
    }

    test "creates a flow owned by the caller", %{conn: conn, user: user, scope: scope} do
      result = call(conn, token(user), "create_flow", %{name: "Agent", nodes: [@logger]})

      assert %{"id" => id, "name" => "Agent"} = payload(result)
      assert Flows.get_flow(scope, id)
    end

    test "returns the validator's message", %{conn: conn, user: user} do
      node = %{"id" => "1", "type" => "No Such Node"}

      result = call(conn, token(user), "create_flow", %{name: "Bad", nodes: [node]})

      assert result["isError"]
      assert text(result) =~ "nodes:"
    end

    test "keeps node positions on update", %{conn: conn, user: user, scope: scope} do
      {:ok, flow} = Flows.create_flow(scope, %{name: "Flow", nodes: [], connections: []})
      node = Map.put(@logger, "position", %{"x" => 777, "y" => 55})

      result =
        call(conn, token(user), "update_flow", %{flow_id: to_string(flow.id), nodes: [node]})

      assert %{"nodes" => [%{"position" => %{"x" => 777, "y" => 55}}]} = payload(result)
    end

    test "only changes what was sent", %{conn: conn, user: user, scope: scope} do
      {:ok, flow} = Flows.create_flow(scope, %{name: "Flow", nodes: [@logger], connections: []})

      call(conn, token(user), "update_flow", %{flow_id: to_string(flow.id), name: "Renamed"})

      assert %{name: "Renamed", nodes: [_node]} = Flows.get_flow(scope, flow.id)
    end
  end

  describe "run_flow" do
    test "queues an execution", %{conn: conn, user: user, scope: scope} do
      {:ok, flow} = Flows.create_flow(scope, %{name: "Flow", nodes: [], connections: []})

      result = call(conn, token(user), "run_flow", %{flow_id: to_string(flow.id)})

      assert %{"id" => public_id} = payload(result)
      assert Executions.get_execution_by_flow_and_public_id(flow.id, public_id)
    end

    test "needs the executions:write scope", %{conn: conn, user: user, scope: scope} do
      {:ok, flow} = Flows.create_flow(scope, %{name: "Flow", nodes: [], connections: []})

      result =
        call(conn, token(user, ["workflows:read"]), "run_flow", %{flow_id: to_string(flow.id)})

      assert result["isError"]
      assert Executions.list_executions_for_flow(flow) == []
    end
  end
end
