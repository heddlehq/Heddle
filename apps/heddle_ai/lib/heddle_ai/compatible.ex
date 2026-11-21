defmodule HeddleAI.Compatible do
  @moduledoc """
  Servers that speak the OpenAI API without being OpenAI: Ollama, OpenRouter, Groq,
  LM Studio, vLLM and the like.

  `req_llm` doesn't know their models, so they are asked for them through
  `GET /models`. The screens ask on every render, so an answer is kept for a minute,
  and a server that doesn't answer is not asked again for a few seconds.
  """

  @table __MODULE__
  @fresh :timer.minutes(1)
  @failed :timer.seconds(10)
  @timeout 3_000

  @doc false
  def create_table do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
  end

  @doc """
  Returns what `req_llm` takes for `model` on the server at `base_url`.

  It is sent through Chat Completions, which every one of these servers has, and not
  through the Responses API, which `req_llm` would pick for a name like `gpt-5`.
  """
  def spec(name, base_url) do
    %{
      provider: :openai,
      id: name,
      base_url: base_url,
      extra: %{wire: %{protocol: "openai_chat"}}
    }
  end

  @doc """
  Returns the models the server lists, as `%{id, label}`, sorted by name.

  A server that can't be reached lists none, so the model set in the credential is
  the one to use.
  """
  def models(base_url, api_key) do
    key = {base_url, :erlang.phash2(api_key)}
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, until, models}] when until > now ->
        models

      _stale ->
        {models, ttl} = fetch(base_url, api_key)
        :ets.insert(@table, {key, now + ttl, models})
        models
    end
  end

  defp fetch(base_url, api_key) do
    request =
      [
        url: base_url <> "/models",
        auth: {:bearer, api_key},
        receive_timeout: @timeout,
        connect_options: [timeout: @timeout],
        retry: false
      ] ++ Application.get_env(:heddle_ai, :compatible_req_options, [])

    case Req.get(request) do
      {:ok, %{status: 200, body: %{"data" => data}}} when is_list(data) ->
        {listed(data), @fresh}

      _other ->
        {[], @failed}
    end
  rescue
    _error -> {[], @failed}
  end

  defp listed(data) do
    data
    |> Enum.flat_map(fn
      %{"id" => id} when is_binary(id) -> [%{id: id, label: id}]
      _other -> []
    end)
    |> Enum.sort_by(& &1.id)
  end
end
