defmodule HeddleAI.Models do
  @moduledoc """
  The models Heddle offers, so nobody has to type one.

  They come from the registry `req_llm` ships with, narrowed to what each task can
  really use: an image node never lists a chat model, and the other way around.
  Updating `req_llm` brings new models.
  """

  @capabilities [:text, :vision, :image, :transcription, :speech]

  @providers [
    google: "Google",
    openai: "OpenAI",
    anthropic: "Anthropic",
    xai: "xAI"
  ]

  # What runs when nobody picks a model. A provider that isn't here for a task can't
  # do it through req_llm.
  @defaults %{
    google: %{
      text: "gemini-3.8-flash",
      vision: "gemini-3.8-flash",
      image: "gemini-nano-banana-2.1"
    },
    openai: %{
      text: "gpt-5.4-mini",
      vision: "gpt-5.4-mini",
      image: "gpt-image-2.5-flare",
      transcription: "gpt-4o-mini-transcribe",
      speech: "gpt-4o-mini-tts"
    },
    anthropic: %{text: "claude-sonnet-5-5", vision: "claude-sonnet-5-5"},
    xai: %{text: "grok-4.7", vision: "grok-4.7", image: "grok-imagine-image"}
  }

  @tasks %{
    text: "write text",
    vision: "read images",
    image: "create images",
    transcription: "transcribe audio",
    speech: "turn text into speech"
  }

  # Dated snapshots and models made for something else, like code or live audio.
  @not_for_tasks ~r/\d{4}-\d{2}-\d{2}|\d{8}|-\d{4}$|preview|latest|codex|realtime|audio|live|embedding|search|diarize/

  @image_models ~r/^(gpt-image|gemini-.*image|gemini-nano-banana|grok-imagine-image)/
  @transcription_models ~r/^(gpt-.*transcribe|whisper)/
  @speech_models ~r/^(gpt-.*tts|tts-1)/

  # Google deprecated it in favor of Nano Banana 2.1, but the registry doesn't say so.
  @superseded ~w(gemini-3.1-flash-image)

  def capabilities, do: @capabilities

  @doc """
  Returns the providers an AI provider credential can hold, as `{label, id}`.
  """
  def providers, do: Enum.map(@providers, fn {id, label} -> {label, to_string(id)} end)

  def provider_label(provider), do: @providers[provider] || to_string(provider)

  @doc """
  Returns the models of a provider that can do a task: its default, then the newest.
  """
  def options(provider, capability) do
    default = default(provider, capability)

    provider
    |> LLMDB.models()
    |> Enum.filter(&(usable?(&1) and fits?(&1, capability, provider)))
    |> Enum.sort_by(&{&1.id == default, &1.release_date || "", &1.id}, :desc)
    |> Enum.map(&%{id: &1.id, label: &1.name || &1.id})
  end

  def default(provider, capability), do: get_in(@defaults, [provider, capability])

  @doc """
  Returns the name of a model, or its ID when the registry doesn't have one.
  """
  def label(provider, id) do
    case Enum.find(LLMDB.models(provider), &(&1.id == id)) do
      %{name: name} when is_binary(name) -> name
      _other -> id
    end
  end

  @doc """
  Says whether `model` can do a task on a provider, with a message for the person.

  `model` is `nil` when nobody picked one, and `configured` is the model the
  instance's environment set, which a text task can use.
  """
  def check(provider, capability, model, configured \\ nil)

  def check(provider, capability, nil, configured) do
    text? = capability in [:text, :vision]

    if default(provider, capability) || (text? && configured) do
      :ok
    else
      {:error, cannot(provider, capability)}
    end
  end

  def check(provider, capability, model, _configured) do
    cond do
      Enum.any?(options(provider, capability), &(&1.id == model)) -> :ok
      options(provider, capability) == [] -> {:error, cannot(provider, capability)}
      true -> {:error, not_available(provider, capability, model)}
    end
  end

  defp cannot(provider, capability) do
    able =
      @providers
      |> Keyword.keys()
      |> Enum.filter(&default(&1, capability))
      |> Enum.map_join(" or ", &provider_label/1)

    "#{provider_label(provider)} can't #{@tasks[capability]} here. Use a #{able} credential."
  end

  defp not_available(provider, capability, model) do
    "#{model} isn't a #{provider_label(provider)} model that can #{@tasks[capability]}. " <>
      "Pick one from the list."
  end

  defp usable?(model), do: !model.deprecated and !model.retired and model.id not in @superseded

  defp fits?(model, :text, _provider) do
    chat?(model) and output(model) == [:text] and not (model.id =~ @not_for_tasks)
  end

  defp fits?(model, :vision, provider) do
    fits?(model, :text, provider) and :image in input(model)
  end

  defp fits?(model, :image, provider) do
    default(provider, :image) != nil and model.id =~ @image_models and
      not (model.id =~ @not_for_tasks)
  end

  defp fits?(model, :transcription, provider) do
    default(provider, :transcription) != nil and model.id =~ @transcription_models and
      not (model.id =~ @not_for_tasks)
  end

  defp fits?(model, :speech, provider) do
    default(provider, :speech) != nil and model.id =~ @speech_models and
      not (model.id =~ @not_for_tasks)
  end

  defp chat?(%{capabilities: %{chat: true}}), do: true
  defp chat?(_model), do: false

  defp output(%{modalities: %{output: output}}), do: output
  defp output(_model), do: []

  defp input(%{modalities: %{input: input}}), do: input
  defp input(_model), do: []
end
