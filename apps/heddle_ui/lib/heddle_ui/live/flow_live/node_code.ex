defmodule HeddleUI.FlowLive.NodeCode do
  @moduledoc """
  Works out the code a node holds, for the config drawer and the code modal.

  A node keeps its code in `code_elixir` and `code_python`. Older nodes have it
  in `code`, which counts for the node's language when that language's own field
  is blank, the same way `HeddleNodes.Nodes.Eval` picks the code at run time.
  """

  @default_language "elixir"

  @doc """
  Resolves the code from the controls of a node in the drawer, where each control
  is a map with a `"value"`.
  """
  def from_controls(controls) when is_map(controls) do
    controls
    |> Map.take(["language", "code", "code_elixir", "code_python"])
    |> Map.new(fn {key, control} -> {key, control["value"]} end)
    |> resolve()
  end

  @doc """
  Resolves the code from plain values under the keys `"language"`, `"code"`,
  `"code_elixir"` and `"code_python"`.
  """
  def resolve(values) when is_map(values) do
    language = present(values["language"]) || @default_language
    older = present(values["code"]) || ""

    %{
      language: language,
      code_elixir: code_for("elixir", values["code_elixir"], language, older),
      code_python: code_for("python", values["code_python"], language, older)
    }
  end

  @doc """
  Returns the code of the selected language.
  """
  def current(%{language: "python", code_python: code}), do: code
  def current(%{code_elixir: code}), do: code

  defp code_for(field_language, value, language, older) do
    cond do
      code = present(value) -> code
      field_language == language -> older
      true -> ""
    end
  end

  defp present(value) when is_binary(value) do
    if String.trim(value) != "", do: value
  end

  defp present(_value), do: nil
end
