defmodule HeddleNodes.Template do
  @moduledoc """
  Reads values from a run's context, and fills `{{name}}` placeholders with them.

  A name can be a dotted path, like `body.user.name`. Flow variables come first,
  then the context.
  """

  @placeholder ~r/\{\{(.*?)\}\}/

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

  defp dig(value, []), do: value
  defp dig(%{} = value, [key | rest]), do: value |> Map.get(key) |> dig(rest)
  defp dig(_value, _path), do: nil

  defp to_text(nil), do: ""
  defp to_text(value) when is_binary(value), do: value
  defp to_text(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp to_text(value), do: to_string(value)
end
