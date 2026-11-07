defmodule HeddleAI.AIMediaTest do
  # Not async: it sets the LLM client and environment for the whole VM.
  use ExUnit.Case, async: false

  alias HeddleAI.AI

  @google %{"provider" => "google", "api_key" => "g-key"}
  @openai %{"provider" => "openai", "api_key" => "o-key"}
  @png <<0x89, "PNG", 1, 2, 3>>

  defmodule FakeClient do
    def generate_text(model, context, opts) do
      send(self(), {:generate_text, model, context, opts})

      {:ok,
       %ReqLLM.Response{
         id: "1",
         model: "m",
         context: context,
         message: ReqLLM.Context.assistant("Reply")
       }}
    end

    def generate_image(model, input, opts) do
      send(self(), {:generate_image, model, input, opts})

      message = %ReqLLM.Message{
        role: :assistant,
        content: [ReqLLM.Message.ContentPart.image(<<1, 2>>, "image/jpeg")]
      }

      {:ok,
       %ReqLLM.Response{id: "1", model: "m", context: ReqLLM.Context.new(), message: message}}
    end

    def transcribe(model, audio, opts) do
      send(self(), {:transcribe, model, audio, opts})

      {:ok, %ReqLLM.Transcription.Result{text: "Oi", language: "pt"}}
    end

    def speak(model, text, opts) do
      send(self(), {:speak, model, text, opts})

      {:ok, %ReqLLM.Speech.Result{audio: <<9>>, media_type: "audio/mpeg"}}
    end
  end

  setup do
    previous = Application.get_env(:heddle_ai, :llm_client)
    Application.put_env(:heddle_ai, :llm_client, FakeClient)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:heddle_ai, :llm_client, previous),
        else: Application.delete_env(:heddle_ai, :llm_client)
    end)
  end

  describe "generate_image/2" do
    test "uses Nano Banana with a Google credential" do
      assert {:ok, {<<1, 2>>, "image/jpeg"}} = AI.generate_image("A cat", credential: @google)

      assert_received {:generate_image, {:google, "gemini-nano-banana-2.1", []}, "A cat", opts}
      assert opts[:api_key] == "g-key"
      refute Keyword.has_key?(opts, :aspect_ratio)
    end

    test "uses GPT Image with an OpenAI credential, and the model picked over it" do
      assert {:ok, _image} = AI.generate_image("A cat", credential: @openai)
      assert_received {:generate_image, {:openai, "gpt-image-2.5-flare", []}, _input, _opts}

      assert {:ok, _image} =
               AI.generate_image("A cat", credential: @google, model: "gemini-3-pro-image")

      assert_received {:generate_image, {:google, "gemini-3-pro-image", []}, _input, _opts}
    end

    test "sends the image to edit in the message to Google" do
      assert {:ok, _image} =
               AI.generate_image("Add a hat",
                 credential: @google,
                 image: {@png, "image/png"},
                 aspect_ratio: "16:9"
               )

      assert_received {:generate_image, _model, %ReqLLM.Context{messages: [message]}, opts}
      assert [%{type: :text, text: "Add a hat"}, %{type: :image, data: @png}] = message.content
      assert opts[:aspect_ratio] == "16:9"
      refute Keyword.has_key?(opts, :source_image)
    end

    test "sends the image to edit as an option to OpenAI" do
      assert {:ok, _image} =
               AI.generate_image("Add a hat", credential: @openai, image: {@png, "image/png"})

      assert_received {:generate_image, _model, "Add a hat", opts}
      assert opts[:source_image] == @png
      assert opts[:source_image_media_type] == "image/png"
    end

    test "says who can draw when the provider can't" do
      credential = %{"provider" => "anthropic", "api_key" => "k"}

      assert {:error, message} = AI.generate_image("A cat", credential: credential)
      assert message =~ "Anthropic can't create images"
      assert message =~ "Google"
    end

    test "refuses a model that isn't one, before spending a call" do
      assert {:error, message} = AI.generate_image("A cat", credential: @google, model: "GPT")
      assert message =~ "GPT isn't a Google model"
      refute_received {:generate_image, _model, _input, _opts}
    end

    test "doesn't create a provider out of a typo" do
      credential = %{"provider" => "gogle", "api_key" => "k"}

      assert {:error, message} = AI.generate_image("A cat", credential: credential)
      assert message =~ "gogle"
    end
  end

  describe "transcribe/2" do
    test "sends the audio and the language" do
      assert {:ok, %{text: "Oi", language: "pt"}} =
               AI.transcribe({<<1>>, "audio/mpeg"}, credential: @openai, language: "pt")

      assert_received {:transcribe, {:openai, "gpt-4o-mini-transcribe", []},
                       {:binary, <<1>>, "audio/mpeg"}, opts}

      assert opts[:language] == "pt"
    end

    test "says Google can't do it, and who can" do
      assert {:error, message} = AI.transcribe({<<1>>, "audio/mpeg"}, credential: @google)
      assert message =~ "Google can't transcribe audio"
      assert message =~ "OpenAI"
    end
  end

  describe "speak/2" do
    test "returns the audio" do
      assert {:ok, {<<9>>, "audio/mpeg"}} =
               AI.speak("Oi", credential: @openai, voice: "nova")

      assert_received {:speak, {:openai, "gpt-4o-mini-tts", []}, "Oi", opts}
      assert opts[:voice] == "nova"
    end
  end

  describe "run/2 with a credential" do
    test "talks to the credential's provider, with the model picked" do
      assert {:ok, "Reply"} =
               AI.run([%{role: "user", content: "Hi"}],
                 tools: [],
                 credential: @openai,
                 model: "gpt-5.5"
               )

      assert_received {:generate_text, {:openai, "gpt-5.5", []}, _context, opts}
      assert opts[:api_key] == "o-key"
    end

    test "uses the provider's default when nobody picked a model" do
      assert {:ok, "Reply"} =
               AI.run([%{role: "user", content: "Hi"}], tools: [], credential: @google)

      assert_received {:generate_text, {:google, "gemini-3.8-flash", []}, _context, _opts}
    end
  end

  describe "check/2" do
    test "accepts what can run" do
      assert AI.check(:image, credential: @google) == :ok
      assert AI.check(:image, credential: @google, model: "gemini-nano-banana-2.1") == :ok
    end

    test "catches what someone would type" do
      for model <- ["GPT", "gpt", "banana", "gemini"] do
        assert {:error, message} = AI.check(:image, credential: @google, model: model)
        assert message =~ model
      end
    end

    test "catches a model made for another task" do
      assert {:error, _message} =
               AI.check(:image, credential: @google, model: "gemini-3.8-flash")

      assert {:error, _message} =
               AI.check(:text, credential: @google, model: "gemini-nano-banana-2.1")
    end

    test "says when no provider is set up" do
      previous = System.get_env() |> Map.take(~w(HEDDLE_LLM_PROVIDER OPENAI_API_KEY))
      Enum.each(Map.keys(previous), &System.delete_env/1)
      on_exit(fn -> System.put_env(previous) end)

      assert {:error, message} = AI.check(:text, [])
      assert message =~ "No AI provider is set up"
    end
  end

  describe "ask_about_image/3" do
    test "sends the question and the image" do
      assert {:ok, "Reply"} =
               AI.ask_about_image({@png, "image/png"}, "What is it?", credential: @openai)

      assert_received {:generate_text, {:openai, "gpt-5.4-mini", []}, context, _opts}
      assert [message] = context.messages
      assert [%{type: :text, text: "What is it?"}, %{type: :image, data: @png}] = message.content
    end
  end

  # The real client, with only the network replaced: what Google gets and gives back.
  describe "generate_image/2 through req_llm" do
    setup do
      Application.delete_env(:heddle_ai, :llm_client)

      Application.put_env(:heddle_ai, :req_options,
        req_http_options: [plug: {Req.Test, __MODULE__}]
      )

      on_exit(fn -> Application.delete_env(:heddle_ai, :req_options) end)
    end

    defp stub_google(reply) do
      test = self()

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test, {:google, conn, Jason.decode!(raw)})
        reply.(conn)
      end)
    end

    defp image_reply(conn) do
      part = %{"inlineData" => %{"mimeType" => "image/png", "data" => Base.encode64(@png)}}

      Req.Test.json(conn, %{"candidates" => [%{"content" => %{"parts" => [part]}}]})
    end

    test "asks for Nano Banana and reads the image it gets" do
      stub_google(&image_reply/1)

      assert {:ok, {@png, "image/png"}} =
               AI.generate_image("A cat", credential: @google, aspect_ratio: "16:9")

      assert_received {:google, conn, body}
      assert conn.request_path =~ "/models/gemini-nano-banana-2.1:generateContent"
      assert Plug.Conn.get_req_header(conn, "x-goog-api-key") == ["g-key"]
      assert get_in(body, ["generationConfig", "imageConfig", "aspectRatio"]) == "16:9"
    end

    test "sends the image to edit as inline data" do
      stub_google(&image_reply/1)

      assert {:ok, _image} =
               AI.generate_image("Add a hat", credential: @google, image: {@png, "image/png"})

      assert_received {:google, _conn, %{"contents" => [%{"parts" => parts}]}}

      assert %{"inline_data" => %{"data" => data, "mime_type" => "image/png"}} =
               Enum.find(parts, & &1["inline_data"])

      assert Base.decode64!(data) == @png
      assert Enum.find(parts, &(&1["text"] == "Add a hat"))
    end

    test "tells why when the model answers with text" do
      stub_google(fn conn ->
        Req.Test.json(conn, %{
          "candidates" => [%{"content" => %{"parts" => [%{"text" => "I can't draw that."}]}}]
        })
      end)

      assert {:error, message} = AI.generate_image("Something", credential: @google)
      assert message =~ "I can't draw that."
    end

    test "returns the error of a rejected key without the key" do
      stub_google(fn conn ->
        conn
        |> Plug.Conn.put_status(403)
        |> Req.Test.json(%{"error" => %{"message" => "API key not valid"}})
      end)

      assert {:error, message} = AI.generate_image("A cat", credential: @google)
      assert is_binary(message)
      refute message =~ "g-key"
    end
  end
end
