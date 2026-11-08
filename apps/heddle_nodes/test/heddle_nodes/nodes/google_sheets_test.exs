defmodule HeddleNodes.Nodes.GoogleSheetsTest do
  use ExUnit.Case, async: false

  alias HeddleNodes.Nodes.HttpRequest
  alias HeddleNodes.Nodes.GoogleSheets.{AddRows, ClearRows, CreateSheet}
  alias HeddleNodes.Nodes.GoogleSheets.{ListSheets, ReadRows, UpdateRows}

  defmodule Vault do
    # A run asks within its workspace, which these tests leave out.
    def fetch(_workspace_id, name, kind), do: fetch(name, kind)

    def fetch("bad", "google"), do: {:ok, %{"json" => "not json"}}

    def fetch("broken-key", "google") do
      {:ok, %{"json" => Jason.encode!(%{client_email: "a@b", private_key: "nope"})}}
    end

    def fetch(_name, "google") do
      {:ok, %{"json" => :persistent_term.get({__MODULE__, :json})}}
    end
  end

  setup_all do
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])

    json = Jason.encode!(%{client_email: "bot@x.iam", private_key: pem})
    :persistent_term.put({Vault, :json}, json)

    %{key: key}
  end

  setup do
    previous = Application.get_env(:heddle_nodes, :credentials_client)
    Application.put_env(:heddle_nodes, :credentials_client, Vault)
    on_exit(fn -> Application.put_env(:heddle_nodes, :credentials_client, previous) end)
  end

  defp stub(reply) do
    Req.Test.stub(HttpRequest, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      if conn.host == "oauth2.googleapis.com" do
        send(self(), {:token, URI.decode_query(raw)})
        Req.Test.json(conn, %{"access_token" => "ya29"})
      else
        send(self(), {:sheets, conn, raw})
        reply.(conn)
      end
    end)
  end

  defp context(fields) do
    Map.merge(
      %{"credential" => "main", "spreadsheet_id" => "ID1", "range" => "Vendas!A:C"},
      fields
    )
  end

  test "signs in with a token the service account's key signed", %{key: key} do
    stub(&Req.Test.json(&1, %{"values" => []}))

    assert {:ok, _context, "success"} = ReadRows.handler(context(%{}), nil)
    assert_received {:token, %{"assertion" => jwt, "grant_type" => grant}}
    assert grant =~ "jwt-bearer"

    [header, claims, signature] = String.split(jwt, ".")
    public = {:RSAPublicKey, elem(key, 2), elem(key, 3)}

    assert :public_key.verify(
             header <> "." <> claims,
             :sha256,
             Base.url_decode64!(signature, padding: false),
             public
           )

    assert %{"iss" => "bot@x.iam", "scope" => scope} =
             claims |> Base.url_decode64!(padding: false) |> Jason.decode!()

    assert scope =~ "spreadsheets"
  end

  test "reads rows with the token" do
    stub(&Req.Test.json(&1, %{"values" => [["a", "b"], ["1", "2"]]}))

    assert {:ok, %{"result" => [["a", "b"], ["1", "2"]]}, "success"} =
             ReadRows.handler(context(%{}), nil)

    assert_received {:sheets, conn, ""}
    assert conn.request_path == "/v4/spreadsheets/ID1/values/Vendas%21A%3AC"
    assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer ya29"]
  end

  test "an empty sheet has no rows" do
    stub(&Req.Test.json(&1, %{}))

    assert {:ok, %{"result" => []}, "success"} = ReadRows.handler(context(%{}), nil)
  end

  test "adds rows from a list of maps" do
    stub(&Req.Test.json(&1, %{"updates" => %{"updatedRows" => 2}}))

    fields = %{
      "rows" => "data",
      "data" => [%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}]
    }

    assert {:ok, %{"result" => %{"updated_rows" => 2}}, "success"} =
             AddRows.handler(context(fields), nil)

    assert_received {:sheets, conn, raw}
    assert String.ends_with?(conn.request_path, "%3AC:append")
    assert conn.query_string == "valueInputOption=USER_ENTERED"
    assert Jason.decode!(raw) == %{"values" => [[1, 2], [3, 4]]}
  end

  test "adds a single row" do
    stub(&Req.Test.json(&1, %{}))

    fields = %{"rows" => "row", "row" => ["x", 1]}

    assert {:ok, _context, "success"} = AddRows.handler(context(fields), nil)
    assert_received {:sheets, _conn, raw}
    assert Jason.decode!(raw) == %{"values" => [["x", 1]]}
  end

  test "takes the error output with no rows to add" do
    stub(&Req.Test.json(&1, %{}))

    fields = %{"rows" => "missing"}

    assert {:ok, _context, "error"} = AddRows.handler(context(fields), nil)
  end

  test "takes the error output with what Google said" do
    stub(fn conn ->
      conn
      |> Plug.Conn.put_status(403)
      |> Req.Test.json(%{"error" => %{"message" => "The caller does not have permission"}})
    end)

    assert {:ok, %{"result" => %{"error" => message}}, "error"} =
             ReadRows.handler(context(%{}), nil)

    assert message =~ "permission"
  end

  test "takes the error output with a bad credential" do
    assert {:ok, %{"result" => %{"error" => message}}, "error"} =
             ReadRows.handler(context(%{"credential" => "bad"}), nil)

    assert message =~ "service account"

    assert {:ok, %{"result" => %{"error" => message}}, "error"} =
             ReadRows.handler(context(%{"credential" => "broken-key"}), nil)

    assert message =~ "can't be read"
  end

  test "writes rows over a range" do
    stub(&Req.Test.json(&1, %{"updatedRows" => 1}))

    fields = %{"rows" => "row", "row" => ["x", 1]}

    assert {:ok, %{"result" => %{"updated_rows" => 1}}, "success"} =
             UpdateRows.handler(context(fields), nil)

    assert_received {:sheets, conn, raw}
    assert conn.method == "PUT"
    assert conn.request_path == "/v4/spreadsheets/ID1/values/Vendas%21A%3AC"
    assert conn.query_string == "valueInputOption=USER_ENTERED"
    assert Jason.decode!(raw) == %{"values" => [["x", 1]]}
  end

  test "clears a range" do
    stub(&Req.Test.json(&1, %{"clearedRange" => "Vendas!A1:C9"}))

    assert {:ok, %{"result" => %{"cleared_range" => "Vendas!A1:C9"}}, "success"} =
             ClearRows.handler(context(%{}), nil)

    assert_received {:sheets, conn, _raw}
    assert conn.method == "POST"
    assert String.ends_with?(conn.request_path, "%3AC:clear")
  end

  test "lists the sheets" do
    sheets = [%{"properties" => %{"sheetId" => 7, "title" => "Vendas"}}]
    stub(&Req.Test.json(&1, %{"sheets" => sheets}))

    assert {:ok, %{"result" => [%{"id" => 7, "title" => "Vendas"}]}, "success"} =
             ListSheets.handler(context(%{}), nil)

    assert_received {:sheets, conn, _raw}
    assert conn.request_path == "/v4/spreadsheets/ID1"
  end

  test "creates a sheet" do
    reply = %{"replies" => [%{"addSheet" => %{"properties" => %{"sheetId" => 9}}}]}
    stub(&Req.Test.json(&1, reply))

    assert {:ok, %{"result" => %{"id" => 9, "title" => "Maio"}}, "success"} =
             CreateSheet.handler(context(%{"title" => "Maio"}), nil)

    assert_received {:sheets, conn, raw}
    assert conn.request_path == "/v4/spreadsheets/ID1:batchUpdate"

    assert %{"requests" => [%{"addSheet" => %{"properties" => %{"title" => "Maio"}}}]} =
             Jason.decode!(raw)
  end
end
