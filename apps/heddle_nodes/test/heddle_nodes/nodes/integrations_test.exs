defmodule HeddleNodes.Nodes.IntegrationsTest do
  use ExUnit.Case, async: false

  alias HeddleNodes.Nodes.{Csv, Email, Ftp, HttpRequest, S3, Slack}

  defmodule Vault do
    def fetch("main", "slack"), do: {:ok, %{"token" => "xoxb-1"}}

    def fetch("mail", "smtp"),
      do: {:ok, %{"host" => "127.0.0.1", "port" => "1", "from" => "a@b.co"}}

    def fetch("aws", "s3") do
      {:ok, %{"access_key_id" => "AK", "secret_access_key" => "SK", "region" => "sa-east-1"}}
    end

    def fetch("minio", "s3") do
      {:ok,
       %{"access_key_id" => "AK", "secret_access_key" => "SK", "endpoint" => "http://m:9000/"}}
    end

    def fetch("down", "ftp") do
      {:ok, %{"host" => "127.0.0.1", "port" => "1", "username" => "u", "password" => "p"}}
    end

    def fetch(name, _kind), do: {:error, "no #{inspect(name)}"}
  end

  setup do
    previous = Application.get_env(:heddle_nodes, :credentials_client)
    Application.put_env(:heddle_nodes, :credentials_client, Vault)
    on_exit(fn -> Application.put_env(:heddle_nodes, :credentials_client, previous) end)
  end

  describe "Slack" do
    @context %{
      "credential" => "main",
      "channel" => "#ops",
      "text" => "Hi {{name}}",
      "name" => "Ana"
    }

    test "posts with the token and fills in the message" do
      Req.Test.stub(HttpRequest, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(self(), {:request, conn, Jason.decode!(raw)})
        Req.Test.json(conn, %{"ok" => true, "channel" => "C1", "ts" => "1.2"})
      end)

      assert {:ok, result, "success"} = Slack.handler(@context, nil)
      assert result["result"] == %{"channel" => "C1", "ts" => "1.2"}

      assert_received {:request, conn, %{"channel" => "#ops", "text" => "Hi Ana"}}
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xoxb-1"]
    end

    test "takes the error output when Slack refuses it" do
      Req.Test.stub(
        HttpRequest,
        &Req.Test.json(&1, %{"ok" => false, "error" => "channel_not_found"})
      )

      assert {:ok, result, "error"} = Slack.handler(@context, nil)
      assert result["result"]["error"] =~ "channel_not_found"
    end

    test "takes the error output without a credential" do
      assert {:ok, result, "error"} = Slack.handler(%{"credential" => "nope"}, nil)
      assert result["result"]["error"] =~ "nope"
    end

    test "never puts the token in the result" do
      Req.Test.stub(HttpRequest, &Req.Test.json(&1, %{"ok" => true}))

      {:ok, result, "success"} = Slack.handler(@context, nil)

      refute inspect(result) =~ "xoxb-1"
    end
  end

  describe "CSV" do
    test "reads rows by their headers" do
      context = %{
        "operation" => "parse",
        "source" => "body",
        "body" => "name,age\nAna,30\n\"B, C\",40\n"
      }

      assert {:ok, %{"result" => rows}, "success"} = Csv.handler(context, nil)
      assert rows == [%{"name" => "Ana", "age" => "30"}, %{"name" => "B, C", "age" => "40"}]
    end

    test "uses the separator picked" do
      context = %{"source" => "x", "x" => "a;b\n1;2\n", "separator" => "semicolon"}

      assert {:ok, %{"result" => [%{"a" => "1", "b" => "2"}]}, "success"} =
               Csv.handler(context, nil)
    end

    test "writes rows back, quoting what needs it" do
      rows = [%{"name" => "B, C", "age" => 40}, %{"name" => "Ana"}]
      context = %{"operation" => "generate", "source" => "rows", "rows" => rows}

      assert {:ok, %{"result" => csv}, "success"} = Csv.handler(context, nil)
      assert csv == "age,name\n40,\"B, C\"\n,Ana\n"
    end

    test "survives a round trip" do
      rows = [%{"a" => "1", "b" => "x\"y"}]

      {:ok, %{"result" => csv}, _} =
        Csv.handler(%{"operation" => "generate", "source" => "r", "r" => rows}, nil)

      assert {:ok, %{"result" => ^rows}, _} = Csv.handler(%{"source" => "c", "c" => csv}, nil)
    end

    test "takes the error output with the wrong data" do
      assert {:ok, _context, "error"} = Csv.handler(%{"source" => "x", "x" => 1}, nil)

      assert {:ok, _context, "error"} =
               Csv.handler(%{"operation" => "generate", "source" => "x", "x" => "text"}, nil)
    end
  end

  describe "Send Email" do
    test "refuses bad addresses before connecting" do
      for to <- ["", "nobody", "a@b.co, nope"] do
        assert {:ok, result, "error"} = Email.handler(%{"credential" => "mail", "to" => to}, nil)
        assert is_binary(result["result"]["error"])
      end
    end

    test "takes the error output when the server can't be reached" do
      context = %{"credential" => "mail", "to" => "x@y.co", "subject" => "s", "message" => "m"}

      assert {:ok, result, "error"} = Email.handler(context, nil)
      assert result["result"]["error"] =~ "email failed"
    end
  end

  describe "S3" do
    defp capture_s3(reply) do
      Req.Test.stub(HttpRequest, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(self(), {:s3, conn, raw})
        reply.(conn)
      end)
    end

    test "signs the request and reads a file on AWS" do
      capture_s3(&Plug.Conn.send_resp(&1, 200, "hello"))

      context = %{
        "credential" => "aws",
        "operation" => "get",
        "bucket" => "b",
        "key" => "a b/c.txt"
      }

      assert {:ok, %{"result" => %{"content" => "hello"}}, "success"} = S3.handler(context, nil)
      assert_received {:s3, conn, ""}
      assert conn.host == "b.s3.sa-east-1.amazonaws.com"
      assert conn.request_path == "/a%20b/c.txt"
      assert [auth] = Plug.Conn.get_req_header(conn, "authorization")
      assert auth =~ "AWS4-HMAC-SHA256 Credential=AK/"
      refute auth =~ "SK"
    end

    test "keeps a binary file safe to save" do
      capture_s3(&Plug.Conn.send_resp(&1, 200, <<255, 254>>))

      context = %{"credential" => "aws", "bucket" => "b", "key" => "k"}

      assert {:ok, %{"result" => result}, "success"} = S3.handler(context, nil)
      assert result == %{"content" => "//4=", "encoding" => "base64"}
    end

    test "puts the bucket in the path of a custom endpoint" do
      capture_s3(&Plug.Conn.send_resp(&1, 200, ""))

      context = %{
        "credential" => "minio",
        "operation" => "put",
        "bucket" => "b",
        "key" => "k",
        "content" => "{{x}}",
        "x" => "data"
      }

      assert {:ok, _context, "success"} = S3.handler(context, nil)
      assert_received {:s3, conn, "data"}
      assert conn.method == "PUT"
      assert conn.host == "m"
      assert conn.request_path == "/b/k"
    end

    test "lists keys" do
      xml = "<R><Contents><Key>a.txt</Key></Contents><Contents><Key>b&amp;c</Key></Contents></R>"
      capture_s3(&Plug.Conn.send_resp(&1, 200, xml))

      context = %{"credential" => "aws", "operation" => "list", "bucket" => "b", "key" => "x/"}

      assert {:ok, %{"result" => %{"keys" => ["a.txt", "b&c"]}}, "success"} =
               S3.handler(context, nil)

      assert_received {:s3, conn, ""}
      assert conn.query_string =~ "list-type=2"
    end

    test "takes the error output with what S3 said" do
      capture_s3(&Plug.Conn.send_resp(&1, 404, "<Error><Code>NoSuchKey</Code></Error>"))

      assert {:ok, %{"result" => %{"error" => message}}, "error"} =
               S3.handler(%{"credential" => "aws", "bucket" => "b", "key" => "k"}, nil)

      assert message =~ "NoSuchKey"
    end
  end

  describe "FTP" do
    test "takes the error output when the server can't be reached" do
      assert {:ok, %{"result" => %{"error" => message}}, "error"} =
               Ftp.handler(%{"credential" => "down", "path" => "a"}, nil)

      assert is_binary(message)
    end

    test "takes the error output without a credential" do
      assert {:ok, _context, "error"} = Ftp.handler(%{"credential" => "nope"}, nil)
    end
  end
end
