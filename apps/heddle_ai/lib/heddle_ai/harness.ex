defmodule HeddleAI.Harness do
  @moduledoc """
  The agent loop: the model answers, the tools it asks for run, and it goes on until it
  has nothing more to call.

  It knows nothing about flows. It takes the tools to offer and reports what happens as
  events, so anything can show the work while it is being done:

    * `{:text_delta, text}` - part of the reply
    * `{:tool_started, %{id: id, name: name, args: args}}`
    * `{:tool_finished, %{id: id, name: name, ok?: boolean, output: text}}`

  A tool that fails doesn't end the turn: the model reads the error and decides. The
  same call three times in a row doesn't run, because a weak model can go on like that
  until it runs out of steps.

  A conversation only grows, and a model only takes so much. Before each call, the
  output of older tools is cut, since the model can call them again, and if that is
  not enough the oldest exchanges go.
  """

  alias HeddleAI.AI
  alias ReqLLM.Context
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.ToolCall

  @max_steps 40
  @kept_tool_outputs 6
  @trimmed_output 400
  @max_context_chars 240_000
  @max_repeats 2
  @repeated "You already made this exact call, and doing it again won't change anything. Try something different, or tell the user where you are."

  @doc """
  Runs one turn of `messages`.

  Takes `:system`, `:tools` and `:on_event`, plus the options of `HeddleAI.AI.connect/1`.

  Returns `{:ok, messages}` with the conversation so far, to send back with the next
  message, or `{:error, message}`.
  """
  def run(messages, opts) do
    tools = Keyword.fetch!(opts, :tools)
    on_event = Keyword.fetch!(opts, :on_event)

    with {:ok, model, request} <- model().connect(opts),
         {:ok, context} <- Context.normalize(messages, system_prompt: opts[:system]) do
      turn = %{model: model, request: request, tools: tools, on_event: on_event}

      step(context, turn, {nil, 0}, @max_steps)
    else
      {:error, reason} -> {:error, AI.describe_error(reason)}
    end
  end

  defp step(_context, _turn, _last_call, 0), do: {:error, "The agent took too many steps."}

  defp step(context, turn, last_call, steps) do
    on_text = &turn.on_event.({:text_delta, &1})
    context = fit(context)

    case model().next(turn.model, context, turn.request, on_text) do
      {:ok, %{context: context, tool_calls: []}} ->
        {:ok, conversation(context)}

      {:ok, %{context: context, tool_calls: calls}} ->
        {context, last_call} =
          Enum.reduce(calls, {context, last_call}, &run_tool(&1, &2, turn))

        step(context, turn, last_call, steps - 1)

      {:error, reason} ->
        {:error, AI.describe_error(reason)}
    end
  end

  defp fit(context) do
    %{context | messages: context.messages |> trim_old_outputs() |> drop_oldest()}
  end

  defp trim_old_outputs(messages) do
    outputs = Enum.count(messages, &(&1.role == :tool))

    {messages, _seen} =
      Enum.map_reduce(messages, 0, fn
        %{role: :tool} = message, seen when outputs - seen > @kept_tool_outputs ->
          {trim_output(message), seen + 1}

        %{role: :tool} = message, seen ->
          {message, seen + 1}

        message, seen ->
          {message, seen}
      end)

    messages
  end

  defp trim_output(message) do
    text = output(message)

    if String.length(text) > @trimmed_output do
      trimmed = String.slice(text, 0, @trimmed_output) <> "... [cut: call the tool again]"
      %{message | content: [ContentPart.text(trimmed)]}
    else
      message
    end
  end

  # An exchange goes whole, because a tool result can't stay without its call.
  defp drop_oldest(messages) do
    {system, rest} = Enum.split_with(messages, &(&1.role == :system))

    system ++ drop_until_it_fits(rest)
  end

  defp drop_until_it_fits(messages) do
    with true <- size(messages) > @max_context_chars,
         [_first | rest] <- messages,
         [_next | _others] = kept <- Enum.drop_while(rest, &(&1.role != :user)) do
      drop_until_it_fits(kept)
    else
      _fits_or_nothing_left_to_drop -> messages
    end
  end

  defp size(messages) do
    Enum.reduce(messages, 0, fn message, total ->
      total + String.length(output(message)) + tool_calls_size(message)
    end)
  end

  defp tool_calls_size(%{tool_calls: calls}) when is_list(calls) do
    Enum.reduce(calls, 0, &(byte_size(ToolCall.args_json(&1)) + &2))
  end

  defp tool_calls_size(_message), do: 0

  defp run_tool(call, {context, last_call}, turn) do
    %{id: id, name: name, arguments: args} = ToolCall.from_map(call)
    last_call = count_call({name, args}, last_call)

    turn.on_event.({:tool_started, %{id: id, name: name, args: args}})

    context =
      if repeated?(last_call) do
        Context.append(context, Context.tool_result(id, @repeated))
      else
        Context.execute_and_append_tools(context, [call], turn.tools)
      end

    result = List.last(context.messages)
    ok? = not error?(result) and not repeated?(last_call)

    turn.on_event.({:tool_finished, %{id: id, name: name, ok?: ok?, output: output(result)}})

    {context, last_call}
  end

  defp count_call(signature, {signature, count}), do: {signature, count + 1}
  defp count_call(signature, _last_call), do: {signature, 0}

  defp repeated?({_signature, count}), do: count >= @max_repeats

  defp error?(message), do: Map.get(message.metadata || %{}, :is_error, false)

  defp output(message) do
    Enum.map_join(message.content, "\n", &(&1.text || ""))
  end

  # The instructions are written again for each turn, with what is true by then.
  defp conversation(context), do: Enum.reject(context.messages, &(&1.role == :system))

  defp model, do: Application.get_env(:heddle_ai, :harness_model, HeddleAI.Harness.ReqModel)
end
