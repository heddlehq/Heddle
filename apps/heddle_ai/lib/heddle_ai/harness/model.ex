defmodule HeddleAI.Harness.Model do
  @moduledoc """
  What the harness needs from a model. The default talks to a provider through
  `req_llm`, and tests can script one.
  """

  @type reply :: %{context: ReqLLM.Context.t(), tool_calls: [map()]}

  @callback connect(keyword()) :: {:ok, term(), keyword()} | {:error, term()}

  @doc "Asks for the next reply, calling `on_text` as it arrives."
  @callback next(term(), ReqLLM.Context.t(), keyword(), (String.t() -> any())) ::
              {:ok, reply()} | {:error, term()}
end
