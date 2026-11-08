defmodule Heddle.Graph.OpsTest do
  use ExUnit.Case, async: true

  alias Heddle.Graph.Ops

  defp step(id, attrs \\ %{}) do
    Map.merge(
      %{"id" => id, "type" => "Start", "controls" => %{}, "position" => %{"x" => 0, "y" => 0}},
      attrs
    )
  end

  defp link(source, target, output \\ "exec"),
    do: %{
      "source" => source,
      "sourceOutput" => output,
      "target" => target,
      "targetInput" => "exec"
    }

  defp graph(nodes, connections \\ [], comments \\ []),
    do: %{nodes: nodes, connections: connections, comments: comments}

  describe "apply/2" do
    test "adds, changes and removes a node, with its connections" do
      {:ok, g} =
        Ops.apply(graph([step("a")]), [
          %{"op" => "add_node", "node" => step("b")},
          %{"op" => "add_connection", "connection" => link("a", "b")},
          %{
            "op" => "update_node",
            "id" => "b",
            "set" => %{"label" => "B", "controls" => %{"x" => 1}}
          }
        ])

      assert [_, %{"label" => "B", "controls" => %{"x" => 1}}] = g.nodes
      assert g.connections == [link("a", "b")]

      {:ok, g} = Ops.apply(g, [%{"op" => "remove_node", "id" => "b"}])
      assert Enum.map(g.nodes, & &1["id"]) == ["a"]
      assert g.connections == []
    end

    test "changes only the controls it names" do
      start = graph([step("a", %{"controls" => %{"x" => 1, "y" => 2}})])

      {:ok, g} =
        Ops.apply(start, [
          %{"op" => "update_node", "id" => "a", "set" => %{"controls" => %{"x" => 5}}},
          %{"op" => "update_node", "id" => "a", "set" => %{"controls" => %{"y" => nil}}}
        ])

      assert [%{"controls" => %{"x" => 5}}] = g.nodes
    end

    test "fails on what isn't there" do
      assert {:error, _} = Ops.apply(graph([]), [%{"op" => "remove_node", "id" => "x"}])

      assert {:error, _} =
               Ops.apply(graph([]), [%{"op" => "update_node", "id" => "x", "set" => %{}}])

      assert {:error, _} =
               Ops.apply(graph([step("a")]), [
                 %{"op" => "add_connection", "connection" => link("a", "z")}
               ])

      assert {:error, _} =
               Ops.apply(graph([step("a")]), [%{"op" => "add_node", "node" => step("a")}])

      assert {:error, _} = Ops.apply(graph([]), [%{"op" => "explode"}])

      assert {:error, _} =
               Ops.apply(graph([step("a")]), [
                 %{"op" => "update_node", "id" => "a", "set" => %{"id" => "b"}}
               ])
    end

    test "moves nodes and comments, and ignores what went meanwhile" do
      note = %{"id" => "n", "kind" => "note", "text" => "", "position" => %{"x" => 0, "y" => 0}}

      {:ok, g} =
        Ops.apply(graph([step("a")], [], [note]), [
          %{
            "op" => "move_nodes",
            "positions" => %{
              "a" => %{"x" => 10, "y" => 5},
              "n" => %{"x" => 3, "y" => 4},
              "gone" => %{"x" => 1, "y" => 1}
            }
          }
        ])

      assert [%{"position" => %{"x" => 10, "y" => 5}}] = g.nodes
      assert [%{"position" => %{"x" => 3, "y" => 4}}] = g.comments
    end

    test "a removed node leaves the sections that held it" do
      section = %{"id" => "s", "kind" => "section", "nodes" => ["a", "b"]}

      {:ok, g} =
        Ops.apply(graph([step("a"), step("b")], [], [section]), [
          %{"op" => "remove_node", "id" => "a"}
        ])

      assert [%{"nodes" => ["b"]}] = g.comments
    end
  end

  describe "between/2" do
    test "turns any change into operations that give the same graph" do
      old =
        graph(
          [step("a"), step("b", %{"controls" => %{"x" => 1}}), step("c")],
          [link("a", "b"), link("a", "c")],
          [%{"id" => "n", "kind" => "note", "text" => "hi", "position" => %{"x" => 0, "y" => 0}}]
        )

      new =
        graph(
          [
            step("a", %{"position" => %{"x" => 40, "y" => 0}}),
            step("b", %{"controls" => %{"x" => 2}, "label" => "B"}),
            step("d")
          ],
          [link("a", "d"), link("a", "b")],
          [%{"id" => "n", "kind" => "note", "text" => "bye", "position" => %{"x" => 9, "y" => 9}}]
        )

      ops = Ops.between(old, new)

      assert {:ok, result} = Ops.apply(old, ops)
      assert result == Ops.normalize(new)
    end

    test "is nothing for the same graph" do
      g = graph([step("a")], [], [])
      assert Ops.between(g, g) == []
    end
  end

  test "fields/1 says what an operation changes" do
    assert Ops.fields(%{
             "op" => "update_node",
             "id" => "a",
             "set" => %{"label" => "x", "controls" => %{"k" => 1}}
           })
           |> Enum.sort() ==
             ["node:a:controls.k", "node:a:label"]

    assert Ops.fields(%{"op" => "move_nodes", "positions" => %{"a" => %{}}}) == ["position:a"]
  end
end
