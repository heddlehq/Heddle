defmodule HeddleCore.ApiKeysTest do
  use HeddleCore.DataCase

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.ApiKeys
  alias HeddleCore.ApiKeys.ApiKey

  import HeddleCore.AccountsFixtures

  defp create_key(user, attrs), do: ApiKeys.create_api_key(user, ensure_workspace(user).id, attrs)
  defp agent_key(user), do: ApiKeys.create_agent_key(user, ensure_workspace(user).id)

  describe "create_api_key/3" do
    test "returns the token once and stores only prefix/hash" do
      user = user_fixture()

      assert {:ok, %{api_key: %ApiKey{} = api_key, token: token}} =
               create_key(user, %{name: "Deploy key", scopes: ["flows:read"]})

      assert token =~ ~r/^hd_live_[a-f0-9]{8}_/
      assert api_key.name == "Deploy key"
      assert api_key.scopes == ["flows:read"]
      assert api_key.prefix != nil
      assert api_key.key_hash == ApiKeys.hash_token(token)
      refute token == api_key.key_hash
    end

    test "validates scopes" do
      user = user_fixture()

      assert {:error, changeset} =
               create_key(user, %{name: "bad", scopes: ["flows:own"]})

      assert "has an invalid entry" in errors_on(changeset).scopes
    end

    test "accepts administrative api key scopes" do
      user = user_fixture()

      assert {:ok, %{api_key: api_key}} =
               create_key(user, %{
                 name: "Admin API key",
                 scopes: ["api_keys:read", "api_keys:write", "api_keys:delete"]
               })

      assert api_key.scopes == ["api_keys:read", "api_keys:write", "api_keys:delete"]
    end
  end

  describe "authenticate/1" do
    test "authenticates an active key" do
      user = user_fixture()
      {:ok, %{api_key: api_key, token: token}} = create_key(user, %{scopes: []})

      assert {:ok, authenticated_key} = ApiKeys.authenticate(token)
      assert authenticated_key.id == api_key.id
      assert authenticated_key.user.id == user.id
      assert authenticated_key.last_used_at != nil
    end

    test "accepts keys issued before the rename" do
      user = user_fixture()

      {:ok, %{api_key: api_key, token: token}} =
        create_key(user, %{name: "Old key", scopes: ["flows:read"]})

      old_token = String.replace_prefix(token, "hd_", "ff_")

      api_key
      |> Ecto.Changeset.change(key_hash: ApiKeys.hash_token(old_token))
      |> HeddleCore.Repo.update!()

      assert {:ok, authenticated_key} = ApiKeys.authenticate(old_token)
      assert authenticated_key.id == api_key.id
    end

    test "rejects invalid tokens" do
      assert ApiKeys.authenticate("hd_live_badtoken") == :error
      assert ApiKeys.authenticate(nil) == :error
    end

    test "rejects revoked keys" do
      user = user_fixture()
      {:ok, %{api_key: api_key, token: token}} = create_key(user, %{scopes: []})
      {:ok, _api_key} = ApiKeys.revoke_api_key(Scope.for_user(user), api_key)

      assert ApiKeys.authenticate(token) == :error
    end

    test "rejects expired keys" do
      user = user_fixture()

      assert {:ok, %{token: token}} =
               create_key(user, %{
                 scopes: [],
                 expires_at: DateTime.add(DateTime.utc_now(:second), -60, :second)
               })

      assert ApiKeys.authenticate(token) == :error
    end
  end

  describe "agent keys" do
    setup do
      %{user: HeddleCore.AccountsFixtures.user_fixture()}
    end

    test "expire within the hour", %{user: user} do
      assert {:ok, %{api_key: api_key}} = agent_key(user)

      limit = DateTime.add(DateTime.utc_now(), 3601)
      assert DateTime.compare(api_key.expires_at, limit) == :lt
    end

    test "can't delete flows", %{user: user} do
      {:ok, %{api_key: api_key}} = agent_key(user)

      refute "workflows:delete" in api_key.scopes
    end

    test "are recognized", %{user: user} do
      {:ok, %{api_key: agent_key}} = agent_key(user)
      {:ok, %{api_key: regular_key}} = create_key(user, %{name: "mine"})

      assert ApiKeys.agent_key?(agent_key)
      refute ApiKeys.agent_key?(regular_key)
    end

    test "stay out of the listings", %{user: user} do
      {:ok, _agent_key} = agent_key(user)
      {:ok, %{api_key: regular_key}} = create_key(user, %{name: "mine"})

      assert Enum.map(ApiKeys.list_api_keys(Scope.for_user(user)), & &1.id) == [regular_key.id]
      refute Enum.any?(ApiKeys.list_api_keys(), &ApiKeys.agent_key?/1)
    end

    test "stop authenticating once deleted", %{user: user} do
      {:ok, %{api_key: api_key, token: token}} = agent_key(user)

      assert {:ok, _api_key} = ApiKeys.delete_api_key(api_key)
      assert ApiKeys.authenticate(token) == :error
    end

    test "can be deleted twice", %{user: user} do
      {:ok, %{api_key: api_key}} = agent_key(user)

      assert {:ok, _api_key} = ApiKeys.delete_api_key(api_key)
      assert {:ok, _api_key} = ApiKeys.delete_api_key(api_key)
    end
  end

  describe "workspaces" do
    test "a person's key is for the workspace they work in, within their role" do
      user = user_fixture()
      workspace = workspace_fixture(user, role: "viewer")
      scope = Scope.for_user(HeddleCore.Repo.reload!(user))

      assert {:ok, %{api_key: key}} =
               ApiKeys.create_api_key(scope, %{name: "read", scopes: ["workflows:read"]})

      assert key.workspace_id == workspace.id

      assert {:error, :forbidden} =
               ApiKeys.create_api_key(scope, %{name: "write", scopes: ["workflows:write"]})
    end

    test "no key for a workspace the person isn't in" do
      user = user_fixture()
      other = workspace_fixture(user_fixture())

      assert {:error, :forbidden} = ApiKeys.create_api_key(user, other.id, %{scopes: []})
    end

    test "a key takes the role its owner has now, and stops when they leave" do
      user = user_fixture()
      workspace = workspace_fixture(user, role: "editor")
      {:ok, %{api_key: key}} = create_key(user, %{scopes: ["workflows:write"]})

      assert %Scope{role: "editor"} = Scope.for_api_key(key)

      member = HeddleCore.Repo.get_by!(HeddleCore.Workspaces.Member, user_id: user.id)
      HeddleCore.Repo.update!(Ecto.Changeset.change(member, role: "viewer"))
      assert %Scope{role: "viewer", workspace: %{id: id}} = Scope.for_api_key(key)
      assert id == workspace.id

      HeddleCore.Repo.delete!(member)
      assert %Scope{role: nil} = Scope.for_api_key(key)
    end

    test "admins see and revoke every key of their workspace; others only their own" do
      admin = user_fixture()
      workspace = workspace_fixture(admin)
      editor = user_fixture()
      member_fixture(workspace, editor, "editor")

      {:ok, %{api_key: admin_key}} = create_key(admin, %{name: "admin's"})
      {:ok, %{api_key: editor_key}} = create_key(editor, %{name: "editor's"})

      admin_scope = Scope.for_user(HeddleCore.Repo.reload!(admin))
      editor_scope = Scope.for_user(HeddleCore.Repo.reload!(editor))

      assert MapSet.new(ApiKeys.list_api_keys(admin_scope), & &1.id) ==
               MapSet.new([admin_key.id, editor_key.id])

      assert Enum.map(ApiKeys.list_api_keys(editor_scope), & &1.id) == [editor_key.id]
      assert {:error, :forbidden} = ApiKeys.revoke_api_key(editor_scope, admin_key)
      assert {:ok, _key} = ApiKeys.revoke_api_key(admin_scope, editor_key)
    end
  end
end
