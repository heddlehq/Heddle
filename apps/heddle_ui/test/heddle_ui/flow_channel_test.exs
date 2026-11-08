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
    subscribe_and_join(socket, "flow:#{flow.id}", %{})
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
end
