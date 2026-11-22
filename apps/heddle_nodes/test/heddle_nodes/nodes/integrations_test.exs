defmodule HeddleNodes.Nodes.IntegrationsTest do
  use ExUnit.Case, async: false

  alias HeddleNodes.Integration
  alias HeddleNodes.Nodes.Csv
  alias HeddleNodes.Runner

  defmodule Vault do
    # Tells the test which workspace a run looked in.
    def fetch(workspace_id, name, kind) do
      send(self(), {:credential_workspace, workspace_id})
      fetch(name, kind)
    end

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

  describe "the workspace of a run" do
    test "a node looks for its credential in its flow's workspace, whatever the run sets" do
      flow = %{
        id: 1,
        workspace_id: 42,
        nodes: [
          %{"id" => "start", "type" => "Start", "label" => "Start", "controls" => %{}},
          %{
            "id" => "slack",
            "type" => "Slack: Send Message",
            "label" => "Slack",
            "controls" => %{
              "credential" => "main",
              "channel" => "#general",
              "text" => "hi",
              "workspace_id" => 999,
              "flow_id" => 7
            }
          }
        ],
        connections: [
          %{
            "source" => "start",
            "sourceOutput" => "exec",
            "target" => "slack",
            "targetInput" => "exec"
          }
        ]
      }

      Runner.run(flow, %{"workspace_id" => 5})

      assert_received {:credential_workspace, 42}
      refute_received {:credential_workspace, _other}
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
end
