defmodule HeddleCore.CredentialsTest do
  use HeddleCore.DataCase, async: false

  import HeddleCore.AccountsFixtures

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Credentials
  alias HeddleCore.Credentials.Credential
  alias HeddleCore.Repo

  @slack %{name: "main", kind: "slack", values: %{"token" => "xoxb-secret"}}

  setup do
    scope = user_scope_fixture()
    %{scope: scope, ws: scope.workspace.id}
  end

  describe "create_credential/2" do
    test "keeps the values encrypted", %{scope: scope, ws: ws} do
      assert {:ok, %Credential{id: id}} = Credentials.create_credential(scope, @slack)

      data = Repo.one!(from c in Credential, where: c.id == ^id, select: c.data)

      refute data =~ "xoxb-secret"
      assert Credentials.fetch(ws, "main", "slack") == {:ok, %{"token" => "xoxb-secret"}}
    end

    test "doesn't load the secret with the record", %{scope: scope} do
      {:ok, _credential} = Credentials.create_credential(scope, @slack)

      assert [%Credential{data: nil}] = Credentials.list_credentials(scope)
    end

    test "needs the required values", %{scope: scope} do
      assert {:error, changeset} =
               Credentials.create_credential(scope, %{name: "x", kind: "slack", values: %{}})

      assert %{kind: ["Bot token can't be blank"]} = errors_on(changeset)
    end

    test "fills in defaults", %{scope: scope, ws: ws} do
      {:ok, _credential} =
        Credentials.create_credential(scope, %{
          name: "mail",
          kind: "smtp",
          values: %{"host" => "smtp.example.com", "from" => "a@example.com"}
        })

      assert {:ok, %{"port" => "587"}} = Credentials.fetch(ws, "mail", "smtp")
    end

    test "refuses an unknown kind and a repeated name", %{scope: scope} do
      assert {:error, _changeset} =
               Credentials.create_credential(scope, %{name: "x", kind: "nope"})

      {:ok, _credential} = Credentials.create_credential(scope, @slack)
      assert {:error, changeset} = Credentials.create_credential(scope, @slack)
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update_credential/3" do
    test "keeps a secret left blank", %{scope: scope, ws: ws} do
      {:ok, credential} = Credentials.create_credential(scope, @slack)

      assert {:ok, _credential} =
               Credentials.update_credential(scope, credential, %{
                 name: "renamed",
                 values: %{"token" => ""}
               })

      assert Credentials.fetch(ws, "renamed", "slack") == {:ok, %{"token" => "xoxb-secret"}}
    end

    test "replaces a secret that is given", %{scope: scope, ws: ws} do
      {:ok, credential} = Credentials.create_credential(scope, @slack)

      {:ok, _credential} =
        Credentials.update_credential(scope, credential, %{values: %{"token" => "xoxb-new"}})

      assert Credentials.fetch(ws, "main", "slack") == {:ok, %{"token" => "xoxb-new"}}
    end
  end

  describe "public_values/1" do
    test "leaves secrets out", %{scope: scope} do
      {:ok, credential} =
        Credentials.create_credential(scope, %{
          name: "files",
          kind: "ftp",
          values: %{"host" => "h", "username" => "u", "password" => "p"}
        })

      assert %{"host" => "h"} = values = Credentials.public_values(credential)
      refute Map.has_key?(values, "password")
    end
  end

  describe "the credentials of a database" do
    test "a SQL one keeps its engine and hides its password", %{scope: scope, ws: ws} do
      {:ok, credential} =
        Credentials.create_credential(scope, %{
          name: "warehouse",
          kind: "sql",
          values: %{"engine" => "mysql", "database" => "shop", "password" => "p"}
        })

      assert {:ok, %{"engine" => "mysql", "password" => "p", "ssl" => "verify"}} =
               Credentials.fetch(ws, "warehouse", "sql")

      refute Map.has_key?(Credentials.public_values(credential), "password")
    end

    test "a connection string counts as a secret, because it holds the password", %{
      scope: scope
    } do
      for {kind, values} <- [
            {"mongodb", %{"url" => "mongodb://u:p@h", "database" => "d"}},
            {"redis", %{"url" => "redis://:p@h"}}
          ] do
        {:ok, credential} =
          Credentials.create_credential(scope, %{name: kind, kind: kind, values: values})

        refute Map.has_key?(Credentials.public_values(credential), "url")
      end
    end

    test "asks for what can't be blank", %{scope: scope} do
      assert {:error, changeset} =
               Credentials.create_credential(scope, %{name: "r", kind: "redis", values: %{}})

      assert %{kind: [_message]} = errors_on(changeset)
    end
  end

  describe "fetch/3" do
    test "explains what went wrong", %{scope: scope, ws: ws} do
      {:ok, _credential} = Credentials.create_credential(scope, @slack)

      assert {:error, message} = Credentials.fetch(ws, "nope", "slack")
      assert message =~ "no credential"
      assert {:error, message} = Credentials.fetch(ws, "main", "s3")
      assert message =~ "is for slack"
      assert {:error, _message} = Credentials.fetch(ws, nil, "slack")
    end

    test "says so when the key changed", %{scope: scope, ws: ws} do
      {:ok, _credential} = Credentials.create_credential(scope, @slack)
      previous = Application.fetch_env!(:heddle_core, :credentials_secret)

      Application.put_env(:heddle_core, :credentials_secret, "another key")
      on_exit(fn -> Application.put_env(:heddle_core, :credentials_secret, previous) end)

      assert {:error, message} = Credentials.fetch(ws, "main", "slack")
      assert message =~ "SECRET_KEY_BASE"
    end
  end

  describe "workspaces" do
    test "a run finds only the credentials of its workspace", %{scope: scope, ws: ws} do
      {:ok, _credential} = Credentials.create_credential(scope, @slack)
      other = user_scope_fixture()

      assert {:ok, _token} = Credentials.fetch(ws, "main", "slack")
      assert {:error, message} = Credentials.fetch(other.workspace.id, "main", "slack")
      assert message =~ "no credential"
      assert Credentials.list_credentials(other) == []
    end

    test "two workspaces can use the same name", %{scope: scope, ws: ws} do
      other = user_scope_fixture()
      {:ok, _credential} = Credentials.create_credential(scope, @slack)

      assert {:ok, _credential} =
               Credentials.create_credential(other, %{@slack | values: %{"token" => "xoxb-b"}})

      assert Credentials.fetch(ws, "main", "slack") == {:ok, %{"token" => "xoxb-secret"}}

      assert Credentials.fetch(other.workspace.id, "main", "slack") ==
               {:ok, %{"token" => "xoxb-b"}}
    end

    test "a shared one reaches every workspace, and its own name wins", %{scope: scope, ws: ws} do
      admin = system_admin_fixture()
      admin_scope = Scope.for_user(admin)

      {:ok, shared} = Credentials.create_credential(admin_scope, Map.put(@slack, :shared, true))
      assert Credential.shared?(shared)

      assert Credentials.fetch(ws, "main", "slack") == {:ok, %{"token" => "xoxb-secret"}}
      assert Credentials.fetch(nil, "main", "slack") == {:ok, %{"token" => "xoxb-secret"}}
      assert [%Credential{workspace_id: nil}] = Credentials.list_credentials(scope)

      {:ok, _own} = Credentials.create_credential(scope, %{@slack | values: %{"token" => "own"}})
      assert Credentials.fetch(ws, "main", "slack") == {:ok, %{"token" => "own"}}
      assert Credentials.fetch(nil, "main", "slack") == {:ok, %{"token" => "xoxb-secret"}}
    end

    test "only system admins share or change a shared one", %{scope: scope} do
      assert {:error, :forbidden} =
               Credentials.create_credential(scope, Map.put(@slack, :shared, true))

      {:ok, shared} =
        Credentials.create_credential(
          Scope.for_user(system_admin_fixture()),
          Map.put(@slack, :shared, true)
        )

      refute Credentials.can_change?(scope, shared)
      assert {:error, :forbidden} = Credentials.update_credential(scope, shared, %{name: "x"})
      assert {:error, :forbidden} = Credentials.delete_credential(scope, shared)
    end

    test "viewers and operators see names but can't change them", %{scope: scope} do
      {:ok, credential} = Credentials.create_credential(scope, @slack)

      for role <- ["viewer", "operator"] do
        user = user_fixture()
        member_fixture(scope.workspace, user, role)
        reader = Scope.for_user(Repo.reload!(user))

        assert [%Credential{name: "main"}] = Credentials.list_credentials(reader)
        assert {:error, :forbidden} = Credentials.create_credential(reader, %{@slack | name: "x"})
        assert {:error, :forbidden} = Credentials.delete_credential(reader, credential)
      end
    end

    test "someone outside can't read one by id", %{scope: scope} do
      {:ok, credential} = Credentials.create_credential(scope, @slack)

      assert Credentials.get_credential(user_scope_fixture(), credential.id) == nil
      assert %Credential{} = Credentials.get_credential(scope, credential.id)
    end
  end
end
