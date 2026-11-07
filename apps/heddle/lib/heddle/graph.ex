defmodule Heddle.Graph do
  @moduledoc """
  A flow as the engine sees it: its steps and what runs after each one.

  This is the only place that knows how a flow is stored. The editor, the API and
  the agents all write the same plain maps, and everything that reads them comes
  through here, so nothing depends on what draws the flow.

  Connections leaving the same output run one after the other, in the order they are
  listed, and each one sees what the previous one left in the context. Whatever
  writes a flow must keep that order.
  """

  alias Heddle.Graph.Node

  @default_input "exec"

  # A field of the body, the way code and placeholders read it: `variable(:body)["x"]`,
  # `variable("body")["x"]`, `body["x"]`, `body.x` and `{{body.x}}`.
  @body_field ~r/\bbody(?:"?\))?(?:\[["'](\w+)["']\]|\.(\w+))/

  defstruct nodes: [], nodes_by_id: %{}, targets: %{}

  @doc "Reads the `:nodes` and `:connections` of a flow."
  def new(%{nodes: nodes, connections: connections}) do
    nodes = nodes |> normalize_nodes() |> Enum.map(&Node.new/1)

    targets =
      connections
      |> normalize_connections()
      |> Enum.group_by(&{&1["source"], &1["sourceOutput"]}, & &1["target"])

    %__MODULE__{nodes: nodes, nodes_by_id: Map.new(nodes, &{&1.id, &1}), targets: targets}
  end

  @doc "Returns the node with `id`, or nil."
  def get(%__MODULE__{nodes_by_id: nodes}, id), do: Map.get(nodes, to_string(id))

  @doc "Returns the nodes of `type`, in the order the flow lists them."
  def of_type(%__MODULE__{nodes: nodes}, type), do: Enum.filter(nodes, &(&1.type == type))

  @doc "Returns the nodes connected to `output` of `node`, in the order they run."
  def next(%__MODULE__{} = graph, %Node{id: id}, output) do
    graph.targets
    |> Map.get({id, to_string(output)}, [])
    |> Enum.flat_map(&List.wrap(get(graph, &1)))
  end

  @doc """
  Returns the fields of a request body the nodes read, in the order they appear.

  It looks at what is written in them, so it knows only what is spelled out.
  """
  def body_fields(%__MODULE__{nodes: nodes}) do
    nodes
    |> Enum.flat_map(&Map.values(&1.controls))
    |> Enum.filter(&is_binary/1)
    |> Enum.flat_map(&Regex.scan(@body_field, &1, capture: :all_but_first))
    |> Enum.map(fn captures -> Enum.find(captures, &(&1 != "")) end)
    |> Enum.uniq()
  end

  @doc """
  Gives nodes the form they are stored in: a string id, and always a `type`.

  Older flows may have only a `label`.
  """
  def normalize_nodes(nodes) do
    nodes
    |> List.wrap()
    |> Enum.map(fn node -> node |> stringify_id("id") |> put_type() end)
  end

  @doc """
  Gives connections the form they are stored in: string ids, and always a `targetInput`.
  """
  def normalize_connections(connections) do
    connections
    |> List.wrap()
    |> Enum.map(fn connection ->
      connection
      |> stringify_id("source")
      |> stringify_id("target")
      |> put_target_input()
    end)
  end

  defp stringify_id(map, key) do
    case map do
      %{^key => id} when is_integer(id) -> Map.put(map, key, Integer.to_string(id))
      _other -> map
    end
  end

  defp put_type(%{"type" => type} = node) when is_binary(type) and type != "", do: node
  defp put_type(%{"label" => label} = node), do: Map.put(node, "type", label)
  defp put_type(node), do: node

  defp put_target_input(%{"targetInput" => input} = connection) when not is_nil(input) do
    connection
  end

  defp put_target_input(connection), do: Map.put(connection, "targetInput", @default_input)
end
