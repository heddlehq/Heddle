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

    test "scoped queries only return owned flows" do
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
      attrs = %{name: "Test Flow", nodes: [], connections: [], user_id: user.id}
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

      attrs = %{
        name: "Invalid Flow",
        user_id: user_fixture().id,
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

    test "get_first_or_create_default_flow/0 returns existing flow" do
      flow = flow_fixture()
      assert {:ok, result} = Flows.get_first_or_create_default_flow()
      assert result.id == flow.id
    end

    test "get_first_or_create_default_flow/0 creates default when none exist" do
      user_fixture()
      assert Flows.list_flows() == []
      assert {:ok, flow} = Flows.get_first_or_create_default_flow()
      assert flow.name == "My First Flow"
    end
  end

  describe "stored form of a flow" do
    test "create_flow/1 stores string ids and fills in the target input" do
      user = HeddleCore.AccountsFixtures.user_fixture()

      assert {:ok, flow} =
               Flows.create_flow(%{
                 name: "Stored",
                 user_id: user.id,
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
