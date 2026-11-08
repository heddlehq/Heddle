defmodule HeddleUI.TerminalChannelTest do
  # Not async: it sets what the terminal runs for the whole VM.
  use HeddleCore.DataCase, async: false

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures
  import Phoenix.ChannelTest

  alias HeddleCore.Settings
  alias HeddleUI.Terminal
  alias HeddleUI.TerminalSocket

  @endpoint HeddleUI.Endpoint

  setup do
    Application.put_env(:heddle_ui, :terminal, true)
    Application.put_env(:heddle_ui, :terminal_command, ["/bin/sh"])
    {:ok, _setting} = Settings.set_terminal_enabled(true)

    on_exit(fn ->
      Application.delete_env(:heddle_ui, :terminal)
      Application.delete_env(:heddle_ui, :terminal_command)
      HeddleUI.AgentHelpers.stop_all()
    end)

    admin = system_admin_fixture()
    %{admin: admin, flow: flow_fixture(%{user: admin})}
  end

  defp connect_as(user) do
    connect(TerminalSocket, %{"token" => Terminal.token(user)})
  end

  defp join_terminal(socket, flow) do
    subscribe_and_join(socket, "terminal:#{flow.id}", %{"cols" => 80, "rows" => 24})
  end

  defp await_screen(text, seen \\ "") do
    if String.contains?(seen, text) do
      seen
    else
      assert_push "output", {:binary, data}, 3000
      await_screen(text, seen <> data)
    end
  end

  test "carries keys and the screen, as binary", %{admin: admin, flow: flow} do
    {:ok, socket} = connect_as(admin)
    {:ok, _reply, socket} = join_terminal(socket, flow)

    push(socket, "input", %{"data" => "echo heddle-$((40 + 2))\n"})

    assert await_screen("heddle-42")
  end

  test "resizes", %{admin: admin, flow: flow} do
    {:ok, socket} = connect_as(admin)
    {:ok, _reply, socket} = join_terminal(socket, flow)

    push(socket, "resize", %{"cols" => 120, "rows" => 40})
    push(socket, "input", %{"data" => "stty size\n"})

    assert await_screen("40 120")
  end

  test "says when the program ends", %{admin: admin, flow: flow} do
    {:ok, socket} = connect_as(admin)
    {:ok, _reply, socket} = join_terminal(socket, flow)

    push(socket, "input", %{"data" => "exit\n"})

    assert_push "exited", %{}, 3000
  end

  describe "refuses" do
    test "a token that isn't one" do
      assert :error = connect(TerminalSocket, %{"token" => "forged"})
    end

    test "no token at all" do
      assert :error = connect(TerminalSocket, %{})
    end

    test "someone who isn't an administrator" do
      assert :error = connect_as(user_fixture())
    end

    test "anyone while it is turned off", %{admin: admin} do
      {:ok, _setting} = Settings.set_terminal_enabled(false)

      assert :error = connect_as(admin)
    end

    test "anyone when this isn't a local install", %{admin: admin} do
      Application.put_env(:heddle_ui, :terminal, false)

      assert :error = connect_as(admin)
    end

    test "a flow that doesn't exist", %{admin: admin, flow: flow} do
      {:ok, socket} = connect_as(admin)

      assert {:error, %{reason: "unavailable"}} = join_terminal(socket, %{flow | id: -1})
    end

    test "someone who isn't a system admin, even an editor of the flow", %{flow: flow} do
      editor = user_fixture()
      member_fixture(HeddleCore.Workspaces.get_workspace(flow.workspace_id), editor, "editor")

      assert :error = connect_as(editor)
    end
  end
end
