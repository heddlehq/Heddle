defmodule HeddleNodes.Trace do
  @moduledoc """
  What a run keeps of each step, to look at afterwards: the context the node got, what
  it changed, and how long it took.

  It is kept in the step's log entry, so it has to stay small whatever went through
  the run. A long text is cut, a file shows only its size, a long list keeps its first
  items, and past a number of values the rest is left out. Anything cut marks the step
  `"truncated"`, so nothing takes it for the whole value: a run can only start again
  from a step that is whole.

  Only the first 500 steps of a run keep their data. The rest keep their timing.
  """

  @max_string 2_000
  @max_items 100
  @max_depth 8
  @max_values 2_000
  @max_steps 500
  @counter {__MODULE__, :steps}
  @cut "…"

  @doc "Starts counting the steps of a run in this process."
  def start, do: Process.put(@counter, 0)

  @doc """
  Returns the data of a step, from the context before it and the context after, both
  without what is internal to the run: `%{"input" => ..., "output" => ...}`, where the
  output is what the step added or changed, with `"removed"` for the keys it took
  away. Returns `%{"omitted" => true}` once the run has too many steps.
  """
  def step(before, after_step) do
    count = Process.get(@counter, 0)
    Process.put(@counter, count + 1)

    if count < @max_steps do
      {input, cut_input} = snapshot(before)
      {output, cut_output} = snapshot(changes(before, after_step))

      %{"input" => input, "output" => output}
      |> maybe_put("removed", removed(before, after_step))
      |> maybe_put("truncated", cut_input or cut_output)
    else
      %{"omitted" => true}
    end
  end

  @doc "What `after_step` has that `before` didn't, or has with another value."
  def changes(before, after_step) when is_map(before) and is_map(after_step) do
    Map.filter(after_step, fn {key, value} ->
      not Map.has_key?(before, key) or Map.get(before, key) != value
    end)
  end

  def changes(_before, after_step) when is_map(after_step), do: after_step
  def changes(_before, _after_step), do: %{}

  defp removed(before, after_step) when is_map(before) and is_map(after_step) do
    case Map.keys(before) -- Map.keys(after_step) do
      [] -> nil
      keys -> Enum.sort(keys)
    end
  end

  defp removed(_before, _after_step), do: nil

  @doc """
  Returns `{value, truncated?}`: `value` made into plain JSON, within the limits above.
  """
  def snapshot(value) do
    {value, {_budget, cut}} = walk(value, 0, {@max_values, false})
    {value, cut}
  end

  defp walk(_value, _depth, {budget, _cut}) when budget <= 0, do: {@cut, {0, true}}
  defp walk(_value, depth, {budget, _cut}) when depth > @max_depth, do: {@cut, {budget, true}}

  defp walk(%{"encoding" => "base64", "content" => content} = file, _depth, {budget, _cut} = acc)
       when is_binary(content) do
    {file
     |> Map.delete("content")
     |> Map.put("size", div(byte_size(content) * 3, 4)), mark(acc, budget - 1)}
  end

  defp walk(%_struct{} = struct, _depth, {budget, cut}) do
    {inspect(struct, limit: 20, printable_limit: 200), {budget - 1, cut}}
  end

  defp walk(%{} = map, depth, acc) do
    {pairs, acc} =
      map
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> take(@max_items, acc)

    {pairs, acc} =
      Enum.map_reduce(pairs, acc, fn {key, value}, acc ->
        {value, acc} = walk(value, depth + 1, spend(acc))
        {{to_string(key), value}, acc}
      end)

    {Map.new(pairs), acc}
  end

  defp walk(list, depth, acc) when is_list(list) do
    {items, acc} = take(list, @max_items, acc)
    {items, acc} = Enum.map_reduce(items, acc, &walk(&1, depth + 1, spend(&2)))

    if length(items) < length(list) do
      {items ++ ["#{@cut} #{length(list) - length(items)} more"], acc}
    else
      {items, acc}
    end
  end

  defp walk(text, _depth, acc) when is_binary(text) do
    cond do
      not String.valid?(text) ->
        {"<#{byte_size(text)} bytes>", mark(acc)}

      String.length(text) > @max_string ->
        {String.slice(text, 0, @max_string) <> @cut, mark(acc)}

      true ->
        {text, acc}
    end
  end

  defp walk(value, _depth, acc) when is_number(value) or is_boolean(value) or is_nil(value),
    do: {value, acc}

  defp walk(atom, _depth, acc) when is_atom(atom), do: {Atom.to_string(atom), acc}

  defp walk(tuple, depth, acc) when is_tuple(tuple),
    do: walk(Tuple.to_list(tuple), depth, mark(acc))

  defp walk(other, _depth, acc), do: {inspect(other, limit: 20), mark(acc)}

  defp take(enum, max, acc) do
    case Enum.split(enum, max) do
      {kept, []} -> {kept, acc}
      {kept, _rest} -> {kept, mark(acc)}
    end
  end

  defp spend({budget, cut}), do: {budget - 1, cut}
  defp mark({budget, _cut}), do: {budget, true}
  defp mark({_budget, _cut}, budget), do: {budget, true}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, false), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
