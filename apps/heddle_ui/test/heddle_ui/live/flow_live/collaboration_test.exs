defmodule HeddleUI.FlowLive.CollaborationTest do
  # Not async: the session of a flow is shared by everyone who edits it.
  use HeddleUI.ConnCase, async: false

  import Phoenix.LiveViewTest
  import HeddleCore.FlowsFixtures
  import HeddleCore.AccountsFixtures

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Flows

  @code %{
    "id" => "1",
    "type" => "Start",
    "label" => "Start",
    "controls" => %{"message" => "hello", "code_elixir" => "1 + 1", "code_python" => ""},
    "position" => %{"x" => 0, "y" => 0}
  }

  setup %{conn: conn} do
    admin = system_admin_fixture()
    Process.put(:heddle_owner, admin)
    flow = flow_fixture(%{nodes: [@code]})

    other = user_fixture()
    member_fixture(HeddleCore.Workspaces.get_workspace(flow.workspace_id), other, "editor")
    other = Scope.for_user(HeddleCore.Repo.reload!(other))

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/flows/#{flow.id}")
    %{lv: lv, flow: flow, other: other}
  end

  defp open_drawer(lv) do
    render_hook(lv, "open_node_config", %{
      "nodeId" => "1",
      "nodeData" => %{
        "id" => "1",
        "type" => "Start",
        "label" => "Start",
        "controls" => %{
          "message" => %{"value" => "hello", "type" => "text", "label" => "Message"}
        },
        "settings" => %{}
      }
    })
  end

  defp change_elsewhere(other, flow, node) do
    {:ok, _flow} = Flows.update_flow(other, flow, %{nodes: [node]})
  end

  describe "the drawer of a node" do
    test "sends each field to the canvas as it changes", %{lv: lv} do
      open_drawer(lv)

      render_change(lv, "node_config_changed", %{"message" => "hi there", "node_label" => "Begin"})

      assert_push_event(lv, "update_node_data", %{nodeId: "1", data: %{"message" => "hi there"}})
      assert_push_event(lv, "update_node_label", %{nodeId: "1", label: "Begin"})
    end

    test "follows what someone else changes in the same node", %{lv: lv, flow: flow, other: other} do
      open_drawer(lv)

      change_elsewhere(other, flow, put_in(@code, ["controls", "message"], "changed by them"))
      _ = :sys.get_state(lv.pid)

      assert has_element?(lv, "input[name='message'][value='changed by them']")
    end

    test "closes when someone else removes the node", %{lv: lv, flow: flow, other: other} do
      open_drawer(lv)

      {:ok, _flow} = Flows.update_flow(other, flow, %{nodes: []})
      _ = :sys.get_state(lv.pid)

      refute has_element?(lv, "input[name='message']")
      assert has_element?(lv, "#flash-info", "removed the node you had open")
    end
  end

  describe "the code of a node" do
    defp open_code(lv) do
      render_hook(lv, "open_code_editor", %{
        "nodeId" => "1",
        "fieldName" => "code",
        "language" => "elixir",
        "code_elixir" => "1 + 1",
        "code_python" => "",
        "variables" => []
      })
    end

    test "saves at once when nobody else changed it", %{lv: lv} do
      open_code(lv)

      render_submit(lv, "save_code", %{"code_elixir" => "2 + 2", "code_python" => ""})

      assert_push_event(lv, "update_node_code", %{nodeId: "1", code_elixir: "2 + 2"})
      refute has_element?(lv, "#code-conflict")
    end

    test "asks before overwriting what someone else saved", %{lv: lv, flow: flow, other: other} do
      open_code(lv)
      change_elsewhere(other, flow, put_in(@code, ["controls", "code_elixir"], "3 + 3"))

      render_submit(lv, "save_code", %{"code_elixir" => "2 + 2", "code_python" => ""})

      assert has_element?(lv, "#code-conflict")
      refute_push_event(lv, "update_node_code", %{})

      # Taking theirs puts it in a new editor.
      render_click(lv, "load_their_code", %{})
      refute has_element?(lv, "#code-conflict")
      assert has_element?(lv, "#code-editor-wrapper-1 #code_elixir_textarea", "3 + 3")

      render_submit(lv, "save_code", %{"code_elixir" => "4 + 4", "code_python" => ""})
      assert_push_event(lv, "update_node_code", %{code_elixir: "4 + 4"})
    end

    test "overwrites when told to", %{lv: lv, flow: flow, other: other} do
      open_code(lv)
      change_elsewhere(other, flow, put_in(@code, ["controls", "code_elixir"], "3 + 3"))

      render_submit(lv, "save_code", %{"code_elixir" => "2 + 2", "code_python" => ""})

      render_submit(lv, "save_code", %{
        "code_elixir" => "2 + 2",
        "code_python" => "",
        "overwrite" => "true"
      })

      assert_push_event(lv, "update_node_code", %{code_elixir: "2 + 2"})
    end
  end
end
