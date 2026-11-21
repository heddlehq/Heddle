defmodule HeddleNodes.Usage do
  @moduledoc """
  What the model calls of each step of a run cost: how many, their tokens, and their
  price in US dollars when the model's price is known.

  Each step opens a frame when it starts, see `enter/0`, and its log entry closes it,
  see `leave/1`. A call adds to the frame on top, so an AI Agent pays for its own calls
  and each tool it runs, a step of its own, pays for its own. Summing the steps of a
  run never counts a call twice.

  It lives in the process dictionary, where the runner works. A call outside a run,
  like the editor's chat, finds no frame and is not counted.
  """

  @stack {__MODULE__, :stack}
  @zero %{calls: 0, input_tokens: 0, output_tokens: 0, cost: nil}

  @doc "Opens a frame for a step, and returns what closes it."
  def enter do
    ref = make_ref()
    Process.put(@stack, [{ref, @zero} | Process.get(@stack, [])])
    ref
  end

  @doc """
  Closes the frame `ref` opened, and returns what it holds as the `"usage"` of a log
  entry, or `nil` when it made no call. A frame a step above it left open is closed
  too, and what it holds counts here, so no call is lost.
  """
  def leave(ref) do
    stack = Process.get(@stack, [])

    case Enum.split_while(stack, fn {frame, _usage} -> frame != ref end) do
      {above, [{^ref, usage} | below]} ->
        Process.put(@stack, below)
        above |> Enum.map(&elem(&1, 1)) |> Enum.reduce(usage, &merge/2) |> entry()

      {_above, []} ->
        nil
    end
  end

  @doc """
  Adds a call to the step on top, from the usage `req_llm` reports, which has
  `:input_tokens`, `:output_tokens` and `:total_cost`, any of them missing.
  """
  def record(usage) do
    case Process.get(@stack, []) do
      [{ref, current} | below] ->
        Process.put(@stack, [{ref, add(current, usage || %{})} | below])
        :ok

      [] ->
        :ok
    end
  end

  @doc """
  The usage of a whole run, from the log entries of its steps, or `nil` when none
  made a call.
  """
  def total(logs) when is_list(logs) do
    logs
    |> Enum.map(&(is_map(&1) && &1["usage"]))
    |> Enum.filter(&is_map/1)
    |> case do
      [] ->
        nil

      usages ->
        usages
        |> Enum.reduce(@zero, fn usage, acc ->
          %{
            calls: acc.calls + (usage["calls"] || 0),
            input_tokens: acc.input_tokens + (usage["input_tokens"] || 0),
            output_tokens: acc.output_tokens + (usage["output_tokens"] || 0),
            cost: add_cost(acc.cost, usage["cost"])
          }
        end)
        |> entry()
    end
  end

  def total(_logs), do: nil

  defp merge(frame, acc) do
    %{
      calls: acc.calls + frame.calls,
      input_tokens: acc.input_tokens + frame.input_tokens,
      output_tokens: acc.output_tokens + frame.output_tokens,
      cost: add_cost(acc.cost, frame.cost)
    }
  end

  defp add(acc, usage) do
    %{
      calls: acc.calls + 1,
      input_tokens: acc.input_tokens + number(usage, :input_tokens),
      output_tokens: acc.output_tokens + number(usage, :output_tokens),
      cost: add_cost(acc.cost, cost(usage))
    }
  end

  defp cost(usage) do
    case usage[:total_cost] || usage["total_cost"] do
      cost when is_number(cost) -> cost
      _unknown -> nil
    end
  end

  defp add_cost(nil, nil), do: nil
  defp add_cost(acc, cost), do: (acc || 0) + (cost || 0)

  defp number(usage, key) do
    case usage[key] || usage[to_string(key)] do
      value when is_integer(value) -> value
      _missing -> 0
    end
  end

  defp entry(%{calls: 0}), do: nil

  defp entry(usage) do
    %{
      "calls" => usage.calls,
      "input_tokens" => usage.input_tokens,
      "output_tokens" => usage.output_tokens
    }
    |> then(fn entry ->
      if usage.cost, do: Map.put(entry, "cost", Float.round(usage.cost * 1.0, 6)), else: entry
    end)
  end
end
