defmodule HeddleNodes.Nodes.NewNodesTest do
  use ExUnit.Case, async: false

  alias HeddleNodes.Nodes.{ForEach, RespondToWebhook, Schedule}
  alias HeddleNodes.Runner

  defp graph_node(id, type, controls \\ %{}) do
    %{"id" => id, "type" => type, "label" => type, "controls" => controls}
  end

  defp link(source, output, target) do
    %{"source" => source, "sourceOutput" => output, "target" => target, "targetInput" => "exec"}
  end

  defp flow(nodes, connections) do
    %{id: 1, nodes: nodes, connections: connections}
  end

  describe "Schedule" do
    test "is a trigger with no input and a cron field" do
      definition = Schedule.definition()

      assert definition.category == :trigger
      assert definition.inputs == []
      assert Enum.any?(definition.ui_fields, &(&1.name == :cron))
    end

    test "a flow runs from its Schedule node when it has no Start" do
      graph =
        flow(
          [graph_node("s", "Schedule", %{"cron" => "* * * * *"}), graph_node("v", "Logger")],
          [link("s", "exec", "v")]
        )

      assert {:ok, %{"logs" => logs}} = Runner.run(graph, %{"trigger" => "manual"})
      assert Enum.map(logs, & &1["node_id"]) == ["s", "v"]
    end

    test "runs from the Schedule node that fired" do
      graph =
        flow(
          [
            graph_node("a", "Schedule", %{"cron" => "0 9 * * *"}),
            graph_node("b", "Schedule", %{"cron" => "0 18 * * *"})
          ],
          []
        )

      assert {:ok, context} = Runner.run(graph, %{"trigger" => "schedule", "node_id" => "b"})
      assert [%{"node_id" => "b"}] = context["logs"]
      refute Map.has_key?(context, "node_id")
    end
  end

  describe "For Each" do
    defp loop_flow(items_key, body \\ []) do
      nodes = [
        graph_node("start", "Start"),
        graph_node("each", "For Each", %{"items" => items_key}),
        graph_node("end", "Logger")
      ]

      connections = [link("start", "exec", "each"), link("each", "done", "end")]

      flow(nodes ++ body, connections)
    end

    defp eval_node(id, code) do
      graph_node(id, "Evaluate Code", %{"language" => "elixir", "code_elixir" => code})
    end

    test "runs its branch once per item and gathers the results" do
      graph = loop_flow("numbers", [eval_node("double", "result * 2")])
      graph = %{graph | connections: [link("each", "item", "double") | graph.connections]}

      assert {:ok, context} = Runner.run(graph, %{"numbers" => [1, 2, 3]})
      assert context["results"] == [2, 4, 6]
      assert context["result"] == [2, 4, 6]
      refute Map.has_key?(context, "item")
    end

    test "gives the branch the item and its index" do
      graph =
        loop_flow("letters", [
          eval_node("pair", ~s|Enum.join([variable(:index), variable(:item)], ":")|)
        ])

      graph = %{graph | connections: [link("each", "item", "pair") | graph.connections]}

      assert {:ok, %{"results" => ["0:a", "1:b"]}} =
               Runner.run(graph, %{"letters" => ["a", "b"]})
    end

    test "reads a list inside the context" do
      graph = loop_flow("body.items")

      assert {:ok, context} = Runner.run(graph, %{"body" => %{"items" => [1, 2]}})
      assert context["results"] == [1, 2]
    end

    test "goes straight to done with an empty list" do
      graph = loop_flow("numbers")

      assert {:ok, context} = Runner.run(graph, %{"numbers" => []})
      assert context["results"] == []
      assert Enum.any?(context["logs"], &(&1["node_id"] == "end"))
    end

    test "stops the run when an iteration fails" do
      graph = loop_flow("numbers", [eval_node("boom", ~s(raise "boom"))])
      graph = %{graph | connections: [link("each", "item", "boom") | graph.connections]}

      assert {:error, reason, "boom", _context} = Runner.run(graph, %{"numbers" => [1]})
      assert reason =~ "boom"
    end

    test "fails on what isn't a list" do
      assert {:error, message} = ForEach.handler(%{"items" => "x", "x" => 1}, nil)
      assert message =~ "not a list"
    end

    test "refuses a list too long to run in one go" do
      items = List.duplicate(1, ForEach.max_items() + 1)

      assert {:error, message} = ForEach.handler(%{"items" => "x", "x" => items}, nil)
      assert message =~ "items"
    end
  end

  describe "Respond to Webhook" do
    test "hands over the response and lets the flow go on" do
      parent = self()

      graph =
        flow(
          [
            graph_node("start", "Start"),
            graph_node("reply", "Respond to Webhook", %{
              "response_status" => "201",
              "response_body" => ~s({"name": "{{name}}"})
            }),
            graph_node("after", "Logger")
          ],
          [link("start", "exec", "reply"), link("reply", "exec", "after")]
        )

      assert {:ok, context} =
               Runner.run(graph, %{"name" => "Ana"},
                 on_respond: fn response -> send(parent, {:responded, response}) end
               )

      assert_received {:responded, response}

      assert response == %{
               "status" => 201,
               "body" => ~s({"name": "Ana"}),
               "content_type" => "application/json"
             }

      assert Enum.any?(context["logs"], &(&1["node_id"] == "after"))
    end

    test "sends plain text as text" do
      assert {:respond, response, _context} =
               RespondToWebhook.handler(
                 %{"response_status" => "200", "response_body" => "ok"},
                 nil
               )

      assert response["content_type"] == "text/plain"
    end

    test "falls back to 200 for a status that isn't one" do
      assert {:respond, %{"status" => 200}, _context} =
               RespondToWebhook.handler(%{"response_status" => "abc"}, nil)

      assert {:respond, %{"status" => 200}, _context} =
               RespondToWebhook.handler(%{"response_status" => "99"}, nil)
    end

    test "doesn't let its fields hide the webhook body" do
      context = %{"body" => %{"name" => "Ana"}, "response_body" => "{{body.name}}"}

      assert {:respond, %{"body" => "Ana"}, _context} = RespondToWebhook.handler(context, nil)
    end

    test "runs fine outside a webhook" do
      graph =
        flow([graph_node("start", "Start"), graph_node("reply", "Respond to Webhook")], [
          link("start", "exec", "reply")
        ])

      assert {:ok, _context} = Runner.run(graph, %{})
    end
  end
end
