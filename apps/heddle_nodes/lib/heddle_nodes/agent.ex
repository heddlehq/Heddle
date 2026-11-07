defmodule HeddleNodes.Agent do
  @moduledoc """
  Runs an AI Agent node.

  The nodes connected to its `tools` output become tools. The model fills in the
  fields left blank on a node, and what's already set stays out of its reach.
  Credentials, models and code are never offered, so it can't pick a secret or write
  code.

  The LLM and the memory come from config, because heddle_ai depends on this app
  and heddle_core is only one of its test dependencies.
  """

  alias HeddleNodes.Nodes

  @json_instruction "Reply with a single valid JSON value and nothing else."
  @max_tool_output 20_000

  @doc """
  Answers `request`. `run_tool` runs a node with its new controls and input.

  Returns `{:ok, value, calls, logs}` or `{:error, message, calls, logs}`.
  """
  def run(%{prompt: prompt} = request, flow_id, tool_nodes, run_tool) do
    if String.trim(prompt) == "" do
      {:error, "The prompt is empty.", [], []}
    else
      ref = make_ref()
      tools = build_tools(tool_nodes, run_tool, {self(), ref})
      history = load_memory(flow_id, request)
      user = %{role: "user", content: prompt}

      reply = llm().run(history ++ [user], options(request, tools))
      {calls, logs} = collect(ref, [], [])

      with {:ok, text} <- reply,
           {:ok, value} <- decode(text, request.output) do
        save_memory(flow_id, request, history ++ [user, %{role: "assistant", content: text}])
        {:ok, value, calls, logs}
      else
        {:error, error} -> {:error, error, calls, logs}
      end
    end
  end

  defp options(request, tools) do
    [
      tools: tools,
      system: system(request),
      credential: request[:credential],
      model: request.model,
      temperature: request.temperature,
      max_steps: request.max_steps
    ]
  end

  defp system(%{output: "json", system: nil}), do: @json_instruction
  defp system(%{output: "json", system: system}), do: system <> "\n\n" <> @json_instruction
  defp system(%{system: system}), do: system

  defp decode(text, "json") do
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/\A```(?:json)?\s*/, "")
      |> String.replace(~r/\s*```\z/, "")

    case Jason.decode(cleaned) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, %{"error" => "The reply is not JSON.", "reply" => text}}
    end
  end

  defp decode(text, _output), do: {:ok, text}

  defp load_memory(_flow_id, %{memory_key: nil}), do: []
  defp load_memory(flow_id, %{memory_key: key}), do: memory().load(flow_id, key)

  defp save_memory(_flow_id, %{memory_key: nil}, _messages), do: :ok

  defp save_memory(flow_id, %{memory_key: key}, messages),
    do: memory().save(flow_id, key, messages)

  defp build_tools(nodes, run_tool, target) do
    nodes
    |> Enum.reduce({[], MapSet.new()}, fn node, {tools, names} ->
      name = unique_name(node, names)
      {[build_tool(node, name, run_tool, target) | tools], MapSet.put(names, name)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp build_tool(node, name, run_tool, target) do
    definition = Nodes.get_node(node.type) || %{}
    fields = open_fields(node, definition)
    allowed = Enum.map(fields, &to_string(&1.name))

    fun = fn args ->
      args = Map.new(args, fn {key, value} -> {to_string(key), value} end)
      controls = Map.merge(node.controls, Map.take(args, allowed))

      name
      |> call_tool(args, run_tool.(%{node | controls: controls}, args["input"]), target)
    end

    llm().tool(name, description(node, definition), schema(fields), fun)
  end

  defp call_tool(name, args, {:ok, context}, {parent, ref}) do
    send(parent, {ref, %{"tool" => name, "args" => args, "ok" => true}, context["logs"] || []})

    {:ok, tool_output(context["result"])}
  end

  defp call_tool(name, args, {:error, reason, _node_id, _context}, {parent, ref}) do
    send(parent, {ref, %{"tool" => name, "args" => args, "ok" => false}, []})

    {:error, if(is_binary(reason), do: reason, else: inspect(reason))}
  end

  defp tool_output(nil), do: "Done."

  # The model can't read base64, and it would fill its context.
  defp tool_output(%{"encoding" => "base64", "type" => type}) do
    "Done. The result is a #{type} file, which the next step of the flow gets."
  end

  defp tool_output(result) do
    result |> Jason.encode!() |> String.slice(0, @max_tool_output)
  end

  defp collect(ref, calls, logs) do
    receive do
      {^ref, call, new_logs} -> collect(ref, [call | calls], logs ++ new_logs)
    after
      0 -> {Enum.reverse(calls), logs}
    end
  end

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

  defp description(node, definition) do
    "#{node.label}: #{Map.get(definition, :description, "A step of this flow.")}"
  end

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

  defp llm, do: Application.fetch_env!(:heddle_nodes, :llm_client)
  defp memory, do: Application.fetch_env!(:heddle_nodes, :agent_memory)
end
