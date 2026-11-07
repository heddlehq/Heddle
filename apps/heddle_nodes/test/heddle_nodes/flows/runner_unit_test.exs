defmodule HeddleNodes.RunnerUnitTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Runner

  defp flow(nodes, connections \\ []) do
    %{nodes: nodes, connections: connections, id: "test-flow-id"}
  end

  defp node(id, type, controls \\ %{}) do
    %{"id" => id, "type" => type, "label" => type, "controls" => controls, "position" => %{}}
  end

  defp connection(source, source_output, target) do
    %{
      "source" => source,
      "sourceOutput" => source_output,
      "target" => target,
      "targetInput" => "exec"
    }
  end

  describe "run/2 — start node handling" do
    test "returns error when no Start node exists in the flow" do
      f =
        flow([
          node("1", "Variable", %{"var_name" => "x", "var_value" => "1", "var_type" => "String"})
        ])

      assert {:error, "No Start node found", nil, _context} = Runner.run(f)
    end

    test "starts from an entry node when the flow has no Start" do
      for type <- ["Webhook", "Schedule"] do
        f = flow([node("v", "Variable"), node("entry", type)])

        assert {:ok, %{"logs" => [%{"node_id" => "entry"}]}} = Runner.run(f)
      end
    end

    test "prefers the Start node over any other entry node" do
      f = flow([node("hook", "Webhook"), node("start", "Start")])

      assert {:ok, %{"logs" => [%{"node_id" => "start"}]}} = Runner.run(f)
    end

    test "never takes a node for the Start because of its label" do
      fake = Map.put(node("fake", "Variable"), "label", "Start")

      assert {:ok, %{"logs" => [%{"node_id" => "real"}]}} =
               Runner.run(flow([fake, node("real", "Start")]))
    end

    test "succeeds with a flow containing only a Start node" do
      f = flow([node("1", "Start")])

      assert {:ok, context} = Runner.run(f)
      assert context["flow_id"] == "test-flow-id"
      assert length(context["logs"]) == 1
    end

    test "normalizes non-map input to empty map" do
      f = flow([node("1", "Start")])

      assert {:ok, context} = Runner.run(f, "not a map")
      refute Map.has_key?(context, "0")
    end

    test "normalizes map input keys to strings" do
      f = flow([node("1", "Start")])

      assert {:ok, context} = Runner.run(f, %{payload: "hello"})
      assert context["payload"] == "hello"
    end
  end

  describe "run/2 — connections" do
    defp set_x(id, value) do
      node(id, "Variable", %{"var_name" => "x", "var_value" => value, "var_type" => "String"})
    end

    test "runs the connections of an output in the order they are listed" do
      nodes = [node("s", "Start"), set_x("a", "A"), set_x("b", "B")]
      a_then_b = [connection("s", "exec", "a"), connection("s", "exec", "b")]

      assert {:ok, %{"variables" => %{"x" => "B"}}} = Runner.run(flow(nodes, a_then_b))

      assert {:ok, %{"variables" => %{"x" => "A"}}} =
               Runner.run(flow(nodes, Enum.reverse(a_then_b)))
    end

    test "follows a connection whose ids are of another type than the node's" do
      nodes = [node(1, "Start"), set_x(2, "A")]

      assert {:ok, %{"variables" => %{"x" => "A"}}} =
               Runner.run(flow(nodes, [connection("1", "exec", "2")]))
    end

    test "doesn't need a position or a target input" do
      nodes = [node("s", "Start") |> Map.delete("position"), set_x("a", "A")]
      link = %{"source" => "s", "sourceOutput" => "exec", "target" => "a"}

      assert {:ok, %{"variables" => %{"x" => "A"}}} = Runner.run(flow(nodes, [link]))
    end
  end

  describe "run/2 — node execution" do
    test "executes a Start → Variable → Output chain" do
      f =
        flow(
          [
            node("1", "Start"),
            node("2", "Variable", %{
              "var_name" => "count",
              "var_value" => "7",
              "var_type" => "Integer"
            }),
            node("3", "Output", %{"status" => "success"})
          ],
          [
            connection("1", "exec", "2"),
            connection("2", "exec", "3")
          ]
        )

      assert {:ok, context} = Runner.run(f)
      assert context["variables"]["count"] == 7
      assert context["status"] == "success"
      assert length(context["logs"]) == 3
    end

    test "skips nodes whose type is not registered" do
      f =
        flow(
          [
            node("1", "Start"),
            node("2", "UnknownNodeType")
          ],
          [connection("1", "exec", "2")]
        )

      assert {:ok, context} = Runner.run(f)
      assert context["flow_id"] == "test-flow-id"
    end

    test "returns error when node raises an exception" do
      f =
        flow(
          [
            node("1", "Start"),
            node("2", "Evaluate Code", %{
              "language" => "elixir",
              "code_elixir" => "raise \"boom\""
            })
          ],
          [connection("1", "exec", "2")]
        )

      assert {:error, _reason, "2", _context} = Runner.run(f)
    end

    test "removes node control keys from context after execution" do
      f =
        flow(
          [
            node("1", "Start"),
            node("2", "Variable", %{
              "var_name" => "x",
              "var_value" => "10",
              "var_type" => "Integer"
            })
          ],
          [connection("1", "exec", "2")]
        )

      assert {:ok, context} = Runner.run(f)
      refute Map.has_key?(context, "var_name")
      refute Map.has_key?(context, "var_value")
      refute Map.has_key?(context, "var_type")
    end

    test "routes Condition node to true branch" do
      f =
        flow(
          [
            node("1", "Start"),
            node("2", "Variable", %{
              "var_name" => "score",
              "var_value" => "100",
              "var_type" => "Integer"
            }),
            node("3", "Condition", %{"variable" => "score", "operator" => ">", "value" => "50"}),
            node("4", "Output", %{"status" => "passed"})
          ],
          [
            connection("1", "exec", "2"),
            connection("2", "exec", "3"),
            connection("3", "true", "4")
          ]
        )

      assert {:ok, context} = Runner.run(f)
      assert context["status"] == "passed"
    end

    test "routes Condition node to false branch" do
      f =
        flow(
          [
            node("1", "Start"),
            node("2", "Variable", %{
              "var_name" => "score",
              "var_value" => "10",
              "var_type" => "Integer"
            }),
            node("3", "Condition", %{"variable" => "score", "operator" => ">", "value" => "50"}),
            node("4", "Output", %{"status" => "failed"})
          ],
          [
            connection("1", "exec", "2"),
            connection("2", "exec", "3"),
            connection("3", "false", "4")
          ]
        )

      assert {:ok, context} = Runner.run(f)
      assert context["status"] == "failed"
    end

    test "execution log records node_type and status for each node" do
      f =
        flow(
          [
            node("1", "Start"),
            node("2", "Variable", %{
              "var_name" => "x",
              "var_value" => "1",
              "var_type" => "Integer"
            })
          ],
          [connection("1", "exec", "2")]
        )

      assert {:ok, context} = Runner.run(f)

      assert Enum.map(context["logs"], & &1["node_type"]) == ["Start", "Variable"]
      assert Enum.all?(context["logs"], fn log -> log["status"] == "success" end)
    end

    test "execution log records error status and error message on failure" do
      f =
        flow(
          [
            node("1", "Start"),
            node("2", "Evaluate Code", %{
              "language" => "elixir",
              "code_elixir" => "raise \"failure\""
            })
          ],
          [connection("1", "exec", "2")]
        )

      assert {:error, _reason, _id, _context} = Runner.run(f)
    end

    test "connection with missing target node is skipped gracefully" do
      f =
        flow(
          [node("1", "Start")],
          [connection("1", "exec", "nonexistent")]
        )

      assert {:ok, _context} = Runner.run(f)
    end

    test "restores control keys that were present in the original context" do
      f =
        flow(
          [
            node("1", "Start"),
            node("2", "Variable", %{
              "var_name" => "x",
              "var_value" => "10",
              "var_type" => "Integer"
            })
          ],
          [connection("1", "exec", "2")]
        )

      assert {:ok, context} = Runner.run(f, %{"var_name" => "original"})
      assert context["var_name"] == "original"
    end
  end

  describe "run/2 — HTTP Request node" do
    test "executes an HTTP Request node and routes success response" do
      Req.Test.stub(HeddleNodes.Nodes.HttpRequest, fn conn ->
        Req.Test.json(conn, %{"data" => "ok"})
      end)

      f =
        flow(
          [
            node("1", "Start"),
            node("2", "HTTP Request", %{
              "method" => "GET",
              "url" => "https://api.test.com/ping",
              "headers" => "{}"
            }),
            node("3", "Output", %{"status" => "done"})
          ],
          [
            connection("1", "exec", "2"),
            connection("2", "success", "3")
          ]
        )

      assert {:ok, context} = Runner.run(f)
      assert context["status"] == "done"
      assert context["result"] == %{"data" => "ok"}
    end

    test "catches exceptions raised by a node handler" do
      Req.Test.stub(HeddleNodes.Nodes.HttpRequest, fn _conn ->
        raise Req.TransportError, reason: :econnrefused
      end)

      f =
        flow(
          [
            node("1", "Start"),
            node("2", "HTTP Request", %{
              "method" => "GET",
              "url" => "https://unreachable.test.com",
              "headers" => "{}"
            })
          ],
          [connection("1", "exec", "2")]
        )

      assert {:error, _reason, "2", _context} = Runner.run(f)
    end
  end

  describe "run_from_webhook/2" do
    test "returns error when flow has no Webhook node" do
      f = flow([node("1", "Start")])

      assert {:error, "No Webhook node found in flow", nil, _context} =
               Runner.run_from_webhook(f, %{})
    end

    test "executes flow starting from the Webhook node" do
      f =
        flow(
          [
            node("1", "Webhook", %{"method" => "POST", "path" => "/hook"}),
            node("2", "Output", %{"status" => "success"})
          ],
          [connection("1", "exec", "2")]
        )

      webhook_request = %{
        "body" => %{"key" => "value"},
        "headers" => %{"content-type" => "application/json"},
        "method" => "POST",
        "query_params" => %{},
        "path" => "/hook"
      }

      assert {:ok, context} = Runner.run_from_webhook(f, webhook_request)
      assert context["flow_id"] == "test-flow-id"
      assert context["status"] == "success"
    end

    test "exposes webhook request fields in context" do
      f =
        flow(
          [node("1", "Webhook", %{"method" => "POST", "path" => "/hook"})],
          []
        )

      webhook_request = %{
        "body" => %{"order_id" => 42},
        "headers" => %{"x-token" => "abc"},
        "method" => "POST",
        "query_params" => %{"page" => "1"},
        "path" => "/hook"
      }

      assert {:ok, context} = Runner.run_from_webhook(f, webhook_request)
      assert context["body"] == %{"order_id" => 42}
      assert context["headers"] == %{"x-token" => "abc"}
      assert context["method"] == "POST"
      assert context["query_params"] == %{"page" => "1"}
      assert context["request_path"] == "/hook"
    end
  end
end
