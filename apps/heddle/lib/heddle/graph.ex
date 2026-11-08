defmodule Heddle.Graph do
  @moduledoc """
  A flow as the engine sees it: its steps and what runs after each one.

  This is the only place that knows how a flow is stored. The editor, the API and
  the agents all write the same plain maps, and everything that reads them comes
  through here, so nothing depends on what draws the flow.

  Connections leaving the same output run one after the other, in the order they are
  listed, and each one sees what the previous one left in the context. Whatever
  writes a flow must keep that order.

  The nodes of a manual section (see `Heddle.Graph.Section`) are not part of the flow
  as it runs: nothing finds them, and a branch that leads to one stops there. They
  run only with `new(flow, section: id)`, which takes that section alone.
  """

  alias Heddle.Graph.Node
  alias Heddle.Graph.Section

  @default_input "exec"

  # A field of the body, the way code and placeholders read it: `variable(:body)["x"]`,
  # `variable("body")["x"]`, `body["x"]`, `body.x` and `{{body.x}}`.
  @body_field ~r/\bbody(?:"?\))?(?:\[["'](\w+)["']\]|\.(\w+))/

  defstruct nodes: [],
            nodes_by_id: %{},
            targets: %{},
            sources: %{},
            held: %{},
            held_ids: MapSet.new(),
            section: nil

  @doc """
  Reads the `:nodes`, `:connections` and `:comments` of a flow.

  With `section: id`, it takes only the nodes of that section and the connections
  between them. `section/1` is then nil if the flow has no such section.
  """
  def new(%{nodes: nodes, connections: connections} = flow, opts \\ []) do
    all = nodes |> normalize_nodes() |> Enum.map(&Node.new/1)
    sections = sections(flow)

    {section, kept} = kept_nodes(all, sections, opts[:section])
    kept_ids = MapSet.new(kept, & &1.id)
    all_by_id = Map.new(all, &{&1.id, &1})

    held_ids =
      if section,
        do: MapSet.new(),
        else: all_by_id |> Map.keys() |> MapSet.new() |> MapSet.difference(kept_ids)

    by_output =
      connections
      |> normalize_connections()
      |> Enum.filter(&MapSet.member?(kept_ids, &1["source"]))
      |> Enum.group_by(&{&1["source"], &1["sourceOutput"]}, & &1["target"])

    targets =
      Map.new(by_output, fn {key, ids} ->
        {key, Enum.filter(ids, &MapSet.member?(kept_ids, &1))}
      end)

    %__MODULE__{
      nodes: kept,
      nodes_by_id: Map.new(kept, &{&1.id, &1}),
      targets: targets,
      sources: sources(targets),
      held: held(by_output, held_ids, all_by_id),
      held_ids: held_ids,
      section: section
    }
  end

  defp kept_nodes(nodes, sections, nil) do
    manual = manual_ids(sections)
    {nil, Enum.reject(nodes, &MapSet.member?(manual, &1.id))}
  end

  defp kept_nodes(nodes, sections, id) do
    case Enum.find(sections, &(&1.id == to_string(id))) do
      nil ->
        {nil, []}

      section ->
        members = MapSet.new(section.nodes)
        {section, Enum.filter(nodes, &MapSet.member?(members, &1.id))}
    end
  end

  defp manual_ids(sections) do
    for %Section{manual: true, nodes: ids} <- sections, id <- ids, into: MapSet.new(), do: id
  end

  # Running a section takes all of it, the manual sections inside it too, and what
  # leaves it was never part of the run: only a manual section holds nodes back.
  defp held(by_output, held_ids, all_by_id) do
    for {key, ids} <- by_output,
        held = for(id <- ids, MapSet.member?(held_ids, id), do: all_by_id[id]),
        held != [],
        into: %{},
        do: {key, held}
  end

  defp sources(targets) do
    for {from, ids} <- targets, id <- Enum.uniq(ids), reduce: %{} do
      acc -> Map.update(acc, id, [from], &(&1 ++ [from]))
    end
  end

  @doc "Returns the sections of a flow, in the order its comments list them."
  def sections(flow), do: flow |> Map.get(:comments) |> Section.list()

  @doc "Returns the section `new(flow, section: id)` took, or nil."
  def section(%__MODULE__{section: section}), do: section

  @doc """
  Returns the nodes a section starts from: the ones nothing in it leads to, in the
  order the section lists them.
  """
  def entries(%__MODULE__{section: nil}), do: []

  def entries(%__MODULE__{section: section} = graph) do
    led_to = graph.targets |> Map.values() |> List.flatten() |> MapSet.new()

    section.nodes
    |> Enum.flat_map(&List.wrap(get(graph, &1)))
    |> Enum.reject(&MapSet.member?(led_to, &1.id))
  end

  @doc """
  Returns the nodes `output` of `node` leads to that are in a manual section, so
  they don't run with the flow.
  """
  def held_back(%__MODULE__{held: held}, %Node{id: id}, output) do
    Map.get(held, {id, to_string(output)}, [])
  end

  @doc "Whether a manual section keeps nodes of the flow from running with it."
  def holds_back?(%__MODULE__{held_ids: ids}), do: MapSet.size(ids) > 0

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
  Returns the outputs that lead to `node`, as `{source_id, output}`, one for each
  connection that arrives at it, whatever input it arrives at.
  """
  def incoming(%__MODULE__{sources: sources}, %Node{id: id}), do: Map.get(sources, id, [])

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
