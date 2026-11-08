defmodule Heddle.Graph.DiffTest do
  use ExUnit.Case, async: true

  alias Heddle.Graph.Diff

  defp step(id, attrs \\ %{}) do
    Map.merge(
      %{"id" => id, "type" => "Start", "controls" => %{}, "position" => %{"x" => 0, "y" => 0}},
      attrs
    )
  end

  defp link(source, target),
    do: %{
      "source" => source,
      "sourceOutput" => "exec",
      "target" => target,
      "targetInput" => "exec"
    }

  defp flow(nodes, connections \\ [], comments \\ []),
    do: %{nodes: nodes, connections: connections, comments: comments}

  describe "between/2" do
    test "is empty for the same flow" do
      a = flow([step("a"), step("b")], [link("a", "b")])

      assert Diff.empty?(Diff.between(a, a))
      assert Diff.summary(Diff.between(a, a)) == %{}
    end

    test "finds nodes added, removed and changed" do
      old = flow([step("a"), step("b"), step("c")])
      new = flow([step("a"), step("c", %{"controls" => %{"x" => 1}}), step("d")])

      diff = Diff.between(old, new)

      assert Enum.map(diff.nodes.added, & &1["id"]) == ["d"]
      assert Enum.map(diff.nodes.removed, & &1["id"]) == ["b"]
      assert [{%{"id" => "c"}, %{"id" => "c", "controls" => %{"x" => 1}}}] = diff.nodes.changed
      assert Diff.node_states(diff) == %{"b" => "removed", "c" => "changed", "d" => "added"}
    end

    test "a node that only moved isn't a change" do
      old = flow([step("a")])
      new = flow([step("a", %{"position" => %{"x" => 50, "y" => 10}})])

      diff = Diff.between(old, new)

      assert diff.nodes.changed == []
      assert [%{"id" => "a"}] = diff.nodes.moved
      assert Diff.empty?(diff)
      assert Diff.summary(diff) == %{nodes_moved: 1}
    end

    test "finds connections added and removed, by what they join" do
      old = flow([step("a"), step("b"), step("c")], [link("a", "b")])
      new = flow([step("a"), step("b"), step("c")], [link("a", "c")])

      diff = Diff.between(old, new)

      assert diff.connections.added == [link("a", "c")]
      assert diff.connections.removed == [link("a", "b")]
      refute diff.connections.reordered
    end

    test "connections in another order run in another order" do
      nodes = [step("a"), step("b"), step("c")]
      old = flow(nodes, [link("a", "b"), link("a", "c")])
      new = flow(nodes, [link("a", "c"), link("a", "b")])

      diff = Diff.between(old, new)

      assert diff.connections.reordered
      refute Diff.empty?(diff)
      assert Diff.summary(diff) == %{connections_reordered: 1}
    end

    test "reads older flows, with integer ids and no type" do
      old = flow([%{"id" => 1, "label" => "Start", "controls" => %{}}])
      new = flow([%{"id" => "1", "type" => "Start", "label" => "Start", "controls" => %{}}])

      assert Diff.empty?(Diff.between(old, new))
    end

    test "takes a missing side as an empty flow" do
      diff = Diff.between(%{}, flow([step("a")]))

      assert Diff.summary(diff) == %{nodes_added: 1}
    end
  end
end
