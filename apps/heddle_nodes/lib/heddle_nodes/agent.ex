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

  alias HeddleNodes.Tools

  @json_instruction "Reply with a single valid JSON value and nothing else."

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

  defp build_tools(nodes, run_tool, {parent, ref}) do
    for tool <- Tools.build(nodes) do
      fun = fn args ->
        case Tools.call(tool, args, run_tool) do
          {:ok, output, call, logs} ->
            send(parent, {ref, call, logs})
            {:ok, output}

          {:error, message, call} ->
            send(parent, {ref, call, []})
            {:error, message}
        end
      end

      llm().tool(tool.name, tool.description, tool.parameters, fun)
    end
  end

  defp collect(ref, calls, logs) do
    receive do
      {^ref, call, new_logs} -> collect(ref, [call | calls], logs ++ new_logs)
    after
      0 -> {Enum.reverse(calls), logs}
    end
  end

  defp llm, do: Application.fetch_env!(:heddle_nodes, :llm_client)
  defp memory, do: Application.fetch_env!(:heddle_nodes, :agent_memory)
end
