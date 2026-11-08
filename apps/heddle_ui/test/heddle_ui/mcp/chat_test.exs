defmodule HeddleUI.MCP.ChatTest do
  # Not async: it sets the LLM client and environment for the whole VM.
  use HeddleUI.ConnCase, async: false

  import HeddleCore.AccountsFixtures

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Executions
  alias HeddleCore.Flows
  alias HeddleUI.FakeLLMAgent

  @scopes ~w(workflows:read workflows:write nodes:read executions:read executions:write)
  @variables ~w(HEDDLE_LLM_PROVIDER HEDDLE_LLM_MODEL HEDDLE_LLM_API_KEY OPENAI_API_KEY)
  @hello [%{role: "user", content: "hello"}]

  setup %{conn: conn} do
    previous = System.get_env() |> Map.take(@variables)
    Enum.each(@variables, &System.delete_env/1)
    System.put_env("OPENAI_API_KEY", "sk-test")

    Application.put_env(:heddle_ai, :llm_client, FakeLLMAgent)
    Application.put_env(:heddle_ui, :llm_agent_test_pid, self())

    on_exit(fn ->
      Enum.each(@variables, &System.delete_env/1)
      System.put_env(previous)
      Application.delete_env(:heddle_ai, :llm_client)
      Application.delete_env(:heddle_ui, :llm_agent_test_pid)
    end)

    user = system_admin_fixture()

    {:ok, flow} =
      Flows.create_flow(Scope.for_user(user), %{name: "Flow", nodes: [], connections: []})

    %{
      conn: conn,
      user: user,
      flow: flow,
      scope: Scope.for_user(user),
      token: token(user, @scopes)
    }
  end

  defp token(user, scopes) do
    {:ok, %{token: token}} =
      HeddleCore.AccountsFixtures.create_api_key(user, %{name: "chat", scopes: scopes})

    token
  end

  defp rpc(conn, token, session, method, params, id) do
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

  defp chat(conn, token, arguments) do
    response =
      rpc(
        conn,
        token,
        nil,
        "initialize",
        %{
          protocolVersion: "2025-06-18",
          capabilities: %{},
          clientInfo: %{name: "t", version: "1"}
        },
        1
      )

    [session] = get_resp_header(response, "mcp-session-id")
    rpc(conn, token, session, "notifications/initialized", %{}, nil)

    conn
    |> rpc(token, session, "tools/call", %{name: "chat", arguments: arguments}, 2)
    |> decode()
    |> Map.fetch!("result")
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

  defp sent(context) do
    inspect(context.messages, limit: :infinity, printable_limit: :infinity, structs: false)
  end

  defp payload(%{"content" => [%{"text" => text} | _]}), do: Jason.decode!(text)
  defp text(%{"content" => [%{"text" => text} | _]}), do: text

  test "answers with the server's LLM", %{conn: conn, token: token} do
    FakeLLMAgent.script(["Hi there."])

    result = chat(conn, token, %{messages: @hello})

    assert %{"reply" => "Hi there.", "run_request" => nil} = payload(result)
    assert_received {:llm_called, {:openai, "gpt-4o-mini", []}, _context, opts}
    assert opts[:api_key] == "sk-test"
  end

  test "gives the model the open flow", %{conn: conn, token: token, flow: flow} do
    FakeLLMAgent.script(["Ok."])

    chat(conn, token, %{messages: @hello, flow_id: to_string(flow.id)})

    assert_received {:llm_called, _model, context, _opts}
    assert sent(context) =~ "id #{flow.id}"
  end

  test "lets the model use the tools until it answers", context do
    %{conn: conn, token: token, flow: flow, scope: scope} = context

    node = %{
      "id" => "1",
      "type" => "Logger",
      "label" => "Log",
      "controls" => %{},
      "position" => %{"x" => 0, "y" => 0}
    }

    FakeLLMAgent.script([
      {:tool, "update_flow", %{flow_id: to_string(flow.id), nodes: [node]}},
      "Added a logger."
    ])

    result = chat(conn, token, %{messages: @hello})

    assert %{"reply" => "Added a logger."} = payload(result)
    assert [%{"id" => "1"}] = Flows.get_flow(scope, flow.id).nodes
  end

  test "shows the model what its tools returned", %{conn: conn, token: token, scope: scope} do
    {:ok, _flow} =
      Flows.create_flow(scope, %{name: "Unmistakable", nodes: [], connections: []})

    FakeLLMAgent.script([{:tool, "list_flows", %{}}, "Two flows."])

    chat(conn, token, %{messages: @hello})

    assert_received {:llm_called, _model, first, _opts}
    assert_received {:llm_called, _model, second, _opts}
    refute sent(first) =~ "Unmistakable"
    assert sent(second) =~ "Unmistakable"
  end

  test "never runs a flow on its own", %{conn: conn, token: token, flow: flow} do
    FakeLLMAgent.script([{:tool, "run_flow", %{flow_id: to_string(flow.id)}}, "Confirm?"])

    result = chat(conn, token, %{messages: @hello})

    assert %{"reply" => "Confirm?", "run_request" => request} = payload(result)
    assert request["flow_id"] == flow.id
    assert request["name"] == "Flow"
    assert Executions.list_executions_for_flow(flow) == []
  end

  test "can't ask to run someone else's flow", %{conn: conn, token: token} do
    other = user_scope_fixture()
    {:ok, theirs} = Flows.create_flow(other, %{name: "Theirs", nodes: [], connections: []})

    FakeLLMAgent.script([{:tool, "run_flow", %{flow_id: to_string(theirs.id)}}, "No."])

    assert %{"run_request" => nil} = payload(chat(conn, token, %{messages: @hello}))
  end

  test "is limited by the scopes of the key", %{conn: conn, user: user, flow: flow, scope: scope} do
    read_only = token(user, ["workflows:read"])

    FakeLLMAgent.script([
      {:tool, "update_flow", %{flow_id: to_string(flow.id), name: "Changed"}},
      "I can't."
    ])

    chat(conn, read_only, %{messages: @hello})

    assert Flows.get_flow(scope, flow.id).name == "Flow"
  end

  test "survives arguments that don't fit a tool", %{conn: conn, token: token, flow: flow} do
    FakeLLMAgent.script([
      {:tool, "get_flow", %{}},
      {:tool, "update_flow", %{flow_id: to_string(flow.id), nodes: "not a list"}},
      "Sorry."
    ])

    assert %{"reply" => "Sorry."} = payload(chat(conn, token, %{messages: @hello}))
  end

  test "gives up on a model that never stops", %{conn: conn, token: token} do
    FakeLLMAgent.script(List.duplicate({:tool, "list_flows", %{}}, 40))

    result = chat(conn, token, %{messages: @hello})

    assert result["isError"]
    assert text(result) =~ "too many steps"
  end

  test "reports a provider failure", %{conn: conn, token: token} do
    FakeLLMAgent.script([{:error, RuntimeError.exception("rate limited")}])

    result = chat(conn, token, %{messages: @hello})

    assert result["isError"]
    assert text(result) =~ "rate limited"
  end

  test "says when the server has no LLM", %{conn: conn, token: token} do
    System.delete_env("OPENAI_API_KEY")

    result = chat(conn, token, %{messages: @hello})

    assert result["isError"]
    assert text(result) =~ "No LLM"
  end

  test "isn't open to the Claude Agent", %{conn: conn, user: user} do
    {:ok, %{token: token}} = HeddleCore.AccountsFixtures.create_agent_key(user)

    assert chat(conn, token, %{messages: @hello})["isError"]
  end

  test "needs read access", %{conn: conn, user: user} do
    assert chat(conn, token(user, ["nodes:read"]), %{messages: @hello})["isError"]
  end
end
