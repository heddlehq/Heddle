defmodule HeddleUI.TerminalTest do
  # Not async: it sets what the terminal runs for the whole VM.
  use HeddleUI.ConnCase, async: false

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.ApiKeys
  alias HeddleUI.Terminal

  setup do
    Application.put_env(:heddle_ui, :terminal, true)
    Application.put_env(:heddle_ui, :terminal_command, ["/bin/sh"])
    {:ok, _setting} = HeddleCore.Settings.set_terminal_enabled(true)

    on_exit(fn ->
      Application.delete_env(:heddle_ui, :terminal)
      Application.delete_env(:heddle_ui, :terminal_command)
      HeddleUI.AgentHelpers.stop_all()
    end)

    user = user_fixture()
    %{scope: Scope.for_user(user), flow: flow_fixture(%{user: user})}
  end

  defp await_output(text, seen \\ "") do
    if String.contains?(seen, text) do
      seen
    else
      receive do
        {:terminal_output, data} -> await_output(text, seen <> data)
      after
        3000 -> flunk("Never printed #{text}. It printed: #{inspect(seen)}")
      end
    end
  end

  test "is off unless this is a local install" do
    Application.put_env(:heddle_ui, :terminal, false)

    refute Terminal.supported?()
    refute Terminal.available?()
  end

  test "is off until someone turns it on" do
    {:ok, _setting} = HeddleCore.Settings.set_terminal_enabled(false)

    assert Terminal.supported?()
    refute Terminal.available?()
  end

  test "is off when the program isn't there" do
    Application.put_env(:heddle_ui, :terminal_command, nil)
    path = System.get_env("PATH")
    System.put_env("PATH", "/nonexistent")
    on_exit(fn -> System.put_env("PATH", path) end)

    refute Terminal.supported?()
  end

  test "runs the program chosen in the AI page" do
    Application.put_env(:heddle_ui, :terminal_command, nil)
    Application.put_env(:heddle_ai, :claude_binary, fn -> "/bin/sh" end)
    on_exit(fn -> Application.put_env(:heddle_ai, :claude_binary, nil) end)

    assert Terminal.command() == ["/bin/sh"]
  end

  test "carries keys to the program and its screen back", %{scope: scope, flow: flow} do
    {:ok, terminal} = Terminal.open(scope, flow, {80, 24})

    Terminal.input(terminal, "echo heddle-$((40 + 2))\n")

    assert await_output("heddle-42")
  end

  test "is a real terminal, with the size the page gave it", %{scope: scope, flow: flow} do
    {:ok, terminal} = Terminal.open(scope, flow, {101, 33})

    Terminal.input(terminal, "stty size\n")

    assert await_output("33 101")
  end

  test "follows a change of size", %{scope: scope, flow: flow} do
    {:ok, terminal} = Terminal.open(scope, flow, {80, 24})

    Terminal.resize(terminal, 120, 40)
    _ = :sys.get_state(terminal)
    Terminal.input(terminal, "stty size\n")

    assert await_output("40 120")
  end

  test "keeps the secrets of this install from the program", %{scope: scope, flow: flow} do
    System.put_env("ANTHROPIC_API_KEY", "sk-secret")
    on_exit(fn -> System.delete_env("ANTHROPIC_API_KEY") end)

    {:ok, terminal} = Terminal.open(scope, flow, {80, 24})

    Terminal.input(terminal, ~s(echo "key=[$ANTHROPIC_API_KEY] mcp=${#HEDDLE_MCP_TOKEN}"\n))

    output = await_output("mcp=")
    output = if output =~ ~r/mcp=\d/, do: output, else: await_output("key=[]", output)

    assert output =~ "key=[]"
    refute output =~ "sk-secret"
  end

  test "says when the program ends, and takes its key away", %{scope: scope, flow: flow} do
    {:ok, terminal} = Terminal.open(scope, flow, {80, 24})
    ref = Process.monitor(terminal)

    Terminal.input(terminal, "exit\n")

    assert_receive :terminal_exited, 3000
    assert_receive {:DOWN, ^ref, :process, ^terminal, :normal}, 3000
    assert ApiKeys.list_api_keys() |> Enum.filter(&ApiKeys.agent_key?/1) == []
  end

  test "ends with whoever opened it", %{scope: scope, flow: flow} do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, terminal} = Terminal.open(scope, flow, {80, 24})
        send(parent, {:opened, terminal})
        Process.sleep(:infinity)
      end)

    assert_receive {:opened, terminal}, 3000
    ref = Process.monitor(terminal)

    Process.exit(owner, :kill)

    assert_receive {:DOWN, ^ref, :process, ^terminal, :normal}, 4000
  end

  describe "in the editor" do
    import Phoenix.LiveViewTest

    setup %{conn: conn} do
      admin = system_admin_fixture()
      Process.put(:heddle_owner, admin)
      flow = flow_fixture()
      {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/flows/#{flow.id}")

      %{view: view, flow: flow, conn: conn, admin: admin}
    end

    test "shows the panel when the button is pressed", %{view: view} do
      view |> element("#terminal-open-button") |> render_click()

      refute has_element?(view, "#terminal-panel.hidden")
    end

    test "offers to start again when the program ends", %{view: view} do
      render_hook(view, "terminal_exited", %{})

      view |> element("#terminal-restart") |> render_click()

      assert_push_event(view, "terminal_restart", %{})
      refute has_element?(view, "#terminal-restart")
    end

    test "isn't there until it is turned on in the AI page",
         %{conn: conn, admin: admin, flow: flow} do
      {:ok, _setting} = HeddleCore.Settings.set_terminal_enabled(false)

      {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/flows/#{flow.id}")

      refute has_element?(view, "#terminal-open-button")
      refute has_element?(view, "#terminal-panel")
    end
  end
end
