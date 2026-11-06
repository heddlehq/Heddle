defmodule HeddleUI.FakeLLMAgent do
  @moduledoc """
  Stands in for `ReqLLM` in tests of the chat: each call takes the next step of the
  script in `:llm_agent_script`, which is a tool call or a final text.
  """

  alias ReqLLM.Context

  def stream_text(_model, _messages, _opts), do: {:error, :not_scripted}

  def generate_text(model, context, opts) do
    test_pid = Application.fetch_env!(:heddle_ui, :llm_agent_test_pid)
    send(test_pid, {:llm_called, model, context, opts})

    script = Agent.get_and_update(__MODULE__, &{List.first(&1), Enum.drop(&1, 1)})
    respond(script, context)
  end

  def script(steps) do
    case Agent.start(fn -> steps end, name: __MODULE__) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> Agent.update(__MODULE__, fn _steps -> steps end)
    end
  end

  defp respond({:error, _reason} = error, _context), do: error

  defp respond({:tool, name, arguments}, context) do
    call =
      ReqLLM.ToolCall.new(
        "call_#{System.unique_integer([:positive])}",
        name,
        Jason.encode!(arguments)
      )

    response(Context.assistant("", tool_calls: [call]), context)
  end

  defp respond(text, context) when is_binary(text) do
    response(Context.assistant(text), context)
  end

  defp response(message, context) do
    response = %ReqLLM.Response{id: "fake", model: "fake", context: context, message: message}
    {:ok, Context.merge_response(context, response)}
  end
end
