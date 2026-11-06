defmodule HeddleUI.FakeClaudeAgent do
  @moduledoc """
  Stands in for `HeddleAI.ClaudeAgent` in tests, reporting each call to the process
  named in `:claude_agent_test_pid`.
  """

  def stream_text(content, opts) do
    test_pid = Application.fetch_env!(:heddle_ui, :claude_agent_test_pid)
    send(test_pid, {:agent_called, content, opts})

    {:ok, %{stream: [{:text_delta, "On "}, {:text_delta, "it."}]}}
  end
end
