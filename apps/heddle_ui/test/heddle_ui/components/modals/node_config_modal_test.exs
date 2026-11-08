defmodule HeddleUI.Components.Modals.NodeConfigModalTest do
  use HeddleUI.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias HeddleCore.Credentials
  alias HeddleUI.Components.Modals.NodeConfigModal

  defp control(label, type \\ "text"), do: %{"label" => label, "type" => type, "value" => ""}

  defp labels(type, controls) do
    data = %{"type" => type, "label" => type, "controls" => controls}

    (&NodeConfigModal.node_config_modal/1)
    |> render_component(config_modal_open: true, editing_node_data: data)
    |> LazyHTML.from_fragment()
    # The node's settings come after its controls.
    |> LazyHTML.query("label:not(#node-settings label)")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  test "shows the fields in the order of the node's definition" do
    controls = %{
      "aspect_ratio" => control("Aspect ratio"),
      "credential" => control("Credential", "credential"),
      "model" => control("Model"),
      "prompt" => control("Prompt")
    }

    assert ["Credential", "Prompt", "Aspect ratio", "Model"] =
             "AI: Generate Image" |> labels(controls) |> Enum.take(-4)
  end

  test "keeps the fields of a node it doesn't know" do
    controls = %{"a" => control("A"), "b" => control("B")}

    assert ["A", "B"] = "Gone" |> labels(controls) |> Enum.take(-2)
  end

  describe "the model of an AI node" do
    setup do
      {:ok, _credential} =
        Credentials.insert_credential(
          %{
            "name" => "gemini",
            "kind" => "ai",
            "values" => %{"provider" => "google", "api_key" => "k"}
          },
          nil
        )

      :ok
    end

    defp panel(type, credential, model) do
      data = %{
        "type" => type,
        "label" => type,
        "controls" => %{
          "credential" => %{
            "label" => "Credential",
            "type" => "credential",
            "value" => credential,
            "credential_kind" => "ai"
          },
          "model" => %{"label" => "Model", "type" => "model", "value" => model}
        }
      }

      (&NodeConfigModal.node_config_modal/1)
      |> render_component(
        config_modal_open: true,
        editing_node_data: data,
        credentials: Credentials.list_shared_credentials()
      )
      |> LazyHTML.from_fragment()
    end

    defp text(html, selector) do
      html |> LazyHTML.query(selector) |> Enum.map(&String.trim(LazyHTML.text(&1)))
    end

    test "is a list that says the default, with no field to type in" do
      html = panel("AI: Generate Image", "gemini", "")

      assert ["Default: Nano Banana 2.1" | models] = text(html, "#node-model-model option")
      assert "Nano Banana Pro" in models
      assert text(html, "#node-model-model-problem") == []
      assert html |> LazyHTML.query("input[name=model]") |> Enum.empty?()
    end

    test "warns about a saved model that can't run, and keeps showing it" do
      html = panel("AI: Generate Image", "gemini", "GPT")

      assert [problem] = text(html, "#node-model-model-problem")
      assert problem =~ "GPT"
      assert "GPT (not available)" in text(html, "#node-model-model option")
    end

    test "says when the provider can't do the task" do
      html = panel("AI: Text to Speech", "gemini", "")

      assert [problem] = text(html, "#node-model-model-problem")
      assert problem =~ "Google"
      assert html |> LazyHTML.query("#node-model-model[disabled]") |> Enum.count() == 1
    end

    test "says when the credential is gone" do
      html = panel("AI: Generate Image", "deleted", "")

      assert [_problem] = text(html, "#node-model-model-problem")
    end

    test "says what a blank credential uses" do
      html = panel("AI: Generate Image", "", "")

      assert [default | _rest] = text(html, "#node-credential-credential option")
      assert String.starts_with?(default, "Default:")
    end
  end
end
