defmodule HeddleNodes.ErrorHandlingTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Runner

  defp flow(nodes, connections), do: %{nodes: nodes, connections: connections, id: "flow-id"}

  defp node(id, type, controls \\ %{}, settings \\ nil) do
    %{"id" => id, "type" => type, "label" => type, "controls" => controls}
    |> then(&if(settings, do: Map.put(&1, "settings", settings), else: &1))
  end

  defp code(id, elixir, settings \\ nil) do
    node(id, "Evaluate Code", %{"language" => "elixir", "code_elixir" => elixir}, settings)
  end

  defp wire(source, output, target) do
    %{"source" => source, "sourceOutput" => output, "target" => target, "targetInput" => "exec"}
  end

  defp ran(context), do: Enum.map(context["logs"], &{&1["node_id"], &1["status"]})

  # A step that fails until it has run `failures` times, then answers "ok".
  defp flaky(id, failures, settings) do
    key = :"#{__MODULE__}.#{id}.#{System.unique_integer([:positive])}"
    :persistent_term.put(key, :counters.new(1, []))

    code(
      id,
      """
      counter = :persistent_term.get(#{inspect(key)})
      :counters.add(counter, 1, 1)
      if :counters.get(counter, 1) <= #{failures}, do: raise("try #{id} failed"), else: "ok"
      """,
      settings
    )
  end

  defp no_sleep(test_pid \\ self()), do: [sleep: &send(test_pid, {:slept, &1})]

  describe "retries" do
    test "runs a failing step again, waiting between tries, until it works" do
      f =
        flow(
          [node("start", "Start"), flaky("api", 2, %{"retries" => 3, "retry_delay" => 1.5})],
          [wire("start", "exec", "api")]
        )

      assert {:ok, context} = Runner.run(f, %{}, no_sleep())
      assert context["result"] == "ok"
      assert_received {:slept, 1500}
      assert_received {:slept, 1500}
      refute_received {:slept, _ms}

      step = List.last(context["logs"])
      assert step["status"] == "success"
      assert step["attempts"] == 3
      assert [first, _second] = step["retry_errors"]
      assert first =~ "try api failed"
    end

    test "waits twice as long after each try with an exponential backoff" do
      settings = %{"retries" => 3, "retry_delay" => 1, "retry_backoff" => "exponential"}

      f =
        flow([node("start", "Start"), flaky("api", 3, settings)], [wire("start", "exec", "api")])

      assert {:ok, _context} = Runner.run(f, %{}, no_sleep())
      assert_received {:slept, 1000}
      assert_received {:slept, 2000}
      assert_received {:slept, 4000}
    end

    test "fails the run once no try is left" do
      f =
        flow(
          [node("start", "Start"), flaky("api", 5, %{"retries" => 1})],
          [wire("start", "exec", "api")]
        )

      assert {:error, message, "api", context} = Runner.run(f, %{}, no_sleep())
      assert message =~ "try api failed"
      assert %{"status" => "error", "attempts" => 2} = List.last(context["logs"])
    end

    test "also runs again a service node that answered through its error output" do
      f =
        flow(
          [
            node("start", "Start"),
            node("http", "HTTP Request", %{"url" => "http://127.0.0.1:1/down"}, %{"retries" => 2})
          ],
          [wire("start", "exec", "http")]
        )

      assert {:error, _message, "http", context} = Runner.run(f, %{}, no_sleep())
      assert %{"attempts" => 3} = List.last(context["logs"])
    end
  end

  describe "on_error" do
    test "continue goes on through the usual output, with the error as the result" do
      f =
        flow(
          [
            node("start", "Start"),
            code("broken", ~s(raise "it broke"), %{"on_error" => "continue"}),
            code("after", ~s{"got: " <> result["error"]})
          ],
          [wire("start", "exec", "broken"), wire("broken", "exec", "after")]
        )

      assert {:ok, context} = Runner.run(f)
      assert "got: " <> message = context["result"]
      assert message =~ "it broke"
      assert %{"result" => %{"error" => ^message}} = Enum.at(context["logs"], 1)["data"]["output"]
      assert ran(context) == [{"start", "success"}, {"broken", "error"}, {"after", "success"}]
      assert %{"continued" => true} = Enum.at(context["logs"], 1)
    end

    test "output sends the failure down an error output any node can have" do
      f =
        flow(
          [
            node("start", "Start"),
            code("broken", ~s(raise "it broke"), %{"on_error" => "output"}),
            code("fine", ~s("never")),
            code("handler", ~s("handled"))
          ],
          [
            wire("start", "exec", "broken"),
            wire("broken", "exec", "fine"),
            wire("broken", "error", "handler")
          ]
        )

      assert {:ok, context} = Runner.run(f)
      assert context["result"] == "handled"
      assert ran(context) == [{"start", "success"}, {"broken", "error"}, {"handler", "success"}]
    end

    test "stop fails the run when nothing is connected to the error output" do
      f =
        flow(
          [node("start", "Start"), code("broken", ~s(raise "it broke"))],
          [wire("start", "exec", "broken")]
        )

      assert {:error, message, "broken", _context} = Runner.run(f)
      assert message =~ "it broke"
    end
  end

  describe "pins" do
    defp pinned_flow do
      pin = %{"pin" => %{"output" => "exec", "data" => %{"result" => %{"id" => 7}}}}

      flow(
        [
          node("start", "Start"),
          code("api", ~s(raise "the real API was called"), pin),
          code("after", ~s{result["id"] + 1})
        ],
        [wire("start", "exec", "api"), wire("api", "exec", "after")]
      )
    end

    test "a run from the editor takes the pinned data instead of running the node" do
      assert {:ok, context} = Runner.run(pinned_flow(), %{}, debug: true)
      assert context["result"] == 8
      assert %{"pinned" => true, "status" => "success"} = Enum.at(context["logs"], 1)
    end

    test "any other run ignores them" do
      assert {:error, message, "api", _context} = Runner.run(pinned_flow())
      assert message =~ "the real API was called"
    end
  end

  describe "trace" do
    test "each step keeps its timing, the context it got and what it changed" do
      f =
        flow(
          [
            node("start", "Start"),
            node("var", "Variable", %{"var_name" => "name", "var_value" => "Ana"}),
            code("greet", ~s{"Hello " <> variable(:name)})
          ],
          [wire("start", "exec", "var"), wire("var", "exec", "greet")]
        )

      assert {:ok, context} =
               Runner.run(f, %{"trigger" => "manual"}, on_step: &send(self(), {:step, &1}))

      step = List.last(context["logs"])
      assert step["data"]["input"]["variables"] == %{"name" => "Ana"}
      assert step["data"]["output"] == %{"result" => "Hello Ana"}
      assert is_number(step["duration_ms"])
      assert {:ok, _at, _offset} = DateTime.from_iso8601(step["started_at"])
      refute Map.has_key?(step["data"]["input"], "logs")

      assert_received {:step, %{"node_id" => "start"}}
      assert_received {:step, %{"node_id" => "greet"}}
    end

    test "a For Each leaves a step when it ends, with what its items gave" do
      f =
        flow(
          [
            node("start", "Start"),
            node("each", "For Each", %{"items" => "list"}),
            code("double", "result * 2")
          ],
          [wire("start", "exec", "each"), wire("each", "item", "double")]
        )

      assert {:ok, context} = Runner.run(f, %{"list" => [1, 2]})

      assert Enum.map(context["logs"], &{&1["node_id"], &1["output"]}) == [
               {"start", "exec"},
               {"each", "item"},
               {"double", "exec"},
               {"double", "exec"},
               {"each", "done"}
             ]

      assert %{"data" => %{"output" => %{"result" => [2, 4]}}} = List.last(context["logs"])
    end

    test "a step can run again from the context it got" do
      f =
        flow(
          [
            node("start", "Start"),
            code("first", ~s(raise "must not run")),
            code("second", ~s{variable(:name) <> "!"})
          ],
          [wire("start", "exec", "first"), wire("first", "exec", "second")]
        )

      input = %{"name" => "Ana", "replay_from" => "second", "debug" => true}

      assert {:ok, context} = Runner.run(f, input)
      assert context["result"] == "Ana!"
      refute Map.has_key?(context, "replay_from")
      assert ran(context) == [{"second", "success"}]
    end

    test "running from a node that is gone says so" do
      f = flow([node("start", "Start")], [])

      assert {:error, "This node is no longer in the flow.", nil, _context} =
               Runner.run(f, %{"replay_from" => "gone"})
    end
  end

  test "a run of a failed flow begins at its Error Trigger" do
    f =
      flow(
        [
          node("start", "Start"),
          node("on_error", "Error Trigger"),
          code("alert", ~s{"alert: " <> variable(:error)["message"]})
        ],
        [wire("on_error", "exec", "alert")]
      )

    input = %{"trigger" => "error", "error" => %{"message" => "boom"}}

    assert {:ok, context} = Runner.run(f, input)
    assert context["result"] == "alert: boom"
  end
end
