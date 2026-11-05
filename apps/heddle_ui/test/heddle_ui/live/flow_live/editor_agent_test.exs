defmodule HeddleUI.FlowLive.EditorAgentTest do
  # Not async: it sets the agent client and environment for the whole VM.
  use HeddleUI.ConnCase, async: false

  import Phoenix.LiveViewTest
  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.ApiKeys
  alias HeddleCore.Flows
  alias HeddleCore.Settings

  @variables ~w(HEDDLE_CLAUDE_BIN HEDDLE_CLAUDE_API_KEY OPENAI_API_KEY)
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
      Enum.each(@variables, &System.delete_env/1)
      System.put_env(previous)
      Application.delete_env(:heddle_ui, :claude_agent)
      Application.delete_env(:heddle_ui, :claude_agent_test_pid)
    end)

    {:ok, _setting} = Settings.set_claude_agent_enabled(true)

    admin = system_admin_fixture()
    Process.put(:heddle_owner, admin)
    flow = flow_fixture()

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/flows/#{flow.id}")

    %{view: view, flow: flow, admin: admin}
  end

  defp say(view, content), do: render_hook(view, "send_message", %{"content" => content})

  describe "sending a message" do
    test "goes to the agent, even with no LLM configured", %{view: view} do
      say(view, "add a logger")

      assert_receive {:agent_called, "add a logger", opts}
      assert opts[:system] =~ "copilot"
      assert render_async(view) =~ "On it."
    end

    test "gives the agent a key that is removed afterwards", %{view: view} do
      say(view, "hi")

      assert_receive {:agent_called, "hi", opts}
      assert {:ok, api_key} = ApiKeys.authenticate(opts[:token])
      assert ApiKeys.agent_key?(api_key)

      opts[:on_finish].()

      assert ApiKeys.authenticate(opts[:token]) == :error
    end

    test "continues the same conversation", %{view: view} do
      say(view, "first")
      assert_receive {:agent_called, "first", first}
      refute first[:resume?]
      render_async(view)

      say(view, "second")
      assert_receive {:agent_called, "second", second}

      assert second[:resume?]
      assert second[:session_id] == first[:session_id]
    end

    test "falls back to the LLM when turned off", %{view: view} do
      {:ok, _setting} = Settings.set_claude_agent_enabled(false)
      System.put_env("OPENAI_API_KEY", "sk-test")
      Application.put_env(:heddle_ai, :llm_client, HeddleUI.FakeLLMClient)
      on_exit(fn -> Application.delete_env(:heddle_ai, :llm_client) end)

      say(view, "hi")
      render_async(view)

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

      assert_receive {:agent_called, "hi", _opts}
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

  describe "confirming a run" do
    defp ask(view) do
      test = self()
      ref = make_ref()

      send(view.pid, {:agent_run_confirmation, %{ref: ref, reply_to: test, flow_name: "Flow"}})
      ref
    end

    setup %{view: view} do
      render_hook(view, "toggle_chat", %{})
      :ok
    end

    test "shows the question and sends the answer", %{view: view} do
      ref = ask(view)

      assert has_element?(view, "#agent-run-confirmation")

      view |> element("#agent-run-approve") |> render_click()

      assert_receive {:agent_run_decision, ^ref, true}
      refute has_element?(view, "#agent-run-confirmation")
    end

    test "can be refused", %{view: view} do
      ref = ask(view)

      view |> element("#agent-run-deny") |> render_click()

      assert_receive {:agent_run_decision, ^ref, false}
    end

    test "ignores an answer nobody asked for", %{view: view} do
      render_hook(view, "agent_run_decision", %{"decision" => "approve"})

      refute_received {:agent_run_decision, _ref, _approved}
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
