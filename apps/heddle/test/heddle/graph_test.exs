defmodule Heddle.GraphTest do
  use ExUnit.Case, async: true

  alias Heddle.Graph
  alias Heddle.Graph.Node

  defp node_map(id, type, attrs \\ %{}) do
    Map.merge(%{"id" => id, "type" => type, "label" => type, "controls" => %{}}, attrs)
  end

  defp connection(source, target, output \\ "exec") do
    %{"source" => source, "sourceOutput" => output, "target" => target}
  end

  describe "new/1" do
    test "keeps only what the engine needs of a node" do
      node =
        node_map("a", "Start", %{
          "label" => "Begin",
          "controls" => %{"x" => 1},
          "position" => %{"x" => 1, "y" => 2}
        })

      graph = Graph.new(%{nodes: [node], connections: []})

      assert Graph.get(graph, "a") ==
               %Node{id: "a", type: "Start", label: "Begin", controls: %{"x" => 1}}
    end

    test "reads a flow with nothing in it" do
      graph = Graph.new(%{nodes: nil, connections: nil})

      assert graph.nodes == []
      assert Graph.of_type(graph, "Start") == []
    end
  end

  describe "of_type/2" do
    test "goes by the type, never by the label" do
      graph =
        Graph.new(%{
          nodes: [
            node_map("fake", "Variable", %{"label" => "Start"}),
            node_map("real", "Start", %{"label" => "Begin"})
          ],
          connections: []
        })

      assert [%Node{id: "real"}] = Graph.of_type(graph, "Start")
    end

    test "reads a node from before it had a type by its label" do
      node = %{"id" => "a", "label" => "Start", "controls" => %{}}

      assert [%Node{id: "a"}] =
               Graph.of_type(Graph.new(%{nodes: [node], connections: []}), "Start")
    end
  end

  describe "next/3" do
    test "follows the output it is asked about" do
      graph =
        Graph.new(%{
          nodes: [node_map("a", "If"), node_map("b", "Output"), node_map("c", "Output")],
          connections: [connection("a", "b", "true"), connection("a", "c", "false")]
        })

      assert [%Node{id: "c"}] = Graph.next(graph, Graph.get(graph, "a"), "false")
      assert [%Node{id: "c"}] = Graph.next(graph, Graph.get(graph, "a"), false)
    end

    test "runs connections of the same output in the order they are listed" do
      nodes = [node_map("a", "Start"), node_map("b", "Output"), node_map("c", "Output")]

      graph =
        Graph.new(%{nodes: nodes, connections: [connection("a", "c"), connection("a", "b")]})

      assert [%Node{id: "c"}, %Node{id: "b"}] = Graph.next(graph, Graph.get(graph, "a"), "exec")
    end

    test "matches an integer id with the same id as a string" do
      graph =
        Graph.new(%{
          nodes: [node_map(1, "Start"), node_map("2", "Output")],
          connections: [connection("1", 2)]
        })

      assert [%Node{id: "2"}] = Graph.next(graph, Graph.get(graph, 1), "exec")
    end

    test "skips a connection to a node that isn't there" do
      graph = Graph.new(%{nodes: [node_map("a", "Start")], connections: [connection("a", "x")]})

      assert Graph.next(graph, Graph.get(graph, "a"), "exec") == []
    end
  end

  describe "body_fields/1" do
    defp fields_of(controls) do
      graph =
        Graph.new(%{
          nodes: [node_map("a", "Evaluate Code", %{"controls" => controls})],
          connections: []
        })

      Graph.body_fields(graph)
    end

    test "finds what the code reads from the body" do
      code = ~s|variable(:body)["x"] * variable(:body)["y"]|

      assert fields_of(%{"code_elixir" => code}) == ["x", "y"]
    end

    test "finds it in Python and in placeholders" do
      assert fields_of(%{"code_python" => ~s|variable("body")["name"]|}) == ["name"]
      assert fields_of(%{"response_body" => "Hi {{body.name}}"}) == ["name"]
      assert fields_of(%{"items" => "body.items"}) == ["items"]
    end

    test "lists a field once" do
      assert fields_of(%{"a" => ~s|body["x"] + body["x"]|}) == ["x"]
    end

    test "ignores what only looks like it" do
      assert fields_of(%{"a" => ~s|response_body.x|, "b" => "nobody.y", "c" => 3}) == []
    end
  end

  describe "normalize_nodes/1" do
    test "turns ids into strings and keeps the rest" do
      position = %{"x" => 1, "y" => 2}

      assert [%{"id" => "1", "type" => "Start", "position" => ^position}] =
               Graph.normalize_nodes([node_map(1, "Start", %{"position" => position})])
    end

    test "fills in a missing type with the label" do
      assert [%{"type" => "Start"}] = Graph.normalize_nodes([%{"id" => "a", "label" => "Start"}])
    end

    test "leaves what it can't fix for the validator" do
      assert Graph.normalize_nodes([%{"id" => nil}]) == [%{"id" => nil}]
    end
  end

  describe "normalize_connections/1" do
    test "turns ids into strings and fills in the input" do
      assert [%{"source" => "1", "target" => "2", "targetInput" => "exec"}] =
               Graph.normalize_connections([connection(1, 2)])
    end

    test "keeps the input of the connection" do
      connection = Map.put(connection("a", "b"), "targetInput", "other")

      assert [%{"targetInput" => "other"}] = Graph.normalize_connections([connection])
    end
  end

  describe "sections" do
    defp section(id, nodes, attrs \\ %{}) do
      Map.merge(
        %{"id" => id, "kind" => "section", "text" => "Billing", "nodes" => nodes},
        attrs
      )
    end

    defp flow(comments) do
      %{
        nodes: [node_map("start", "Start"), node_map("a", "Variable"), node_map("b", "Variable")],
        connections: [connection("start", "a"), connection("a", "b")],
        comments: comments
      }
    end

    test "leave out the nodes of a manual section, and what leads to them is held back" do
      graph = Graph.new(flow([section("s", ["a", "b"], %{"manual" => true})]))

      assert Enum.map(graph.nodes, & &1.id) == ["start"]
      assert Graph.get(graph, "a") == nil
      assert Graph.next(graph, Graph.get(graph, "start"), "exec") == []
      assert [%Node{id: "a"}] = Graph.held_back(graph, Graph.get(graph, "start"), "exec")
      assert Graph.holds_back?(graph)
    end

    test "keep the nodes of a section that runs with the flow" do
      graph = Graph.new(flow([section("s", ["a", "b"])]))

      assert Enum.map(graph.nodes, & &1.id) == ["start", "a", "b"]
      refute Graph.holds_back?(graph)
    end

    test "a manual section holds back the nodes of the sections inside it" do
      comments = [section("outer", ["a", "b"], %{"manual" => true}), section("inner", ["b"])]

      assert Enum.map(Graph.new(flow(comments)).nodes, & &1.id) == ["start"]
    end

    test "take one section alone, with the connections inside it" do
      graph = Graph.new(flow([section("s", ["a", "b"], %{"manual" => true})]), section: "s")

      assert %Graph.Section{id: "s", name: "Billing", manual: true} = Graph.section(graph)
      assert Enum.map(graph.nodes, & &1.id) == ["a", "b"]
      assert [%Node{id: "a"}] = Graph.entries(graph)
      assert [%Node{id: "b"}] = Graph.next(graph, Graph.get(graph, "a"), "exec")
      refute Graph.holds_back?(graph)
    end

    test "start a section from every node nothing in it leads to, in the order it lists them" do
      flow = %{flow([]) | comments: [section("s", ["b", "start"])], connections: []}

      assert ["b", "start"] =
               flow |> Graph.new(section: "s") |> Graph.entries() |> Enum.map(& &1.id)
    end

    test "take nothing for a section that is not there, or for ids of nodes that are gone" do
      graph = Graph.new(flow([section("s", ["gone"])]), section: "missing")

      assert Graph.section(graph) == nil
      assert graph.nodes == []
      assert Graph.entries(Graph.new(flow([section("s", ["gone"])]), section: "s")) == []
    end

    test "read only sections, among the comments" do
      comments = [
        %{"id" => "n", "kind" => "note", "text" => "x", "manual" => true, "nodes" => ["a"]}
      ]

      assert Graph.sections(flow(comments)) == []
      assert length(Graph.new(flow(comments)).nodes) == 3
    end
  end
end
