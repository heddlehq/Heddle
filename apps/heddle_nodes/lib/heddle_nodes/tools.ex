defmodule HeddleNodes.Tools do
  @moduledoc """
  The nodes connected to a node's `tools` output, as tools a model can call.

  The model fills in the fields left blank on a node, and what's already set stays out
  of its reach. Credentials, models and code are never offered, so it can't pick a
  secret or write code. A node with nothing left blank takes an `input`, which the
  steps after it read.

  The AI Agent uses them, and so does any node that returns `{:with_tools, fun}` to the
  runner, like a node of a package that brings its own agent.
  """

  alias HeddleNodes.Nodes

  @max_output 20_000

  @typedoc "A tool: what the model sees, and the node it runs."
  @type t :: %{
          name: String.t(),
          description: String.t(),
          parameters: map(),
          node: map(),
          allowed: [String.t()]
        }

  @doc "The tools for `nodes`, each with a name no other one has."
  @spec build([map()]) :: [t()]
  def build(nodes) do
    nodes
    |> Enum.reduce({[], MapSet.new()}, fn node, {tools, names} ->
      name = unique_name(node, names)
      {[tool(node, name) | tools], MapSet.put(names, name)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  @doc "What a model is told about `tool`: its name, description and JSON Schema."
  def describe(tool), do: Map.take(tool, [:name, :description, :parameters])

  @doc """
  Runs `tool` with the arguments the model gave, through `run_node`, which takes the
  node with its new controls and the `input`, and answers like `Runner.execute_node`.

  Returns `{:ok, output, call, logs}`, with what the model reads back, or
  `{:error, message, call}`. `call` is the entry for the run's `tool_calls`.
  """
  def call(tool, args, run_node) do
    args = Map.new(args || %{}, fn {key, value} -> {to_string(key), value} end)
    controls = Map.merge(tool.node.controls, Map.take(args, tool.allowed))
    call = %{"tool" => tool.name, "args" => args}

    case run_node.(%{tool.node | controls: controls}, args["input"]) do
      {:ok, context} ->
        {:ok, output(context["result"]), Map.put(call, "ok", true), context["logs"] || []}

      {:error, reason, _node_id, _context} ->
        message = if is_binary(reason), do: reason, else: inspect(reason)
        {:error, message, Map.put(call, "ok", false)}
    end
  end

  defp tool(node, name) do
    definition = Nodes.get_node(node.type) || %{}
    fields = open_fields(node, definition)

    %{
      name: name,
      description: "#{node.label}: #{Map.get(definition, :description, "A step of this flow.")}",
      parameters: schema(fields),
      node: node,
      allowed: Enum.map(fields, &to_string(&1.name))
    }
  end

  defp output(nil), do: "Done."

  # The model can't read base64, and it would fill its context.
  defp output(%{"encoding" => "base64", "type" => type}) do
    "Done. The result is a #{type} file, which the next step of the flow gets."
  end

  defp output(result), do: result |> Jason.encode!() |> String.slice(0, @max_output)

  defp open_fields(node, definition) do
    definition
    |> Map.get(:ui_fields, [])
    |> Enum.reject(&(&1.type in [:credential, :code, :model]))
    |> Enum.filter(&blank?(node.controls[to_string(&1.name)]))
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp schema([]) do
    input = %{type: "string", description: "What to pass to this step, if it needs anything."}

    %{type: "object", properties: %{"input" => input}, required: []}
  end

  defp schema(fields) do
    properties = Map.new(fields, &{to_string(&1.name), property(&1)})

    %{type: "object", properties: properties, required: Map.keys(properties)}
  end

  defp property(%{type: :select, options: options} = field) do
    %{type: "string", description: field.label, enum: Enum.map(options, &option/1)}
  end

  defp property(field), do: %{type: "string", description: field.label}

  defp option(%{value: value}), do: value
  defp option(value), do: to_string(value)

  defp unique_name(node, names) do
    base =
      (node.label || node.type)
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")
      |> then(&if(&1 =~ ~r/\A[a-z]/, do: &1, else: "tool_" <> &1))
      |> String.slice(0, 48)

    if MapSet.member?(names, base), do: "#{base}_#{node.id}", else: base
  end
end
