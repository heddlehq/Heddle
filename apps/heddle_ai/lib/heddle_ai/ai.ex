defmodule HeddleAI.AI do
  @moduledoc """
  LLM streaming entrypoint.

  Provider-specific code stays behind this boundary: `req_llm` does the talking and
  `HeddleAI.LLM` decides who to talk to, so UI, core, nodes and worker apps never
  see a provider.
  """

  alias HeddleAI.LLM
  alias ReqLLM.Context
  alias ReqLLM.Response

  @max_tool_rounds 12

  @doc """
  Streams a reply as `{:text_delta, text}` events.

  Always returns `{:ok, %{stream: stream}}`. A failure to start arrives as an
  `{:error, message}` event in the stream, which is where consumers already look for
  one. The message comes from the exception and not from `inspect/1`, which could
  carry request headers to the screen.
  """
  def stream_text(messages, opts \\ []) do
    with {:ok, model, api_key} <- LLM.credentials(),
         {:ok, response} <- client().stream_text(model, messages, request_opts(opts, api_key)) do
      {:ok, %{stream: Stream.flat_map(response.stream, &to_events/1)}}
    else
      {:error, reason} -> {:ok, %{stream: [{:error, error_message(reason)}]}}
    end
  end

  @doc """
  Builds a tool for `run/2`. `fun` takes the arguments the model sent and returns
  `{:ok, text}` or `{:error, text}`.
  """
  def tool(name, description, json_schema, fun) do
    ReqLLM.Tool.new!(
      name: name,
      description: description,
      parameter_schema: json_schema,
      callback: fun
    )
  end

  @doc """
  Answers `messages`, calling `:tools` for as long as the model asks for them.

  Returns `{:ok, text}` with its final reply, or `{:error, message}`.
  """
  def run(messages, opts) do
    tools = Keyword.fetch!(opts, :tools)

    with {:ok, model, api_key} <- LLM.credentials(),
         {:ok, context} <- Context.normalize(messages, system_prompt: opts[:system]) do
      step(context, model, [api_key: api_key, tools: tools], @max_tool_rounds)
    else
      {:error, reason} -> {:error, error_message(reason)}
    end
  end

  defp step(_context, _model, _request, 0), do: {:error, "The agent took too many steps."}

  defp step(context, model, request, rounds) do
    case client().generate_text(model, context, request) do
      {:ok, response} ->
        case Response.tool_calls(response) do
          [] ->
            {:ok, Response.text(response) || ""}

          calls ->
            response.context
            |> Context.execute_and_append_tools(calls, request[:tools])
            |> step(model, request, rounds - 1)
        end

      {:error, reason} ->
        {:error, error_message(reason)}
    end
  end

  defp request_opts(opts, api_key) do
    case Keyword.get(opts, :system) do
      nil -> [api_key: api_key]
      system -> [api_key: api_key, system_prompt: system]
    end
  end

  defp to_events(%{type: :content, text: text}) when is_binary(text), do: [{:text_delta, text}]
  defp to_events(_chunk), do: []

  defp error_message(:not_configured), do: "No LLM provider is configured."
  defp error_message(%{__exception__: true} = error), do: Exception.message(error)
  defp error_message(reason), do: inspect(reason)

  defp client, do: Application.get_env(:heddle_ai, :llm_client, ReqLLM)
end
