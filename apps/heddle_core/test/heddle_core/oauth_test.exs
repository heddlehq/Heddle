defmodule HeddleCore.OAuthTest do
  use HeddleCore.DataCase

  alias HeddleCore.ApiKeys
  alias HeddleCore.ApiKeys.ApiKey
  alias HeddleCore.OAuth
  alias HeddleCore.OAuth.AuthorizationCode
  alias HeddleCore.Repo

  import HeddleCore.AccountsFixtures

  @redirect_uri "http://127.0.0.1:53124/callback"
  @verifier String.duplicate("a", 64)

  defp challenge(verifier \\ @verifier) do
    :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
  end

  defp code_for(user) do
    client = OAuth.get_client("treadle")
    workspace = ensure_workspace(user)

    {:ok, code} =
      OAuth.create_authorization_code(user, workspace.id, client, @redirect_uri, challenge())

    code
  end

  defp exchange(code, overrides \\ %{}) do
    %{
      "code" => code,
      "code_verifier" => @verifier,
      "redirect_uri" => @redirect_uri,
      "client_id" => "treadle"
    }
    |> Map.merge(overrides)
    |> OAuth.exchange_code()
  end

  describe "valid_redirect_uri?/1" do
    test "accepts loopback addresses on any port" do
      assert OAuth.valid_redirect_uri?("http://127.0.0.1:53124/callback")
      assert OAuth.valid_redirect_uri?("http://localhost:8080/callback")
      assert OAuth.valid_redirect_uri?("http://[::1]:8080/callback")
    end

    test "rejects everything else" do
      refute OAuth.valid_redirect_uri?("https://evil.example/callback")
      refute OAuth.valid_redirect_uri?("http://evil.example:8080/callback")
      refute OAuth.valid_redirect_uri?("http://127.0.0.1.evil.example:8080/callback")
      refute OAuth.valid_redirect_uri?("http://127.0.0.1@evil.example:8080/callback")
      refute OAuth.valid_redirect_uri?("http://user@127.0.0.1:8080/callback")
      refute OAuth.valid_redirect_uri?("https://127.0.0.1:8080/callback")
      refute OAuth.valid_redirect_uri?("http://127.0.0.1:8080/callback#fragment")
      refute OAuth.valid_redirect_uri?("javascript:alert(1)")
      refute OAuth.valid_redirect_uri?(nil)
    end
  end

  describe "exchange_code/1" do
    test "returns an API key that works, with the client's scopes" do
      user = user_fixture()

      assert {:ok, %{access_token: token, scopes: scopes}} = exchange(code_for(user))

      assert {:ok, %ApiKey{} = api_key} = ApiKeys.authenticate(token)
      assert api_key.user_id == user.id
      assert api_key.scopes == scopes
      assert "workflows:write" in scopes
      refute "admin" in scopes
    end

    test "stores only a hash of the code" do
      code = code_for(user_fixture())

      record = Repo.one!(AuthorizationCode)

      refute record.code_hash == code
      assert record.code_hash == ApiKeys.hash_token(code)
    end

    test "works once" do
      code = code_for(user_fixture())

      assert {:ok, _token} = exchange(code)
      assert {:error, :invalid_grant} = exchange(code)
    end

    test "rejects a wrong verifier, and the code can't be retried" do
      code = code_for(user_fixture())

      assert {:error, :invalid_grant} =
               exchange(code, %{"code_verifier" => String.duplicate("b", 64)})

      assert {:error, :invalid_grant} = exchange(code)
    end

    test "rejects a different redirect_uri or client" do
      user = user_fixture()

      assert {:error, :invalid_grant} =
               exchange(code_for(user), %{"redirect_uri" => "http://127.0.0.1:1/callback"})

      assert {:error, :invalid_grant} = exchange(code_for(user), %{"client_id" => "other"})
    end

    test "rejects an expired code" do
      code = code_for(user_fixture())

      past = DateTime.add(DateTime.utc_now(:second), -1, :second)
      Repo.update_all(AuthorizationCode, set: [expires_at: past])

      assert {:error, :invalid_grant} = exchange(code)
    end

    test "rejects an unknown code and malformed params" do
      assert {:error, :invalid_grant} = exchange("nope")
      assert {:error, :invalid_grant} = OAuth.exchange_code(%{})
      assert {:error, :invalid_grant} = OAuth.exchange_code(%{"code" => %{"a" => "b"}})
    end
  end

  describe "create_authorization_code/5" do
    test "the token reaches the workspace picked, within the person's role there" do
      user = user_fixture()
      workspace = workspace_fixture(user, role: "viewer")
      client = OAuth.get_client("treadle")

      {:ok, code} =
        OAuth.create_authorization_code(user, workspace.id, client, @redirect_uri, challenge())

      assert {:ok, %{access_token: token, scopes: scopes}} = exchange(code)
      assert {:ok, %ApiKey{workspace_id: id}} = ApiKeys.authenticate(token)
      assert id == workspace.id
      assert "workflows:read" in scopes
      refute "workflows:write" in scopes
    end

    test "refuses a workspace the person isn't in" do
      other = workspace_fixture(user_fixture())

      assert {:error, :forbidden} =
               OAuth.create_authorization_code(
                 user_fixture(),
                 other.id,
                 OAuth.get_client("treadle"),
                 @redirect_uri,
                 challenge()
               )
    end
  end
end
