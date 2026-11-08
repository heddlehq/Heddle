defmodule HeddleUI.PublicAPI.V1.AgentControllerTest do
  # Not async: the session and its tasks share the connection of the test.
  use HeddleUI.ConnCase, async: false

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Accounts.Scope
  alias HeddleUI.Agent
  alias HeddleUI.FakeHarnessModel
  alias HeddleUI.PublicAPI.V1.AgentEvents

  setup %{conn: conn} do
    Application.put_env(:heddle_ai, :harness_model, FakeHarnessModel)
    on_exit(fn -> Application.delete_env(:heddle_ai, :harness_model) end)

    user = user_fixture()
    flow = flow_fixture(%{user: user})
    scope = Scope.for_user(user)
    :ok = Agent.subscribe(scope, flow.id)

    on_exit(fn ->
      HeddleUI.AgentHelpers.stop_all()
    end)

    %{conn: authorize(conn, user), user: user, flow: flow, scope: scope}
  end

  defp authorize(conn, user, scopes \\ ~w(workflows:read workflows:write)) do
    {:ok, %{token: token}} =
      HeddleCore.AccountsFixtures.create_api_key(user, %{name: "test", scopes: scopes})

    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp idle, do: assert_receive({:agent_event, %{type: "status", status: "idle"}}, 2000)

  test "sends a message and shows the conversation", %{conn: conn, flow: flow} do
    FakeHarnessModel.script(["Hello."])

    assert conn
           |> post(~p"/api/v1/workflows/#{flow.id}/agent/messages", %{content: "hi"})
           |> response(202)

    idle()

    assert %{
             "data" => %{
               "status" => "idle",
               "items" => [
                 %{"role" => "user", "text" => "hi"},
                 %{"role" => "assistant", "text" => "Hello."}
               ]
             }
           } = conn |> get(~p"/api/v1/workflows/#{flow.id}/agent") |> json_response(200)
  end

  test "refuses a message while the agent works", %{conn: conn, flow: flow} do
    FakeHarnessModel.script([:hang])

    post(conn, ~p"/api/v1/workflows/#{flow.id}/agent/messages", %{content: "go"})

    assert conn
           |> post(~p"/api/v1/workflows/#{flow.id}/agent/messages", %{content: "more"})
           |> json_response(409)

    HeddleUI.AgentHelpers.wait_for_script()
  end

  test "stops the agent", %{conn: conn, flow: flow} do
    FakeHarnessModel.script([:hang])

    post(conn, ~p"/api/v1/workflows/#{flow.id}/agent/messages", %{content: "go"})
    HeddleUI.AgentHelpers.wait_for_script()

    assert conn |> post(~p"/api/v1/workflows/#{flow.id}/agent/stop") |> response(204)
    idle()
  end

  test "says when there is nothing to decide", %{conn: conn, flow: flow} do
    FakeHarnessModel.script(["Ok."])
    post(conn, ~p"/api/v1/workflows/#{flow.id}/agent/messages", %{content: "go"})
    idle()

    assert conn
           |> post(~p"/api/v1/workflows/#{flow.id}/agent/decision", %{decision: "once"})
           |> json_response(409)
  end

  test "doesn't reach the flow of someone else", %{conn: conn} do
    other = flow_fixture(%{user: user_fixture()})

    assert conn |> get(~p"/api/v1/workflows/#{other.id}/agent") |> json_response(404)
  end

  test "needs write access to talk to the agent", %{flow: flow, user: user} do
    conn = authorize(build_conn(), user, ["workflows:read"])

    assert conn
           |> post(~p"/api/v1/workflows/#{flow.id}/agent/messages", %{content: "go"})
           |> json_response(403)
  end

  describe "events" do
    test "are written as server-sent events" do
      assert "event: text_delta\ndata: " <> rest =
               AgentEvents.event(%{type: "text_delta", text: "hi"})

      assert String.ends_with?(rest, "\n\n")
      assert %{"type" => "text_delta", "text" => "hi"} = Jason.decode!(rest)
    end

    test "start with the whole conversation" do
      assert "event: snapshot\ndata: " <> _rest = AgentEvents.snapshot(%{items: []})
    end
  end

  test "joining doesn't count twice what is already in the transcript", %{
    scope: scope,
    flow: flow
  } do
    FakeHarnessModel.script(["Ok."])
    :ok = Agent.send_message(scope, flow.id, "go")
    idle()

    assert %{items: [_user, _reply]} = Agent.join(scope, flow.id)
    refute_received {:agent_event, _event}
  end
end
