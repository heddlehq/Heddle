defmodule HeddleUI.FlowChannelTest do
  # Not async: the session of a flow is shared by everyone who edits it.
  use HeddleCore.DataCase, async: false

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures
  import Phoenix.ChannelTest

  alias HeddleCore.Flows
  alias HeddleCore.Flows.Session
  alias HeddleUI.FlowSocket

  @endpoint HeddleUI.Endpoint

  @start %{
    "id" => "1",
    "type" => "Start",
    "label" => "Start",
    "controls" => %{},
    "position" => %{"x" => 0, "y" => 0}
  }
  @output %{
    "id" => "2",
    "type" => "Output",
    "label" => "Output",
    "controls" => %{},
    "position" => %{"x" => 200, "y" => 0}
  }

  setup do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    flow = flow_fixture(%{user: owner, workspace: workspace, nodes: [@start]})

    on_exit(fn ->
      case Session.whereis(flow.id) do
        nil -> :ok
        pid -> Horde.DynamicSupervisor.terminate_child(Session.supervisor(), pid)
      end
    end)

    %{owner: owner, workspace: workspace, flow: flow}
  end

  defp member(workspace, role) do
    user = user_fixture()
    member_fixture(workspace, user, role)
    HeddleCore.Repo.reload!(user)
  end

  defp join_as(user, flow) do
    {:ok, socket} = connect(FlowSocket, %{"token" => FlowSocket.token(user)})
    subscribe_and_join(socket, "canvas:#{flow.id}", %{})
  end

  test "needs a token" do
    assert :error = connect(FlowSocket, %{})
    assert :error = connect(FlowSocket, %{"token" => "forged"})
  end

  test "joining gives the draft, and whether it can be changed", %{
    owner: owner,
    flow: flow,
    workspace: workspace
  } do
    assert {:ok, reply, _socket} = join_as(owner, flow)
    assert %{graph: %{nodes: [%{"id" => "1"}]}, seq: 0, can_edit: true, client: client} = reply
    assert is_binary(client)
    assert is_map(reply.definitions)

    viewer = member(workspace, "viewer")
    assert {:ok, %{can_edit: false}, _socket} = join_as(viewer, flow)
  end

  test "a flow of another workspace looks missing", %{flow: flow} do
    assert {:error, %{reason: "not_found"}} = join_as(user_fixture(), flow)
  end

  test "a change reaches everyone in the flow, numbered", %{
    owner: owner,
    flow: flow,
    workspace: workspace
  } do
    {:ok, _reply, mine} = join_as(owner, flow)
    {:ok, _reply, _theirs} = join_as(member(workspace, "editor"), flow)

    ref = push(mine, "ops", %{"ops" => [%{"op" => "add_node", "node" => @output}], "ref" => 1})
    assert_reply ref, :ok, %{seq: 1}

    # Both joined from this process, so it hears the change twice.
    assert_push "ops", %{seq: 1, ops: [%{"op" => "add_node"}], ref: 1}
    assert_push "ops", %{seq: 1}

    assert [_, _] = Flows.get_flow!(flow.id).nodes
  end

  test "a change that doesn't apply goes back to who sent it", %{owner: owner, flow: flow} do
    {:ok, _reply, socket} = join_as(owner, flow)

    ref = push(socket, "ops", %{"ops" => [%{"op" => "remove_node", "id" => "nope"}]})
    assert_reply ref, :error, %{reason: reason}

    assert reason =~ "doesn't exist"
    refute_push "ops", _change
  end

  test "someone who may only see the flow can't change it", %{flow: flow, workspace: workspace} do
    {:ok, _reply, socket} = join_as(member(workspace, "viewer"), flow)

    ref = push(socket, "ops", %{"ops" => [%{"op" => "add_node", "node" => @output}]})
    assert_reply ref, :error, %{reason: "forbidden"}
    assert [_one] = Flows.get_flow!(flow.id).nodes
  end

  test "a change made elsewhere reaches the canvas", %{owner: owner, flow: flow} do
    {:ok, _reply, _socket} = join_as(owner, flow)

    {:ok, _flow} = Flows.update_flow(flow, %{nodes: [@start, @output]})

    assert_push "ops", %{seq: 1, client: "server", ops: [%{"op" => "add_node"}]}
  end

  test "a canvas that lost track asks for the draft again", %{owner: owner, flow: flow} do
    {:ok, _reply, socket} = join_as(owner, flow)
    {:ok, _flow} = Flows.update_flow(flow, %{nodes: [@start, @output]})

    ref = push(socket, "snapshot", %{})
    assert_reply ref, :ok, %{graph: %{nodes: [_, _]}, seq: 1}
  end

  describe "presence" do
    test "everyone on the canvas is there, with a name and a color", %{owner: owner, flow: flow} do
      {:ok, %{client: client}, _socket} = join_as(owner, flow)

      assert_push "presence_state", state

      assert %{metas: [%{kind: "person", user_id: user_id, color: "#" <> _, name: name}]} =
               state[client]

      assert user_id == owner.id
      assert is_binary(name)
    end

    test "cursors go to the others, not to who moved", %{
      owner: owner,
      flow: flow,
      workspace: workspace
    } do
      {:ok, %{client: mine}, socket} = join_as(owner, flow)
      {:ok, _reply, _theirs} = join_as(member(workspace, "viewer"), flow)

      push(socket, "cursor", %{"x" => 120, "y" => -40.5})
      assert_push "cursor", %{client: ^mine, x: 120, y: -40.5}

      push(socket, "cursor", %{})
      assert_push "cursor", %{client: ^mine, x: nil}
    end

    test "what is dragged goes to the others, from those who may edit", %{
      owner: owner,
      flow: flow,
      workspace: workspace
    } do
      {:ok, %{client: mine}, socket} = join_as(owner, flow)
      {:ok, _reply, viewer} = join_as(member(workspace, "viewer"), flow)

      push(socket, "drag", %{"positions" => %{"1" => %{"x" => 5, "y" => 6}}})
      assert_push "drag", %{client: ^mine, positions: %{"1" => %{"x" => 5}}}

      push(viewer, "drag", %{"positions" => %{"1" => %{"x" => 9, "y" => 9}}})
      refute_push "drag", %{positions: %{"1" => %{"x" => 9}}}
    end

    test "what someone selects and has open is part of their presence", %{
      owner: owner,
      flow: flow
    } do
      {:ok, %{client: client}, socket} = join_as(owner, flow)

      push(socket, "focus", %{"selected" => ["1", 7], "editing" => "1"})
      _ = :sys.get_state(socket.channel_pid)

      assert %{metas: [%{selected: ["1"], editing: "1"}]} =
               HeddleUI.FlowPresence.list("canvas:#{flow.id}")[client]
    end

    test "the agent is there while it works", %{owner: owner, flow: flow} do
      {:ok, _reply, _socket} = join_as(owner, flow)

      :ok = HeddleUI.FlowPresence.track_agent(flow.id, owner)
      key = "agent:#{owner.id}"

      assert %{metas: [%{kind: "agent", user_id: user_id}]} =
               HeddleUI.FlowPresence.list("canvas:#{flow.id}")[key]

      assert user_id == owner.id

      HeddleUI.FlowPresence.untrack_agent(flow.id, owner)
      refute Map.has_key?(HeddleUI.FlowPresence.list("canvas:#{flow.id}"), key)
    end

    test "what the agent of the editor changes says so", %{owner: owner, flow: flow} do
      {:ok, _reply, _socket} = join_as(owner, flow)

      {:ok, _flow} =
        Flows.update_flow(
          HeddleCore.Accounts.Scope.for_user(owner),
          flow,
          %{nodes: [@start, @output]},
          client: "agent"
        )

      assert_push "ops", %{client: "agent"}
    end
  end
end
