defmodule HeddleNodes.FlowControlTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Runner

  defp flow(nodes, connections) do
    %{nodes: nodes, connections: connections, id: "flow-id"}
  end

  defp node(id, type, controls \\ %{}) do
    %{"id" => id, "type" => type, "label" => type, "controls" => controls}
  end

  defp code(id, elixir) do
    node(id, "Evaluate Code", %{"language" => "elixir", "code_elixir" => elixir})
  end

  defp wire(source, output, target) do
    %{"source" => source, "sourceOutput" => output, "target" => target, "targetInput" => "exec"}
  end

  defp ran(context), do: Enum.map(context["logs"], &{&1["node_id"], &1["output"]})

  # What the worker does: the pause goes to the database and comes back as JSON.
  defp saved(paused), do: paused |> Jason.encode!() |> Jason.decode!()

  defp resume(flow, paused, by \\ %{"by" => "time"}), do: Runner.resume(flow, saved(paused), by)

  describe "Switch" do
    defp switch(cases) do
      controls = Map.merge(%{"switch_value" => "{{status}}"}, cases)
      node("switch", "Switch", controls)
    end

    test "goes down the output of the first case equal to the value" do
      f =
        flow(
          [
            node("start", "Start"),
            switch(%{"case_1" => "pending", "case_2" => "paid", "case_3" => "paid"}),
            code("paid", ~s("paid branch")),
            code("third", ~s("third branch"))
          ],
          [
            wire("start", "exec", "switch"),
            wire("switch", "case 2", "paid"),
            wire("switch", "case 3", "third")
          ]
        )

      assert {:ok, context} = Runner.run(f, %{"status" => "paid"})
      assert ran(context) == [{"start", "exec"}, {"switch", "case 2"}, {"paid", "exec"}]
      assert context["result"] == "paid branch"
    end

    test "goes down otherwise when no case is equal, and an empty case never is" do
      f =
        flow(
          [node("start", "Start"), switch(%{"case_1" => "", "case_2" => "paid"})],
          [wire("start", "exec", "switch")]
        )

      assert {:ok, context} = Runner.run(f, %{"status" => ""})
      assert List.last(ran(context)) == {"switch", "otherwise"}
    end

    test "fills placeholders in the cases" do
      f =
        flow(
          [node("start", "Start"), switch(%{"case_1" => "{{expected}}"})],
          [wire("start", "exec", "switch")]
        )

      assert {:ok, context} = Runner.run(f, %{"status" => "ok", "expected" => "ok"})
      assert List.last(ran(context)) == {"switch", "case 1"}
    end
  end

  describe "Merge" do
    test "waits for every branch, then goes on once with their results" do
      f =
        flow(
          [
            node("start", "Start"),
            code("a", ~s("A")),
            code("b", ~s("B")),
            node("merge", "Merge"),
            code("after", "result")
          ],
          [
            wire("start", "exec", "a"),
            wire("start", "exec", "b"),
            wire("a", "exec", "merge"),
            wire("b", "exec", "merge"),
            wire("merge", "exec", "after")
          ]
        )

      assert {:ok, context} = Runner.run(f)

      assert ran(context) == [
               {"start", "exec"},
               {"a", "exec"},
               {"b", "exec"},
               {"merge", "exec"},
               {"after", "exec"}
             ]

      assert context["result"] == ["A", "B"]
      refute Map.has_key?(context, "_merging")
    end

    test "goes on with the branches that came, when the others never can" do
      f =
        flow(
          [
            node("start", "Start"),
            node("if", "Condition", %{"variable" => "go", "operator" => "==", "value" => "a"}),
            code("a", ~s("A")),
            code("b", ~s("B")),
            node("merge", "Merge"),
            code("after", "result")
          ],
          [
            wire("start", "exec", "if"),
            wire("if", "true", "a"),
            wire("if", "false", "b"),
            wire("a", "exec", "merge"),
            wire("b", "exec", "merge"),
            wire("merge", "exec", "after")
          ]
        )

      assert {:ok, context} = Runner.run(f, %{"go" => "a"})
      assert Enum.count(ran(context), &(elem(&1, 0) == "merge")) == 1
      assert context["result"] == ["A"]
    end

    test "joins lists and merges objects" do
      results = [[1, 2], [3], nil]
      assert {:result, [1, 2, 3]} = merge(results, "concat")

      assert {:result, %{"a" => 1, "b" => 3}} =
               merge([%{"a" => 1, "b" => 2}, %{"b" => 3}, 4], "objects")

      assert {:result, ^results} = merge(results, "list")
    end

    defp merge(results, combine) do
      HeddleNodes.Nodes.Merge.handler(%{"result" => results, "combine" => combine}, nil)
    end

    test "inside a For Each, waits for the branches of each item" do
      f =
        flow(
          [
            node("start", "Start"),
            node("each", "For Each", %{"items" => "numbers"}),
            code("x", "result * 10"),
            code("y", "result + 1"),
            node("merge", "Merge")
          ],
          [
            wire("start", "exec", "each"),
            wire("each", "item", "x"),
            wire("each", "item", "y"),
            wire("x", "exec", "merge"),
            wire("y", "exec", "merge")
          ]
        )

      assert {:ok, context} = Runner.run(f, %{"numbers" => [1, 2]})
      assert context["result"] == [[10, 11], [20, 21]]
    end
  end

  describe "Wait" do
    defp wait(controls), do: node("wait", "Wait", controls)

    test "pauses the run, and goes on from there when resumed" do
      f =
        flow(
          [
            node("start", "Start"),
            wait(%{"wait_for" => "time", "amount" => "5", "unit" => "minutes"}),
            code("after", ~s("done"))
          ],
          [wire("start", "exec", "wait"), wire("wait", "exec", "after")]
        )

      assert {:wait, paused} = Runner.run(f, %{"name" => "Ana"})
      assert paused["wait"]["node_id"] == "wait"
      {:ok, at, _offset} = DateTime.from_iso8601(paused["wait"]["resume_at"])
      assert_in_delta DateTime.diff(at, DateTime.utc_now()), 300, 5
      assert ran(paused["context"]) == [{"start", "exec"}]

      assert {:ok, context} = resume(f, paused)
      assert ran(context) == [{"start", "exec"}, {"wait", "exec"}, {"after", "exec"}]
      assert context["result"] == "done"
      assert context["name"] == "Ana"
      refute Map.has_key?(context, "amount")
    end

    test "what is already due doesn't stop the run" do
      f =
        flow(
          [
            node("start", "Start"),
            wait(%{"wait_for" => "date", "wait_until" => "2001-01-01T00:00:00Z"})
          ],
          [wire("start", "exec", "wait")]
        )

      assert {:ok, context} = Runner.run(f)
      assert List.last(ran(context)) == {"wait", "exec"}
    end

    test "fails on a duration that isn't a number" do
      f =
        flow(
          [node("start", "Start"), wait(%{"wait_for" => "time", "amount" => "soon"})],
          [wire("start", "exec", "wait")]
        )

      assert {:error, message, "wait", _context} = Runner.run(f)
      assert message =~ "must be a number"
    end

    test "a call goes on with its request as the result, and the time limit through timeout" do
      f =
        flow(
          [
            node("start", "Start"),
            wait(%{"wait_for" => "call", "amount" => "1", "unit" => "hours"}),
            code("approved", "result[\"body\"][\"ok\"]"),
            code("late", ~s("too late"))
          ],
          [
            wire("start", "exec", "wait"),
            wire("wait", "exec", "approved"),
            wire("wait", "timeout", "late")
          ]
        )

      assert {:wait, paused} = Runner.run(f, %{}, resume_url: "http://heddle/resume/abc")
      assert paused["wait"]["call"] == true
      assert paused["wait"]["resume_at"]
      assert paused["context"]["resume_url"] == "http://heddle/resume/abc"

      request = %{"body" => %{"ok" => true}, "query_params" => %{}}
      assert {:ok, context} = resume(f, paused, %{"by" => "call", "request" => request})
      assert context["result"] == true
      refute Map.has_key?(context, "resume_url")

      assert {:ok, context} = resume(f, paused, %{"by" => "timeout"})
      assert List.last(ran(context)) == {"late", "exec"}
    end

    test "gives the resume url only to a flow with a Wait" do
      f =
        flow([node("start", "Start"), code("url", "variable(:resume_url)")], [
          wire("start", "exec", "url")
        ])

      assert {:ok, context} = Runner.run(f, %{}, resume_url: "http://heddle/resume/abc")
      assert context["result"] == nil
    end

    test "runs what came after the paused branch once it is resumed" do
      f =
        flow(
          [
            node("start", "Start"),
            wait(%{"wait_for" => "time", "amount" => "1"}),
            code("a", ~s("A")),
            code("b", ~s("B"))
          ],
          [wire("start", "exec", "wait"), wire("wait", "exec", "a"), wire("start", "exec", "b")]
        )

      assert {:wait, paused} = Runner.run(f)
      assert {:ok, context} = resume(f, paused)
      assert Enum.map(ran(context), &elem(&1, 0)) == ["start", "wait", "a", "b"]
    end

    test "inside a For Each, pauses once per item and keeps the results" do
      f =
        flow(
          [
            node("start", "Start"),
            node("each", "For Each", %{"items" => "numbers"}),
            wait(%{"wait_for" => "time", "amount" => "1"}),
            code("x", "result * 10"),
            code("out", "result")
          ],
          [
            wire("start", "exec", "each"),
            wire("each", "item", "wait"),
            wire("wait", "exec", "x"),
            wire("each", "done", "out")
          ]
        )

      assert {:wait, first} = Runner.run(f, %{"numbers" => [1, 2]})
      assert {:wait, second} = resume(f, first)
      assert second["context"]["item"] == 2
      assert {:ok, context} = resume(f, second)
      assert context["result"] == [10, 20]
    end

    test "a Merge keeps the branches that arrived while the run waited" do
      f =
        flow(
          [
            node("start", "Start"),
            code("a", ~s("A")),
            wait(%{"wait_for" => "time", "amount" => "1"}),
            code("b", ~s("B")),
            node("merge", "Merge")
          ],
          [
            wire("start", "exec", "a"),
            wire("start", "exec", "wait"),
            wire("a", "exec", "merge"),
            wire("wait", "exec", "b"),
            wire("b", "exec", "merge")
          ]
        )

      assert {:wait, paused} = Runner.run(f)
      assert {:ok, context} = resume(f, paused)
      assert context["result"] == ["A", "B"]
    end

    test "skips a Wait deleted while the run waited" do
      nodes = [node("start", "Start"), wait(%{"amount" => "1"}), code("b", ~s("B"))]
      f = flow(nodes, [wire("start", "exec", "wait"), wire("start", "exec", "b")])

      assert {:wait, paused} = Runner.run(f)

      edited = flow(List.delete_at(nodes, 1), [wire("start", "exec", "b")])
      assert {:ok, context} = resume(edited, paused)
      assert context["result"] == "B"
    end
  end
end
