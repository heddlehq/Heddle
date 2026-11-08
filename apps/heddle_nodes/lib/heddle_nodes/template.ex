defmodule HeddleNodes.Template do
  @moduledoc """
  Reads values from a run's context, and fills `{{name}}` placeholders with them.

  A name can be a dotted path, like `body.user.name`, where a number picks an item of
  a list, like `body.items.0.name`. Flow variables come first, then the context.
  """

  @placeholder ~r/\{\{(.*?)\}\}/
  # Stands for a placeholder while the JSON around it is parsed. A flow can't write it
  # by accident, because it starts with a NUL.
  @value_mark ~S("\u0000)

  def fetch(context, path) when is_map(context) and is_binary(path) do
    [first | rest] = path |> String.trim() |> String.split(".")

    context
    |> Map.get("variables", %{})
    |> Map.get(first, Map.get(context, first))
    |> dig(rest)
  end

  def render(template, context) when is_binary(template) do
    Regex.replace(@placeholder, template, fn _match, path ->
      context |> fetch(path) |> to_text()
    end)
  end

  def render(_template, _context), do: ""

  @doc """
  Reads a template that holds JSON, and returns the value it describes.

  The JSON is parsed before anything is filled in, so what a run brings is data and
  can't change the shape the flow's author wrote. A placeholder outside a string takes
  the value as it is, and one inside a string is written into that string.

  `check` sees each of those values and can refuse one with `{:error, message}`.
  """
  def json(template, context, check \\ fn _value -> :ok end) do
    {text, paths} = isolate(template, [], [])

    case Jason.decode(IO.iodata_to_binary(text)) do
      {:ok, value} -> {:ok, fill(value, paths, context, check)}
      {:error, error} -> {:error, "This isn't valid JSON: #{Exception.message(error)}"}
    end
  catch
    {:refused, message} -> {:error, message}
  end

  defp isolate(<<>>, text, paths), do: {Enum.reverse(text), Enum.reverse(paths)}

  defp isolate(<<?", rest::binary>>, text, paths) do
    {string, rest} = take_string(rest, [?"])

    isolate(rest, [string | text], paths)
  end

  defp isolate("{{" <> rest, text, paths) do
    case String.split(rest, "}}", parts: 2) do
      [path, rest] ->
        isolate(rest, [[@value_mark, Integer.to_string(length(paths)), ?"] | text], [path | paths])

      [_unclosed] ->
        isolate(<<>>, [["{{", rest] | text], paths)
    end
  end

  defp isolate(<<char, rest::binary>>, text, paths), do: isolate(rest, [char | text], paths)

  defp take_string(<<?\\, char, rest::binary>>, acc), do: take_string(rest, [acc, ?\\, char])
  defp take_string(<<?", rest::binary>>, acc), do: {[acc, ?"], rest}
  defp take_string(<<char, rest::binary>>, acc), do: take_string(rest, [acc, char])
  defp take_string(<<>>, acc), do: {acc, <<>>}

  defp fill(%{} = map, paths, context, check) do
    Map.new(map, fn {key, value} ->
      {render(key, context), fill(value, paths, context, check)}
    end)
  end

  defp fill(list, paths, context, check) when is_list(list) do
    Enum.map(list, &fill(&1, paths, context, check))
  end

  defp fill(<<0, index::binary>>, paths, context, check) do
    value = fetch(context, Enum.at(paths, String.to_integer(index)))

    case check.(value) do
      :ok -> value
      {:error, message} -> throw({:refused, message})
    end
  end

  defp fill(text, _paths, context, _check) when is_binary(text), do: render(text, context)
  defp fill(value, _paths, _context, _check), do: value

  defp dig(value, []), do: value
  defp dig(%{} = value, [key | rest]), do: value |> Map.get(key) |> dig(rest)

  # `items.0.name` reads the first item of a list.
  defp dig(list, [index | rest]) when is_list(list) do
    case Integer.parse(index) do
      {position, ""} when position >= 0 -> list |> Enum.at(position) |> dig(rest)
      _not_a_position -> nil
    end
  end

  defp dig(_value, _path), do: nil

  defp to_text(nil), do: ""
  defp to_text(value) when is_binary(value), do: value
  defp to_text(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp to_text(value), do: to_string(value)
end
