defmodule HeddleCore.FlowsTest do
  use HeddleCore.DataCase

  alias HeddleCore.Flows
  alias HeddleCore.Accounts.Scope
  import HeddleCore.AccountsFixtures

  defmodule Manifest do
    def get_definitions do
      [
        %{name: "Start", inputs: [], outputs: ["exec"]}
      ]
    end
  end

  describe "flows" do
    import HeddleCore.FlowsFixtures

    test "list_flows/0 returns all flows" do
      flow = flow_fixture()
      assert Flows.list_flows() |> Enum.map(& &1.id) |> Enum.member?(flow.id)
    end

    test "get_flow!/1 returns the flow with given id" do
      flow = flow_fixture()
      assert Flows.get_flow!(flow.id).id == flow.id
    end

    test "update_flow/2 keeps the comments of a save that doesn't send them" do
      comment = %{
        "id" => "note",
        "kind" => "title",
        "color" => "default",
        "text" => "Billing",
        "width" => 240,
        "height" => 140,
        "position" => %{"x" => 10, "y" => 20}
      }

      flow = flow_fixture()
      assert flow.comments == []

      assert {:ok, flow} = Flows.update_flow(flow, %{comments: [comment]})
      assert {:ok, flow} = Flows.update_flow(flow, %{nodes: [], connections: []})

      assert Flows.get_flow!(flow.id).comments == [comment]
    end

    test "update_flow/2 refuses an invalid comment" do
      assert {:error, changeset} =
               Flows.update_flow(flow_fixture(), %{comments: [%{"id" => "note"}]})

      assert %{comments: ["contains an invalid comment"]} = errors_on(changeset)
    end

    test "scoped queries only return the flows of the caller's workspace" do
      user = user_fixture()
      owned_flow = flow_fixture(%{user: user})
      other_flow = flow_fixture()
      scope = Scope.for_user(user)

      assert Flows.list_flows(scope) |> Enum.map(& &1.id) == [owned_flow.id]
      assert Flows.get_flow!(scope, owned_flow.id).id == owned_flow.id
      assert_raise Ecto.NoResultsError, fn -> Flows.get_flow!(scope, other_flow.id) end
    end

    test "create_flow/1 with valid data creates a flow" do
      user = user_fixture()
      workspace = workspace_fixture(user)

      attrs = %{
        name: "Test Flow",
        nodes: [],
        connections: [],
        user_id: user.id,
        workspace_id: workspace.id
      }

      assert {:ok, flow} = Flows.create_flow(attrs)
      assert flow.name == "Test Flow"
      assert flow.user_id == user.id
      assert flow.nodes == []
      assert flow.connections == []
    end

    test "create_flow/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Flows.create_flow(%{})
    end

    test "create_flow/1 with invalid graph returns error changeset" do
      previous_manifest = Application.get_env(:heddle_core, :graph_manifest)
      Application.put_env(:heddle_core, :graph_manifest, Manifest)

      on_exit(fn ->
        if previous_manifest do
          Application.put_env(:heddle_core, :graph_manifest, previous_manifest)
        else
          Application.delete_env(:heddle_core, :graph_manifest)
        end
      end)

      user = user_fixture()

      attrs = %{
        name: "Invalid Flow",
        user_id: user.id,
        workspace_id: workspace_fixture(user).id,
        nodes: [
          %{
            "id" => "start",
            "type" => "Missing",
            "controls" => %{},
            "position" => %{"x" => 0, "y" => 0}
          }
        ],
        connections: []
      }

      assert {:error, changeset} = Flows.create_flow(attrs)
      assert "contains unknown node type" in errors_on(changeset).nodes
    end

    test "update_flow/2 with valid data updates the flow" do
      flow = flow_fixture()
      assert {:ok, updated} = Flows.update_flow(flow, %{name: "Updated Flow"})
      assert updated.name == "Updated Flow"
    end

    test "delete_flow/1 deletes the flow" do
      flow = flow_fixture()
      assert {:ok, _} = Flows.delete_flow(flow)
      assert_raise Ecto.NoResultsError, fn -> Flows.get_flow!(flow.id) end
    end

    test "change_flow/1 returns a flow changeset" do
      flow = flow_fixture()
      assert %Ecto.Changeset{} = Flows.change_flow(flow)
    end
  end

  describe "workspaces and roles" do
    import HeddleCore.FlowsFixtures

    setup do
      admin = user_fixture()
      workspace = workspace_fixture(admin)
      flow = flow_fixture(%{user: admin, workspace: workspace})
      %{workspace: workspace, flow: flow}
    end

    defp scope_as(workspace, role) do
      user = user_fixture()
      member_fixture(workspace, user, role)
      Scope.for_user(HeddleCore.Repo.reload!(user))
    end

    test "every member sees the workspace's flows", %{workspace: workspace, flow: flow} do
      for role <- HeddleCore.Workspaces.Role.all() do
        scope = scope_as(workspace, role)
        assert [%{id: id}] = Flows.list_flows(scope)
        assert id == flow.id
        assert Flows.get_flow(scope, flow.id)
      end
    end

    test "someone outside sees nothing, and a flow looks missing", %{flow: flow} do
      outsider = user_scope_fixture()

      assert Flows.list_flows(outsider) == []
      assert Flows.get_flow(outsider, flow.id) == nil
      assert {:error, :not_found} = Flows.update_flow(outsider, flow, %{name: "x"})
      assert {:error, :not_found} = Flows.delete_flow(outsider, flow)
    end

    test "a person with no workspace sees nothing" do
      flow_fixture()
      scope = Scope.for_user(user_fixture())

      assert scope.workspace == nil
      assert Flows.list_flows(scope) == []
      assert {:error, :forbidden} = Flows.create_flow(scope, %{name: "x"})
    end

    test "viewers and operators can't change a flow", %{workspace: workspace, flow: flow} do
      for role <- ["viewer", "operator"] do
        scope = scope_as(workspace, role)

        assert {:error, :forbidden} = Flows.create_flow(scope, %{name: "x", nodes: []})
        assert {:error, :forbidden} = Flows.update_flow(scope, flow, %{name: "x"})
        assert {:error, :forbidden} = Flows.delete_flow(scope, flow)
      end
    end

    test "editors create flows in their workspace, as their author", %{workspace: workspace} do
      scope = scope_as(workspace, "editor")

      assert {:ok, flow} =
               Flows.create_flow(scope, %{"name" => "Mine", "workspace_id" => -1, "user_id" => -1})

      assert flow.workspace_id == workspace.id
      assert flow.user_id == scope.user.id
    end

    test "a change can't move a flow to another workspace", %{workspace: workspace, flow: flow} do
      scope = scope_as(workspace, "editor")
      other = workspace_fixture(scope.user)

      assert {:ok, flow} = Flows.update_flow(scope, flow, %{"workspace_id" => other.id})
      assert flow.workspace_id == workspace.id
    end

    test "system admins reach every workspace", %{flow: flow} do
      scope = Scope.for_user(system_admin_fixture())

      assert {:ok, _flow} = Flows.update_flow(scope, flow, %{name: "Fixed by an admin"})
    end
  end

  describe "stored form of a flow" do
    test "create_flow/1 stores string ids and fills in the target input" do
      user = HeddleCore.AccountsFixtures.user_fixture()

      assert {:ok, flow} =
               Flows.create_flow(%{
                 name: "Stored",
                 user_id: user.id,
                 workspace_id: workspace_fixture(user).id,
                 nodes: [
                   %{"id" => 1, "type" => "Start", "controls" => %{}},
                   %{"id" => 2, "type" => "Output", "controls" => %{}}
                 ],
                 connections: [%{"source" => 1, "sourceOutput" => "exec", "target" => 2}]
               })

      assert [%{"id" => "1"}, %{"id" => "2"}] = flow.nodes

      assert flow.connections == [
               %{
                 "source" => "1",
                 "sourceOutput" => "exec",
                 "target" => "2",
                 "targetInput" => "exec"
               }
             ]
    end
  end

  describe "execution_logs" do
    import HeddleCore.FlowsFixtures

    test "create_execution_log/1 with valid data creates a log" do
      flow = flow_fixture()
      attrs = %{flow_id: flow.id, status: "running", context: %{}}

      assert {:ok, log} = Flows.create_execution_log(attrs)
      assert log.status == "running"
    end

    test "create_execution_log/1 without context returns error" do
      flow = flow_fixture()
      attrs = %{flow_id: flow.id, status: "running"}

      assert {:error, %Ecto.Changeset{}} = Flows.create_execution_log(attrs)
    end
  end

  describe "subscribe_to_flow/1" do
    import HeddleCore.FlowsFixtures

    test "announces updates, whoever makes them" do
      flow = flow_fixture()
      Flows.subscribe_to_flow(flow.id)

      assert {:ok, updated} = Flows.update_flow(flow, %{name: "Renamed"})

      assert_receive {:flow_updated, ^updated}
    end

    test "stays quiet about other flows and failed updates" do
      flow = flow_fixture()
      other = flow_fixture()
      Flows.subscribe_to_flow(flow.id)

      {:ok, _other} = Flows.update_flow(other, %{name: "Other"})
      {:error, _changeset} = Flows.update_flow(flow, %{name: nil})

      refute_receive {:flow_updated, _flow}, 50
    end
  end
end
