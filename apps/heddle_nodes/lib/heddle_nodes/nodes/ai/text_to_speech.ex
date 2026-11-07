defmodule HeddleNodes.Nodes.AI.TextToSpeech do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.AI

  @voices ~w(alloy ash ballad coral echo fable nova onyx sage shimmer verse)

  definition do
    AI.definition(
      "Text to Speech",
      "Reads a text out loud into an audio file. Needs an OpenAI credential.",
      "hero-speaker-wave-solid",
      :speech,
      [
        AI.text_field(),
        %{
          type: :select,
          name: :voice,
          label: "Voice",
          options: Enum.map(@voices, &%{label: String.capitalize(&1), value: &1}),
          default: "alloy"
        }
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    AI.run(context, :speech, fn options ->
      options = Keyword.put(options, :voice, AI.optional(context, "voice"))

      with {:ok, {data, type}} <-
             AI.client().speak(Integration.field(context, "text"), options) do
        {:ok, Integration.to_file(data, type)}
      end
    end)
  end
end
