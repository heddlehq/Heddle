defmodule Heddle.Graph.Diff do
  @moduledoc """
  What changed from one flow to another: the nodes, connections and comments that came,
  went or changed.

  Both sides are anything with `:nodes`, `:connections` and `:comments`, such as a flow
  or one of its versions. A node or comment that only moved is `moved`, apart from what
  `changed`, since moving one doesn't change what the flow does.

  Connections have no id: one is the same as another when it joins the same output to
  the same input. The order of those leaving one output is what runs first (see
  `Heddle.Graph`), so `reordered` says when the ones both sides have are in another
  order.
  """

  alias Heddle.Graph

  @connection_keys ~w(source sourceOutput target targetInput)

  defstruct nodes: %{added: [], removed: [], changed: [], moved: []},
            connections: %{added: [], removed: [], reordered: false},
            comments: %{added: [], removed: [], changed: [], moved: []}

  @type t :: %__MODULE__{}

  @doc "The changes that turn `old` into `new`."
  def between(old, new) do
    %__MODULE__{
      nodes:
        by_id(
          Graph.normalize_nodes(field(old, :nodes)),
          Graph.normalize_nodes(field(new, :nodes))
        ),
      connections: connections(field(old, :connections), field(new, :connections)),
      comments: by_id(stringify_ids(field(old, :comments)), stringify_ids(field(new, :comments)))
    }
  end

  @doc "Whether `old` and `new` are the same flow, apart from where things are."
  def empty?(%__MODULE__{} = diff) do
    diff.nodes.added == [] and diff.nodes.removed == [] and diff.nodes.changed == [] and
      diff.connections.added == [] and diff.connections.removed == [] and
      not diff.connections.reordered and diff.comments.added == [] and
      diff.comments.removed == [] and diff.comments.changed == []
  end

  @doc """
  How each node differs, by id: `"added"`, `"removed"` or `"changed"`. Moving one
  isn't a change worth pointing at.
  """
  def node_states(%__MODULE__{nodes: nodes}) do
    Map.new(
      Enum.map(nodes.added, &{&1["id"], "added"}) ++
        Enum.map(nodes.removed, &{&1["id"], "removed"}) ++
        Enum.map(nodes.changed, fn {_old, new} -> {new["id"], "changed"} end)
    )
  end

  @doc """
  Counts what changed, for a short summary: `%{nodes_added: 2, ...}`, leaving out what
  didn't change.
  """
  def summary(%__MODULE__{} = diff) do
    %{
      nodes_added: length(diff.nodes.added),
      nodes_removed: length(diff.nodes.removed),
      nodes_changed: length(diff.nodes.changed),
      nodes_moved: length(diff.nodes.moved),
      connections_added: length(diff.connections.added),
      connections_removed: length(diff.connections.removed),
      comments_changed:
        length(diff.comments.added) + length(diff.comments.removed) +
          length(diff.comments.changed)
    }
    |> Map.reject(fn {_key, count} -> count == 0 end)
    |> then(fn summary ->
      if diff.connections.reordered,
        do: Map.put(summary, :connections_reordered, 1),
        else: summary
    end)
  end

  defp field(%{} = graph, key), do: Map.get(graph, key) || []

  defp by_id(old, new) do
    old_by_id = Map.new(old, &{&1["id"], &1})
    new_by_id = Map.new(new, &{&1["id"], &1})

    {changed, moved} =
      new
      |> Enum.filter(&Map.has_key?(old_by_id, &1["id"]))
      |> Enum.map(&{old_by_id[&1["id"]], &1})
      |> Enum.reject(fn {before, now} -> before == now end)
      |> Enum.split_with(fn {before, now} ->
        Map.delete(before, "position") != Map.delete(now, "position")
      end)

    %{
      added: Enum.reject(new, &Map.has_key?(old_by_id, &1["id"])),
      removed: Enum.reject(old, &Map.has_key?(new_by_id, &1["id"])),
      changed: changed,
      moved: Enum.map(moved, fn {_before, now} -> now end)
    }
  end

  defp connections(old, new) do
    old = old |> Graph.normalize_connections() |> Enum.map(&Map.take(&1, @connection_keys))
    new = new |> Graph.normalize_connections() |> Enum.map(&Map.take(&1, @connection_keys))
    old_set = MapSet.new(old)
    new_set = MapSet.new(new)
    kept_old = Enum.filter(old, &MapSet.member?(new_set, &1))
    kept_new = Enum.filter(new, &MapSet.member?(old_set, &1))

    %{
      added: Enum.reject(new, &MapSet.member?(old_set, &1)),
      removed: Enum.reject(old, &MapSet.member?(new_set, &1)),
      reordered: kept_old != kept_new
    }
  end

  defp stringify_ids(items) do
    Enum.map(items, fn
      %{"id" => id} = item when is_integer(id) -> Map.put(item, "id", Integer.to_string(id))
      item -> item
    end)
  end
end
