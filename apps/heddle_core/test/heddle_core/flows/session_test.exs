defmodule HeddleCore.Flows.SessionTest do
  use HeddleCore.DataCase

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Flows
  alias HeddleCore.Flows.{Session, Version, Versions}

  defmodule Manifest do
    def get_definitions do
      [
        %{name: "Start", inputs: [], outputs: ["exec"]},
        %{name: "Output", inputs: ["exec"], outputs: []},
        %{name: "Schedule", inputs: [], outputs: ["exec"]}
      ]
    end
  end

  @start %{"id" => "1", "type" => "Start", "controls" => %{}, "position" => %{"x" => 0, "y" => 0}}
  @output %{
    "id" => "2",
    "type" => "Output",
    "controls" => %{},
    "position" => %{"x" => 200, "y" => 0}
  }
  @link %{"source" => "1", "sourceOutput" => "exec", "target" => "2", "targetInput" => "exec"}

  setup do
    previous = Application.get_env(:heddle_core, :graph_manifest)
    Application.put_env(:heddle_core, :graph_manifest, Manifest)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:heddle_core, :graph_manifest, previous),
        else: Application.delete_env(:heddle_core, :graph_manifest)
    end)

    user = user_fixture()
    workspace = workspace_fixture(user)
    scope = Scope.for_user(Repo.reload!(user))
    flow = flow_fixture(%{user: user, workspace: workspace, nodes: [@start]})
    :ok = Session.subscribe(flow.id)

    on_exit(fn -> stop(flow.id) end)

    %{user: user, scope: scope, flow: flow}
  end

  defp stop(flow_id) do
    case Session.whereis(flow_id) do
      nil -> :ok
      pid -> Horde.DynamicSupervisor.terminate_child(Session.supervisor(), pid)
    end
  end

  test "joining gives the draft and where the changes are", %{flow: flow} do
    assert {:ok, %{graph: graph, seq: 0, epoch: epoch}} = Session.join(flow.id)
    assert [%{"id" => "1"}] = graph.nodes
    assert is_binary(epoch)
  end

  test "applies changes in order, tells everyone and saves them", %{flow: flow, user: user} do
    {:ok, _joined} = Session.join(flow.id, user.id)

    ops = [
      %{"op" => "add_node", "node" => @output},
      %{"op" => "add_connection", "connection" => @link}
    ]

    assert {:ok, 1} = Session.apply_ops(flow.id, user.id, ops, %{client: "tab-1", ref: 7})

    assert_receive {:flow_ops, %{seq: 1, ops: ^ops, user_id: user_id, client: "tab-1", ref: 7}}
    assert user_id == user.id

    saved = Flows.get_flow!(flow.id)
    assert [%{"id" => "1"}, %{"id" => "2"}] = saved.nodes
    assert saved.connections == [@link]
    assert user.id in saved.draft_contributor_ids

    assert {:ok, 2} =
             Session.apply_ops(flow.id, user.id, [
               %{"op" => "move_nodes", "positions" => %{"2" => %{"x" => 300, "y" => 40}}}
             ])
  end

  test "refuses what doesn't apply, and nobody hears of it", %{flow: flow, user: user} do
    assert {:error, message} =
             Session.apply_ops(flow.id, user.id, [%{"op" => "remove_node", "id" => "nope"}])

    assert message =~ "doesn't exist"

    assert {:error, _unknown_type} =
             Session.apply_ops(flow.id, user.id, [
               %{"op" => "add_node", "node" => %{@output | "id" => "3", "type" => "Nope"}}
             ])

    refute_receive {:flow_ops, _change}
    assert [%{"id" => "1"}] = Flows.get_flow!(flow.id).nodes
  end

  test "a draft may hold what is still being typed", %{flow: flow, user: user} do
    schedule = %{"id" => "s", "type" => "Schedule", "controls" => %{"cron" => "0 9"}}

    assert {:ok, 1} =
             Session.apply_ops(flow.id, user.id, [%{"op" => "add_node", "node" => schedule}])

    # Publishing checks it in full.
    assert {:error, {:invalid, message}} = Versions.publish_draft(Flows.get_flow!(flow.id))
    assert message =~ "cron"
  end

  test "writing a whole flow becomes changes everyone sees", %{flow: flow, scope: scope} do
    assert {:ok, updated} =
             Flows.update_flow(scope, flow, %{nodes: [@start, @output], connections: [@link]})

    assert_receive {:flow_ops, %{seq: 1, ops: ops, client: "server"}}

    assert Enum.map(ops, & &1["op"]) == ["add_node", "add_connection"]
    assert length(updated.nodes) == 2
    assert length(Flows.get_flow!(flow.id).nodes) == 2
  end

  test "reading a flow someone edits gives what they have", %{flow: flow, scope: scope} do
    Application.put_env(:heddle_core, :session_flush_after, 60_000)
    on_exit(fn -> Application.put_env(:heddle_core, :session_flush_after, :sync) end)

    {:ok, _joined} = Session.join(flow.id, scope.user.id)

    {:ok, 1} =
      Session.apply_ops(flow.id, scope.user.id, [%{"op" => "add_node", "node" => @output}])

    # Not saved yet, but whoever reads it sees it.
    assert [_one] = Repo.get!(HeddleCore.Flows.Flow, flow.id).nodes
    assert [_, _] = Flows.get_flow(scope, flow.id).nodes

    # A run takes what was saved, so it saves first.
    assert {:ok, %Version{nodes: [_, _]}} = Versions.freeze_draft(flow)
    assert [_, _] = Repo.get!(HeddleCore.Flows.Flow, flow.id).nodes
  end

  test "saves when it stops, keeping what was edited", %{flow: flow, user: user} do
    Application.put_env(:heddle_core, :session_flush_after, 60_000)
    on_exit(fn -> Application.put_env(:heddle_core, :session_flush_after, :sync) end)

    {:ok, _joined} = Session.join(flow.id, user.id)
    {:ok, 1} = Session.apply_ops(flow.id, user.id, [%{"op" => "add_node", "node" => @output}])

    pid = Session.whereis(flow.id)
    ref = Process.monitor(pid)
    :ok = Horde.DynamicSupervisor.terminate_child(Session.supervisor(), pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

    assert [_, _] = Flows.get_flow!(flow.id).nodes
    assert %Version{kind: "checkpoint", nodes: [_, _]} = Versions.latest(flow)
  end

  test "a snapshot gives the draft and its number without joining", %{flow: flow, scope: scope} do
    {:ok, 1} =
      Session.apply_ops(flow.id, scope.user.id, [%{"op" => "add_node", "node" => @output}])

    assert {:ok, %{graph: %{nodes: [_, _]}, seq: 1, epoch: epoch}} = Session.snapshot(flow.id)
    assert is_binary(epoch) or is_integer(epoch)

    assert {:ok, _flow, %{seq: 1}} = Flows.session_snapshot(scope, :view, flow.id)

    assert {:error, :not_found} =
             Flows.session_snapshot(Scope.for_user(user_fixture()), :view, flow.id)
  end

  test "a session that starts again has another epoch", %{flow: flow} do
    {:ok, %{epoch: first}} = Session.join(flow.id)
    stop(flow.id)
    {:ok, %{epoch: second}} = Session.join(flow.id)

    assert first != second
  end

  test "a flow that doesn't exist has no session" do
    assert {:error, :not_found} = Session.join(-1)
  end
end
