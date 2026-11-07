defmodule HeddleAI.Harness.ReqModel do
  @moduledoc """
  Streams a reply from the provider set up in this instance.
  """

  @behaviour HeddleAI.Harness.Model

  alias HeddleAI.AI
  alias ReqLLM.Response
  alias ReqLLM.StreamResponse

  @impl true
  def connect(opts), do: AI.connect(opts)

  @impl true
  def next(model, context, request, on_text) do
    with {:ok, stream} <- ReqLLM.stream_text(model, context, request),
         {:ok, response} <- StreamResponse.process_stream(stream, on_result: on_text) do
      {:ok, %{context: response.context, tool_calls: Response.tool_calls(response)}}
    end
  end
end
