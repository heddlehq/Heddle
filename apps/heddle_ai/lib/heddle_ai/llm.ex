defmodule HeddleAI.LLM do
  @moduledoc """
  Resolves which LLM this instance talks to from the environment.

  The provider is an operator decision, so it lives in env and not in the database:

      HEDDLE_LLM_PROVIDER=anthropic
      HEDDLE_LLM_MODEL=claude-sonnet-5-5
      HEDDLE_LLM_API_KEY=sk-ant-...

  Installs from before these variables keep working through `OPENAI_API_KEY` and
  `OPENAI_MODEL`, which only apply while `HEDDLE_LLM_PROVIDER` is unset.
  """

  @legacy_model "gpt-4o-mini"

  @type status :: %{
          state: :ready | :not_configured | :invalid,
          provider: String.t() | nil,
          model: String.t() | nil,
          source: :heddle | :openai_legacy | nil,
          missing: [String.t()]
        }

  @doc """
  Describes the configured LLM without ever exposing the key.

  `:missing` names the variables to set when `:state` is `:invalid`. A provider that
  `req_llm` doesn't know is reported there as `HEDDLE_LLM_PROVIDER`.
  """
  @spec status(%{String.t() => String.t()}) :: status()
  def status(env \\ System.get_env()) do
    case read(env, "HEDDLE_LLM_PROVIDER") do
      nil -> legacy_status(env)
      provider -> heddle_status(env, provider)
    end
  end

  @spec configured?() :: boolean()
  def configured?, do: status().state == :ready

  @doc """
  Returns the model spec and API key to call `req_llm` with.
  """
  @spec credentials(%{String.t() => String.t()}) ::
          {:ok, {atom(), String.t(), []}, String.t()} | {:error, :not_configured}
  def credentials(env \\ System.get_env()) do
    case status(env) do
      %{state: :ready, source: :openai_legacy, model: model} ->
        {:ok, {:openai, model, []}, read(env, "OPENAI_API_KEY")}

      %{state: :ready, provider: provider, model: model} ->
        {:ok, {known_provider(provider), model, []}, read(env, "HEDDLE_LLM_API_KEY")}

      _status ->
        {:error, :not_configured}
    end
  end

  defp heddle_status(env, provider) do
    model = read(env, "HEDDLE_LLM_MODEL")

    missing =
      [
        known_provider(provider) == nil && "HEDDLE_LLM_PROVIDER",
        model == nil && "HEDDLE_LLM_MODEL",
        read(env, "HEDDLE_LLM_API_KEY") == nil && "HEDDLE_LLM_API_KEY"
      ]
      |> Enum.filter(& &1)

    %{
      state: if(missing == [], do: :ready, else: :invalid),
      provider: provider,
      model: model,
      source: :heddle,
      missing: missing
    }
  end

  defp legacy_status(env) do
    if read(env, "OPENAI_API_KEY") do
      %{
        state: :ready,
        provider: "openai",
        model: read(env, "OPENAI_MODEL") || @legacy_model,
        source: :openai_legacy,
        missing: []
      }
    else
      %{state: :not_configured, provider: nil, model: nil, source: nil, missing: []}
    end
  end

  # Matched against the registry so a typo in env never creates an atom.
  defp known_provider(name) do
    Enum.find(ReqLLM.Providers.list(), &(Atom.to_string(&1) == name))
  end

  defp read(env, name) do
    case Map.get(env, name) do
      value when value in [nil, ""] -> nil
      value -> value
    end
  end
end
