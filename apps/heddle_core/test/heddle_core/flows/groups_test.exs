defmodule HeddleCore.Flows.GroupsTest do
  use HeddleCore.DataCase, async: true

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Flows
  alias HeddleCore.Flows.Groups

  setup do
    scope = user_scope_fixture()
    flow = flow_fixture(%{user: scope.user, workspace: scope.workspace})
    {:ok, group} = Groups.create_group(scope, %{"name" => "Sales"})

    %{scope: scope, flow: flow, group: group}
  end

  defp scope_as(scope, role) do
    user = user_fixture()
    member_fixture(scope.workspace, user, role)
    user_scope_fixture(user)
  end

  test "lists the groups of the workspace by name", %{scope: scope, group: sales} do
    {:ok, billing} = Groups.create_group(scope, %{"name" => "  billing "})

    assert billing.name == "billing"
    assert Enum.map(Groups.list_groups(scope), & &1.id) == [billing.id, sales.id]
    assert Groups.list_groups(user_scope_fixture()) == []
  end

  test "a name is needed, and only once per workspace", %{scope: scope} do
    assert {:error, changeset} = Groups.create_group(scope, %{"name" => " "})
    assert %{name: ["can't be blank"]} = errors_on(changeset)

    assert {:error, changeset} = Groups.create_group(scope, %{"name" => "SALES"})
    assert %{name: ["is already taken by another group"]} = errors_on(changeset)

    # Another workspace has its own names.
    assert {:ok, _group} = Groups.create_group(user_scope_fixture(), %{"name" => "Sales"})
  end

  test "moves a flow to a group and out of it", %{scope: scope, flow: flow, group: group} do
    assert {:ok, moved} = Groups.move_flow(scope, flow.id, to_string(group.id))
    assert moved.group_id == group.id
    assert Flows.get_flow(scope, flow.id).group_id == group.id

    assert {:ok, moved} = Groups.move_flow(scope, flow.id, "")
    assert moved.group_id == nil
  end

  test "deleting a group leaves its flows without one", %{scope: scope, flow: flow, group: group} do
    {:ok, _flow} = Groups.move_flow(scope, flow.id, group.id)

    assert {:ok, _group} = Groups.delete_group(scope, group.id)
    assert Groups.list_groups(scope) == []
    assert Flows.get_flow(scope, flow.id).group_id == nil
  end

  test "renames a group", %{scope: scope, group: group} do
    assert {:ok, %{name: "Leads"}} = Groups.rename_group(scope, group.id, %{"name" => "Leads"})
  end

  test "what isn't in the workspace looks missing", %{scope: scope, flow: flow, group: group} do
    other = user_scope_fixture()
    {:ok, theirs} = Groups.create_group(other, %{"name" => "Theirs"})

    assert Groups.get_group(other, group.id) == nil
    assert {:error, :not_found} = Groups.rename_group(other, group.id, %{"name" => "x"})
    assert {:error, :not_found} = Groups.delete_group(other, group.id)
    assert {:error, :not_found} = Groups.move_flow(other, flow.id, theirs.id)
    assert {:error, :not_found} = Groups.move_flow(scope, flow.id, theirs.id)
  end

  test "viewers see the groups, editors change them", %{scope: scope, flow: flow, group: group} do
    viewer = scope_as(scope, "viewer")
    editor = scope_as(scope, "editor")

    assert [_group] = Groups.list_groups(viewer)
    assert {:error, :forbidden} = Groups.create_group(viewer, %{"name" => "v"})
    assert {:error, :forbidden} = Groups.rename_group(viewer, group.id, %{"name" => "v"})
    assert {:error, :forbidden} = Groups.delete_group(viewer, group.id)
    assert {:error, :forbidden} = Groups.move_flow(viewer, flow.id, group.id)

    assert {:ok, _group} = Groups.create_group(editor, %{"name" => "Editors"})
    assert {:ok, _flow} = Groups.move_flow(editor, flow.id, group.id)
  end
end
