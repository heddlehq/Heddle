defmodule HeddleNodes.Nodes.IntegrationsTest do
  use ExUnit.Case, async: false

  alias HeddleNodes.Integration
  alias HeddleNodes.Nodes.{Csv, Ftp, HttpRequest, S3, Slack}
  alias HeddleNodes.Runner

  defmodule Vault do
    def fetch("main", "slack"), do: {:ok, %{"token" => "xoxb-1"}}

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

  defp capture_slack(reply) do
    Req.Test.stub(HttpRequest, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = if raw == "", do: %{}, else: Jason.decode!(raw)
      send(self(), {:slack, conn, body})
      Req.Test.json(conn, reply)
    end)
  end

  describe "an error in a flow" do
    defp flow(connections) do
      node = fn id, type, controls ->
        %{"id" => id, "type" => type, "label" => type, "controls" => controls}
      end

      link = fn source, output, target ->
        %{
          "source" => source,
          "sourceOutput" => output,
          "target" => target,
          "targetInput" => "exec"
        }
      end

      %{
        id: 1,
        nodes: [
          node.("start", "Start", %{}),
          node.("slack", "Slack: Send Message", %{"credential" => "gone"}),
          node.("ko", "Logger", %{})
        ],
        connections: [
          link.("start", "exec", "slack") | Enum.map(connections, &link.("slack", &1, "ko"))
        ]
      }
    end

    test "fails the run on that node when nobody handles it" do
      assert {:error, message, "slack", _context} = Runner.run(flow([]), %{})
      assert message =~ "gone"
    end

    test "still fails it when only the success output is connected" do
      assert {:error, _message, "slack", _context} = Runner.run(flow(["success"]), %{})
    end

    test "goes on through the error output when it's connected" do
      assert {:ok, context} = Runner.run(flow(["error"]), %{})
      assert context["result"]["error"] =~ "gone"
      assert Enum.any?(context["logs"], &(&1["node_id"] == "ko"))
    end
  end

  describe "Integration.content/2" do
    test "fills in placeholders in text" do
      context = %{"content" => "Hi {{name}}", "name" => "Ana"}

      assert Integration.content(context, "content") == "Hi Ana"
    end

    test "takes the file a Download node returned" do
      text = %{"content" => "{{result}}", "result" => %{"content" => "hello"}}
      binary = put_in(text["result"], %{"content" => "//4=", "encoding" => "base64"})

      assert Integration.content(text, "content") == "hello"
      assert Integration.content(binary, "content") == <<255, 254>>
    end
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

      assert {:ok, result, "success"} = Slack.SendMessage.handler(@context, nil)
      assert result["result"] == %{"channel" => "C1", "ts" => "1.2"}

      assert_received {:request, conn, %{"channel" => "#ops", "text" => "Hi Ana"}}
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xoxb-1"]
    end

    test "takes the error output when Slack refuses it" do
      Req.Test.stub(
        HttpRequest,
        &Req.Test.json(&1, %{"ok" => false, "error" => "channel_not_found"})
      )

      assert {:ok, result, "error"} = Slack.SendMessage.handler(@context, nil)
      assert result["result"]["error"] =~ "channel_not_found"
    end

    test "takes the error output without a credential" do
      assert {:ok, result, "error"} = Slack.SendMessage.handler(%{"credential" => "nope"}, nil)
      assert result["result"]["error"] =~ "nope"
    end

    test "never puts the token in the result" do
      Req.Test.stub(HttpRequest, &Req.Test.json(&1, %{"ok" => true}))

      {:ok, result, "success"} = Slack.SendMessage.handler(@context, nil)

      refute inspect(result) =~ "xoxb-1"
    end

    test "replies in a thread when given one" do
      capture_slack(%{"ok" => true})

      context = Map.put(@context, "thread_ts", "1.1")

      assert {:ok, _context, "success"} = Slack.SendMessage.handler(context, nil)
      assert_received {:slack, conn, %{"thread_ts" => "1.1"}}
      assert conn.request_path == "/api/chat.postMessage"
    end

    test "updates, deletes and reacts to a message from the last step" do
      capture_slack(%{"ok" => true, "channel" => "C1", "ts" => "1.2"})

      context = %{
        "credential" => "main",
        "channel" => "{{result.channel}}",
        "ts" => "{{result.ts}}",
        "text" => "New",
        "emoji" => ":tada:",
        "result" => %{"channel" => "C1", "ts" => "1.2"}
      }

      assert {:ok, _context, "success"} = Slack.UpdateMessage.handler(context, nil)
      assert_received {:slack, conn, %{"channel" => "C1", "ts" => "1.2", "text" => "New"}}
      assert conn.request_path == "/api/chat.update"

      assert {:ok, _context, "success"} = Slack.DeleteMessage.handler(context, nil)
      assert_received {:slack, conn, %{"channel" => "C1", "ts" => "1.2"}}
      assert conn.request_path == "/api/chat.delete"

      assert {:ok, %{"result" => %{"emoji" => "tada"}}, "success"} =
               Slack.AddReaction.handler(context, nil)

      assert_received {:slack, conn, %{"name" => "tada", "timestamp" => "1.2"}}
      assert conn.request_path == "/api/reactions.add"
    end

    test "reads the messages of a channel" do
      message = %{"user" => "U1", "text" => "Hi", "ts" => "1.2", "blocks" => []}
      capture_slack(%{"ok" => true, "messages" => [message]})

      context = %{"credential" => "main", "channel" => "C1", "limit" => "5"}

      assert {:ok, %{"result" => [read]}, "success"} = Slack.ReadMessages.handler(context, nil)
      assert read == %{"user" => "U1", "text" => "Hi", "ts" => "1.2"}
      assert_received {:slack, conn, _body}
      assert conn.method == "GET"
      assert %{"channel" => "C1", "limit" => "5"} = URI.decode_query(conn.query_string)
    end

    test "lists the channels of every page" do
      Req.Test.stub(HttpRequest, fn conn ->
        case URI.decode_query(conn.query_string)["cursor"] do
          "" ->
            Req.Test.json(conn, %{
              "ok" => true,
              "channels" => [%{"id" => "C1", "name" => "a", "is_member" => true}],
              "response_metadata" => %{"next_cursor" => "next"}
            })

          "next" ->
            Req.Test.json(conn, %{"ok" => true, "channels" => [%{"id" => "C2", "name" => "b"}]})
        end
      end)

      assert {:ok, %{"result" => channels}, "success"} =
               Slack.ListChannels.handler(%{"credential" => "main"}, nil)

      assert channels == [%{"id" => "C1", "name" => "a"}, %{"id" => "C2", "name" => "b"}]
    end

    test "uploads a file a Download node returned, in Slack's three steps" do
      test = self()

      Req.Test.stub(HttpRequest, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test, {:step, conn.request_path, conn.query_string, raw})

        case conn.request_path do
          "/api/files.getUploadURLExternal" ->
            Req.Test.json(conn, %{
              "ok" => true,
              "upload_url" => "https://files.slack.com/upload/1",
              "file_id" => "F1"
            })

          "/upload/1" ->
            Plug.Conn.send_resp(conn, 200, "OK")

          "/api/files.completeUploadExternal" ->
            Req.Test.json(conn, %{"ok" => true})
        end
      end)

      context = %{
        "credential" => "main",
        "channel" => "C1",
        "filename" => "a.bin",
        "comment" => "Here",
        "content" => "{{result}}",
        "result" => %{"content" => "//4=", "encoding" => "base64"}
      }

      assert {:ok, %{"result" => %{"file_id" => "F1"}}, "success"} =
               Slack.UploadFile.handler(context, nil)

      assert_received {:step, "/api/files.getUploadURLExternal", query, ""}
      assert %{"filename" => "a.bin", "length" => "2"} = URI.decode_query(query)
      assert_received {:step, "/upload/1", "", <<255, 254>>}
      assert_received {:step, "/api/files.completeUploadExternal", "", raw}

      assert %{"channel_id" => "C1", "initial_comment" => "Here", "files" => [%{"id" => "F1"}]} =
               Jason.decode!(raw)
    end
  end

  describe "Read CSV" do
    test "reads rows by their headers" do
      context = %{"source" => "body", "body" => "name,age\nAna,30\n\"B, C\",40\n"}

      assert {:ok, %{"result" => rows}, "success"} = Csv.Read.handler(context, nil)
      assert rows == [%{"name" => "Ana", "age" => "30"}, %{"name" => "B, C", "age" => "40"}]
    end

    test "uses the separator picked" do
      context = %{"source" => "x", "x" => "a;b\n1;2\n", "separator" => "semicolon"}

      assert {:ok, %{"result" => [%{"a" => "1", "b" => "2"}]}, "success"} =
               Csv.Read.handler(context, nil)
    end

    test "reads the last result by default" do
      assert {:ok, %{"result" => [%{"a" => "1"}]}, "success"} =
               Csv.Read.handler(%{"result" => "a\n1\n"}, nil)
    end

    test "takes the error output when the data is not text" do
      assert {:ok, %{"result" => %{"error" => "x is not text."}}, "error"} =
               Csv.Read.handler(%{"source" => "x", "x" => 1}, nil)

      assert {:ok, %{"result" => %{"error" => "result is not text."}}, "error"} =
               Csv.Read.handler(%{"result" => 1}, nil)
    end
  end

  describe "Write CSV" do
    test "writes rows, quoting what needs it" do
      rows = [%{"name" => "B, C", "age" => 40}, %{"name" => "Ana"}]
      context = %{"source" => "rows", "rows" => rows}

      assert {:ok, %{"result" => csv}, "success"} = Csv.Write.handler(context, nil)
      assert csv == "age,name\n40,\"B, C\"\n,Ana\n"
    end

    test "uses the separator picked" do
      context = %{"source" => "r", "r" => [%{"a" => 1, "b" => 2}], "separator" => "tab"}

      assert {:ok, %{"result" => "a\tb\n1\t2\n"}, "success"} = Csv.Write.handler(context, nil)
    end

    test "writes nothing for an empty list" do
      assert {:ok, %{"result" => ""}, "success"} = Csv.Write.handler(%{"result" => []}, nil)
    end

    test "gives rows Read CSV can read back" do
      rows = [%{"a" => "1", "b" => "x\"y"}]

      {:ok, %{"result" => csv}, _} = Csv.Write.handler(%{"source" => "r", "r" => rows}, nil)

      assert {:ok, %{"result" => ^rows}, _} =
               Csv.Read.handler(%{"source" => "c", "c" => csv}, nil)
    end

    test "takes the error output when the data is not a list of rows" do
      assert {:ok, %{"result" => %{"error" => "x is not a list of rows."}}, "error"} =
               Csv.Write.handler(%{"source" => "x", "x" => "text"}, nil)
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
        "bucket" => "b",
        "key" => "a b/c.txt"
      }

      assert {:ok, %{"result" => %{"content" => "hello"}}, "success"} =
               S3.Download.handler(context, nil)

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

      assert {:ok, %{"result" => result}, "success"} = S3.Download.handler(context, nil)
      assert result == %{"content" => "//4=", "encoding" => "base64"}
    end

    test "puts the bucket in the path of a custom endpoint" do
      capture_s3(&Plug.Conn.send_resp(&1, 200, ""))

      context = %{
        "credential" => "minio",
        "bucket" => "b",
        "key" => "k",
        "content" => "{{x}}",
        "x" => "data"
      }

      assert {:ok, _context, "success"} = S3.Upload.handler(context, nil)
      assert_received {:s3, conn, "data"}
      assert conn.method == "PUT"
      assert conn.host == "m"
      assert conn.request_path == "/b/k"
    end

    test "lists keys" do
      xml = "<R><Contents><Key>a.txt</Key></Contents><Contents><Key>b&amp;c</Key></Contents></R>"
      capture_s3(&Plug.Conn.send_resp(&1, 200, xml))

      context = %{"credential" => "aws", "bucket" => "b", "prefix" => "x/"}

      assert {:ok, %{"result" => %{"keys" => ["a.txt", "b&c"]}}, "success"} =
               S3.List.handler(context, nil)

      assert_received {:s3, conn, ""}
      assert %{"list-type" => "2", "prefix" => "x/"} = URI.decode_query(conn.query_string)
    end

    test "takes the error output with what S3 said" do
      capture_s3(&Plug.Conn.send_resp(&1, 404, "<Error><Code>NoSuchKey</Code></Error>"))

      assert {:ok, %{"result" => %{"error" => message}}, "error"} =
               S3.Download.handler(%{"credential" => "aws", "bucket" => "b", "key" => "k"}, nil)

      assert message =~ "NoSuchKey"
    end

    test "uploads with the content type, and a file from a Download node intact" do
      capture_s3(&Plug.Conn.send_resp(&1, 200, ""))

      context = %{
        "credential" => "aws",
        "bucket" => "b",
        "key" => "k",
        "content" => "{{result}}",
        "content_type" => "image/png",
        "result" => %{"content" => "//4=", "encoding" => "base64"}
      }

      assert {:ok, _context, "success"} = S3.Upload.handler(context, nil)
      assert_received {:s3, conn, <<255, 254>>}
      assert Plug.Conn.get_req_header(conn, "content-type") == ["image/png"]
    end

    test "deletes a file" do
      capture_s3(&Plug.Conn.send_resp(&1, 204, ""))

      context = %{"credential" => "aws", "bucket" => "b", "key" => "k"}

      assert {:ok, %{"result" => %{"key" => "k"}}, "success"} = S3.Delete.handler(context, nil)
      assert_received {:s3, %{method: "DELETE"}, ""}
    end

    test "copies a file without reading it" do
      capture_s3(&Plug.Conn.send_resp(&1, 200, "<CopyObjectResult/>"))

      context = %{
        "credential" => "minio",
        "bucket" => "from",
        "key" => "a b.txt",
        "target_bucket" => "to",
        "target_key" => "c.txt"
      }

      assert {:ok, %{"result" => %{"key" => "c.txt"}}, "success"} = S3.Copy.handler(context, nil)
      assert_received {:s3, conn, ""}
      assert conn.method == "PUT"
      assert conn.request_path == "/to/c.txt"
      assert Plug.Conn.get_req_header(conn, "x-amz-copy-source") == ["/from/a%20b.txt"]
    end

    test "tells about a file without reading it" do
      capture_s3(fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-length", "12")
        |> Plug.Conn.put_resp_header("content-type", "text/plain")
        |> Plug.Conn.put_resp_header("last-modified", "Fri, 06 Nov 2026 10:00:00 GMT")
        |> Plug.Conn.send_resp(200, "")
      end)

      context = %{"credential" => "aws", "bucket" => "b", "key" => "k"}

      assert {:ok, %{"result" => info}, "success"} = S3.Info.handler(context, nil)
      assert %{"size" => 12, "type" => "text/plain", "key" => "k"} = info
      assert_received {:s3, %{method: "HEAD"}, ""}
    end

    test "creates a link that expires, without the secret in it" do
      context = %{"credential" => "aws", "bucket" => "b", "key" => "a b", "expires" => "999999"}

      assert {:ok, %{"result" => %{"url" => url, "expires_in" => 604_800}}, "success"} =
               S3.ShareLink.handler(context, nil)

      uri = URI.parse(url)
      query = URI.decode_query(uri.query)

      assert uri.host == "b.s3.sa-east-1.amazonaws.com"
      assert uri.path == "/a%20b"
      assert query["X-Amz-Expires"] == "604800"
      assert query["X-Amz-Signature"]
      refute url =~ "SK"
    end
  end

  describe "FTP" do
    test "takes the error output when the server can't be reached" do
      assert {:ok, %{"result" => %{"error" => message}}, "error"} =
               Ftp.Download.handler(%{"credential" => "down", "path" => "a"}, nil)

      assert is_binary(message)
    end

    test "takes the error output without a credential" do
      assert {:ok, _context, "error"} = Ftp.List.handler(%{"credential" => "nope"}, nil)
    end
  end
end
