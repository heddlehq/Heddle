defmodule HeddleUI.FakeFlowPlanner do
  @moduledoc """
  Stands in for `HeddleAI.Agents.FlowPlanner` in tests: it proposes a plan, answers
  with the flow JSON once the last message approves it, chats on "hello", and returns
  a flow the validator rejects on "invalid".
  """

  @plan "Here is the plan:\n- Add a Webhook node\n- Add a Logger node\nDoes that work? [PLAN_PROPOSED]"

  @flow ~s({"action": "create_flow", "name": "Planned Flow", ) <>
          ~s("nodes": [{"id": "1", "name": "Logger", "type": "Logger"}], "connections": []})

  @invalid_flow ~s({"action": "create_flow", "name": "Broken", ) <>
                  ~s("nodes": [{"id": "1", "type": "Missing Node"}], "connections": []})

  def chat(messages, _current_flow, _locale) do
    {:ok,
     %{stream: messages |> List.last() |> reply() |> chunks() |> Enum.map(&{:text_delta, &1})}}
  end

  defp reply(%{content: "hello"}), do: "Hi! What should we automate?"
  defp reply(%{content: "invalid"}), do: @invalid_flow

  defp reply(%{content: content}) do
    if content =~ "build this flow", do: @flow, else: @plan
  end

  defp chunks(text) do
    text |> String.graphemes() |> Enum.chunk_every(7) |> Enum.map(&Enum.join/1)
  end
end
