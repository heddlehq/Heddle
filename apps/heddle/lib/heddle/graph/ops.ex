defmodule Heddle.Graph.Ops do
  @moduledoc """
  The small changes people make to a flow while they edit it together, and how each
  one changes a graph: a map with `:nodes`, `:connections` and `:comments`, stored as
  `Heddle.Graph` reads them.

  An operation is a map with string keys, as it arrives from a client:

    * `add_node` `node`, `remove_node` `id` (and the connections that touch it),
    * `update_node` `id` `set`: `label`, `type` and `settings` replace what the node
      has (a `nil` settings removes them), and `controls` changes only the controls
      it names (a `nil` value removes one),
    * `move_nodes` `positions`: `%{id => %{"x" => x, "y" => y}}`, for nodes and comments,
    * `add_connection` `connection`, added after those leaving the same output, and
      `remove_connection` `connection`,
    * `set_connections` `connections`, all of them in a new order,
    * `add_comment` `comment`, `remove_comment` `id`, and `update_comment` `id` `set`,
      which replaces the fields it names.

  What changes the same field last wins: the order of operations is the order a flow's
  session applies them, see `HeddleCore.Flows.Session`. An operation on something
  that isn't there anymore fails, and the client that sent it reloads the flow.
  """

  alias Heddle.Graph
  alias Heddle.Graph.Diff

  @connection_keys ~w(source sourceOutput target targetInput)
  @node_fields ~w(label type settings controls)

  @doc "Applies `ops` in order. Returns `{:ok, graph}` or `{:error, reason}`."
  def apply(graph, ops) when is_list(ops) do
    Enum.reduce_while(ops, {:ok, normalize(graph)}, fn op, {:ok, graph} ->
      case apply_one(graph, op) do
        {:ok, graph} -> {:cont, {:ok, graph}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def apply(_graph, _ops), do: {:error, "operations must be a list"}

  @doc "Gives a graph the stored form, with all three lists."
  def normalize(graph) do
    %{
      nodes: Graph.normalize_nodes(field(graph, :nodes)),
      connections: Graph.normalize_connections(field(graph, :connections)),
      comments: field(graph, :comments)
    }
  end

  @doc """
  The operations that turn `old` into `new`, for whatever writes a whole flow at once,
  such as the API or an agent.
  """
  def between(old, new) do
    old = normalize(old)
    new = normalize(new)
    diff = Diff.between(old, new)

    removed_nodes = Enum.map(diff.nodes.removed, &%{"op" => "remove_node", "id" => &1["id"]})
    added_nodes = Enum.map(diff.nodes.added, &%{"op" => "add_node", "node" => &1})

    changed_nodes =
      Enum.flat_map(diff.nodes.changed, fn {before, now} -> node_update(before, now) end)

    moved =
      (diff.nodes.moved ++
         Enum.map(diff.nodes.changed, &elem(&1, 1)) ++
         diff.comments.moved ++ Enum.map(diff.comments.changed, &elem(&1, 1)))
      |> Enum.filter(&moved?(&1, old))
      |> Map.new(&{&1["id"], &1["position"]})

    connections = connection_ops(old, new, diff)

    comments =
      Enum.map(diff.comments.removed, &%{"op" => "remove_comment", "id" => &1["id"]}) ++
        Enum.map(diff.comments.added, &%{"op" => "add_comment", "comment" => &1}) ++
        Enum.map(diff.comments.changed, fn {_before, now} ->
          %{
            "op" => "update_comment",
            "id" => now["id"],
            "set" => Map.drop(now, ["id", "position"])
          }
        end)

    removed_nodes ++
      added_nodes ++
      changed_nodes ++
      comments ++
      connections ++
      if(moved == %{}, do: [], else: [%{"op" => "move_nodes", "positions" => moved}])
  end

  # Added connections go after the others of their output. When that isn't the order
  # of `new`, it takes all of them in its order instead.
  defp connection_ops(old, new, diff) do
    # Removing a node takes its connections with it.
    gone = MapSet.new(diff.nodes.removed, & &1["id"])

    old = %{
      old
      | connections: Enum.reject(old.connections, &(&1["source"] in gone or &1["target"] in gone))
    }

    ops =
      diff.connections.removed
      |> Enum.reject(&(&1["source"] in gone or &1["target"] in gone))
      |> Enum.map(&%{"op" => "remove_connection", "connection" => &1})
      |> Kernel.++(
        Enum.map(diff.connections.added, &%{"op" => "add_connection", "connection" => &1})
      )

    in_order? =
      not diff.connections.reordered and
        match?(
          {:ok, %{connections: same}} when same == new.connections,
          apply_connections(old, ops)
        )

    cond do
      ops == [] and not diff.connections.reordered -> []
      in_order? -> ops
      true -> [%{"op" => "set_connections", "connections" => new.connections}]
    end
  end

  defp apply_connections(old, ops) do
    ops
    |> Enum.reduce_while({:ok, old.connections}, fn
      %{"op" => "remove_connection", "connection" => c}, {:ok, acc} ->
        {:cont, {:ok, List.delete(acc, c)}}

      %{"op" => "add_connection", "connection" => c}, {:ok, acc} ->
        {:cont, {:ok, acc ++ [c]}}
    end)
    |> case do
      {:ok, connections} -> {:ok, %{connections: connections}}
    end
  end

  @doc """
  The fields an operation changes, as `"node:ID:FIELD"` and `"comment:ID:FIELD"`, so a
  client knows which of its own changes a later one overrides.
  """
  def fields(%{"op" => "update_node", "id" => id, "set" => set}) do
    Enum.flat_map(set, fn
      {"controls", controls} when is_map(controls) ->
        Enum.map(Map.keys(controls), &"node:#{id}:controls.#{&1}")

      {key, _value} ->
        ["node:#{id}:#{key}"]
    end)
  end

  def fields(%{"op" => "move_nodes", "positions" => positions}),
    do: Enum.map(Map.keys(positions), &"position:#{&1}")

  def fields(%{"op" => "update_comment", "id" => id, "set" => set}),
    do: Enum.map(Map.keys(set), &"comment:#{id}:#{&1}")

  def fields(_op), do: []

  ## Applying one

  defp apply_one(graph, %{"op" => "add_node", "node" => %{"id" => id} = node})
       when is_map(node) do
    [node] = Graph.normalize_nodes([node])

    if find(graph.nodes, node["id"]) || find(graph.comments, node["id"]),
      do: {:error, "node #{id} already exists"},
      else: {:ok, %{graph | nodes: graph.nodes ++ [node]}}
  end

  defp apply_one(graph, %{"op" => "remove_node", "id" => id}) do
    id = to_string(id)

    if find(graph.nodes, id) do
      {:ok,
       %{
         graph
         | nodes: Enum.reject(graph.nodes, &(&1["id"] == id)),
           connections:
             Enum.reject(graph.connections, &(&1["source"] == id or &1["target"] == id)),
           comments: Enum.map(graph.comments, &forget_member(&1, id))
       }}
    else
      {:error, "node #{id} doesn't exist"}
    end
  end

  defp apply_one(graph, %{"op" => "update_node", "id" => id, "set" => set}) when is_map(set) do
    id = to_string(id)

    with %{} <- find(graph.nodes, id) || {:error, "node #{id} doesn't exist"},
         :ok <- only(set, @node_fields) do
      {:ok,
       %{
         graph
         | nodes: Enum.map(graph.nodes, &if(&1["id"] == id, do: set_node(&1, set), else: &1))
       }}
    end
  end

  defp apply_one(graph, %{"op" => "move_nodes", "positions" => positions})
       when is_map(positions) do
    if Enum.all?(positions, fn {_id, position} -> position?(position) end) do
      move = fn item ->
        case Map.fetch(positions, item["id"]) do
          {:ok, position} -> Map.put(item, "position", Map.take(position, ["x", "y"]))
          :error -> item
        end
      end

      # Something moved that was removed meanwhile just isn't there to move.
      {:ok,
       %{graph | nodes: Enum.map(graph.nodes, move), comments: Enum.map(graph.comments, move)}}
    else
      {:error, "a position needs a numeric x and y"}
    end
  end

  defp apply_one(graph, %{"op" => "add_connection", "connection" => connection})
       when is_map(connection) do
    [connection] = Graph.normalize_connections([Map.take(connection, @connection_keys)])

    cond do
      connection in graph.connections ->
        {:error, "that connection already exists"}

      !(find(graph.nodes, connection["source"]) && find(graph.nodes, connection["target"])) ->
        {:error, "that connection joins a node that doesn't exist"}

      true ->
        {:ok, %{graph | connections: graph.connections ++ [connection]}}
    end
  end

  defp apply_one(graph, %{"op" => "remove_connection", "connection" => connection})
       when is_map(connection) do
    [connection] = Graph.normalize_connections([Map.take(connection, @connection_keys)])

    if connection in graph.connections,
      do: {:ok, %{graph | connections: List.delete(graph.connections, connection)}},
      else: {:error, "that connection doesn't exist"}
  end

  defp apply_one(graph, %{"op" => "set_connections", "connections" => connections})
       when is_list(connections) do
    {:ok,
     %{
       graph
       | connections:
           Graph.normalize_connections(Enum.map(connections, &Map.take(&1, @connection_keys)))
     }}
  end

  defp apply_one(graph, %{"op" => "add_comment", "comment" => %{"id" => id} = comment})
       when is_map(comment) do
    id = to_string(id)

    if find(graph.comments, id) || find(graph.nodes, id),
      do: {:error, "comment #{id} already exists"},
      else: {:ok, %{graph | comments: graph.comments ++ [Map.put(comment, "id", id)]}}
  end

  defp apply_one(graph, %{"op" => "remove_comment", "id" => id}) do
    id = to_string(id)

    if find(graph.comments, id),
      do: {:ok, %{graph | comments: Enum.reject(graph.comments, &(&1["id"] == id))}},
      else: {:error, "comment #{id} doesn't exist"}
  end

  defp apply_one(graph, %{"op" => "update_comment", "id" => id, "set" => set}) when is_map(set) do
    id = to_string(id)

    if find(graph.comments, id) do
      update = fn comment ->
        if comment["id"] == id do
          set
          |> Map.delete("id")
          |> Enum.reduce(comment, fn
            {key, nil}, comment -> Map.delete(comment, key)
            {key, value}, comment -> Map.put(comment, key, value)
          end)
        else
          comment
        end
      end

      {:ok, %{graph | comments: Enum.map(graph.comments, update)}}
    else
      {:error, "comment #{id} doesn't exist"}
    end
  end

  defp apply_one(_graph, %{"op" => op}) when is_binary(op),
    do: {:error, "unknown operation #{op}"}

  defp apply_one(_graph, _op), do: {:error, "an operation needs an op"}

  ## Helpers

  defp set_node(node, set) do
    Enum.reduce(set, node, fn
      {"controls", controls}, node when is_map(controls) ->
        merged =
          Enum.reduce(controls, node["controls"] || %{}, fn
            {key, nil}, acc -> Map.delete(acc, key)
            {key, value}, acc -> Map.put(acc, key, value)
          end)

        Map.put(node, "controls", merged)

      {"settings", nil}, node ->
        Map.delete(node, "settings")

      {key, value}, node ->
        Map.put(node, key, value)
    end)
  end

  defp node_update(before, now) do
    fields =
      ["label", "type", "settings"]
      |> Enum.filter(&(Map.get(before, &1) != Map.get(now, &1)))
      |> Map.new(&{&1, Map.get(now, &1)})

    before_controls = before["controls"] || %{}
    now_controls = now["controls"] || %{}

    controls =
      now_controls
      |> Enum.reject(fn {key, value} -> Map.get(before_controls, key) == value end)
      |> Map.new()
      |> Map.merge(Map.new(Map.keys(before_controls) -- Map.keys(now_controls), &{&1, nil}))

    set = if controls == %{}, do: fields, else: Map.put(fields, "controls", controls)

    if set == %{}, do: [], else: [%{"op" => "update_node", "id" => now["id"], "set" => set}]
  end

  defp moved?(item, old) do
    case find(old.nodes, item["id"]) || find(old.comments, item["id"]) do
      nil -> false
      before -> before["position"] != item["position"] and position?(item["position"])
    end
  end

  # A section remembers the nodes it holds, see `Heddle.Graph.Section`.
  defp forget_member(%{"nodes" => ids} = comment, id) when is_list(ids),
    do: %{comment | "nodes" => Enum.reject(ids, &(to_string(&1) == id))}

  defp forget_member(comment, _id), do: comment

  defp only(set, allowed) do
    case Map.keys(set) -- allowed do
      [] -> :ok
      unknown -> {:error, "a node has no #{Enum.join(unknown, ", ")} to change"}
    end
  end

  defp find(items, id), do: Enum.find(items, &(to_string(&1["id"]) == to_string(id)))

  defp position?(%{"x" => x, "y" => y}) when is_number(x) and is_number(y), do: true
  defp position?(_position), do: false

  defp field(graph, key), do: Map.get(graph, key) || Map.get(graph, to_string(key)) || []
end
