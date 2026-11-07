defmodule HeddleUI.FlowLive.EditorAgentTest do
  # Not async: it sets the agent client and environment for the whole VM.
  use HeddleUI.ConnCase, async: false

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.ApiKeys
  alias HeddleCore.Flows
  alias HeddleCore.Settings
  alias HeddleUI.Agent

  @variables ~w(
    HEDDLE_CLAUDE_BIN HEDDLE_CLAUDE_API_KEY OPENAI_API_KEY
    HEDDLE_LLM_PROVIDER HEDDLE_LLM_MODEL HEDDLE_LLM_API_KEY
  )
  @node %{
    "id" => "1",
    "type" => "Logger",
    "label" => "Log",
    "controls" => %{},
    "position" => %{"x" => 0, "y" => 0}
  }

  setup %{conn: conn} do
    previous = System.get_env() |> Map.take(@variables)
    Enum.each(@variables, &System.delete_env/1)
    System.put_env(%{"HEDDLE_CLAUDE_BIN" => "/bin/true", "HEDDLE_CLAUDE_API_KEY" => "sk-ant"})

    Application.put_env(:heddle_ui, :claude_agent, HeddleUI.FakeClaudeAgent)
    Application.put_env(:heddle_ui, :claude_agent_test_pid, self())

    on_exit(fn ->
      HeddleUI.AgentHelpers.stop_all()
      Enum.each(@variables, &System.delete_env/1)
      System.put_env(previous)
      Application.delete_env(:heddle_ui, :claude_agent)
      Application.delete_env(:heddle_ui, :claude_agent_test_pid)
    end)

    {:ok, _setting} = Settings.set_claude_agent_enabled(true)

    admin = system_admin_fixture()
    Process.put(:heddle_owner, admin)
    flow = flow_fixture()
    scope = HeddleCore.Accounts.Scope.for_user(admin)
    :ok = Agent.subscribe(scope, flow.id)

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/flows/#{flow.id}")

    %{view: view, flow: flow, admin: admin}
  end

  defp say(view, content), do: render_hook(view, "send_message", %{"content" => content})

  defp finished(view) do
    assert_receive {:agent_event, %{type: "status", status: "idle"}}, 2000
    _ = :sys.get_state(view.pid)
    render(view)
  end

  describe "chat button" do
    test "shows when the agent is on", %{view: view} do
      assert has_element?(view, "#chat-open-button")
    end

    test "shows with only an LLM", %{conn: conn, admin: admin, flow: flow} do
      {:ok, _setting} = Settings.set_claude_agent_enabled(false)
      System.put_env("OPENAI_API_KEY", "sk-test")

      {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/flows/#{flow.id}")

      assert has_element?(view, "#chat-open-button")
    end

    test "is hidden with nothing configured", %{conn: conn, admin: admin, flow: flow} do
      {:ok, _setting} = Settings.set_claude_agent_enabled(false)

      {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/flows/#{flow.id}")

      refute has_element?(view, "#chat-open-button")
    end
  end

  describe "sending a message" do
    test "goes to the agent, even with no LLM configured", %{view: view} do
      say(view, "add a logger")

      assert_receive {:agent_called, "add a logger" <> _state, opts}
      assert opts[:system] =~ "agent of Heddle"
      assert finished(view) =~ "On it."
    end

    test "gives the agent a key that is removed afterwards", %{view: view} do
      say(view, "hi")

      assert_receive {:agent_called, "hi" <> _state, opts}
      assert {:ok, api_key} = ApiKeys.authenticate(opts[:token])
      assert ApiKeys.agent_key?(api_key)

      opts[:on_finish].()

      assert ApiKeys.authenticate(opts[:token]) == :error
    end

    test "continues the same conversation", %{view: view} do
      say(view, "first")
      assert_receive {:agent_called, "first" <> _state, first}
      refute first[:resume?]
      finished(view)

      say(view, "second")
      assert_receive {:agent_called, "second" <> _state, second}

      assert second[:resume?]
      assert second[:session_id] == first[:session_id]
    end

    test "falls back to the LLM when turned off", %{view: view} do
      {:ok, _setting} = Settings.set_claude_agent_enabled(false)
      System.put_env("OPENAI_API_KEY", "sk-test")
      Application.put_env(:heddle_ai, :harness_model, HeddleUI.FakeHarnessModel)
      on_exit(fn -> Application.delete_env(:heddle_ai, :harness_model) end)
      HeddleUI.FakeHarnessModel.script(["From the LLM."])

      say(view, "hi")

      assert finished(view) =~ "From the LLM."
      refute_received {:agent_called, _content, _opts}
    end
  end

  describe "unsaved changes" do
    test "are saved before the agent reads the flow", %{view: view, flow: flow} do
      render_hook(view, "graph_changed", %{})

      say(view, "hi")

      assert_push_event(view, "request_graph_data", %{})
      refute_received {:agent_called, _content, _opts}

      render_hook(view, "save_graph_data", %{"data" => %{"nodes" => [@node], "connections" => []}})

      assert_receive {:agent_called, "hi" <> _state, _opts}
      assert [%{"id" => "1"}] = Flows.get_flow!(flow.id).nodes
    end

    test "that can't be saved stop the message", %{view: view} do
      render_hook(view, "graph_changed", %{})
      say(view, "hi")

      bad = %{"id" => "1", "type" => "No Such Node"}
      render_hook(view, "save_graph_data", %{"data" => %{"nodes" => [bad], "connections" => []}})

      refute_received {:agent_called, _content, _opts}
      refute has_element?(view, "#chat-input-field[disabled]")
    end
  end

  describe "the work of the agent" do
    setup %{view: view} do
      {:ok, _setting} = Settings.set_claude_agent_enabled(false)
      System.put_env("OPENAI_API_KEY", "sk-test")
      Application.put_env(:heddle_ai, :harness_model, HeddleUI.FakeHarnessModel)
      on_exit(fn -> Application.delete_env(:heddle_ai, :harness_model) end)

      render_hook(view, "toggle_chat", %{})
      :ok
    end

    test "shows each tool it calls, and what came out", %{view: view, flow: flow} do
      HeddleUI.FakeHarnessModel.script([
        {:tool, "get_flow", %{flow_id: to_string(flow.id)}},
        "Ok."
      ])

      say(view, "what is wrong?")
      finished(view)

      assert has_element?(view, ~s([id^="agent-tool-"][data-status="ok"]), "Reading the flow")
    end

    test "asks before running, and sends the answer", %{view: view, flow: flow} do
      HeddleUI.FakeHarnessModel.script([
        {:tool, "test_flow", %{flow_id: to_string(flow.id)}},
        "Ok."
      ])

      say(view, "test it")

      assert_receive {:agent_event, %{type: "permission", permission: %{flow_name: _name}}}, 2000
      _ = :sys.get_state(view.pid)
      assert has_element?(view, "#agent-run-confirmation")

      view |> element("#agent-run-deny") |> render_click()
      finished(view)

      refute has_element?(view, "#agent-run-confirmation")
      assert has_element?(view, ~s([id^="agent-tool-"][data-status="error"]), "Testing the flow")
    end

    test "can be stopped", %{view: view} do
      HeddleUI.FakeHarnessModel.script([:hang])

      say(view, "go")
      assert_receive {:agent_event, %{type: "status", status: "running"}}, 2000
      _ = :sys.get_state(view.pid)
      HeddleUI.AgentHelpers.wait_for_script()

      view |> element("#agent-stop") |> render_click()

      finished(view)
      refute has_element?(view, "#agent-stop")
    end

    test "starts a new chat on reload, and keeps the old one in the history",
         %{conn: conn, admin: admin, flow: flow, view: view} do
      HeddleUI.FakeHarnessModel.script(["Still here."])

      say(view, "hi")
      finished(view)

      {:ok, reloaded, _html} = conn |> log_in_user(admin) |> live(~p"/flows/#{flow.id}")

      refute render(reloaded) =~ "Still here."

      reloaded |> element("#agent-history-toggle") |> render_click()
      reloaded |> element(~s([id^="agent-conversation-"])) |> render_click()

      assert_receive {:agent_event, %{type: "reset", items: [_user, _reply]}}, 2000
      _ = :sys.get_state(reloaded.pid)

      assert render(reloaded) =~ "Still here."
    end

    test "a reload in the middle of the work shows the work",
         %{conn: conn, admin: admin, flow: flow, view: view} do
      HeddleUI.FakeHarnessModel.script([:hang])

      say(view, "go")
      HeddleUI.AgentHelpers.wait_for_script()

      {:ok, reloaded, _html} = conn |> log_in_user(admin) |> live(~p"/flows/#{flow.id}")

      assert has_element?(reloaded, "#agent-stop")
      assert render(reloaded) =~ "go"
    end

    test "says when there is nothing in the history", %{view: view} do
      view |> element("#agent-history-toggle") |> render_click()

      assert has_element?(view, "#agent-history")
      refute has_element?(view, ~s([id^="agent-conversation-"]))
    end

    test "starts over with the button", %{view: view} do
      HeddleUI.FakeHarnessModel.script(["Bye."])

      say(view, "hi")
      finished(view)

      view |> element("#agent-new-chat") |> render_click()
      assert_receive {:agent_event, %{type: "reset", items: []}}, 2000
      _ = :sys.get_state(view.pid)

      refute render(view) =~ "Bye."
    end
  end

  describe "a flow changed elsewhere" do
    test "reloads the canvas", %{view: view, flow: flow} do
      {:ok, _flow} = Flows.update_flow(flow, %{nodes: [@node]})

      assert_push_event(view, "load_graph_data", %{nodes: [%{"id" => "1"}]})
    end

    test "doesn't reload for the editor's own save", %{view: view} do
      data = %{"nodes" => [@node], "connections" => []}
      render_hook(view, "save_graph_data", %{"data" => data})

      _ = :sys.get_state(view.pid)

      refute_push_event(view, "load_graph_data", %{nodes: [%{"id" => "1"}]})
    end
  end
end
