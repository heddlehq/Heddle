defmodule Heddle.Graph.Layout do
  @moduledoc """
  Places the nodes that have no position, so a flow written by the API or an agent
  doesn't need to think about the canvas.

  Each node goes one column after what leads to it, and the branches of a column
  stack down. The nodes that have a position stay where they are.
  """

  alias Heddle.Graph

  @origin 100
  @column_width 500
  @row_height 200

  @doc "Returns `nodes` in their stored form, all of them with a position."
  def place(nodes, connections) do
    nodes = Graph.normalize_nodes(nodes)
    columns = columns(nodes, Graph.normalize_connections(connections))

    {placed, _rows} =
      Enum.map_reduce(nodes, %{}, fn node, rows ->
        column = Map.get(columns, node["id"], 0)
        row = Map.get(rows, column, 0)

        {put_position(node, column, row), Map.put(rows, column, row + 1)}
      end)

    placed
  end

  defp put_position(%{"position" => %{}} = node, _column, _row), do: node

  defp put_position(node, column, row) do
    Map.put(node, "position", %{
      "x" => @origin + column * @column_width,
      "y" => @origin + row * @row_height
    })
  end

  defp columns(nodes, connections) do
    targets = Enum.group_by(connections, & &1["source"], & &1["target"])
    reached = MapSet.new(connections, & &1["target"])

    nodes
    |> Enum.map(& &1["id"])
    |> Enum.reject(&MapSet.member?(reached, &1))
    |> walk(0, targets, %{})
  end

  defp walk([], _column, _targets, columns), do: columns

  defp walk(ids, column, targets, columns) do
    new_ids = ids |> Enum.uniq() |> Enum.reject(&Map.has_key?(columns, &1))
    columns = Enum.reduce(new_ids, columns, &Map.put(&2, &1, column))

    new_ids
    |> Enum.flat_map(&Map.get(targets, &1, []))
    |> walk(column + 1, targets, columns)
  end
end
