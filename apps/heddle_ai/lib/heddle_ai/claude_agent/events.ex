defmodule HeddleAI.ClaudeAgent.Events do
  @moduledoc """
  Reads the `stream-json` output of `claude -p`.
  """

  @doc """
  Turns one output line into stream events.

  Lines that aren't JSON come from stderr and are dropped.
  """
  def parse(line) do
    case Jason.decode(line) do
      {:ok, event} -> from_event(event)
      {:error, _reason} -> []
    end
  end

  defp from_event(%{
         "type" => "stream_event",
         "event" => %{
           "type" => "content_block_delta",
           "delta" => %{"type" => "text_delta", "text" => text}
         }
       }) do
    [{:text_delta, text}]
  end

  defp from_event(%{"type" => "assistant", "message" => %{"content" => content}}) do
    for %{"type" => "tool_use", "id" => id, "name" => name} = block <- content do
      {:tool_started, %{id: id, name: tool_name(name), args: block["input"] || %{}}}
    end
  end

  defp from_event(%{"type" => "user", "message" => %{"content" => content}})
       when is_list(content) do
    for %{"type" => "tool_result", "tool_use_id" => id} = block <- content do
      {:tool_finished,
       %{id: id, name: nil, ok?: block["is_error"] != true, output: output(block["content"])}}
    end
  end

  defp from_event(%{"type" => "result", "is_error" => true} = result) do
    [{:error, error_message(result)}]
  end

  defp from_event(_event), do: []

  defp tool_name(name), do: String.replace_prefix(name, "mcp__heddle__", "")

  defp output(content) when is_binary(content), do: content

  defp output(content) when is_list(content) do
    Enum.map_join(content, "\n", &(&1["text"] || ""))
  end

  defp output(_content), do: ""

  defp error_message(%{"subtype" => "error_max_budget_usd"}) do
    "This message reached the spending limit."
  end

  defp error_message(%{"result" => result}) when is_binary(result) and result != "", do: result
  defp error_message(%{"subtype" => subtype}), do: "The agent stopped: #{subtype}."
  defp error_message(_result), do: "The agent stopped."
end
