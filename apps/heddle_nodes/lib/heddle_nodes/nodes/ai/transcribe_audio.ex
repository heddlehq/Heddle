defmodule HeddleNodes.Nodes.AI.TranscribeAudio do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.AI

  definition do
    AI.definition(
      "Transcribe Audio",
      "Turns speech into text. Needs an OpenAI credential.",
      "hero-microphone-solid",
      :transcription,
      [
        AI.file_field(:audio, "Audio, or its URL"),
        %{
          type: :select,
          name: :language,
          label: "Language",
          options: [
            %{label: "Detect it", value: ""},
            %{label: "Portuguese", value: "pt"},
            %{label: "English", value: "en"},
            %{label: "Spanish", value: "es"},
            %{label: "French", value: "fr"},
            %{label: "German", value: "de"},
            %{label: "Italian", value: "it"}
          ],
          default: ""
        }
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    AI.run(context, :transcription, fn options ->
      options = Keyword.put(options, :language, AI.optional(context, "language"))

      with {:ok, audio} <- Integration.media(context, "audio"),
           {:ok, %{text: text, language: language}} <- AI.client().transcribe(audio, options) do
        {:ok, %{"text" => text, "language" => language}}
      end
    end)
  end
end
