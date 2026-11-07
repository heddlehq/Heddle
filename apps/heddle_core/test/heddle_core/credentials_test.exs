defmodule HeddleCore.CredentialsTest do
  use HeddleCore.DataCase, async: false

  alias HeddleCore.Credentials
  alias HeddleCore.Credentials.Credential
  alias HeddleCore.Repo

  @slack %{name: "main", kind: "slack", values: %{"token" => "xoxb-secret"}}

  describe "create_credential/1" do
    test "keeps the values encrypted" do
      assert {:ok, %Credential{id: id}} = Credentials.create_credential(@slack)

      data = Repo.one!(from c in Credential, where: c.id == ^id, select: c.data)

      refute data =~ "xoxb-secret"
      assert Credentials.fetch("main", "slack") == {:ok, %{"token" => "xoxb-secret"}}
    end

    test "doesn't load the secret with the record" do
      {:ok, _credential} = Credentials.create_credential(@slack)

      assert [%Credential{data: nil}] = Credentials.list_credentials()
    end

    test "needs the required values" do
      assert {:error, changeset} =
               Credentials.create_credential(%{name: "x", kind: "slack", values: %{}})

      assert %{kind: ["Bot token can't be blank"]} = errors_on(changeset)
    end

    test "fills in defaults" do
      {:ok, _credential} =
        Credentials.create_credential(%{
          name: "mail",
          kind: "smtp",
          values: %{"host" => "smtp.example.com", "from" => "a@example.com"}
        })

      assert {:ok, %{"port" => "587"}} = Credentials.fetch("mail", "smtp")
    end

    test "refuses an unknown kind and a repeated name" do
      assert {:error, _changeset} = Credentials.create_credential(%{name: "x", kind: "nope"})

      {:ok, _credential} = Credentials.create_credential(@slack)
      assert {:error, changeset} = Credentials.create_credential(@slack)
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update_credential/2" do
    test "keeps a secret left blank" do
      {:ok, credential} = Credentials.create_credential(@slack)

      assert {:ok, _credential} =
               Credentials.update_credential(credential, %{
                 name: "renamed",
                 values: %{"token" => ""}
               })

      assert Credentials.fetch("renamed", "slack") == {:ok, %{"token" => "xoxb-secret"}}
    end

    test "replaces a secret that is given" do
      {:ok, credential} = Credentials.create_credential(@slack)

      {:ok, _credential} =
        Credentials.update_credential(credential, %{values: %{"token" => "xoxb-new"}})

      assert Credentials.fetch("main", "slack") == {:ok, %{"token" => "xoxb-new"}}
    end
  end

  describe "public_values/1" do
    test "leaves secrets out" do
      {:ok, credential} =
        Credentials.create_credential(%{
          name: "files",
          kind: "ftp",
          values: %{"host" => "h", "username" => "u", "password" => "p"}
        })

      assert %{"host" => "h"} = values = Credentials.public_values(credential)
      refute Map.has_key?(values, "password")
    end
  end

  describe "the credentials of a database" do
    test "a SQL one keeps its engine and hides its password" do
      {:ok, credential} =
        Credentials.create_credential(%{
          name: "warehouse",
          kind: "sql",
          values: %{"engine" => "mysql", "database" => "shop", "password" => "p"}
        })

      assert {:ok, %{"engine" => "mysql", "password" => "p", "ssl" => "verify"}} =
               Credentials.fetch("warehouse", "sql")

      refute Map.has_key?(Credentials.public_values(credential), "password")
    end

    test "a connection string counts as a secret, because it holds the password" do
      for {kind, values} <- [
            {"mongodb", %{"url" => "mongodb://u:p@h", "database" => "d"}},
            {"redis", %{"url" => "redis://:p@h"}}
          ] do
        {:ok, credential} =
          Credentials.create_credential(%{name: kind, kind: kind, values: values})

        refute Map.has_key?(Credentials.public_values(credential), "url")
      end
    end

    test "asks for what can't be blank" do
      assert {:error, changeset} =
               Credentials.create_credential(%{name: "r", kind: "redis", values: %{}})

      assert %{kind: [_message]} = errors_on(changeset)
    end
  end

  describe "fetch/2" do
    test "explains what went wrong" do
      {:ok, _credential} = Credentials.create_credential(@slack)

      assert {:error, message} = Credentials.fetch("nope", "slack")
      assert message =~ "no credential"
      assert {:error, message} = Credentials.fetch("main", "s3")
      assert message =~ "is for slack"
      assert {:error, _message} = Credentials.fetch(nil, "slack")
    end

    test "says so when the key changed" do
      {:ok, _credential} = Credentials.create_credential(@slack)
      previous = Application.fetch_env!(:heddle_core, :credentials_secret)

      Application.put_env(:heddle_core, :credentials_secret, "another key")
      on_exit(fn -> Application.put_env(:heddle_core, :credentials_secret, previous) end)

      assert {:error, message} = Credentials.fetch("main", "slack")
      assert message =~ "SECRET_KEY_BASE"
    end
  end
end
