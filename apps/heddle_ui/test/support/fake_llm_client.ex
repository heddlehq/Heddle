defmodule HeddleUI.FakeLLMClient do
  @moduledoc """
  Stands in for `ReqLLM` in tests.
  """

  def stream_text(_model, _messages, _opts) do
    {:ok, %{stream: [%{type: :content, text: "From the LLM."}]}}
  end
end
