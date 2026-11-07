defmodule HeddleAI.ModelsTest do
  use ExUnit.Case, async: true

  alias HeddleAI.Models

  defp ids(provider, capability) do
    provider |> Models.options(capability) |> Enum.map(& &1.id)
  end

  describe "options/2" do
    test "lists the default of every task first" do
      for {_label, id} <- Models.providers(),
          provider = String.to_existing_atom(id),
          capability <- Models.capabilities(),
          default = Models.default(provider, capability) do
        assert hd(ids(provider, capability)) == default,
               "#{default} is missing from #{provider}/#{capability}: a req_llm update changed it"
      end
    end

    test "only offers image models for images" do
      image = ids(:google, :image)

      assert "gemini-nano-banana-2.1" in image
      assert "gemini-3-pro-image" in image
      refute "gemini-3.8-flash" in image
    end

    test "leaves out what Google deprecated and what isn't for a task" do
      refute "gemini-3.1-flash-image" in ids(:google, :image)
      refute "gemini-nano-banana-2.1" in ids(:google, :text)

      refute Enum.any?(
               ids(:openai, :text),
               &(&1 =~ ~r/embedding|realtime|codex|\d{4}-\d{2}-\d{2}/)
             )
    end

    test "offers nothing for what a provider can't do here" do
      assert Models.options(:anthropic, :image) == []
      assert Models.options(:google, :transcription) == []
      assert Models.options(:google, :speech) == []
    end

    test "always has something to show" do
      assert Enum.all?(Models.options(:openai, :speech), &is_binary(&1.label))
    end
  end

  describe "check/4" do
    test "accepts a listed model, and a blank one when there's a default" do
      assert Models.check(:google, :image, "gemini-3-pro-image") == :ok
      assert Models.check(:google, :image, nil) == :ok
    end

    test "names the model and the provider when it's wrong" do
      assert {:error, message} = Models.check(:google, :image, "GPT")
      assert message =~ "GPT"
      assert message =~ "Google"
    end

    test "says who can do a task a provider can't" do
      assert {:error, message} = Models.check(:anthropic, :speech, nil)
      assert message =~ "Anthropic can't turn text into speech"
      assert message =~ "OpenAI"
    end

    test "trusts the model the environment set for text" do
      assert Models.check(:mistral, :text, nil, "mistral-large") == :ok
      assert {:error, _message} = Models.check(:mistral, :text, nil, nil)
    end
  end

  describe "label/2" do
    test "gives the name, or the ID when there's none" do
      assert Models.label(:google, "gemini-nano-banana-2.1") == "Nano Banana 2.1"
      assert Models.label(:openai, "whisper-1") == "whisper-1"
      assert Models.label(:google, "nope") == "nope"
    end
  end
end
