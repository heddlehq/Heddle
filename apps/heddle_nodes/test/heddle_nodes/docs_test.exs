defmodule HeddleNodes.DocsTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Docs

  test "every node is documented, and nothing else is" do
    assert %{missing: [], unknown: []} = Docs.coverage(),
           "Add the node to a file of docs/nodes/, or remove what is left of it"
  end

  test "every entry says what the node leaves, in English and Portuguese" do
    for {name, entry} <- Docs.notes() do
      assert Map.has_key?(entry, "result"), "#{name} has no \"result\""

      for language <- ["en", "pt"] do
        assert is_binary(get_in(entry, ["notes", language])) and
                 String.trim(entry["notes"][language]) != "",
               "#{name} has no notes in #{language}"
      end
    end
  end

  test "the reference the site reads is up to date" do
    assert File.read!(Docs.reference_path()) == Docs.encode(),
           "Run `mix heddle.docs` and commit docs/reference/nodes.json"
  end

  test "pages have stable addresses" do
    assert Docs.slug("Slack: Send Message") == "slack-send-message"
    assert Docs.slug("AI: Text to Speech") == "ai-text-to-speech"
    assert Docs.slug("Respond to Webhook") == "respond-to-webhook"
  end
end
