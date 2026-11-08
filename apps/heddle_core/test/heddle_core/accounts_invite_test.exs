defmodule HeddleCore.AccountsInviteTest do
  use HeddleCore.DataCase

  alias HeddleCore.Accounts
  alias HeddleCore.Accounts.{Invite, Scope}
  alias HeddleCore.Repo

  import HeddleCore.AccountsFixtures

  describe "list_users/0" do
    test "returns all users including newly created ones" do
      u1 = user_fixture()
      u2 = user_fixture()
      users = Accounts.list_users()
      ids = Enum.map(users, & &1.id)
      assert u1.id in ids
      assert u2.id in ids
      assert length(users) >= 2
    end
  end

  describe "create_invite/3" do
    setup do
      admin = user_fixture()
      workspace = workspace_fixture(admin)
      %{scope: Scope.for_user(Repo.reload!(admin)), workspace: workspace}
    end

    test "only the workspace's admins invite", %{workspace: workspace} do
      editor = user_fixture()
      member_fixture(workspace, editor, "editor")

      assert {:error, :forbidden} =
               Accounts.create_invite(Scope.for_user(Repo.reload!(editor)), workspace, "viewer")

      assert {:error, :forbidden} =
               Accounts.create_invite(user_scope_fixture(), workspace, "viewer")
    end

    test "brings a role into the workspace", %{scope: scope, workspace: workspace} do
      assert {:ok, %Invite{} = invite} = Accounts.create_invite(scope, workspace, "operator")
      assert invite.workspace_id == workspace.id
      assert invite.role == "operator"
      assert invite.invited_by_user_id == scope.user.id
      assert DateTime.compare(DateTime.utc_now(), invite.expires_at) == :lt
    end

    test "reuses an open one for the same role", %{scope: scope, workspace: workspace} do
      {:ok, first} = Accounts.create_invite(scope, workspace, "editor")
      {:ok, second} = Accounts.create_invite(scope, workspace, "editor")
      {:ok, other} = Accounts.create_invite(scope, workspace, "viewer")

      assert first.id == second.id
      assert other.id != first.id
    end

    test "makes a new one once the last is used or expired", %{scope: scope, workspace: workspace} do
      {:ok, used} = Accounts.create_invite(scope, workspace, "editor")
      Accounts.mark_invite_used(used)
      {:ok, fresh} = Accounts.create_invite(scope, workspace, "editor")
      assert fresh.id != used.id

      fresh |> Ecto.Changeset.change(expires_at: ~U[2020-01-01 00:00:00Z]) |> Repo.update!()
      {:ok, newer} = Accounts.create_invite(scope, workspace, "editor")
      assert newer.id != fresh.id
    end

    test "refuses a role that doesn't exist", %{scope: scope, workspace: workspace} do
      assert {:error, :invalid_role} = Accounts.create_invite(scope, workspace, "owner")
    end

    test "can be canceled by an admin", %{scope: scope, workspace: workspace} do
      {:ok, invite} = Accounts.create_invite(scope, workspace, "editor")

      assert [%Invite{}] = Accounts.list_open_invites(scope, workspace)
      assert {:error, :forbidden} = Accounts.revoke_invite(user_scope_fixture(), invite)
      assert {:ok, _invite} = Accounts.revoke_invite(scope, invite)
      assert Accounts.list_open_invites(scope, workspace) == []
    end
  end

  describe "register_user_with_invite/2" do
    test "joins the workspace with the invite's role, and works there" do
      workspace = workspace_fixture(user_fixture())
      invite = invite_fixture(workspace: workspace, role: "operator")

      assert {:ok, user} = Accounts.register_user_with_invite(valid_user_attributes(), invite)
      assert HeddleCore.Workspaces.role_of(user, workspace.id) == "operator"
      assert %Scope{workspace: %{id: id}, role: "operator"} = Scope.for_user(user)
      assert id == workspace.id
    end

    test "an invite without a workspace only creates the account" do
      invite = invite_fixture()

      assert {:ok, user} = Accounts.register_user_with_invite(valid_user_attributes(), invite)
      assert %Scope{workspace: nil} = Scope.for_user(user)
    end
  end

  describe "get_invite_by_token/1" do
    test "returns nil for unknown token" do
      assert is_nil(Accounts.get_invite_by_token("unknown"))
    end

    test "returns invite with preloaded invited_by_user" do
      invite = invite_fixture()
      found = Accounts.get_invite_by_token(invite.token)
      assert found.id == invite.id
      assert found.invited_by_user.id == invite.invited_by_user_id
    end
  end

  describe "mark_invite_used/1" do
    test "sets used_at on invite" do
      invite = invite_fixture()
      assert invite.used_at == nil
      assert {:ok, updated} = Accounts.mark_invite_used(invite)
      assert updated.used_at != nil
    end
  end

  describe "list_invites_by_admin/1" do
    test "returns invites for given admin only" do
      admin = system_admin_fixture()
      other = system_admin_fixture()
      i1 = invite_fixture(invited_by_user: admin)
      _i2 = invite_fixture(invited_by_user: other)
      invites = Accounts.list_invites_by_admin(admin)
      assert length(invites) == 1
      assert hd(invites).id == i1.id
    end
  end
end
