defmodule HeddleAI.AI do
  @moduledoc """
  LLM streaming entrypoint.

  Provider-specific code stays behind this boundary: `req_llm` does the talking and
  `HeddleAI.LLM` decides who to talk to, so UI, core, nodes and worker apps never
  see a provider.
  """

  alias HeddleAI.LLM
  alias HeddleAI.Models
  alias ReqLLM.Context
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.Response

  @max_tool_rounds 12

  # These take the image to edit as an option. The others take it in the message.
  @source_image_providers [:openai, :azure]

  @doc """
  Streams a reply as `{:text_delta, text}` events.

  Always returns `{:ok, %{stream: stream}}`. A failure to start arrives as an
  `{:error, message}` event in the stream, which is where consumers already look for
  one. The message comes from the exception and not from `inspect/1`, which could
  carry request headers to the screen.
  """
  def stream_text(messages, opts \\ []) do
    with {:ok, model, api_key} <- LLM.connection(nil),
         {:ok, model} <- text_model(model, nil, :text),
         {:ok, response} <- client().stream_text(model, messages, request_opts(opts, api_key)) do
      {:ok, %{stream: Stream.flat_map(response.stream, &to_events/1)}}
    else
      {:error, reason} -> {:ok, %{stream: [{:error, error_message(reason)}]}}
    end
  end

  @doc """
  Says who would answer: the provider, and the model the environment set, if any.
  """
  def target(opts) do
    case LLM.connection(opts[:credential]) do
      {:ok, {provider, configured, _options}, _api_key} -> {:ok, provider, configured}
      {:error, reason} -> {:error, error_message(reason)}
    end
  end

  @doc """
  Checks a task can run with these options, before spending a call on it.

  Takes `:credential` and `:model`, and returns `:ok` or `{:error, message}`.
  """
  def check(capability, opts) do
    with {:ok, provider, configured} <- target(opts) do
      Models.check(provider, capability, opts[:model], configured)
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

  `:credential`, `:model` and `:temperature` override what the instance uses, and
  `:max_steps` limits how many times the model can come back for tools.

  Returns `{:ok, text}` with its final reply, or `{:error, message}`.
  """
  def run(messages, opts) do
    tools = Keyword.fetch!(opts, :tools)

    with {:ok, model, api_key} <- LLM.connection(opts[:credential]),
         {:ok, model} <- text_model(model, opts[:model], opts[:capability] || :text),
         {:ok, context} <- Context.normalize(messages, system_prompt: opts[:system]) do
      request = request(api_key, tools, opts)

      step(context, model, request, opts[:max_steps] || @max_tool_rounds)
    else
      {:error, reason} -> {:error, error_message(reason)}
    end
  end

  @doc """
  Says what to call `req_llm` with for a conversation with `:tools`.

  Returns `{:ok, model, request}` or `{:error, message}`.
  """
  def connect(opts) do
    with {:ok, model, api_key} <- LLM.connection(opts[:credential]),
         {:ok, model} <- text_model(model, opts[:model], :text) do
      {:ok, model, request(api_key, Keyword.fetch!(opts, :tools), opts)}
    else
      {:error, reason} -> {:error, error_message(reason)}
    end
  end

  @doc "Turns what a provider failed with into something to show."
  def describe_error(reason), do: error_message(reason)

  @doc """
  Asks about an image, given as `{bytes, media_type}`.

  Takes the same options as `run/2`, without the tools.
  """
  def ask_about_image({data, media_type}, question, opts) do
    message = Context.user([ContentPart.text(question), ContentPart.image(data, media_type)])

    run([message], Keyword.merge(opts, tools: [], capability: :vision))
  end

  @doc """
  Makes an image from `prompt`.

  `:image` is an image to edit or start from, as `{bytes, media_type}`. Also takes
  `:credential`, `:model` and `:aspect_ratio`.

  Returns `{:ok, {bytes, media_type}}` or `{:error, message}`.
  """
  def generate_image(prompt, opts) do
    with {:ok, {provider, _name, _options} = model, api_key} <- media_model(:image, opts),
         {input, image_opts} = image_input(provider, prompt, opts[:image]),
         request = image_opts ++ aspect_ratio(opts[:aspect_ratio]) ++ request_base(api_key),
         {:ok, response} <- client().generate_image(model, input, request) do
      image_from(response)
    else
      {:error, reason} -> {:error, error_message(reason)}
    end
  end

  @doc """
  Turns audio, given as `{bytes, media_type}`, into text.

  Takes `:credential`, `:model` and `:language`.

  Returns `{:ok, %{text: text, language: language}}` or `{:error, message}`.
  """
  def transcribe({data, media_type}, opts) do
    language = if opts[:language], do: [language: opts[:language]], else: []

    with {:ok, model, api_key} <- media_model(:transcription, opts),
         request = language ++ request_base(api_key),
         {:ok, result} <- client().transcribe(model, {:binary, data, media_type}, request) do
      {:ok, %{text: result.text, language: result.language}}
    else
      {:error, reason} -> {:error, error_message(reason)}
    end
  end

  @doc """
  Turns text into audio.

  Takes `:credential`, `:model` and `:voice`.

  Returns `{:ok, {bytes, media_type}}` or `{:error, message}`.
  """
  def speak(text, opts) do
    voice = if opts[:voice], do: [voice: opts[:voice]], else: []

    with {:ok, model, api_key} <- media_model(:speech, opts),
         {:ok, result} <- client().speak(model, text, voice ++ request_base(api_key)) do
      {:ok, {result.audio, result.media_type}}
    else
      {:error, reason} -> {:error, error_message(reason)}
    end
  end

  defp media_model(capability, opts) do
    with {:ok, {provider, _name, options}, api_key} <- LLM.connection(opts[:credential]),
         :ok <- Models.check(provider, capability, opts[:model]) do
      {:ok, {provider, opts[:model] || Models.default(provider, capability), options}, api_key}
    end
  end

  defp image_input(_provider, prompt, nil), do: {prompt, []}

  defp image_input(provider, prompt, {data, media_type})
       when provider in @source_image_providers do
    {prompt, [source_image: data, source_image_media_type: media_type]}
  end

  defp image_input(_provider, prompt, {data, media_type}) do
    parts = [ContentPart.text(prompt), ContentPart.image(data, media_type)]

    {Context.new([Context.user(parts)]), []}
  end

  defp aspect_ratio(nil), do: []
  defp aspect_ratio(ratio), do: [aspect_ratio: ratio]

  # A model that won't draw something says why in text.
  defp image_from(response) do
    case Response.image(response) do
      %{data: data, media_type: media_type} when is_binary(data) ->
        {:ok, {data, media_type}}

      _other ->
        {:error, "The model returned no image. #{Response.text(response)}" |> String.trim()}
    end
  end

  defp request_base(api_key) do
    [api_key: api_key] ++ Application.get_env(:heddle_ai, :req_options, [])
  end

  defp request(api_key, tools, opts) do
    case opts[:temperature] do
      nil -> [tools: tools] ++ request_base(api_key)
      temperature -> [tools: tools, temperature: temperature] ++ request_base(api_key)
    end
  end

  defp text_model({provider, _configured, options}, name, _capability) when is_binary(name) do
    {:ok, {provider, name, options}}
  end

  # The model set for text may not see images, so the default for images comes first.
  defp text_model({provider, configured, options}, nil, :vision) do
    pick_text_model(provider, Models.default(provider, :vision) || configured, options)
  end

  defp text_model({provider, configured, options}, nil, _capability) do
    pick_text_model(provider, configured || Models.default(provider, :text), options)
  end

  defp pick_text_model(provider, nil, _options) do
    {:error, "#{Models.provider_label(provider)} has no default model. Pick one in the AI page."}
  end

  defp pick_text_model(provider, name, options), do: {:ok, {provider, name, options}}

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

  defp error_message(:not_configured) do
    "No AI provider is set up. Add a credential and pick it in the AI page."
  end

  defp error_message(%{__exception__: true} = error), do: Exception.message(error)
  defp error_message(reason), do: inspect(reason)

  defp client, do: Application.get_env(:heddle_ai, :llm_client, ReqLLM)
end
