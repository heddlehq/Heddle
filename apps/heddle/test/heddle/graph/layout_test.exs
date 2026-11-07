defmodule Heddle.Graph.LayoutTest do
  use ExUnit.Case, async: true

  alias Heddle.Graph.Layout

  defp connection(source, target) do
    %{"source" => source, "sourceOutput" => "exec", "target" => target}
  end

  defp positions(nodes), do: Map.new(nodes, &{&1["id"], &1["position"]})

  test "puts each node one column after what leads to it" do
    nodes = [%{"id" => "a"}, %{"id" => "b"}, %{"id" => "c"}]

    placed = Layout.place(nodes, [connection("a", "b"), connection("b", "c")])

    assert %{
             "a" => %{"x" => 100, "y" => 100},
             "b" => %{"x" => 600, "y" => 100},
             "c" => %{"x" => 1100, "y" => 100}
           } = positions(placed)
  end

  test "stacks the branches of a column" do
    nodes = [%{"id" => "a"}, %{"id" => "b"}, %{"id" => "c"}]

    placed = Layout.place(nodes, [connection("a", "b"), connection("a", "c")])

    assert %{"b" => %{"x" => 600, "y" => 100}, "c" => %{"x" => 600, "y" => 300}} =
             positions(placed)
  end

  test "keeps a position that is already there" do
    position = %{"x" => -5, "y" => 7}

    assert [%{"position" => ^position}] =
             Layout.place([%{"id" => "a", "position" => position}], [])
  end

  test "places the nodes of a loop that nothing leads to" do
    nodes = [%{"id" => "a"}, %{"id" => "b"}]

    placed = Layout.place(nodes, [connection("a", "b"), connection("b", "a")])

    assert %{"a" => %{"y" => 100}, "b" => %{"y" => 300}} = positions(placed)
  end

  test "keeps the order of the nodes" do
    nodes = [%{"id" => "b"}, %{"id" => "a"}]

    assert ["b", "a"] = nodes |> Layout.place([]) |> Enum.map(& &1["id"])
  end
end
