defmodule HeddleUI.FlowLive.AgentSteps do
  @moduledoc """
  Asks the editor's agent to turn what an AI Agent node did in one run into steps of
  the flow, so the next runs do the same without a model deciding each time.

  It writes the request from the run: the node's prompt, what it got, the tools it
  called with their arguments and what each returned, and what it answered. The agent
  then plans the change and makes it on the draft, like any other request in the chat.
  """

  alias Heddle.Graph

  # What goes to the model stays readable: a value this long is cut.
  @max_value 1_500

  @doc """
  Whether a step is one this can turn into steps: an AI Agent that succeeded and used
  at least one tool.
  """
  def eligible?(%{"node_type" => "AI Agent", "status" => "success"} = step),
    do: tool_calls(step) != []

  def eligible?(_step), do: false

  @doc """
  Writes the request for the step at `index` of `steps`, the log of a run of `flow`.

  Returns `{:ok, text}`, or `:error` when the step isn't eligible or its node is no
  longer in the flow.
  """
  def request(flow, steps, index, run_id) do
    step = Enum.at(steps, index)
    graph = Graph.new(flow)

    with true <- is_map(step) and eligible?(step),
         %{} = node <- Graph.get(graph, step["node_id"]) do
      tools = graph |> Graph.next(node, "tools") |> MapSet.new(& &1.id)
      {:ok, text(node, step, tool_steps(steps, index, node.id, tools), run_id)}
    else
      _other -> :error
    end
  end

  defp text(node, step, tool_steps, run_id) do
    data = step["data"] || %{}

    """
    Turn the AI Agent "#{node.label || node.type}" (node `#{node.id}`) into steps that don't need a model, from what it did in run #{run_id}.

    Its prompt:
    #{block(node.controls["prompt"])}
    #{system(node.controls["system"])}
    What it got:
    #{block(data["input"])}

    The tools it called, in order:
    #{calls(tool_calls(step), tool_steps)}

    What it answered:
    #{block(get_in(data, ["output", "result"]))}

    Replace the AI Agent with the nodes it used, wired in the order it used them, so the flow does the same thing without a model deciding on each run. Where a value came from the run, write it as a {{placeholder}} of the context, not as the value of this run. Keep an AI node, like Classify, Extract Data or Summarize, only where a step really needs judgment, and say which and why. Keep connected what came after the AI Agent. Tell me the plan before you change the flow.
    """
    |> String.trim()
  end

  defp system(value) when value in [nil, ""], do: ""
  defp system(value), do: "\nIts instructions:\n#{block(value)}\n"

  defp calls(calls, tool_steps) do
    calls
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {call, number} ->
      returned =
        case Enum.at(tool_steps, number - 1) do
          %{"data" => %{"output" => %{"result" => result}}} ->
            "\n   It returned: " <> inline(result)

          _unknown ->
            ""
        end

      status = if call["ok"], do: "", else: " (it failed)"

      "#{number}. `#{call["tool"]}` with #{inline(call["args"] || %{})}#{status}#{returned}"
    end)
  end

  # The steps of the agent's tools in this turn: after the last time the agent ran
  # before, so a loop that ran it again doesn't mix two turns.
  defp tool_steps(steps, index, agent_id, tools) do
    steps
    |> Enum.take(index)
    |> Enum.reverse()
    |> Enum.take_while(&(&1["node_id"] != agent_id))
    |> Enum.reverse()
    |> Enum.filter(&MapSet.member?(tools, &1["node_id"]))
  end

  defp tool_calls(step) do
    case get_in(step, ["data", "output", "tool_calls"]) do
      calls when is_list(calls) -> Enum.filter(calls, &is_map/1)
      _none -> []
    end
  end

  defp block(nil), do: "(nothing)"
  defp block(value) when is_binary(value), do: "```\n#{cut(value)}\n```"
  defp block(value), do: "```json\n#{value |> Jason.encode!(pretty: true) |> cut()}\n```"

  defp inline(value) when is_binary(value), do: "`#{cut(value)}`"
  defp inline(value), do: "`#{value |> Jason.encode!() |> cut()}`"

  defp cut(text) when byte_size(text) > @max_value,
    do: String.slice(text, 0, @max_value) <> "…"

  defp cut(text), do: text
end
