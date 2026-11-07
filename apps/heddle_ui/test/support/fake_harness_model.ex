defmodule HeddleUI.FakeHarnessModel do
  @moduledoc """
  Stands in for the model behind `HeddleAI.Harness`. Each call takes the next step of
  the script: a text, `{:tool, name, args}`, `{:error, reason}`, `:hang` or `:crash`.
  """

  @behaviour HeddleAI.Harness.Model

  alias ReqLLM.Context
  alias ReqLLM.ToolCall

  def script(steps) do
    case Agent.start(fn -> steps end, name: __MODULE__) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> Agent.update(__MODULE__, fn _steps -> steps end)
    end

    Agent.start(fn -> nil end, name: __MODULE__.Seen)
    Agent.start(fn -> [] end, name: __MODULE__.All)
    :ok
  end

  @doc "The last message the model was given."
  def last_message do
    Agent.get(__MODULE__.Seen, & &1)
  end

  @doc "All the messages of the last call."
  def all_messages, do: Agent.get(__MODULE__.All, & &1)

  @doc "What is left of the script."
  def remaining, do: Agent.get(__MODULE__, & &1)

  @impl true
  def connect(_opts), do: {:ok, :fake, []}

  @impl true
  def next(:fake, context, _request, on_text) do
    Agent.update(__MODULE__.Seen, fn _seen -> text_of(List.last(context.messages)) end)
    Agent.update(__MODULE__.All, fn _all -> Enum.map(context.messages, &text_of/1) end)

    __MODULE__
    |> Agent.get_and_update(&{List.first(&1), Enum.drop(&1, 1)})
    |> play(context, on_text)
  end

  defp play({:tool, name, args}, context, _on_text) do
    call = ToolCall.new("call_#{System.unique_integer([:positive])}", name, Jason.encode!(args))
    {:ok, %{context: Context.append(context, assistant(call)), tool_calls: [call]}}
  end

  defp play({:error, _reason} = error, _context, _on_text), do: error
  defp play(:crash, _context, _on_text), do: raise("the model broke")

  defp play(:hang, _context, _on_text) do
    Process.sleep(:infinity)
  end

  defp play(text, context, on_text) when is_binary(text) do
    on_text.(text)
    {:ok, %{context: Context.append(context, Context.assistant(text)), tool_calls: []}}
  end

  defp text_of(message), do: Enum.map_join(message.content, &(&1.text || ""))

  defp assistant(call), do: Context.assistant("", tool_calls: [call])
end
