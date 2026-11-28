defmodule HeddleUI.ChatText do
  @moduledoc """
  An agent's message on a chat page, as HTML: the little Markdown models write, like
  **bold**, *italic*, `code`, lists and paragraphs. Everything is escaped first, so a
  message can't bring HTML of its own, whatever a visitor got the model to write.
  """

  @doc "The HTML of `text`, safe to show."
  def to_html(text) when is_binary(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.trim()
    |> String.split(~r/\n{2,}/)
    |> Enum.map_join(&block/1)
    |> Phoenix.HTML.raw()
  end

  def to_html(_text), do: Phoenix.HTML.raw("")

  defp block(paragraph) do
    lines = String.split(paragraph, "\n")

    cond do
      Enum.all?(lines, &bullet?/1) ->
        "<ul>" <>
          Enum.map_join(lines, &("<li>" <> inline(strip_bullet(&1)) <> "</li>")) <> "</ul>"

      Enum.all?(lines, &numbered?/1) ->
        "<ol>" <>
          Enum.map_join(lines, &("<li>" <> inline(strip_number(&1)) <> "</li>")) <> "</ol>"

      true ->
        "<p>" <> Enum.map_join(lines, "<br>", &inline/1) <> "</p>"
    end
  end

  defp bullet?(line), do: line =~ ~r/^\s*[-*•]\s+/
  defp numbered?(line), do: line =~ ~r/^\s*\d+[.)]\s+/
  defp strip_bullet(line), do: String.replace(line, ~r/^\s*[-*•]\s+/, "")
  defp strip_number(line), do: String.replace(line, ~r/^\s*\d+[.)]\s+/, "")

  defp inline(line) do
    line
    |> String.trim()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace(~r/`([^`]+)`/, "<code>\\1</code>")
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])/, "<em>\\1</em>")
  end
end
