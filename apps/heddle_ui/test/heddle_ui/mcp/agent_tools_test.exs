defmodule HeddleUI.MCP.AgentToolsTest do
  # The node registry is global: one test at a time.
  use HeddleUI.ConnCase, async: false

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  @all_scopes ~w(workflows:read workflows:write nodes:read executions:read executions:write)

  setup %{conn: conn} do
    on_exit(HeddleUI.FakeChatNode.register())
    user = system_admin_fixture()

    flow =
      flow_fixture(
        user: user,
        nodes: [
          %{
            "id" => "talk",
            "type" => "Test: Talk",
            "label" => "Talk",
            "controls" => %{"name" => "Ana"}
          }
        ]
      )

    %{conn: conn, user: user, flow: flow}
  end

  defp token(user, scopes \\ @all_scopes) do
    {:ok, %{token: token}} =
      HeddleCore.AccountsFixtures.create_api_key(user, %{name: "mcp", scopes: scopes})

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

  test "list_agents names the published triggers people talk to", %{
    conn: conn,
    user: user,
    flow: flow
  } do
    result = call(conn, token(user), "list_agents")

    assert %{"agents" => [%{"name" => "Ana", "flow_id" => flow_id, "node_id" => "talk"}]} =
             payload(result)

    assert flow_id == flow.id
  end

  test "read_agent shows its panel", %{conn: conn, user: user} do
    result = call(conn, token(user), "read_agent", %{name: "ana"})
    assert %{"name" => "Ana", "panel" => [%{"title" => "Instances"}]} = payload(result)

    assert call(conn, token(user), "read_agent", %{name: "Bia"})["isError"]
  end

  test "message_agent talks to it and waits for its reply", %{conn: conn, user: user} do
    result = call(conn, token(user), "message_agent", %{name: "Ana", message: "oi"})
    assert %{"reply" => "You said: oi", "answered" => true} = payload(result)

    refused = call(conn, token(user), "message_agent", %{name: "Ana", message: "fail"})
    assert refused["isError"]
    assert text(refused) =~ "It can't now."
  end

  test "message_agent needs executions:write", %{conn: conn, user: user} do
    result =
      call(conn, token(user, ~w(workflows:read)), "message_agent", %{name: "Ana", message: "oi"})

    assert text(result) =~ "executions:write"
  end
end
