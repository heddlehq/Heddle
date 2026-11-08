defmodule HeddleCore.WorkspacesTest do
  use HeddleCore.DataCase, async: true

  import HeddleCore.AccountsFixtures
  import HeddleCore.FlowsFixtures

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Repo
  alias HeddleCore.Workspaces
  alias HeddleCore.Workspaces.{Member, Role, Workspace}

  defp scope(user), do: Scope.for_user(Repo.reload!(user))

  describe "Role" do
    test "each role holds what the one below it does" do
      assert Role.allows?("viewer", :view)
      refute Role.allows?("viewer", :run)
      assert Role.allows?("operator", :run)
      refute Role.allows?("operator", :edit)
      assert Role.allows?("editor", :edit)
      refute Role.allows?("editor", :manage)
      assert Role.allows?("admin", :manage)
    end

    test "nothing is allowed without a role, or for an unknown one" do
      refute Role.allows?(nil, :view)
      refute Role.allows?("owner", :view)
      refute Role.allows?("admin", :delete_everything)
    end
  end

  describe "the workspace someone works in" do
    test "is the one they chose, while they are in it, else the first they joined" do
      user = user_fixture()
      first = workspace_fixture(user)
      second = workspace_fixture(user, role: "viewer")

      assert %Scope{workspace: %{id: id}, role: "viewer"} = scope(user)
      assert id == second.id

      Repo.delete!(Repo.get_by!(Member, user_id: user.id, workspace_id: second.id))
      assert scope(user).workspace.id == first.id
    end

    test "is none for someone in no workspace" do
      workspace_fixture(user_fixture())

      assert %Scope{workspace: nil, role: nil} = scope(user_fixture())
    end

    test "can be switched to another of theirs, but not to someone else's" do
      user = user_fixture()
      first = workspace_fixture(user)
      _second = workspace_fixture(user)
      other = workspace_fixture(user_fixture())

      assert {:ok, %Scope{workspace: %{id: id}}} = Workspaces.switch_workspace(scope(user), first)
      assert id == first.id
      assert scope(user).workspace.id == first.id
      assert {:error, :forbidden} = Workspaces.switch_workspace(scope(user), other)
    end

    test "for a system admin, is any of them, as admin" do
      workspace = workspace_fixture(user_fixture())
      admin = system_admin_fixture()

      assert Workspaces.role_of(admin, workspace.id) == "admin"
      assert {:ok, _scope} = Workspaces.switch_workspace(scope(admin), workspace)
    end
  end

  describe "creating and deleting workspaces" do
    test "only system admins create one, and become its admin" do
      admin = system_admin_fixture()

      assert {:ok, %Workspace{} = workspace} =
               Workspaces.create_workspace(scope(admin), %{"name" => "Finanças & Co"})

      assert workspace.slug == "financas-co"
      assert Workspaces.role_of(%{admin | is_system_admin: false}, workspace.id) == "admin"

      assert {:error, :forbidden} =
               Workspaces.create_workspace(user_scope_fixture(), %{"name" => "Mine"})
    end

    test "names that make the same slug get their own" do
      admin = scope(system_admin_fixture())

      {:ok, first} = Workspaces.create_workspace(admin, %{"name" => "Ops"})
      {:ok, second} = Workspaces.create_workspace(admin, %{"name" => "ops"})

      assert first.slug == "ops"
      assert second.slug == "ops-2"
    end

    test "deleting one takes its flows with it, and only system admins can" do
      admin = system_admin_fixture()
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      flow = flow_fixture(%{user: owner, workspace: workspace})

      assert {:error, :forbidden} = Workspaces.delete_workspace(scope(owner), workspace)
      assert {:ok, _workspace} = Workspaces.delete_workspace(scope(admin), workspace)

      refute Repo.get(HeddleCore.Flows.Flow, flow.id)
      assert scope(owner).workspace == nil
    end

    test "the first admin of an instance gets one to start in" do
      {:ok, admin} =
        HeddleCore.Accounts.register_system_admin(%{
          email: "first@example.com",
          username: "first",
          password: "a long password"
        })

      assert %Scope{workspace: %Workspace{name: "Default"}, role: "admin"} = scope(admin)
    end
  end

  describe "members" do
    setup do
      admin = user_fixture()
      workspace = workspace_fixture(admin)
      %{admin: admin, workspace: workspace}
    end

    test "admins add people who have an account, by email or username", %{
      admin: admin,
      workspace: workspace
    } do
      person = user_fixture()

      assert {:ok, %Member{role: "editor"}} =
               Workspaces.add_member(
                 scope(admin),
                 workspace,
                 String.upcase(person.email),
                 "editor"
               )

      assert {:error, :already_member} =
               Workspaces.add_member(scope(admin), workspace, person.username, "viewer")

      assert {:error, :user_not_found} =
               Workspaces.add_member(scope(admin), workspace, "nobody@example.com", "viewer")

      assert {:error, :invalid_role} =
               Workspaces.add_member(scope(admin), workspace, user_fixture().username, "owner")
    end

    test "only admins add people or change roles", %{workspace: workspace} do
      editor = user_fixture()
      member = member_fixture(workspace, editor, "editor")

      assert {:error, :forbidden} =
               Workspaces.add_member(scope(editor), workspace, user_fixture().email, "viewer")

      assert {:error, :forbidden} = Workspaces.change_role(scope(editor), member, "admin")
    end

    test "a workspace always keeps an admin", %{admin: admin, workspace: workspace} do
      member = Repo.get_by!(Member, user_id: admin.id, workspace_id: workspace.id)

      assert {:error, :last_admin} = Workspaces.change_role(scope(admin), member, "editor")
      assert {:error, :last_admin} = Workspaces.remove_member(scope(admin), member)

      second = user_fixture()
      member_fixture(workspace, second, "admin")

      assert {:ok, %Member{role: "editor"}} =
               Workspaces.change_role(scope(admin), member, "editor")
    end

    test "anyone can leave, and admins can remove anyone", %{admin: admin, workspace: workspace} do
      viewer = user_fixture()
      viewer_member = member_fixture(workspace, viewer, "viewer")
      other = user_fixture()
      other_member = member_fixture(workspace, other, "viewer")

      assert {:error, :forbidden} = Workspaces.remove_member(scope(viewer), other_member)
      assert {:ok, _member} = Workspaces.remove_member(scope(viewer), viewer_member)
      assert {:ok, _member} = Workspaces.remove_member(scope(admin), other_member)

      assert Enum.map(Workspaces.list_members(scope(admin), workspace), & &1.user_id) == [
               admin.id
             ]
    end

    test "members are listed admins first, and only to members", %{
      admin: admin,
      workspace: workspace
    } do
      viewer = user_fixture(%{username: "aaa#{System.unique_integer([:positive])}"})
      member_fixture(workspace, viewer, "viewer")

      assert [%{role: "admin"}, %{role: "viewer"}] =
               Workspaces.list_members(scope(admin), workspace)

      assert Workspaces.list_members(user_scope_fixture(), workspace) == []
    end
  end
end
